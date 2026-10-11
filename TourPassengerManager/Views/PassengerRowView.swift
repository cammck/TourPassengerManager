import SwiftUI

struct PassengerRowView: View {
    let passenger: Passenger
    var isLinkedBooking: Bool = false
    var bookingColor: Color? = nil
    /// This passenger's face, tagged on the tour's group photo (if it has been).
    var passengerFace: PassengerFace? = nil
    /// When some passengers have faces tagged, untagged ones show a blank placeholder
    /// so every name in the list lines up.
    var reservesFaceSlot: Bool = false

    private let faceSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(bookingColor ?? .clear)
                .frame(width: 4)

            if let passengerFace {
                FaceThumbnailView(
                    photoFilename: passengerFace.photoFilename,
                    face: passengerFace.face,
                    size: faceSize
                )
            } else if reservesFaceSlot {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: faceSize, height: faceSize)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(passenger.displayName)
                        .font(.body.weight(.medium))
                    if passenger.isCrew {
                        Text("CREW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.15), in: Capsule())
                    }
                    if isLinkedBooking {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                }
                HStack(spacing: 8) {
                    if !passenger.preferredName.isEmpty && passenger.preferredName != passenger.displayName {
                        Label(passenger.preferredName, systemImage: "person")
                    }
                    if !passenger.mobileNumber.isEmpty {
                        Label(passenger.mobileNumber, systemImage: "phone")
                    }
                    if !passenger.dietaryRequirements.isEmpty {
                        Label(passenger.dietaryRequirements, systemImage: "fork.knife")
                    }
                    if !passenger.medicalCondition.isEmpty {
                        Label("Medical", systemImage: "cross.case")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
