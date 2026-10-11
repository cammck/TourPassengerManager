import SwiftUI

struct ToursListView: View {
    @EnvironmentObject var store: TourStore
    @EnvironmentObject var templateStore: TemplateStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var authManager: AuthManager
    @State private var showingAddTour = false
    @State private var showingImportBackup = false
    @State private var shareFile: ShareableFile?
    @State private var isPreparingExport = false
    @State private var showingGlobalSearch = false
    @State private var showingAllPassengersMap = false
    @State private var pendingBackupAction: PendingBackupAction?
    @State private var pendingShowGlobalSearch = false
    @State private var pendingShowAllPassengersMap = false

    private enum PendingBackupAction {
        case export
        case importBackup
    }

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func isCurrent(_ tour: Tour) -> Bool {
        guard let start = tour.startDate, let end = tour.endDate else { return false }
        let startDay = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        return startDay <= today && today <= endDay
    }

    private func isPast(_ tour: Tour) -> Bool {
        guard let end = tour.endDate else { return false }
        return Calendar.current.startOfDay(for: end) < today
    }

    /// Current tour(s) first, then upcoming tours soonest-first, then any tours
    /// with no dates set at all (sorted by code) at the end.
    private var currentAndUpcomingTours: [Tour] {
        store.tours
            .filter { !isPast($0) }
            .sorted { a, b in
                let aCurrent = isCurrent(a)
                let bCurrent = isCurrent(b)
                if aCurrent != bCurrent { return aCurrent }

                switch (a.startDate, b.startDate) {
                case let (dateA?, dateB?):
                    return dateA < dateB
                case (nil, nil):
                    return a.code.localizedCaseInsensitiveCompare(b.code) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
    }

    /// Past tours, most recently ended first.
    private var pastTours: [Tour] {
        store.tours
            .filter { isPast($0) }
            .sorted { a, b in
                guard let endA = a.endDate, let endB = b.endDate else { return false }
                return endA > endB
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if !currentAndUpcomingTours.isEmpty {
                    Section("Current & Upcoming") {
                        ForEach(currentAndUpcomingTours) { tour in
                            tourRow(tour)
                        }
                    }
                }

                if !pastTours.isEmpty {
                    Section("Past") {
                        ForEach(pastTours) { tour in
                            tourRow(tour)
                        }
                    }
                }

                if store.tours.isEmpty {
                    ContentUnavailableView(
                        "No Tours Yet",
                        systemImage: "bus.doubledecker",
                        description: Text("Tap + to create your first tour and start adding passengers.")
                    )
                }
            }
            .navigationTitle("Tours")
            .navigationDestination(for: UUID.self) { tourID in
                RosterGateView(tour: store.binding(for: tourID))
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        NavigationLink {
                            TemplatesListView()
                        } label: {
                            Image(systemName: "text.bubble")
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        Menu {
                            Button {
                                requestBackupAction(.export)
                            } label: {
                                Label("Export Backup", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                requestBackupAction(.importBackup)
                            } label: {
                                Label("Import Backup", systemImage: "square.and.arrow.down")
                            }
                        } label: {
                            Image(systemName: "externaldrive")
                        }
                        Button {
                            requestGlobalSearch()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        Button {
                            requestAllPassengersMap()
                        } label: {
                            Image(systemName: "map")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddTour = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTour) {
                AddTourView()
            }
            .sheet(isPresented: $showingImportBackup) {
                BackupImportView()
            }
            .sheet(item: $shareFile) { file in
                ShareSheet(activityItems: [file.url])
            }
            .overlay {
                if isPreparingExport {
                    ProgressView("Preparing backup…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .sheet(isPresented: $showingGlobalSearch) {
                GlobalPassengerSearchView()
            }
            .sheet(isPresented: $showingAllPassengersMap) {
                AllPassengersMapView()
            }
            .onChange(of: authManager.isUnlocked) { _, unlocked in
                guard unlocked else { return }
                if let action = pendingBackupAction {
                    pendingBackupAction = nil
                    performBackupAction(action)
                }
                if pendingShowGlobalSearch {
                    pendingShowGlobalSearch = false
                    showingGlobalSearch = true
                }
                if pendingShowAllPassengersMap {
                    pendingShowAllPassengersMap = false
                    showingAllPassengersMap = true
                }
            }
        }
    }

    /// Search results surface passenger details across every tour, so — like
    /// backup export/import — this needs to go through the same Face ID gate as
    /// viewing a single tour's roster, since the Tours list itself isn't behind it.
    private func requestGlobalSearch() {
        if authManager.isUnlocked {
            showingGlobalSearch = true
        } else {
            pendingShowGlobalSearch = true
            authManager.authenticate()
        }
    }

    /// The All Passengers map surfaces passenger names and home locations across
    /// every tour — the same class of cross-tour passenger data as global search
    /// and backups, so it goes through the same Face ID gate those do.
    private func requestAllPassengersMap() {
        if authManager.isUnlocked {
            showingAllPassengersMap = true
        } else {
            pendingShowAllPassengersMap = true
            authManager.authenticate()
        }
    }

    /// Backups contain every passenger's details across every tour, so exporting
    /// or importing one needs to go through the same Face ID gate as viewing a
    /// single tour's roster — otherwise it'd be a way to bypass that protection
    /// entirely from the Tours list, which isn't itself behind the gate.
    private func requestBackupAction(_ action: PendingBackupAction) {
        if authManager.isUnlocked {
            performBackupAction(action)
        } else {
            pendingBackupAction = action
            authManager.authenticate()
        }
    }

    private func performBackupAction(_ action: PendingBackupAction) {
        switch action {
        case .export:
            guard !isPreparingExport else { return }
            isPreparingExport = true

            // A backup can embed every tour's group photo, so building it can take a
            // moment. Do that off the main thread and show a spinner meanwhile.
            let tours = store.tours
            let templates = templateStore.templates
            let snippets = templateStore.snippets
            let settings = settingsStore.settings

            Task { @MainActor in
                let url = await Task.detached(priority: .userInitiated) {
                    BackupService.exportBackup(
                        tours: tours,
                        templates: templates,
                        snippets: snippets,
                        settings: settings
                    )
                }.value

                isPreparingExport = false
                if let url {
                    shareFile = ShareableFile(url: url)
                }
            }
        case .importBackup:
            showingImportBackup = true
        }
    }

    /// "42 passengers", or "42 passengers · 3 crew" when some have no booking number.
    private func passengerSummary(for tour: Tour) -> String {
        let crewCount = tour.passengers.filter { $0.isCrew }.count
        let passengerCount = tour.passengers.count - crewCount
        var text = "\(passengerCount) passenger\(passengerCount == 1 ? "" : "s")"
        if crewCount > 0 {
            text += " · \(crewCount) crew"
        }
        return text
    }

    @ViewBuilder
    private func tourRow(_ tour: Tour) -> some View {
        NavigationLink(value: tour.id) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tour.code.isEmpty ? "(No Code)" : tour.code)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tour.code.isEmpty ? .secondary : .primary)
                    if isCurrent(tour) {
                        Text("CURRENT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(passengerSummary(for: tour))
                    if let range = dateRangeText(for: tour) {
                        Text(range)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteTour(tour)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func dateRangeText(for tour: Tour) -> String? {
        guard let start = tour.startDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if let end = tour.endDate {
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }
}

#Preview {
    ToursListView()
        .environmentObject(TourStore())
        .environmentObject(TemplateStore())
        .environmentObject(SettingsStore())
        .environmentObject(AuthManager())
}
