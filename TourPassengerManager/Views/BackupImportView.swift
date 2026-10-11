import SwiftUI
import UniformTypeIdentifiers

struct BackupImportView: View {
    @EnvironmentObject private var tourStore: TourStore
    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var replaceExisting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var pendingBackup: AppBackup?
    @State private var showingReplaceConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Import a backup file exported from this app on another device — it contains every tour, its passengers, booking links, and notes, plus SMS templates and snippets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Replace existing data", isOn: $replaceExisting)
                    Text(replaceExisting
                         ? "Every tour, template, and snippet currently in the app — and your Tour Director/Tour Name settings — will be permanently replaced with what's in the backup file. You'll be asked to confirm before this happens."
                         : "Tours, templates, and snippets from the backup are added, or update the matching ones already here (matched by their internal ID, so re-importing the same backup twice won't create duplicates). Your current Settings are left untouched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Choose Backup File", systemImage: "doc.badge.plus")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Import Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Replace All Data?", isPresented: $showingReplaceConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingBackup = nil
                }
                Button("Replace", role: .destructive) {
                    if let backup = pendingBackup {
                        applyReplace(backup)
                    }
                    pendingBackup = nil
                }
            } message: {
                Text("This permanently deletes every tour, template, snippet, and setting currently in the app, replacing them with the contents of the backup file. This can't be undone.")
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        successMessage = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let backup = try BackupService.readBackup(from: url)
                if replaceExisting {
                    pendingBackup = backup
                    showingReplaceConfirmation = true
                } else {
                    applyMerge(backup)
                }
            } catch {
                errorMessage = "Couldn't read that file: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func applyReplace(_ backup: AppBackup) {
        let tours = TourPhotoStore.restoreGroupPhotos(into: backup.tours, from: backup.tourPhotos)
        tourStore.replaceAllTours(with: tours)
        templateStore.replaceAllTemplates(with: backup.templates)
        templateStore.replaceAllSnippets(with: backup.snippets)
        settingsStore.replaceSettings(with: backup.settings)
        successMessage = "Replaced all data with the backup (\(backup.tours.count) tour\(backup.tours.count == 1 ? "" : "s"))."
    }

    private func applyMerge(_ backup: AppBackup) {
        let tours = TourPhotoStore.restoreGroupPhotos(into: backup.tours, from: backup.tourPhotos)
        tourStore.mergeTours(tours)
        templateStore.mergeTemplates(backup.templates)
        templateStore.mergeSnippets(backup.snippets)
        successMessage = "Merged \(backup.tours.count) tour\(backup.tours.count == 1 ? "" : "s"), \(backup.templates.count) template\(backup.templates.count == 1 ? "" : "s"), and \(backup.snippets.count) snippet\(backup.snippets.count == 1 ? "" : "s")."
    }
}

#Preview {
    BackupImportView()
        .environmentObject(TourStore())
        .environmentObject(TemplateStore())
        .environmentObject(SettingsStore())
}
