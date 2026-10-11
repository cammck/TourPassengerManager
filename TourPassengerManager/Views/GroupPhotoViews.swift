import SwiftUI
import UIKit

// MARK: - Thumbnail

/// Loads a tour's stored group photo (as a screen-sized thumbnail, off the main
/// thread) and shows it filling a fixed aspect ratio (so several sit evenly side by
/// side when a tour has more than one photo). Shows a spinner while loading and a
/// placeholder icon if the file can't be read.
struct GroupPhotoThumbnail: View {
    let filename: String

    @State private var image: UIImage?
    @State private var loadFailed = false

    init(filename: String) {
        self.filename = filename
        // Seed from the in-memory cache so a row scrolling back into view doesn't flash.
        _image = State(initialValue: TourPhotoStore.cachedThumbnail(named: filename))
    }

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if loadFailed {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: filename) {
                let loaded = await TourPhotoStore.thumbnail(named: filename)
                image = loaded
                loadFailed = (loaded == nil)
            }
    }
}

/// Proposes a fixed fraction of the available width to its single child and centers
/// it, so the child (an image, here) picks its own height from its aspect ratio.
/// Used instead of a GeometryReader, which collapses to zero height inside a List row.
private struct FractionalWidthLayout: Layout {
    var fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let containerWidth = proposal.width ?? subview.sizeThatFits(.unspecified).width
        let child = subview.sizeThatFits(ProposedViewSize(width: containerWidth * fraction, height: nil))
        return CGSize(width: containerWidth, height: child.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let childWidth = bounds.width * fraction
        let child = subview.sizeThatFits(ProposedViewSize(width: childWidth, height: nil))
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.minY),
            anchor: .top,
            proposal: ProposedViewSize(width: childWidth, height: child.height)
        )
    }
}

/// The group photo(s) shown at the top of a tour's passenger list, together taking up
/// about three-quarters of the row's width, centered. A tour can have up to
/// `Tour.maxGroupPhotos` photos (for full coverage of a large group), shown side by
/// side; tapping one calls `onTap` with its index so the viewer can open on that photo.
struct GroupPhotoHeaderView: View {
    let photos: [TourGroupPhoto]
    let onTap: (Int) -> Void

    /// How much of the available width the photo(s) take up together.
    private let widthFraction: CGFloat = 0.75
    private let spacing: CGFloat = 6

    var body: some View {
        FractionalWidthLayout(fraction: widthFraction) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    GroupPhotoThumbnail(filename: photo.filename)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(index) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(photos.count > 1 ? "Group photo \(index + 1) of \(photos.count)" : "Group photo")
                        .accessibilityHint("Opens the photo full screen, where you can zoom and pan")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}

// MARK: - Full-screen viewer

/// Full-screen, pinch-to-zoom and pan viewer for a tour's group photos — swipe between
/// photos when the tour has more than one, each independently zoomable. Double-tap
/// toggles between fit-to-screen and a closer zoom.
///
/// Faces found by Vision are outlined on the current photo — orange until a passenger
/// is tagged, green once they are. Tap a face to choose who it is. Presented with
/// `.fullScreenCover`.
struct GroupPhotoViewerView: View {
    @Binding var tour: Tour

