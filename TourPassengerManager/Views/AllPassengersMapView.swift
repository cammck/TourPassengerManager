import SwiftUI
import MapKit
import CoreLocation

/// One passenger plus which tour they're on — several tours' passengers can
/// combine onto the same pin here (e.g. a repeat traveler, or family members on
/// different departures), unlike a single tour's own Passenger Map.
private struct CrossTourPassengerEntry: Identifiable {
    /// Passenger IDs are UUIDs generated per-passenger, unique across every tour,
    /// so this is safe as a cross-tour identity.
    var id: UUID { passenger.id }
    let passenger: Passenger
    let tourID: UUID
    let tourCode: String
}

/// One map pin: every passenger, from any tour, who shares the same address.
private struct CrossTourAddressGroup: Identifiable {
    var id: String
    var displayAddress: String
    var entries: [CrossTourPassengerEntry]
    var coordinate: CLLocationCoordinate2D

    static func personLabel(_ passenger: Passenger) -> String {
        let composed = "\(passenger.firstName) \(passenger.surname)".trimmingCharacters(in: .whitespaces)
        return composed.isEmpty ? passenger.displayName : composed
    }

    /// "Jane Smith", "Jane Smith and John Smith", or "Jane Smith, John Smith and
    /// Alex Brown" — everyone sharing this address, across every tour, combined
    /// under their first and last names into one natural-reading line.
    var combinedNameLine: String {
        let names = entries.map { Self.personLabel($0.passenger) }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last!)"
        }
    }
}

/// Shows where passengers from every tour are coming from, on one map — the same
/// idea as a single tour's own Passenger Map, but combining every tour's roster.
///
/// Unlike that per-tour map, this view never geocodes anything itself: it only
/// shows a passenger whose address has already been looked up (successfully) by
/// opening their own tour's Passenger Map at some point — reading `GeocodeCache`
/// rather than adding to it. That keeps opening this view fast regardless of how
/// many tours or passengers exist, at the cost (as expected) of passengers from a
/// tour whose own map has never been opened not appearing here yet.
struct AllPassengersMapView: View {
    @EnvironmentObject var store: TourStore

