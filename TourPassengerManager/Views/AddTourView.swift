import SwiftUI

struct AddTourView: View {
    @EnvironmentObject var store: TourStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var hasDates = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var townTourTime = ""
    @State private var prefillSourceCode: String?

    /// The most recently scheduled existing tour (by end date, falling back to
    /// start date), used as the basis for predicting the next tour's code and
    /// start date. Tours with no dates at all are ignored for this purpose.
    private var mostRecentTour: Tour? {
        store.tours
            .filter { $0.endDate != nil || $0.startDate != nil }
            .max { a, b in
                let dateA = a.endDate ?? a.startDate ?? .distantPast
                let dateB = b.endDate ?? b.startDate ?? .distantPast
                return dateA < dateB
            }
    }

    private func prefillFromPreviousTour() {
        guard let previous = mostRecentTour else { return }

        if let suggestedCode = Tour.incrementedCode(from: previous.code) {
            code = suggestedCode
            prefillSourceCode = previous.code
        }

        if let previousEnd = previous.endDate,
           let predictedStart = Tour.predictedNextStartDate(afterPreviousEndDate: previousEnd) {
            startDate = predictedStart
            endDate = Tour.defaultEndDate(from: predictedStart)
            hasDates = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. RCE2609", text: $code)
                } header: {
                    Text("Tour Code")
                } footer: {
                    if let prefillSourceCode {
                        Text("Suggested by incrementing the previous tour's code (\(prefillSourceCode)). The tour's product name is set once for all tours in Settings.")
                    } else {
                        Text("How this tour is identified in the tours list — e.g. a booking or departure code. The tour's product name is set once for all tours in Settings.")
                    }
                }
                Section {
                    Toggle("Set dates", isOn: $hasDates.animation())
                        .onChange(of: hasDates) { _, newValue in
                            if newValue {
                                endDate = Tour.defaultEndDate(from: startDate)
                            }
                        }
                    if hasDates {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            .onChange(of: startDate) { _, newValue in
                                endDate = Tour.defaultEndDate(from: newValue)
                            }
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } footer: {
                    if hasDates {
                        Text("End date defaults to 7 days after the start date — adjust it if the tour runs a different length. Dates also determine where this tour appears in the tours list (current, upcoming, or past).")
                    }
                }
                Section {
                    TextField("e.g. 2:00 PM", text: $townTourTime)
                } header: {
                    Text("Town Tour Time")
                } footer: {
                    Text("Optional — can also be set or changed later from the info icon inside the tour.")
                }
            }
            .navigationTitle("New Tour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var tour = Tour(code: code.trimmingCharacters(in: .whitespaces))
                        if hasDates {
                            tour.startDate = startDate
                            tour.endDate = endDate
                        }
                        tour.townTourTime = townTourTime
                        store.addTour(tour)
                        dismiss()
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                prefillFromPreviousTour()
            }
        }
    }
}

#Preview {
    AddTourView()
        .environmentObject(TourStore())
}