    init(tour: Binding<Tour>, initialIndex: Int = 0) {
        _tour = tour
        _selectedIndex = State(initialValue: initialIndex)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int
    @State private var loadedImages: [UUID: UIImage] = [:]
    @State private var failedPhotoIDs: Set<UUID> = []
    @State private var showFaces = true
    @State private var isAddingFace = false
    @State private var isScanning = false
    @State private var editingFace: FaceSelection?
    @State private var confirmingRescan = false

    private struct FaceSelection: Identifiable {
        var id: UUID { faceID }
        let photoID: UUID
        let faceID: UUID
    }

    // MARK: Derived state

    private var photos: [TourGroupPhoto] {
        tour.groupPhotos
    }

    private var currentPhoto: TourGroupPhoto? {
        photos.indices.contains(selectedIndex) ? photos[selectedIndex] : nil
    }

    private var currentFaces: [PhotoFace] {
        currentPhoto?.faces ?? []
    }

    private var currentTaggedCount: Int {
        let passengerIDs = Set(tour.passengers.map { $0.id })
        return currentFaces.filter { face in
            guard let id = face.passengerID else { return false }
            return passengerIDs.contains(id)
        }.count
    }

    private var title: String {
        tour.code.isEmpty ? "Group Photo" : tour.code
    }

    private func overlayItems(for photo: TourGroupPhoto) -> [FaceOverlayItem] {
        guard showFaces else { return [] }
        let passengerIDs = Set(tour.passengers.map { $0.id })
        return (photo.faces ?? []).map { face in
            var isTagged = false
            if let id = face.passengerID {
                isTagged = passengerIDs.contains(id)
            }
            return FaceOverlayItem(id: face.id, rect: face.rect, isTagged: isTagged)
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !photos.isEmpty {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        page(for: photo)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { statusPill }
        .preferredColorScheme(.dark)
        .sheet(item: $editingFace) { selection in
            FaceAssignmentSheet(tour: $tour, photoID: selection.photoID, faceID: selection.faceID)
        }
        .alert("Scan This Photo Again?", isPresented: $confirmingRescan) {
            Button("Cancel", role: .cancel) {}
            Button("Scan Again", role: .destructive) {
                if let photoID = currentPhoto?.id {
                    Task { await scanForFaces(photoID: photoID) }
                }
            }
        } message: {
            Text("This replaces every face box on this photo and clears its face tags.")
        }
        .task(id: photos.map { $0.filename }) {
            await loadAndScanAllIfNeeded()
        }
    }

    @ViewBuilder
    private func page(for photo: TourGroupPhoto) -> some View {
        if let image = loadedImages[photo.id] {
            ZoomableImageView(
                image: image,
                faces: overlayItems(for: photo),
                onFaceTap: { faceID in
                    if !isAddingFace {
                        editingFace = FaceSelection(photoID: photo.id, faceID: faceID)
                    }
                },
                onBackgroundTap: { point in
                    if isAddingFace {
                        addFace(atNormalizedPoint: point, in: image, photoID: photo.id)
                    }
                }
            )
        } else if failedPhotoIDs.contains(photo.id) {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 44))
                Text("This photo couldn't be loaded.")
                    .font(.subheadline)
            }
            .foregroundStyle(Color.white.opacity(0.7))
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(photos.count > 1 ? "\(title) · \(selectedIndex + 1)/\(photos.count)" : title)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45), in: Capsule())

            Spacer()

