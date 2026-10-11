import SwiftUI
import PhotosUI

struct TourDetailsView: View {
    @Binding var tour: Tour
    @Environment(\.dismiss) private var dismiss

    @State private var hasDates: Bool
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isSavingPhoto = false
    @State private var photoErrorMessage: String?

    init(tour: Binding<Tour>) {
        _tour = tour
        _hasDates = State(initialValue: tour.wrappedValue.startDate != nil)
    }

    /// How many more photos this tour can have.
    private var remainingPhotoSlots: Int {
        max(0, Tour.maxGroupPhotos - tour.groupPhotos.count)
    }

    /// Loads each picked photo in turn, downsizes/saves it to disk and scans it for
    /// faces (both off the main thread), then appends it — stopping early if the tour
    /// reaches its photo limit partway through a multi-photo pick.
    @MainActor
    private func importGroupPhotos(from items: [PhotosPickerItem]) async {
        isSavingPhoto = true
        defer {
            isSavingPhoto = false
            photoItems = []
        }

        for item in items {
            guard tour.groupPhotos.count < Tour.maxGroupPhotos else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw TourPhotoStore.PhotoError.unreadableImage
                }
                let filename = try await TourPhotoStore.saveGroupPhoto(from: data, forTourID: tour.id)
                // Find the faces in the new photo. (nil if the scan couldn't run; the
                // full-screen viewer will simply try again when it's opened.)
                let detectedFaces = await FaceDetectionService.detectFaces(inPhotoNamed: filename)
                tour.groupPhotos.append(TourGroupPhoto(filename: filename, faces: detectedFaces))
            } catch {
                photoErrorMessage = error.localizedDescription
            }
        }
    }

    private func removeGroupPhoto(_ photo: TourGroupPhoto) {
        tour.groupPhotos.removeAll { $0.id == photo.id }
        TourPhotoStore.delete(filename: photo.filename)
    }

    /// "12 of 38 faces tagged", or a scan-status message, for a photo's subtitle.
    private func faceSummary(for photo: TourGroupPhoto) -> String {
        guard let faces = photo.faces else { return "Not scanned for faces yet" }
        if faces.isEmpty { return "No faces found" }
        let passengerIDs = Set(tour.passengers.map { $0.id })
        let tagged = faces.filter { face in
            guard let id = face.passengerID else { return false }
            return passengerIDs.contains(id)
        }.count
        return "\(tagged) of \(faces.count) faces tagged"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. RCE2609", text: $tour.code)
                } header: {
                    Text("Tour Code")
                } footer: {
                    Text("How this tour is identified in the tours list. Used in SMS templates via {TourCode}.")
                }

                Section {
                    Toggle("Set dates", isOn: $hasDates.animation())
                        .onChange(of: hasDates) { _, newValue in
                            if !newValue {
                                tour.startDate = nil
                                tour.endDate = nil
                            } else if tour.startDate == nil {
                                let start = Date()
                                tour.startDate = start
                                tour.endDate = Tour.defaultEndDate(from: start)
                            }
                        }

                    if hasDates {
                        DatePicker(
                            "Start",
                            selection: Binding(
                                get: { tour.startDate ?? Date() },
                                set: { newValue in
                                    tour.startDate = newValue
                                    tour.endDate = Tour.defaultEndDate(from: newValue)
                                }
                            ),
                            displayedComponents: .date
                        )
                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { tour.endDate ?? tour.startDate ?? Date() },
                                set: { tour.endDate = $0 }
                            ),
                            in: (tour.startDate ?? Date())...,
                            displayedComponents: .date
                        )
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    if hasDates {
                        Text("Changing the start date resets the end date to 7 days later — adjust it afterward if the tour runs a different length.")
                    }
                }

                Section {
                    TextField("e.g. 2:00 PM", text: $tour.townTourTime)
                } header: {
                    Text("Town Tour Time")
                } footer: {
                    Text("Used in SMS templates via {TownTourTime}.")
                }

                Section {
                    ForEach(tour.groupPhotos) { photo in
                        HStack(spacing: 12) {
                            GroupPhotoThumbnail(filename: photo.filename)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(faceSummary(for: photo))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(role: .destructive) {
                                removeGroupPhoto(photo)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(isSavingPhoto)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    if remainingPhotoSlots > 0 {
                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: remainingPhotoSlots,
                            matching: .images
                        ) {
                            HStack {
                                Label(
                                    tour.groupPhotos.isEmpty ? "Choose Group Photo" : "Add Another Group Photo",
                                    systemImage: "photo.badge.plus"
                                )
                                Spacer()
                                if isSavingPhoto {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSavingPhoto)
                    }
                } header: {
                    Text("Group Photos (\(tour.groupPhotos.count) of \(Tour.maxGroupPhotos))")
                } footer: {
                    Text("Shown at the top of this tour's passenger list. Add up to \(Tour.maxGroupPhotos) photos for full coverage of a large group — faces are found automatically in each. Tap a photo there to view it full screen, zoom in, and tag each face with a passenger. Removing a photo clears its face tags.")
                }
            }
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await importGroupPhotos(from: newItems) }
            }
            .alert(
                "Couldn't Add Photo",
                isPresented: Binding(
                    get: { photoErrorMessage != nil },
                    set: { if !$0 { photoErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoErrorMessage ?? "")
            }
            .navigationTitle("Tour Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    TourDetailsView(tour: .constant(Tour(code: "Sample Tour", startDate: Date())))
}
