import SwiftUI
import MapKit
import CoreLocation

/// One map pin: every passenger who shares the same address (matched after
/// trimming/case-folding/whitespace-collapsing — see `GeocodeCache.normalize`),
/// combined together under their first and last names. `coordinate` is nil until
/// geocoding for this address finishes (or if it failed).
struct AddressGroup: Identifiable {
    /// The normalized address — stable and unique per group, so it's safe as an ID
    /// even before geocoding assigns a coordinate.
    var id: String
    /// The address as first seen among this group's passengers, for display —
    /// not the normalized form.
    var displayAddress: String
    var passengers: [Passenger]
    var coordinate: CLLocationCoordinate2D?

    /// First and last name only — falling back to the app-wide display name (e.g. a
    /// manifest's Combined Name column) only if both are blank.
    static func personLabel(_ passenger: Passenger) -> String {
        let composed = "\(passenger.firstName) \(passenger.surname)".trimmingCharacters(in: .whitespaces)
        return composed.isEmpty ? passenger.displayName : composed
    }

    /// "Jane Smith", "Jane Smith and John Smith", or "Jane Smith, John Smith and
    /// Alex Brown" — everyone sharing this address, combined under their first and
    /// last names into one natural-reading line.
    var combinedNameLine: String {
        let names = passengers.map(Self.personLabel)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last!)"
        }
    }
}