            Menu {
                Button {
                    showFaces.toggle()
                } label: {
                    Label(showFaces ? "Hide Face Boxes" : "Show Face Boxes",
                          systemImage: showFaces ? "eye.slash" : "eye")
                }

                Button {
                    showFaces = true
                    isAddingFace = true
                } label: {
                    Label("Add a Missed Face", systemImage: "plus.viewfinder")
                }
                .disabled(currentPhoto == nil || loadedImages[currentPhoto?.id ?? UUID()] == nil)

                Divider()

                Button {
                    requestRescan()
                } label: {
                    Label("Scan This Photo Again", systemImage: "arrow.clockwise")
                }
                .disabled(isScanning || currentPhoto == nil)
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.45))
            }
            .accessibilityLabel("Face options")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.45))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusPill: some View {
        if let message = statusMessage {
            HStack(spacing: 8) {
                if isScanning {
                    ProgressView()
                        .tint(.white)
                }
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                if isAddingFace {
                    Button("Cancel") { isAddingFace = false }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6), in: Capsule())
            .padding(.bottom, 24)
        }
    }

    private var statusMessage: String? {
        guard let currentPhoto, loadedImages[currentPhoto.id] != nil else { return nil }
        if isScanning { return "Scanning for faces…" }
        if isAddingFace { return "Tap the middle of the face to add it" }
        guard showFaces else { return nil }
        if currentPhoto.faces == nil { return "Couldn't scan this photo for faces" }
        if currentFaces.isEmpty { return "No faces found — try ⋯ › Add a Missed Face" }
        return "\(currentTaggedCount) of \(currentFaces.count) faces tagged · tap a face to tag it"
    }

    // MARK: Actions

    /// Loads every photo (there are at most a few) and scans any that haven't been
    /// scanned yet — photos added before face tagging existed have never been scanned.
    @MainActor
    private func loadAndScanAllIfNeeded() async {
        for photo in photos {
            if loadedImages[photo.id] == nil, !failedPhotoIDs.contains(photo.id) {
                if let image = await TourPhotoStore.fullImage(named: photo.filename) {
                    loadedImages[photo.id] = image
                } else {
                    failedPhotoIDs.insert(photo.id)
                }
            }
            if loadedImages[photo.id] != nil, currentFaces(for: photo.id) == nil {
                await scanForFaces(photoID: photo.id)
            }
        }
    }

    private func currentFaces(for photoID: UUID) -> [PhotoFace]? {
        tour.groupPhotos.first(where: { $0.id == photoID })?.faces
    }

    private func requestRescan() {
        if currentTaggedCount > 0 {
            confirmingRescan = true
        } else if let photoID = currentPhoto?.id {
            Task { await scanForFaces(photoID: photoID) }
        }
    }

    @MainActor
    private func scanForFaces(photoID: UUID) async {
        guard let index = tour.groupPhotos.firstIndex(where: { $0.id == photoID }) else { return }
        isScanning = true
        defer { isScanning = false }

        let faces = await FaceDetectionService.detectFaces(inPhotoNamed: tour.groupPhotos[index].filename)
        if let currentIndex = tour.groupPhotos.firstIndex(where: { $0.id == photoID }) {
            tour.groupPhotos[currentIndex].faces = faces
        }
    }

    /// Adds a face box of typical size (the median of the boxes already found on this
    /// photo) centered on the tapped point, then opens the tagging sheet for it.
    private func addFace(atNormalizedPoint point: CGPoint, in image: UIImage, photoID: UUID) {
        guard let index = tour.groupPhotos.firstIndex(where: { $0.id == photoID }) else { return }
        let existingFaces = tour.groupPhotos[index].faces ?? []

        let widths = existingFaces.map { $0.width }.sorted()
        let width = widths.isEmpty ? 0.06 : widths[widths.count / 2]
        // Keep the box square in pixels, not just in fractions of a non-square photo.
        let height = width * Double(image.size.width / max(image.size.height, 1))

        let x = min(max(Double(point.x) - width / 2, 0), 1 - width)
        let y = min(max(Double(point.y) - height / 2, 0), 1 - height)

        let face = PhotoFace(rect: CGRect(x: x, y: y, width: width, height: height))
        tour.groupPhotos[index].faces = existingFaces + [face]
        isAddingFace = false
        editingFace = FaceSelection(photoID: photoID, faceID: face.id)
    }
}

// MARK: - Zoomable image (UIScrollView wrapper)

/// A face outline to draw on the zoomable photo.
struct FaceOverlayItem: Equatable {
    let id: UUID
    /// Fractions of the photo, origin top-left.
    let rect: CGRect
    let isTagged: Bool
}

