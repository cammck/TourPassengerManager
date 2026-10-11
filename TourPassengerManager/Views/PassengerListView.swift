import SwiftUI
import UIKit

struct PassengerListView: View {
    @Binding var tour: Tour
    @EnvironmentObject private var authManager: AuthManager

    @State private var searchText = ""
    @State private var groupingMode: RosterGroupingMode = .all
    @State private var showingAddSheet = false
    @State private var showingCSVPicker = false
    @State private var shareFile: ShareableFile?
    @State private var isSelecting = false
    @State private var selectedPassengerIDs: Set<UUID> = []
    @State private var showingSendSMS = false
    @State private var showingTourDetails = false
    @State private var showingCantSendMailAlert = false
    @State private var showingGroupPhoto = false
    @State private var groupPhotoInitialIndex = 0
    @State private var showingAddressMap = false

    // MARK: - Filtering & grouping

    private var searchFilteredPassengers: [Passenger] {
        var result = tour.passengers

        if !searchText.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.preferredName.localizedCaseInsensitiveContains(searchText) ||
                $0.email.localizedCaseInsensitiveContains(searchText) ||
                $0.mobileNumber.localizedCaseInsensitiveContains(searchText) ||
                $0.bookingNumber.localizedCaseInsensitiveContains(searchText) ||
                $0.roomType.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    /// Flat, alphabetically sorted list — used for the "All Passengers" mode.
    /// Booking clusters (see BookingLink and bookingClusterKey below) sort together
    /// at the alphabetical position of the earliest name in the cluster.
    private var flatPassengers: [Passenger] {
        sortedByBookingCluster(searchFilteredPassengers)
    }

    /// Sections used for every grouped mode: (section title, passengers in that section).
    /// Within each section, passengers are also sorted by booking cluster (see
    /// sortedByBookingCluster) so bookings stay adjacent even inside e.g. a pickup
    /// location group.
    private var groupedSections: [(title: String, passengers: [Passenger])] {
        let base = searchFilteredPassengers
        switch groupingMode {
        case .all:
            return []
        case .pickup:
            // Grouped by location AND time together, not location alone — a pickup
            // point often sees more than one drop that day (e.g. two trains into the
            // same station), and those shouldn't be lumped into a single group.
            return groupedByPickup(in: base)
        case .dropoff:
            return groupedByValue(\.dropoffLocation, in: base, unassignedLabel: "No Dropoff Location")
        case .dietary:
            let withDietary = base.filter { !$0.dietaryRequirements.trimmingCharacters(in: .whitespaces).isEmpty }
            return groupedByValue(\.dietaryRequirements, in: withDietary, unassignedLabel: "")
        case .medical:
            let withMedical = base.filter { !$0.medicalCondition.trimmingCharacters(in: .whitespaces).isEmpty }
            return groupedByValue(\.medicalCondition, in: withMedical, unassignedLabel: "")
        }
    }

    /// All booking numbers transitively connected to `bookingNumber` via bookingLinks
    /// (including itself). Two links that share a booking number are merged, so
    /// A-linked-to-B and B-linked-to-C both end up in the same connected set.
    private func connectedBookingNumbers(for bookingNumber: String) -> Set<String> {
        let trimmed = bookingNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var connected: Set<String> = [trimmed]
        var changed = true
        while changed {
            changed = false
            for link in tour.bookingLinks where !link.bookingNumbers.isDisjoint(with: connected) {
                let before = connected.count
                connected.formUnion(link.bookingNumbers)
                if connected.count != before { changed = true }
            }
        }
        return connected
    }

    /// The alphabetical sort anchor for a passenger: the earliest display name among
    /// everyone who shares their booking number — whether that's simply multiple
    /// passengers booked under the same literal booking number, or bookings joined
    /// via an explicit BookingLink — so the whole group sorts together regardless
    /// of whose surname happens to come first.
    private func clusterAnchor(for passenger: Passenger) -> String {
        let bookingNumber = passenger.bookingNumber.trimmingCharacters(in: .whitespaces)
        guard !bookingNumber.isEmpty else { return passenger.displayName }

        let connected = connectedBookingNumbers(for: bookingNumber)
        let namesInGroup = tour.passengers
            .filter { connected.contains($0.bookingNumber.trimmingCharacters(in: .whitespaces)) }
            .map { $0.displayName }
        return namesInGroup.min { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } ?? passenger.displayName
    }

    /// A stable identity for the booking (or linked-booking group) a passenger
    /// belongs to — nil if they have no booking number. Used to detect where one
    /// booking ends and the next begins, for the visible delineator between them.
    private func bookingClusterKey(for passenger: Passenger) -> String? {
        let trimmed = passenger.bookingNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return connectedBookingNumbers(for: trimmed).sorted().joined(separator: " + ")
    }

    /// Sorts passengers so that booking clusters (a shared or linked booking number)
    /// stay adjacent, anchored at the earliest name in the cluster, with individual
    /// (unlinked, no-shared-booking) passengers sorting normally by their own name.
    /// Crew (no booking number) always come after every passenger, in name order.
    private func sortedByBookingCluster(_ passengers: [Passenger]) -> [Passenger] {
        passengers.sorted { a, b in
            if a.isCrew != b.isCrew { return !a.isCrew }
            let anchorA = clusterAnchor(for: a)
            let anchorB = clusterAnchor(for: b)
            if anchorA != anchorB {
                return anchorA.localizedCaseInsensitiveCompare(anchorB) == .orderedAscending
            }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// The passenger IDs exactly as currently displayed on screen (respecting search,
    /// grouping, and section order), used to drive swipe/prev-next navigation in
    /// PassengerDetailView so it matches what's visually adjacent.
    private var displayedOrderedPassengerIDs: [UUID] {
        if groupingMode == .all {
            return flatPassengers.map { $0.id }
        } else {
            return groupedSections.flatMap { $0.passengers }.map { $0.id }
        }
    }

    /// Groups passengers by pickup location AND pickup time together, so (for
    /// example) two trains arriving at the same station at different times become
    /// two separate groups rather than one. A location with no time set becomes its
    /// own group titled with just the location; passengers with no pickup location
    /// at all are grouped separately regardless of any time.
    ///
    /// Groups are sorted by location alphabetically, then — within a location — by
    /// pickup time chronologically where the time can be parsed (see
    /// `parsedPickupTime`), falling back to alphabetical order for times that can't
    /// be (pickup time is free text, e.g. "TBC" or "Morning"). A location with no
    /// time set sorts after every timed group for that same location.
    private func groupedByPickup(in passengers: [Passenger]) -> [(title: String, passengers: [Passenger])] {
        struct Key: Hashable {
            let location: String
            let time: String
        }

        let unassignedLabel = "No Pickup Location"

        let dict = Dictionary(grouping: passengers) { passenger -> Key in
            Key(
                location: passenger.pickupLocation.trimmingCharacters(in: .whitespaces),
                time: passenger.pickupTime.trimmingCharacters(in: .whitespaces)
            )
        }

        return dict
            .map { key, value -> (key: Key, title: String, passengers: [Passenger]) in
                let title: String
                if key.location.isEmpty {
                    title = unassignedLabel
                } else if key.time.isEmpty {
                    title = key.location
                } else {
                    title = "\(key.location) · \(key.time)"
                }
                return (key: key, title: title, passengers: sortedByBookingCluster(value))
            }
            .sorted { lhs, rhs in
                let lhsUnassigned = lhs.key.location.isEmpty
                let rhsUnassigned = rhs.key.location.isEmpty
                if lhsUnassigned != rhsUnassigned { return rhsUnassigned }
                if lhsUnassigned && rhsUnassigned {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

                let locationOrder = lhs.key.location.localizedCaseInsensitiveCompare(rhs.key.location)
                if locationOrder != .orderedSame { return locationOrder == .orderedAscending }

                // Same location: order by pickup time. No-time sorts after every timed
                // group; between two timed groups, chronological order wins when both
                // parse, otherwise alphabetical order of the time text.
                if lhs.key.time.isEmpty != rhs.key.time.isEmpty { return rhs.key.time.isEmpty }
                if let lhsTime = parsedPickupTime(lhs.key.time), let rhsTime = parsedPickupTime(rhs.key.time) {
                    return lhsTime < rhsTime
                }
                return lhs.key.time.localizedCaseInsensitiveCompare(rhs.key.time) == .orderedAscending
            }
            .map { (title: $0.title, passengers: $0.passengers) }
    }

    /// Best-effort parse of a free-text pickup time (e.g. "2:00 PM", "14:00") into a
    /// time-of-day for sorting. Only the hour/minute matter — the date is fixed to an
    /// arbitrary reference day so different formats compare correctly against each
    /// other. Returns nil for text that isn't a recognizable clock time (e.g. "TBC").
    private func parsedPickupTime(_ text: String) -> Date? {
        let formats = ["h:mm a", "h:mma", "HH:mm", "H:mm", "h a", "ha"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }

    /// Groups passengers by the string value at the given key path, sorting groups
    /// alphabetically (unassigned bucket last), and sorting passengers within each
    /// group by booking cluster rather than plain name order.
    private func groupedByValue(
        _ keyPath: KeyPath<Passenger, String>,
        in passengers: [Passenger],
        unassignedLabel: String
    ) -> [(title: String, passengers: [Passenger])] {
        let dict = Dictionary(grouping: passengers) { passenger -> String in
            let value = passenger[keyPath: keyPath].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? unassignedLabel : value
        }

        return dict
            .map { key, value in
                (title: key, passengers: sortedByBookingCluster(value))
            }
            .sorted { lhs, rhs in
                if lhs.title == unassignedLabel { return false }
                if rhs.title == unassignedLabel { return true }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// "42 passengers", or "42 passengers · 3 crew" when some people have no booking number.
    private var passengerCountText: String {
        let crewCount = tour.passengers.filter { $0.isCrew }.count
        let passengerCount = tour.passengers.count - crewCount
        var text = "\(passengerCount) passenger\(passengerCount == 1 ? "" : "s")"
        if crewCount > 0 {
            text += " · \(crewCount) crew"
        }
        return text
    }

    private var dietaryCount: Int {
        tour.passengers.filter { !$0.dietaryRequirements.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private var medicalCount: Int {
        tour.passengers.filter { !$0.medicalCondition.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Every passenger currently on screen, respecting search and grouping — used for "Select All".
    private var visiblePassengers: [Passenger] {
        groupingMode == .all ? flatPassengers : groupedSections.flatMap { $0.passengers }
    }

    private var selectedPassengers: [Passenger] {
        tour.passengers.filter { selectedPassengerIDs.contains($0.id) }
    }

    /// Every passenger's email in this tour, trimmed, blanks dropped, and
    /// deduplicated (case-insensitive) while preserving first-seen order — used
    /// for emailing the whole tour at once.
    private var allPassengerEmails: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for passenger in tour.passengers {
            let email = passenger.email.trimmingCharacters(in: .whitespaces)
            guard !email.isEmpty else { continue }
            let key = email.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(email)
        }
        return result
    }

    /// Opens a single email addressed to every passenger in this tour who has an
    /// email on file, all in Bcc — so passengers on the same tour don't see each
    /// other's address, the same way a bulk email to a group normally works.
    ///
    /// Uses a `mailto:` link opened via `UIApplication.shared.open(_:)` rather
    /// than `MFMailComposeViewController` (the framework used for the SMS/Mail
    /// composer elsewhere in the app): that class is hard-coded to always use
    /// Apple's built-in Mail app, regardless of what's set as the default mail
    /// client in iOS Settings — it doesn't respect that setting at all. A
    /// `mailto:` link opened this way does, correctly routing to Outlook, Gmail,
    /// or whatever the person actually has set as their default.
    private func emailAllPassengers() {
        let recipients = allPassengerEmails
        guard !recipients.isEmpty else { return }

        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "bcc", value: recipients.joined(separator: ",")),
            URLQueryItem(name: "subject", value: tour.code)
        ]

        guard let url = components.url else {
            showingCantSendMailAlert = true
            return
        }

        UIApplication.shared.open(url) { success in
            if !success {
                DispatchQueue.main.async {
                    showingCantSendMailAlert = true
                }
            }
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            if !tour.groupPhotos.isEmpty {
                Section {
                    GroupPhotoHeaderView(photos: tour.groupPhotos) { index in
                        groupPhotoInitialIndex = index
                        showingGroupPhoto = true
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                HStack {
                    Label(passengerCountText, systemImage: "person.2.fill")
                    Spacer()
                    if dietaryCount > 0 {
                        Label("\(dietaryCount)", systemImage: "fork.knife")
                            .foregroundStyle(.orange)
                    }
                    if medicalCount > 0 {
                        Label("\(medicalCount)", systemImage: "cross.case")
                            .foregroundStyle(.red)
                    }
                }
                .font(.subheadline)
            }

            if groupingMode == .all {
                let sortedPassengers = flatPassengers
                let bookedPassengers = sortedPassengers.filter { !$0.isCrew }
                let crewMembers = sortedPassengers.filter { $0.isCrew }

                if !bookedPassengers.isEmpty || crewMembers.isEmpty {
                    Section {
                        passengerRows(bookedPassengers)
                    } header: {
                        if !tour.passengers.isEmpty {
                            Text("Roster")
                        }
                    }
                }

                if !crewMembers.isEmpty {
                    Section {
                        passengerRows(crewMembers)
                    } header: {
                        Text("Crew · \(crewMembers.count)")
                    }
                }
            } else {
                ForEach(groupedSections, id: \.title) { section in
                    Section {
                        passengerRows(section.passengers)
                    } header: {
                        Text("\(section.title) · \(section.passengers.count)")
                    }
                }

                if groupedSections.isEmpty && !tour.passengers.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(emptyGroupDescription)
                    )
                }
            }

            if tour.passengers.isEmpty {
                ContentUnavailableView(
                    "No Passengers Yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Import a CSV or add passengers manually to get started.")
                )
            }
        }
        .navigationTitle(tour.code.isEmpty ? "Tour" : tour.code)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search name, email, mobile, booking #, room")
        .navigationDestination(for: Passenger.self) { passenger in
            PassengerDetailView(
                tour: $tour,
                orderedPassengerIDs: displayedOrderedPassengerIDs,
                initialPassengerID: passenger.id,
                onDelete: deletePassenger
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelecting {
                    Button(selectedPassengerIDs.count == visiblePassengers.count && !visiblePassengers.isEmpty ? "Deselect All" : "Select All") {
                        if selectedPassengerIDs.count == visiblePassengers.count {
                            selectedPassengerIDs.removeAll()
                        } else {
                            selectedPassengerIDs = Set(visiblePassengers.map { $0.id })
                        }
                    }
                } else {
                    HStack {
                        Button {
                            showingTourDetails = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        Menu {
                            Picker("Group By", selection: $groupingMode) {
                                ForEach(RosterGroupingMode.allCases) { mode in
                                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                                }
                            }
                            Divider()
                            Button {
                                if let url = CSVParser.export(passengers: tour.passengers).writtenToTempCSV(named: tour.code) {
                                    shareFile = ShareableFile(url: url)
                                }
                            } label: {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                            }
                            .disabled(tour.passengers.isEmpty)
                            Divider()
                            Button {
                                emailAllPassengers()
                            } label: {
                                Label("Email All Passengers", systemImage: "envelope")
                            }
                            .disabled(allPassengerEmails.isEmpty)
                            Divider()
                            Button {
                                showingAddressMap = true
                            } label: {
                                Label("Passenger Map", systemImage: "map")
                            }
                            .disabled(tour.passengers.isEmpty)
                            Divider()
                            Button {
                                authManager.lock()
                            } label: {
                                Label("Lock Passenger Details", systemImage: "lock.fill")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button("Cancel") {
                        isSelecting = false
                        selectedPassengerIDs.removeAll()
                    }
                } else {
                    HStack {
                        Button {
                            showingCSVPicker = true
                        } label: {
                            Image(systemName: "square.and.arrow.down.on.square")
                        }
                        Button {
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button {
                            isSelecting = true
                        } label: {
                            Image(systemName: "message")
                        }
                        .disabled(tour.passengers.isEmpty)
                    }
                }
            }
            if isSelecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Text("\(selectedPassengerIDs.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showingSendSMS = true
                    } label: {
                        Label("Send SMS", systemImage: "paperplane.fill")
                    }
                    .disabled(selectedPassengerIDs.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddPassengerView(tour: $tour)
        }
        .sheet(isPresented: $showingCSVPicker) {
            CSVImportView(tour: $tour)
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .sheet(isPresented: $showingSendSMS) {
            SendSMSView(tour: tour, passengers: selectedPassengers) {
                isSelecting = false
                selectedPassengerIDs.removeAll()
            }
        }
        .sheet(isPresented: $showingTourDetails) {
            TourDetailsView(tour: $tour)
        }
        .fullScreenCover(isPresented: $showingGroupPhoto) {
            GroupPhotoViewerView(tour: $tour, initialIndex: groupPhotoInitialIndex)
        }
        .sheet(isPresented: $showingAddressMap) {
            PassengerAddressMapView(tour: $tour)
        }
        .onChange(of: authManager.isUnlocked) { _, unlocked in
            // The group photo is passenger imagery, so — like the roster itself — it
            // shouldn't stay on screen once the app re-locks. (Unlike the SMS compose
            // sheet, these screens hold no in-progress work that closing would lose.)
            if !unlocked {
                showingGroupPhoto = false
                showingTourDetails = false
                showingAddressMap = false
            }
        }
        .alert("Can't Send Mail", isPresented: $showingCantSendMailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device isn't set up to send email. Add a Mail account under Settings > Mail, then try again.")
        }
    }

    /// Renders passenger rows with a thin colored accent bar delineating bookings —
    /// same color for everyone in a booking cluster, a different color for the next
    /// one — in every grouping mode, not just a dedicated "by booking" view. Chosen
    /// over a full divider line since it needs no extra vertical space.
    @ViewBuilder
    private func passengerRows(_ passengers: [Passenger]) -> some View {
        let colors = bookingClusterColors(for: passengers)
        ForEach(passengers) { passenger in
            passengerRow(passenger, bookingColor: colors[passenger.id])
        }
    }

    /// A small palette cycled through per distinct booking cluster encountered, in
    /// order, so adjacent clusters always get a different color from one another.
    /// Passengers with no booking number get no color (nil).
    private let bookingClusterPalette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]

    private func bookingClusterColors(for passengers: [Passenger]) -> [UUID: Color] {
        var colors: [UUID: Color] = [:]
        var paletteIndex = 0
        var previousKey: String?

        for passenger in passengers {
            guard let key = bookingClusterKey(for: passenger) else { continue }
            if key != previousKey {
                if previousKey != nil {
                    paletteIndex = (paletteIndex + 1) % bookingClusterPalette.count
                }
                previousKey = key
            }
            colors[passenger.id] = bookingClusterPalette[paletteIndex]
        }
        return colors
    }

    @ViewBuilder
    private func passengerRow(_ passenger: Passenger, bookingColor: Color?) -> some View {
        if isSelecting {
            Button {
                toggleSelection(passenger)
            } label: {
                HStack {
                    Image(systemName: selectedPassengerIDs.contains(passenger.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedPassengerIDs.contains(passenger.id) ? .blue : .secondary)
                        .font(.title3)
                    rosterRow(for: passenger, bookingColor: bookingColor)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: passenger) {
                rosterRow(for: passenger, bookingColor: bookingColor)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deletePassenger(passenger)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func isLinkedBooking(_ passenger: Passenger) -> Bool {
        let bookingNumber = passenger.bookingNumber.trimmingCharacters(in: .whitespaces)
        guard !bookingNumber.isEmpty else { return false }
        return tour.bookingLinks.contains { $0.bookingNumbers.contains(bookingNumber) }
    }

    private func toggleSelection(_ passenger: Passenger) {
        if selectedPassengerIDs.contains(passenger.id) {
            selectedPassengerIDs.remove(passenger.id)
        } else {
            selectedPassengerIDs.insert(passenger.id)
        }
    }

    private var emptyGroupDescription: String {
        switch groupingMode {
        case .dietary:
            return "No passengers in this tour have dietary requirements on file."
        case .medical:
            return "No passengers in this tour have a medical condition on file."
        default:
            return "Try a different grouping or clear your search."
        }
    }

    private func deletePassenger(_ passenger: Passenger) {
        tour.clearFaceTag(forPassenger: passenger.id)
        tour.passengers.removeAll { $0.id == passenger.id }
    }

    /// A roster row, with the passenger's face from the group photo when they've been tagged.
    private func rosterRow(for passenger: Passenger, bookingColor: Color?) -> some View {
        PassengerRowView(
            passenger: passenger,
            isLinkedBooking: isLinkedBooking(passenger),
            bookingColor: bookingColor,
            passengerFace: tour.taggedFace(for: passenger.id),
            reservesFaceSlot: tour.hasTaggedFaces
        )
    }
}

private extension String {
    /// Writes this string to a temp CSV file with a filename based on the tour name.
    func writtenToTempCSV(named tourName: String) -> URL? {
        let safeName = tourName.isEmpty ? "tour-roster" : tourName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").inverted)
            .joined()
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-roster.csv")
        do {
            try self.write(to: tmpURL, atomically: true, encoding: .utf8)
            return tmpURL
        } catch {
            return nil
        }
    }
}

#Preview {
    NavigationStack {
        PassengerListView(tour: .constant(Tour(code: "Sample Tour")))
    }
    .environmentObject(TemplateStore())
    .environmentObject(AuthManager())
}