/// Shows where a tour's passengers are coming from: one pin per distinct home
/// address, with passengers at the same address combined onto a single pin rather
/// than stacking separate pins on top of each other. Addresses are looked up via
/// `GeocodeCache`, sequentially (Apple's geocoding service is meant to handle one
/// request at a time per request stream, and sequential lookups let the map fill in
/// progressively rather than firing off dozens of requests at once).
struct PassengerAddressMapView: View {
    @Binding var tour: Tour
    /// When set, the map opens zoomed in on just this passenger's pin (rather than
    /// fitted to everyone) and immediately shows their address-group detail sheet —
    /// for navigating here from that one passenger's own detail screen rather than
    /// from the tour's general filter menu. Falls back to the usual fit-everyone
    /// behavior if this passenger has no address or it couldn't be geocoded.
    var focusedPassengerID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var addressGroups: [AddressGroup] = []
    @State private var geocodedCount = 0
    @State private var isLoading = true
    @State private var hasFitInitialRegion = false
    @State private var failedAddresses: [String] = []
    @State private var selectedGroup: AddressGroup?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 170)
        )
    )

    private var totalToGeocode: Int {
        addressGroups.count
    }

    private var geocodedGroups: [AddressGroup] {
        addressGroups.filter { $0.coordinate != nil }
    }

    /// Crew never have an address on file and aren't meant to be on this map at
    /// all (see `groupedByAddress`), so they're excluded here too — otherwise
    /// every crew member would misleadingly count as a passenger "not shown."
    private var passengersWithNoAddress: Int {
        let bookedPassengers = tour.passengers.filter { !$0.isCrew }
        return bookedPassengers.count - addressGroups.reduce(0) { $0 + $1.passengers.count }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    ForEach(geocodedGroups) { group in
                        Annotation(group.combinedNameLine, coordinate: group.coordinate!) {
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

                if addressGroups.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Addresses on File",
                        systemImage: "mappin.slash",
                        description: Text("None of this tour's passengers have an address entered.")
                    )
                    .background(.thinMaterial)
                }

                VStack {
                    statusBanner
                    Spacer()
                }
                .padding(.top, 8)
            }
            .navigationTitle("Passenger Addresses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedGroup) { group in
                AddressGroupDetailSheet(tour: $tour, group: group)
                    .presentationDetents([.medium, .large])
            }
            .task(id: tour.id) {
                await loadAndGeocode()
            }
        }
    }

    // MARK: - Pins

    @ViewBuilder
    private func pin(for group: AddressGroup) -> some View {
        VStack(spacing: 2) {
            Image(systemName: group.passengers.count > 1 ? "person.2.circle.fill" : "mappin.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.red)
                .shadow(radius: 1)

            if group.passengers.count > 1 {
                Text("\(group.passengers.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
            }
        }
    }

    // MARK: - Status banner

    @ViewBuilder
    private var statusBanner: some View {
        if isLoading {
            Label("Locating addresses… \(geocodedCount) of \(totalToGeocode)", systemImage: "location.magnifyingglass")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal)
        } else if !failedAddresses.isEmpty || passengersWithNoAddress > 0 {
            Menu {
                if passengersWithNoAddress > 0 {
                    Text("\(passengersWithNoAddress) passenger\(passengersWithNoAddress == 1 ? "" : "s") with no address on file")
                }
                if !failedAddresses.isEmpty {
                    Section("Couldn't be located") {
                        ForEach(failedAddresses, id: \.self) { address in
                            Text(address)
                        }
                    }
                }
            } label: {
                Label(
                    "\(passengersWithNoAddress + failedAddresses.count) passenger\((passengersWithNoAddress + failedAddresses.count) == 1 ? "" : "s") not shown on the map",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Grouping

    /// Groups passengers by normalized address, skipping anyone with a blank
    /// address and skipping crew entirely — crew don't have a home address on
    /// file, and aren't meant to appear on this map regardless. Within a group,
    /// passengers are sorted alphabetically for predictable, deterministic output.
    private static func groupedByAddress(_ passengers: [Passenger]) -> [AddressGroup] {
        var groupsByKey: [String: AddressGroup] = [:]
        var order: [String] = []

        for passenger in passengers {
            guard !passenger.isCrew else { continue }
            let trimmedAddress = passenger.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAddress.isEmpty else { continue }
            let key = GeocodeCache.normalize(trimmedAddress)

            if groupsByKey[key] == nil {
                groupsByKey[key] = AddressGroup(id: key, displayAddress: trimmedAddress, passengers: [])
                order.append(key)
            }
            groupsByKey[key]?.passengers.append(passenger)
        }

        return order.compactMap { key in
            guard var group = groupsByKey[key] else { return nil }
            group.passengers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return group
        }
    }

    // MARK: - Geocoding

    @MainActor
    private func loadAndGeocode() async {
        let groups = Self.groupedByAddress(tour.passengers)
        addressGroups = groups
        geocodedCount = 0
        failedAddresses = []
        hasFitInitialRegion = false
        isLoading = !groups.isEmpty

        for group in groups {
            let coordinate = await GeocodeCache.shared.coordinate(for: group.displayAddress)
            if let index = addressGroups.firstIndex(where: { $0.id == group.id }) {
                addressGroups[index].coordinate = coordinate
            }
            if coordinate == nil {
                failedAddresses.append(group.displayAddress)
            }
            geocodedCount += 1
        }

        addressGroups = Self.consolidateNearbyGroups(addressGroups)
        isLoading = false
        fitInitialRegionIfNeeded()
    }

    /// How close two geocoded addresses need to land to be treated as "the same
    /// place" — roughly a property width. Deliberately small, so genuinely
    /// different (if neighboring) addresses aren't merged by mistake.
    private static let sameAddressThresholdMeters: CLLocationDistance = 50

    /// A second line of defense beyond `GeocodeCache.normalize`'s text-based
    /// matching: merges any groups whose geocoded coordinates land within
    /// `sameAddressThresholdMeters` of each other. Catches an address-text
    /// difference normalization doesn't recognize as equivalent (an abbreviation
    /// not in its list, a typo, a differently formatted unit number) that still
    /// geocodes to essentially the same spot — the exact situation that could
    /// otherwise leave one of two passengers at the same place missing from the
    /// map, or sharing it with an all-but-invisible pin stacked on the other's.
    private static func consolidateNearbyGroups(_ groups: [AddressGroup]) -> [AddressGroup] {
        var remaining = groups
        var merged: [AddressGroup] = []

        while !remaining.isEmpty {
            var group = remaining.removeFirst()
            guard let anchor = group.coordinate else {
                merged.append(group)
                continue
            }
            let anchorLocation = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)

            var index = 0
            while index < remaining.count {
                guard let coordinate = remaining[index].coordinate else {
                    index += 1
                    continue
                }
                let candidateLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if anchorLocation.distance(from: candidateLocation) <= sameAddressThresholdMeters {
                    group.passengers.append(contentsOf: remaining[index].passengers)
                    remaining.remove(at: index)
                } else {
                    index += 1
                }
            }

            group.passengers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            merged.append(group)
        }

        return merged
    }

    /// Zooms/pans the map to fit every located pin, once — after that, the person's
    /// own panning and zooming is left alone rather than being reset every time
    /// this view's state changes. If `focusedPassengerID` is set and that passenger
    /// was successfully located, zooms tightly on just their pin and opens their
    /// address-group detail sheet instead of fitting everyone.
    private func fitInitialRegionIfNeeded() {
        guard !hasFitInitialRegion else { return }

        if let focusedPassengerID,
           let focusedGroup = addressGroups.first(where: { group in
               group.passengers.contains(where: { $0.id == focusedPassengerID })
           }),
           let coordinate = focusedGroup.coordinate {
            hasFitInitialRegion = true
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
            selectedGroup = focusedGroup
            return
        }

        let coordinates = geocodedGroups.compactMap { $0.coordinate }
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

/// The passenger names and a couple of contact details for one address pin,
/// shown when its pin is tapped — most useful when several passengers share one
/// pin and their individual names don't all fit in a map callout. Tapping a
/// passenger pushes into their full detail screen.
private struct AddressGroupDetailSheet: View {
    @Binding var tour: Tour
    let group: AddressGroup

    @Environment(\.dismiss) private var dismiss

    /// `group`'s passengers re-derived from the live tour, rather than the
    /// snapshot `group` was built from — so this sheet reflects a name or number
    /// edited just now, and drops anyone deleted while viewing their details,
    /// rather than showing stale information that no longer matches the tour.
    private var liveGroup: AddressGroup {
        var updated = group
        updated.passengers = group.passengers.compactMap { original in
            tour.passengers.first(where: { $0.id == original.id })
        }
        return updated
    }

    /// Every passenger originally in this group, in the same order, so paging
    /// through the detail screen for one of them steps through this address's
    /// household rather than the whole tour roster.
    private var orderedPassengerIDs: [UUID] {
        group.passengers.map { $0.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if liveGroup.passengers.isEmpty {
                    ContentUnavailableView(
                        "No Passengers Here",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Everyone who was at this address has been removed from the tour.")
                    )
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(liveGroup.combinedNameLine)
                                    .font(.headline)
                                Text(liveGroup.displayAddress)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        Section(liveGroup.passengers.count > 1 ? "\(liveGroup.passengers.count) Passengers Here" : "Passenger") {
                            ForEach(liveGroup.passengers) { passenger in
                                NavigationLink {
                                    PassengerDetailView(
                                        tour: $tour,
                                        orderedPassengerIDs: orderedPassengerIDs,
                                        initialPassengerID: passenger.id,
                                        onDelete: { deleted in
                                            tour.clearFaceTag(forPassenger: deleted.id)
                                            tour.passengers.removeAll { $0.id == deleted.id }
                                        }
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(AddressGroup.personLabel(passenger))
                                            .font(.body.weight(.medium))
                                        if !passenger.mobileNumber.trimmingCharacters(in: .whitespaces).isEmpty {
                                            Text(passenger.mobileNumber)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
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
}
