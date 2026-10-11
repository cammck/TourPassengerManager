import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                TextField("e.g. Red Centre Explorer Tour", text: $store.settings.tourName)
            } header: {
                Text("Tour Name")
            } footer: {
                Text("The tour product's name — used in SMS templates via {TourName}. Applies to every tour, since it doesn't change between departures; each tour is distinguished by its Tour Code and dates instead.")
            }

            Section("Tour Director") {
                TextField("First Name", text: $store.settings.tourDirectorFirstName)
                TextField("Preferred Name", text: $store.settings.tourDirectorPreferredName)
                TextField("Surname", text: $store.settings.tourDirectorSurname)
            }

            Section {
                Text("These apply across every tour and can be used in SMS templates via {TourDirectorFirstName}, {TourDirectorPreferredName}, {TourDirectorSurname}, and the combined {TourDirectorName} — handy for signing off messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(SettingsStore())
    }
}
