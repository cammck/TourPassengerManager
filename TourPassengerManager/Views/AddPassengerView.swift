import SwiftUI

struct AddPassengerView: View {
    @Binding var tour: Tour
    @Environment(\.dismiss) private var dismiss

    @State private var surname = ""
    @State private var firstName = ""
    @State private var preferredName = ""
    @State private var mobileNumber = ""
    @State private var email = ""
    @State private var dietaryRequirements = ""
    @State private var medicalCondition = ""
    @State private var emergencyContactName = ""
    @State private var emergencyContactNumber = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Surname", text: $surname)
                    TextField("First Name", text: $firstName)
                    TextField("Preferred Name", text: $preferredName)
                }
                Section("Contact") {
                    TextField("Mobile", text: $mobileNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                Section("Emergency Contact") {
                    TextField("Name", text: $emergencyContactName)
                    TextField("Number", text: $emergencyContactNumber)
                        .keyboardType(.phonePad)
                }
                Section("Catering & Welfare") {
                    TextField("Dietary Requirements", text: $dietaryRequirements)
                    TextField("Manifest Medical Condition", text: $medicalCondition)
                }
                Section {
                    Text("Booking, room, and pickup/dropoff details can be added afterwards from the passenger's detail screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Passenger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var passenger = Passenger()
                        passenger.surname = surname
                        passenger.firstName = firstName
                        passenger.preferredName = preferredName
                        passenger.mobileNumber = mobileNumber
                        passenger.email = email
                        passenger.dietaryRequirements = dietaryRequirements
                        passenger.medicalCondition = medicalCondition
                        passenger.emergencyContactName = emergencyContactName
                        passenger.emergencyContactNumber = emergencyContactNumber
                        tour.passengers.append(passenger)
                        dismiss()
                    }
                    .disabled(surname.trimmingCharacters(in: .whitespaces).isEmpty &&
                              firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddPassengerView(tour: .constant(Tour(code: "Sample Tour")))
}