/// SwiftUI has no built-in pinch-zoom-and-pan container, so this wraps UIScrollView —
/// the same mechanism Photos uses — which gives proper pinch anchoring, momentum
/// panning, bounce, and double-tap zoom for free. Face outlines are drawn as subviews of
/// the image itself, so they zoom and pan with it.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var faces: [FaceOverlayItem] = []
    var onFaceTap: ((UUID) -> Void)? = nil
    var onBackgroundTap: ((CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.onFaceTap = onFaceTap
        view.onBackgroundTap = onBackgroundTap
        view.setImage(image)
        view.setFaces(faces)
        return view
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {
        uiView.onFaceTap = onFaceTap
        uiView.onBackgroundTap = onBackgroundTap
        uiView.setImage(image)
        uiView.setFaces(faces)
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    /// Called with a face's ID when the tap lands on (or just next to) one of its outlines.
    var onFaceTap: ((UUID) -> Void)?
    /// Called when a tap lands on the photo but not on a face, with the point as
    /// fractions of the photo (origin top-left).
    var onBackgroundTap: ((CGPoint) -> Void)?

    private let imageView = UIImageView()
    private var imageSize: CGSize = .zero
    private var lastLayoutSize: CGSize = .zero
    private var needsFitOnNextLayout = true

    private var faceItems: [FaceOverlayItem] = []
    private var faceViews: [UUID: UIView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)

        delegate = self
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        decelerationRate = .fast

        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Group photo"
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard imageView.image !== image else { return }

        // Reset any zoom left over from a previous image before resizing the new one.
        minimumZoomScale = 1.0
        maximumZoomScale = 1.0
        zoomScale = 1.0

        imageView.image = image
        imageSize = image.size
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        contentSize = imageSize

        layoutFaceViews()
        needsFitOnNextLayout = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != lastLayoutSize || needsFitOnNextLayout {
            // Keep the current zoom across rotation/resizing unless the photo was
            // still fitted to the screen (or is brand new), in which case re-fit it.
            let wasFitted = needsFitOnNextLayout || zoomScale <= minimumZoomScale + 0.001
            lastLayoutSize = bounds.size
            needsFitOnNextLayout = false
            updateZoomScales(refit: wasFitted)
        }

        centerImage()
        layoutFaceViews()
    }

    private func updateZoomScales(refit: Bool) {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        let fitScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        minimumZoomScale = fitScale
        // Up to 4x the fitted size, but never less than 1 image pixel per point, so even
        // small photos can be zoomed in on.
        maximumZoomScale = max(fitScale * 4, 1.0)

        if refit {
            zoomScale = fitScale
        } else {
            zoomScale = min(max(zoomScale, minimumZoomScale), maximumZoomScale)
        }
    }

    /// Keeps the image centered when it's smaller than the screen along an axis
    /// (e.g. a landscape photo fitted to a portrait screen).
    private func centerImage() {
        var frame = imageView.frame
        frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
        imageView.frame = frame
    }

    // MARK: Face outlines

    func setFaces(_ items: [FaceOverlayItem]) {
        guard items != faceItems else { return }
        faceItems = items

        let currentIDs = Set(items.map { $0.id })
        for (id, view) in faceViews where !currentIDs.contains(id) {
            view.removeFromSuperview()
            faceViews[id] = nil
        }
        for item in items where faceViews[item.id] == nil {
            let view = UIView()
            view.isUserInteractionEnabled = false
            imageView.addSubview(view)
            faceViews[item.id] = view
        }

        layoutFaceViews()
    }

    /// Positions and styles every outline. Outlines live in the image's own coordinate
    /// space (so they zoom with it); the border width and corner radius are divided by
    /// the zoom scale so the lines stay the same thickness on screen at any zoom.
    private func layoutFaceViews() {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = max(zoomScale, 0.0001)

        for item in faceItems {
            guard let view = faceViews[item.id] else { continue }
            view.frame = CGRect(
                x: item.rect.minX * imageSize.width,
                y: item.rect.minY * imageSize.height,
                width: item.rect.width * imageSize.width,
                height: item.rect.height * imageSize.height
            )

            let color: UIColor = item.isTagged ? .systemGreen : .systemOrange
            view.layer.borderColor = color.cgColor
            view.layer.borderWidth = 2.5 / scale
            view.layer.cornerRadius = 4 / scale
            view.backgroundColor = color.withAlphaComponent(0.15)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        layoutFaceViews()
    }

    // MARK: Taps

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let point = gesture.location(in: imageView)

        // Small faces are small targets at fit-to-screen zoom, so each outline gets
        // roughly 10 points of extra tap area on every side.
        let slop = 10 / max(zoomScale, 0.0001)
        var bestID: UUID?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for item in faceItems {
            let rect = CGRect(
                x: item.rect.minX * imageSize.width,
                y: item.rect.minY * imageSize.height,
                width: item.rect.width * imageSize.width,
                height: item.rect.height * imageSize.height
            ).insetBy(dx: -slop, dy: -slop)

            guard rect.contains(point) else { continue }
            let distance = hypot(rect.midX - point.x, rect.midY - point.y)
            if distance < bestDistance {
                bestDistance = distance
                bestID = item.id
            }
        }

        if let bestID {
            onFaceTap?(bestID)
            return
        }

        if CGRect(origin: .zero, size: imageSize).contains(point) {
            onBackgroundTap?(CGPoint(x: point.x / imageSize.width, y: point.y / imageSize.height))
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let targetScale = min(maximumZoomScale, minimumZoomScale * 3)
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
            let rect = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            zoom(to: rect, animated: true)
        }
    }
}
