import SwiftUI

/// A swipeable, paged view through a tour's passengers, starting at
/// `initialPassengerID`. Built on `TabView(.page)` — Apple's native horizontal
/// paging container — rather than a hand-rolled drag gesture, so adjacent
/// passengers' cards are genuinely already laid out and visible peeking in from
/// the edges as you drag, not just a same-card animation that starts after you
/// release.
struct PassengerDetailView: View {
    @Binding var tour: Tour
    let orderedPassengerIDs: [UUID]
    var onDelete: (Passenger) -> Void

    @State private var currentPassengerID: UUID
    @State private var isEditing = false
    @Environment(\.dismiss) private var dismiss

    init(tour: Binding<Tour>, orderedPassengerIDs: [UUID], initialPassengerID: UUID, onDelete: @escaping (Passenger) -> Void) {
        self._tour = tour
        self.orderedPassengerIDs = orderedPassengerIDs
        self._currentPassengerID = State(initialValue: initialPassengerID)
        self.onDelete = onDelete
    }

    var body: some View {
        TabView(selection: $currentPassengerID) {
            ForEach(orderedPassengerIDs, id: \.self) { id in
                if let index = tour.passengers.firstIndex(where: { $0.id == id }) {
                    PassengerCardView(
                        tour: $tour,
                        passenger: $tour.passengers[index],
                        isEditing: $isEditing,
                        onDelete: {
                            onDelete(tour.passengers[index])
                            dismiss()
                        }
                    )
                    .tag(id)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentPassengerDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(orderedPassengerIDs.count > 1)
        .toolbar {
            if orderedPassengerIDs.count > 1 {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
            }
            if orderedPassengerIDs.count > 1 {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        goToPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoPrevious)

                    Spacer()

                    if let index = currentOrderedIndex {
                        Text("\(index + 1) of \(orderedPassengerIDs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        goToNext()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoNext)
                }
            }
        }
        .onChange(of: currentPassengerID) { _, _ in
            // Edit mode is scoped to whichever passenger you were looking at —
            // moving to a different one (by swipe or by button) always starts
            // that passenger in read-only mode, never mid-edit by surprise.
            isEditing = false
        }
    }

    private var currentPassengerDisplayName: String {
        tour.passengers.first(where: { $0.id == currentPassengerID })?.displayName ?? ""
    }

    private var currentOrderedIndex: Int? {
        orderedPassengerIDs.firstIndex(of: currentPassengerID)
    }

    private var canGoPrevious: Bool {
        guard let index = currentOrderedIndex else { return false }
        return index > 0
    }

    private var canGoNext: Bool {
        guard let index = currentOrderedIndex else { return false }
        return index < orderedPassengerIDs.count - 1
    }

    private func goToPrevious() {
        guard canGoPrevious, let index = currentOrderedIndex else { return }
        withAnimation {
            currentPassengerID = orderedPassengerIDs[index - 1]
        }
    }

    private func goToNext() {
        guard canGoNext, let index = currentOrderedIndex else { return }
        withAnimation {
            currentPassengerID = orderedPassengerIDs[index + 1]
        }
    }
}

#Preview {
    let janie = Passenger(surname: "Doe", firstName: "Jane", preferredName: "Janie", bookingNumber: "BK1001")
    let john = Passenger(surname: "Smith", firstName: "John", bookingNumber: "BK1002")
    return NavigationStack {
        PassengerDetailView(
            tour: .constant(Tour(code: "Sample Tour", passengers: [janie, john])),
            orderedPassengerIDs: [janie.id, john.id],
            initialPassengerID: janie.id,
            onDelete: { _ in }
        )
    }
}