    @Environment(\.dismiss) private var dismiss
    @State private var addressGroups: [CrossTourAddressGroup] = []
    @State private var isLoading = true
    @State private var hasFitInitialRegion = false
    @State private var selectedGroup: CrossTourAddressGroup?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 170)
        )
    )

    /// Matches the per-tour Passenger Map's own threshold — see that view for why.
    private static let sameAddressThresholdMeters: CLLocationDistance = 50

    /// Crew are excluded from this map entirely (see `buildGroups`), so they're
    /// excluded from this count too — otherwise every crew member across every
    /// tour would misleadingly count toward "not yet located."
    private var totalPassengerCount: Int {
        store.tours.reduce(0) { total, tour in total + tour.passengers.filter { !$0.isCrew }.count }
    }

    private var shownPassengerCount: Int {
        addressGroups.reduce(0) { $0 + $1.entries.count }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    ForEach(addressGroups) { group in
                        Annotation(group.combinedNameLine, coordinate: group.coordinate) {
                            Button {
                                selectedGroup = group
                            } label: {
                                pin(for: group)
                            }
                            .accessibilityLabel(group.combinedNameLine)
                            .accessibilityHint(group.displayAddress)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                if !isLoading && addressGroups.isEmpty {
                    ContentUnavailableView(
                        "No Located Passengers Yet",
                        systemImage: "mappin.slash",
                        description: Text("This shows passengers whose address has already been looked up from their own tour's Passenger Map. Open a tour's Passenger Map first to start locating passengers.")
                    )
                    .background(.thinMaterial)
                }

                if !isLoading && !addressGroups.isEmpty {
                    VStack {
                        statusBanner
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("All Passengers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedGroup) { group in
                CrossTourAddressGroupDetailSheet(group: group)
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
            .task {
                await load()
            }
        }
    }

    // MARK: - Pins

    @ViewBuilder
    private func pin(for group: CrossTourAddressGroup) -> some View {
        VStack(spacing: 2) {
            Image(systemName: group.entries.count > 1 ? "person.2.circle.fill" : "mappin.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.red)
                .shadow(radius: 1)

            if group.entries.count > 1 {
                Text("\(group.entries.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
            }
        }
    }

    private var statusBanner: some View {
        Label(
            "\(shownPassengerCount) of \(totalPassengerCount) passengers located so far",
            systemImage: "info.circle"
        )
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
    }

    // MARK: - Building groups (cache reads only — no geocoding)

    @MainActor
    private func load() async {
        isLoading = true
        addressGroups = await Self.buildGroups(from: store.tours)
        isLoading = false
        fitInitialRegionIfNeeded()
    }

    /// Crew are skipped entirely — they don't have a home address on file and
    /// aren't meant to appear on this map regardless of tour.
    private static func buildGroups(from tours: [Tour]) async -> [CrossTourAddressGroup] {
        var groupsByKey: [String: CrossTourAddressGroup] = [:]
        var order: [String] = []

        for tour in tours {
            for passenger in tour.passengers {
                guard !passenger.isCrew else { continue }
                let trimmedAddress = passenger.address.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedAddress.isEmpty else { continue }
                guard let coordinate = await GeocodeCache.shared.cachedCoordinateIfKnown(for: trimmedAddress) else { continue }

                let key = GeocodeCache.normalize(trimmedAddress)
                let entry = CrossTourPassengerEntry(passenger: passenger, tourID: tour.id, tourCode: tour.code)

                if groupsByKey[key] == nil {
                    groupsByKey[key] = CrossTourAddressGroup(
                        id: key,
                        displayAddress: trimmedAddress,
                        entries: [],
                        coordinate: coordinate
                    )
                    order.append(key)
                }
                groupsByKey[key]?.entries.append(entry)
            }
        }

        let groups = order.compactMap { groupsByKey[$0] }
        return consolidateNearbyGroups(groups).map { group in
            var sorted = group
            sorted.entries.sort {
                CrossTourAddressGroup.personLabel($0.passenger)
                    .localizedCaseInsensitiveCompare(CrossTourAddressGroup.personLabel($1.passenger)) == .orderedAscending
            }
            return sorted
        }
    }

    /// Same idea as the per-tour Passenger Map's own consolidation pass: merges
    /// any pins that land within `sameAddressThresholdMeters` of each other, for
    /// an address-text difference `GeocodeCache.normalize` doesn't recognize as
    /// equivalent but that still geocoded to essentially the same spot.
    private static func consolidateNearbyGroups(_ groups: [CrossTourAddressGroup]) -> [CrossTourAddressGroup] {
        var remaining = groups
        var merged: [CrossTourAddressGroup] = []

        while !remaining.isEmpty {
            var group = remaining.removeFirst()
            let anchorLocation = CLLocation(latitude: group.coordinate.latitude, longitude: group.coordinate.longitude)

            var index = 0
            while index < remaining.count {
                let candidate = remaining[index]
                let candidateLocation = CLLocation(latitude: candidate.coordinate.latitude, longitude: candidate.coordinate.longitude)
                if anchorLocation.distance(from: candidateLocation) <= sameAddressThresholdMeters {
                    group.entries.append(contentsOf: candidate.entries)
                    remaining.remove(at: index)
                } else {
                    index += 1
                }
            }

            merged.append(group)
        }

        return merged
    }

    /// Zooms/pans the map to fit every pin, once — after that, the person's own
    /// panning and zooming is left alone.
    private func fitInitialRegionIfNeeded() {
        guard !hasFitInitialRegion else { return }
        let coordinates = addressGroups.map { $0.coordinate }
        guard !coordinates.isEmpty else { return }
        hasFitInitialRegion = true

        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// The passenger names (with which tour each is on) for one cross-tour address
/// pin. Tapping a passenger pushes into their full detail screen, paging through
/// that one tour's own roster — not across tours, since a detail screen is bound
/// to a single tour.
private struct CrossTourAddressGroupDetailSheet: View {
    @EnvironmentObject var store: TourStore
    let group: CrossTourAddressGroup

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.combinedNameLine)
                            .font(.headline)
                        Text(group.displayAddress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section(group.entries.count > 1 ? "\(group.entries.count) Passengers Here" : "Passenger") {
                    ForEach(group.entries) { entry in
                        NavigationLink {
                            PassengerDetailView(
                                tour: store.binding(for: entry.tourID),
                                orderedPassengerIDs: orderedPassengerIDs(for: entry.tourID),
                                initialPassengerID: entry.passenger.id,
                                onDelete: { deleted in
                                    var tourBinding = store.binding(for: entry.tourID)
                                    tourBinding.wrappedValue.clearFaceTag(forPassenger: deleted.id)
                                    tourBinding.wrappedValue.passengers.removeAll { $0.id == deleted.id }
                                }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(CrossTourAddressGroup.personLabel(entry.passenger))
                                        .font(.body.weight(.medium))
                                    Spacer(minLength: 8)
                                    Text(entry.tourCode.isEmpty ? "No Code" : entry.tourCode)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue, in: Capsule())
                                }
                                if !entry.passenger.mobileNumber.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(entry.passenger.mobileNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Passengers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Every passenger on `tourID`'s own roster, in the same order used
    /// elsewhere for cross-tour results — crew last, then alphabetical — so
    /// paging through this passenger's detail screen steps through their whole
    /// tour, not just this one address.
    private func orderedPassengerIDs(for tourID: UUID) -> [UUID] {
        guard let tour = store.tours.first(where: { $0.id == tourID }) else { return [] }
        return tour.passengers
            .sorted {
                if $0.isCrew != $1.isCrew { return !$0.isCrew }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .map { $0.id }
    }
}
