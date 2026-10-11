import SwiftUI
import UIKit

// MARK: - Face thumbnail

/// A small round thumbnail of one face, cropped from the tour's group photo. Used next
/// to passengers in the roster and inside the tagging sheet.
struct FaceThumbnailView: View {
    let photoFilename: String
    let face: PhotoFace
    var size: CGFloat = 44

    @State private var image: UIImage?

    init(photoFilename: String, face: PhotoFace, size: CGFloat = 44) {
        self.photoFilename = photoFilename
        self.face = face
        self.size = size
        // Seed from the in-memory cache so a row scrolling back into view doesn't flash.
        _image = State(initialValue: TourPhotoStore.cachedFaceThumbnail(photoNamed: photoFilename, face: face))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemFill))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .task(id: photoFilename + face.id.uuidString) {
            image = await TourPhotoStore.faceThumbnail(photoNamed: photoFilename, face: face)
        }
    }
}

// MARK: - Assignment sheet

/// "Who is this?" — shown when a face box is tapped in the full-screen photo viewer.
/// Pick a passenger from the tour to tag the face as them, change or remove an
/// existing tag, or delete the box if it isn't really a face.
struct FaceAssignmentSheet: View {
    @Binding var tour: Tour
    let photoID: UUID
    let faceID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var untaggedOnly = false

    private var photo: TourGroupPhoto? {
        tour.groupPhotos.first { $0.id == photoID }
    }

    private var photoFilename: String? {
        photo?.filename
    }

    private var face: PhotoFace? {
        photo?.faces?.first { $0.id == faceID }
    }

    /// The passenger currently tagged on this face, if they still exist on the tour.
    private var currentPassenger: Passenger? {
        guard let id = face?.passengerID else { return nil }
        return tour.passengers.first { $0.id == id }
    }

    /// Every tagged face across every one of the tour's photos, keyed by the passenger
    /// it's tagged as — a passenger can only be tagged to one face across the whole tour.
    private var facesByPassenger: [UUID: PassengerFace] {
        var result: [UUID: PassengerFace] = [:]
        for photo in tour.groupPhotos {
            for face in photo.faces ?? [] {
                if let id = face.passengerID {
                    result[id] = PassengerFace(photoFilename: photo.filename, face: face)
                }
            }
        }
        return result
    }

    private var candidates: [Passenger] {
        let tagged = facesByPassenger
        let currentID = currentPassenger?.id
        var result: [Passenger] = []

        for passenger in tour.passengers {
            if untaggedOnly, passenger.id != currentID, tagged[passenger.id] != nil {
                continue
            }
            if !searchText.isEmpty {
                let matches = passenger.displayName.localizedCaseInsensitiveContains(searchText)
                    || passenger.preferredName.localizedCaseInsensitiveContains(searchText)
                if !matches { continue }
            }
            result.append(passenger)
        }

        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var bookedCandidates: [Passenger] {
        candidates.filter { !$0.isCrew }
    }

    /// Crew (no booking number) can be tagged in the photo just like passengers.
    private var crewCandidates: [Passenger] {
        candidates.filter { $0.isCrew }
    }

    var body: some View {
        NavigationStack {
            List {
                if let face, let photoFilename {
                    Section {
                        HStack(spacing: 16) {
                            FaceThumbnailView(photoFilename: photoFilename, face: face, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentPassenger?.displayName ?? "Not tagged yet")
                                    .font(.headline)
                                Text(currentPassenger == nil
                                     ? "Choose who this is from the list below."
                                     : "Choose someone else below to change it.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if tour.passengers.isEmpty {
                    ContentUnavailableView(
                        "No Passengers",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Add or import passengers first, then tag their faces.")
                    )
                } else {
                    Section {
                        Toggle("Only show untagged people", isOn: $untaggedOnly)

                        ForEach(bookedCandidates) { passenger in
                            passengerButton(passenger)
                        }
                    } header: {
                        Text("Passengers")
                    }

                    if !crewCandidates.isEmpty {
                        Section {
                            ForEach(crewCandidates) { passenger in
                                passengerButton(passenger)
                            }
                        } header: {
                            Text("Crew")
                        }
                    }
                }

                if face != nil {
                    Section {
                        if currentPassenger != nil {
                            Button("Remove Tag") {
                                tour.assignPassenger(nil, toFace: faceID)
                                dismiss()
                            }
                        }
                        Button("Delete This Face Box", role: .destructive) {
                            tour.removeFace(faceID)
                            dismiss()
                        }
                    } footer: {
                        Text("Delete the box if it isn't actually a face.")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search passengers")
            .navigationTitle("Who is this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func passengerButton(_ passenger: Passenger) -> some View {
        let existingFace = facesByPassenger[passenger.id]
        let isCurrent = passenger.id == currentPassenger?.id

        Button {
            tour.assignPassenger(passenger.id, toFace: faceID)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                if let existingFace {
                    FaceThumbnailView(photoFilename: existingFace.photoFilename, face: existingFace.face, size: 32)
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(passenger.displayName)
                        .foregroundStyle(.primary)
                    if existingFace != nil, !isCurrent {
                        Text("Already tagged — choosing them moves the tag to this face")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}
