import SwiftUI
import UIKit

/// One passenger's editable detail form — a single "page" inside the TabView
/// paging container in PassengerDetailView. Bound directly into the tour's
/// passengers array by the parent, so edits save immediately with no separate
/// local-state-sync step, and multiple pages can be mounted at once (which is
/// what gives the native page-swipe its "peek at the next card" effect).
struct PassengerCardView: View {
    @Binding var tour: Tour
    @Binding var passenger: Passenger
    @Binding var isEditing: Bool
    var onDelete: () -> Void

    @State private var selectedBookingToLink: String?
    @State private var manualLinkEntry = ""
    @State private var showingAddressMap = false

    /// This passenger's face, tagged on the tour's group photo(s), if any.
    private var passengerFace: PassengerFace? {
        tour.taggedFace(for: passenger.id)
    }

    var body: some View {
        Form {
            if let passengerFace {
                Section {
                    HStack {
                        Spacer()
                        FaceThumbnailView(
                            photoFilename: passengerFace.photoFilename,
                            face: passengerFace.face,
                            size: 96
                        )
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if passenger.isCrew {
                Section {
                    Label("Crew", systemImage: "person.badge.shield.checkmark")
                        .foregroundStyle(.indigo)
                } footer: {
                    Text("No booking number, so this person is listed as crew. Add a Booking Number or JBR Booking Number to list them as a passenger.")
                }
            }

            Section("Name") {
                LabeledRow(title: "Surname", text: $passenger.surname, isEditing: isEditing)
                LabeledRow(title: "First Name", text: $passenger.firstName, isEditing: isEditing)
                LabeledRow(title: "Preferred Name", text: $passenger.preferredName, isEditing: isEditing)
                LabeledRow(title: "Combined Name", text: $passenger.combinedName, isEditing: isEditing)
            }

            Section("Contact") {
                PhoneActionRow(title: "Mobile", text: $passenger.mobileNumber, isEditing: isEditing)
                PhoneActionRow(title: "Home Number", text: $passenger.homeNumber, isEditing: isEditing)
                EmailActionRow(title: "Email", text: $passenger.email, isEditing: isEditing)
                AddressActionRow(text: $passenger.address, isEditing: isEditing, isTappable: !passenger.isCrew) {
                    showingAddressMap = true
                }
            }

            Section("Emergency Contact") {
                LabeledRow(title: "Name", text: $passenger.emergencyContactName, isEditing: isEditing)
                PhoneActionRow(title: "Number", text: $passenger.emergencyContactNumber, isEditing: isEditing)
            }

            Section("Booking & Logistics") {
                LabeledRow(title: "Booking Number", text: $passenger.bookingNumber, isEditing: isEditing)
                LabeledRow(title: "JBR Booking Number", text: $passenger.jbrBookingNumber, isEditing: isEditing)
                LabeledRow(title: "Room Type", text: $passenger.roomType, isEditing: isEditing)
                LabeledRow(title: "Explorer Pack", text: $passenger.explorerPack, isEditing: isEditing)
                LabeledRow(title: "Pickup Location", text: $passenger.pickupLocation, isEditing: isEditing)
                LabeledRow(title: "Pickup Time", text: $passenger.pickupTime, isEditing: isEditing)
                LabeledRow(title: "Pickup Flight Number", text: $passenger.pickupFlightNumber, isEditing: isEditing)
                LabeledRow(title: "Pickup Flight Origin", text: $passenger.pickupFlightOrigin, isEditing: isEditing)
                LabeledRow(title: "Dropoff Location", text: $passenger.dropoffLocation, isEditing: isEditing)
                LabeledRow(title: "Dropoff Time", text: $passenger.dropoffTime, isEditing: isEditing)
                LabeledRow(title: "Dropoff Flight Number", text: $passenger.dropoffFlightNumber, isEditing: isEditing)
                LabeledRow(title: "Dropoff Flight Destination", text: $passenger.dropoffFlightDestination, isEditing: isEditing)
                LabeledRow(title: "Weight", text: $passenger.weight, isEditing: isEditing, keyboard: .decimalPad)
            }

            Section {
                if passenger.bookingNumber.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Add a Booking Number above to link this booking with others.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if linkedBookingNumbers.isEmpty && !isEditing {
                    Text("No related bookings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linkedBookingNumbers, id: \.self) { number in
                        HStack {
                            Text(number)
                            if isEditing {
                                Spacer()
                                Button(role: .destructive) {
                                    unlink(number)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if isEditing {
                        if !otherBookingNumbers.isEmpty {
                            Picker("Link to booking", selection: $selectedBookingToLink) {
                                Text("Choose a booking number").tag(String?.none)
                                ForEach(otherBookingNumbers, id: \.self) { number in
                                    Text(number).tag(Optional(number))
                                }
                            }
                            .onChange(of: selectedBookingToLink) { _, newValue in
                                if let newValue {
                                    link(newValue)
                                }
                            }
                        }
                        HStack {
                            TextField("Or type a booking number", text: $manualLinkEntry)
                            Button("Link") {
                                link(manualLinkEntry)
                                manualLinkEntry = ""
                            }
                            .disabled(manualLinkEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            } header: {
                Text("Related Bookings")
            } footer: {
                Text("Linked bookings are listed and grouped together throughout the roster, in every view, separated from other bookings by a divider.")
            }

            Section("Catering & Welfare") {
                LabeledRow(title: "Yayes Lunch", text: $passenger.lunch, isEditing: isEditing)
                LabeledRow(title: "Dietary Requirements", text: $passenger.dietaryRequirements, isEditing: isEditing)
                if isEditing {
                    VStack(alignment: .leading) {
                        Text("Manifest Medical Condition")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $passenger.medicalCondition)
                            .frame(minHeight: 60)
                    }
                } else {
                    HStack {
                        Text("Manifest Medical Condition")
                        Spacer()
                        Text(passenger.medicalCondition.isEmpty ? "—" : passenger.medicalCondition)
                            .foregroundStyle(passenger.medicalCondition.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Staff Notes") {
                if isEditing {
                    TextEditor(text: $passenger.staffNotes)
                        .frame(minHeight: 80)
                } else {
                    Text(passenger.staffNotes.isEmpty ? "No notes" : passenger.staffNotes)
                        .foregroundStyle(passenger.staffNotes.isEmpty ? .secondary : .primary)
                }
            }

            if isEditing {
                Section {
                    Button("Delete Passenger", role: .destructive) {
                        onDelete()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddressMap) {
            PassengerAddressMapView(tour: $tour, focusedPassengerID: passenger.id)
        }
    }

    /// Distinct booking numbers in this tour, excluding the current passenger's own.
    private var otherBookingNumbers: [String] {
        let trimmed = passenger.bookingNumber.trimmingCharacters(in: .whitespaces)
        let all = Set(tour.passengers.map { $0.bookingNumber.trimmingCharacters(in: .whitespaces) })
            .subtracting([trimmed, ""])
        return all.sorted()
    }

    /// Every other booking number related to this passenger's booking, via any
    /// link group it belongs to.
    private var linkedBookingNumbers: [String] {
        let current = passenger.bookingNumber.trimmingCharacters(in: .whitespaces)
        guard !current.isEmpty else { return [] }

        var related: Set<String> = []
        for link in tour.bookingLinks where link.bookingNumbers.contains(current) {
            related.formUnion(link.bookingNumbers)
        }
        related.remove(current)
        return related.sorted()
    }

    /// Links this passenger's booking number with another, merging into an
    /// existing link group if either booking number is already part of one.
    private func link(_ other: String) {
        let a = passenger.bookingNumber.trimmingCharacters(in: .whitespaces)
        let b = other.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, !b.isEmpty, a != b else { return }

        let matchingIndices = tour.bookingLinks.indices.filter {
            tour.bookingLinks[$0].bookingNumbers.contains(a) || tour.bookingLinks[$0].bookingNumbers.contains(b)
        }

        if matchingIndices.isEmpty {
            tour.bookingLinks.append(BookingLink(bookingNumbers: [a, b]))
        } else {
            let first = matchingIndices[0]
            for idx in matchingIndices.dropFirst() {
                tour.bookingLinks[first].bookingNumbers.formUnion(tour.bookingLinks[idx].bookingNumbers)
            }
            tour.bookingLinks[first].bookingNumbers.insert(a)
            tour.bookingLinks[first].bookingNumbers.insert(b)
            for idx in matchingIndices.dropFirst().sorted(by: >) {
                tour.bookingLinks.remove(at: idx)
            }
        }

        selectedBookingToLink = nil
    }

    /// Removes just `other` from this booking's link group (not the whole group).
    private func unlink(_ other: String) {
        let current = passenger.bookingNumber.trimmingCharacters(in: .whitespaces)
        for idx in tour.bookingLinks.indices.reversed() where tour.bookingLinks[idx].bookingNumbers.contains(current) {
            tour.bookingLinks[idx].bookingNumbers.remove(other)
            if tour.bookingLinks[idx].bookingNumbers.count <= 1 {
                tour.bookingLinks.remove(at: idx)
            }
        }
    }
}

/// A row that shows either static text or a text field depending on edit mode.
private struct LabeledRow: View {
    let title: String
    @Binding var text: String
    let isEditing: Bool
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isEditing {
                TextField(title, text: $text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
            } else {
                Text(text.isEmpty ? "—" : text)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
            }
        }
    }
}

/// A row for the Address field. While editing, behaves like any other text field.
/// Otherwise, if an address is on file AND `isTappable` (crew are excluded from
/// the map entirely, so their address — if they somehow have one on file — is
/// never tappable, since there's no pin for it to open), tapping it opens the
/// Passenger Map, zoomed in on this passenger's own pin.
private struct AddressActionRow: View {
    @Binding var text: String
    let isEditing: Bool
    var isTappable: Bool = true
    var onTap: () -> Void

    var body: some View {
        HStack {
            Text("Address")
            Spacer()
            if isEditing {
                TextField("Address", text: $text)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
            } else if text.trimmingCharacters(in: .whitespaces).isEmpty || !isTappable {
                Text(text.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : text)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                Button(action: onTap) {
                    Text(text)
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

/// A row for a phone number. While editing, behaves like any other text field.
/// Otherwise, tapping the number offers a quick Call or Message action —
/// ad hoc, no template involved.
private struct PhoneActionRow: View {
    let title: String
    @Binding var text: String
    let isEditing: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isEditing {
                TextField(title, text: $text)
                    .keyboardType(.phonePad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
            } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Button {
                        open(scheme: "tel", value: text)
                    } label: {
                        Label("Call \(text)", systemImage: "phone")
                    }
                    Button {
                        open(scheme: "sms", value: text)
                    } label: {
                        Label("Message \(text)", systemImage: "message")
                    }
                } label: {
                    Text(text)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func open(scheme: String, value: String) {
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let cleaned = String(value.unicodeScalars.filter { allowed.contains($0) })
        guard !cleaned.isEmpty, let url = URL(string: "\(scheme):\(cleaned)") else { return }
        UIApplication.shared.open(url)
    }
}

/// A row for an email address. While editing, behaves like any other text field.
/// Otherwise, tapping the address opens Mail with a blank compose to that
/// recipient — ad hoc, no template involved.
private struct EmailActionRow: View {
    let title: String
    @Binding var text: String
    let isEditing: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isEditing {
                TextField(title, text: $text)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
            } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                          let url = URL(string: "mailto:\(encoded)") else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Text(text)
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

#Preview {
    PassengerCardView(
        tour: .constant(Tour(code: "Sample Tour", passengers: [Passenger(surname: "Doe", firstName: "Jane")])),
        passenger: .constant(Passenger(surname: "Doe", firstName: "Jane", preferredName: "Janie")),
        isEditing: .constant(false),
        onDelete: {}
    )
}
