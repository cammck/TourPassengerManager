import SwiftUI

/// Searches passenger details across every tour at once, rather than within a
/// single tour's roster (that's PassengerListView's own `.searchable`). Each
/// result shows which tour it came from, and tapping one goes straight to that
/// passenger's detail screen.
struct GlobalPassengerSearchView: View {
    @EnvironmentObject private var tourStore: TourStore
    @State private var searchText = ""

    private struct SearchResult: Identifiable {
        let tour: Tour
        let passenger: Passenger
        var id: UUID { passenger.id }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var results: [SearchResult] {
        guard !trimmedQuery.isEmpty else { return [] }

        var matches: [SearchResult] = []
        for tour in tourStore.tours {
            for passenger in tour.passengers where passengerMatches(passenger) {
                matches.append(SearchResult(tour: tour, passenger: passenger))
            }
        }
        return matches.sorted {
            if $0.passenger.isCrew != $1.passenger.isCrew { return !$0.passenger.isCrew }
            return $0.passenger.displayName.localizedCaseInsensitiveCompare($1.passenger.displayName) == .orderedAscending
        }
    }

    private func passengerMatches(_ passenger: Passenger) -> Bool {
        passenger.displayName.localizedCaseInsensitiveContains(trimmedQuery) ||
        passenger.preferredName.localizedCaseInsensitiveContains(trimmedQuery) ||
        passenger.email.localizedCaseInsensitiveContains(trimmedQuery) ||
        passenger.mobileNumber.localizedCaseInsensitiveContains(trimmedQuery) ||
        passenger.bookingNumber.localizedCaseInsensitiveContains(trimmedQuery) ||
        passenger.roomType.localizedCaseInsensitiveContains(trimmedQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        "Search All Tours",
                        systemImage: "magnifyingglass",
                        description: Text("Search by name, email, mobile number, booking number, or room type across every tour at once.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("No passengers found matching \"\(searchText)\" in any tour.")
                    )
                } else {
                    ForEach(results) { result in
                        NavigationLink {
                            PassengerDetailView(
                                tour: tourStore.binding(for: result.tour.id),
                                orderedPassengerIDs: orderedIDs(for: result.tour),
                                initialPassengerID: result.passenger.id,
                                onDelete: { deleted in
                                    tourStore.binding(for: result.tour.id).wrappedValue.passengers.removeAll { $0.id == deleted.id }
                                }
                            )
                        } label: {
                            resultRow(result)
                        }
                    }
                }
            }
            .navigationTitle("Search All Tours")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Name, email, mobile, booking #, room")
        }
    }

    @ViewBuilder
    private func resultRow(_ result: SearchResult) -> some View {
        HStack(spacing: 10) {
            if let face = result.tour.taggedFace(for: result.passenger.id) {
                FaceThumbnailView(photoFilename: face.photoFilename, face: face.face, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.passenger.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(result.tour.code.isEmpty ? "No Code" : result.tour.code)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue, in: Capsule())
                        .fixedSize()
                        .layoutPriority(1)
                }
                HStack(spacing: 8) {
                    if !result.passenger.preferredName.isEmpty && result.passenger.preferredName != result.passenger.displayName {
                        Label(result.passenger.preferredName, systemImage: "person")
                    }
                    if !result.passenger.mobileNumber.isEmpty {
                        Label(result.passenger.mobileNumber, systemImage: "phone")
                    }
                    if !result.passenger.email.isEmpty {
                        Label(result.passenger.email, systemImage: "envelope")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    /// A simple alphabetical order for the matched tour's full roster, used so
    /// swiping from a search result still lets you page through that tour's other
    /// passengers. Deliberately not the booking-cluster-aware ordering
    /// PassengerListView uses for its own roster view — arriving via search is a
    /// different enough context that a plain alphabetical fallback is reasonable.
    private func orderedIDs(for tour: Tour) -> [UUID] {
        tour.passengers
            .sorted {
                if $0.isCrew != $1.isCrew { return !$0.isCrew }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .map { $0.id }
    }
}

#Preview {
    GlobalPassengerSearchView()
        .environmentObject(TourStore())
}
