import SwiftUI

@main
struct TourPassengerManagerApp: App {
    @StateObject private var tourStore = TourStore()
    @StateObject private var templateStore = TemplateStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ToursListView()
                .environmentObject(tourStore)
                .environmentObject(templateStore)
                .environmentObject(settingsStore)
                .environmentObject(authManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-lock passenger details whenever the app leaves the foreground, so a
            // previous Face ID unlock doesn't carry over if someone else picks up the phone.
            if newPhase == .background {
                authManager.lock()
            }
        }
    }
}
