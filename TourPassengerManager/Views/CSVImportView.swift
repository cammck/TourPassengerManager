import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Binding var tour: Tour
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var replaceExisting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose a CSV file with a header row matching your manifest: Surname, Firstname, Preferred Name, Combined Name, Yayes Lunch, Dietary Requirements, Manifest Medical Condition, Home Number, Mobile Number, Address, Email, Emergency Contact Name, Emergency Contact Number, Booking Number, JBR Booking Number, Room Type, Explorer Pack, Pickup Details, Pickup Flight Number, Pickup Flight Origin, Dropoff Details, Dropoff Flight Number, Dropoff Flight Destination, Weight. A Surname (or Combined Name) column is required; the rest are optional. Pickup Details and Dropoff Details (e.g. \"Downtown Hotel 7:30am\") are automatically split into separate location and time fields; the flight columns only need values when a pickup/dropoff involves a flight.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Replace existing roster", isOn: $replaceExisting)
                    Text(replaceExisting
                         ? "This tour's current roster will be cleared before importing."
                         : "New passengers will be added; existing names will be skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Choose CSV File", systemImage: "doc.badge.plus")
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
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
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
                let countBefore = tour.passengers.count
                let text = try readCSVText(from: url)
                let imported = try CSVParser.parsePassengers(from: text)
                let previousPassengers = tour.passengers
                tour.passengers = CSVParser.merge(imported: imported, into: tour.passengers, replaceExisting: replaceExisting)
                if replaceExisting {
                    // Re-imported passengers get new internal IDs; keep their face tags.
                    tour.remapFaceTags(from: previousPassengers, to: tour.passengers)
                }
                let countAfter = tour.passengers.count
                let added = replaceExisting ? countAfter : (countAfter - countBefore)
                successMessage = "Imported \(added) passenger\(added == 1 ? "" : "s")."
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func readCSVText(from url: URL) throws -> String {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CSVParserError.emptyFile
        }
        return text
    }
}

#Preview {
    CSVImportView(tour: .constant(Tour(code: "Sample Tour")))
}
