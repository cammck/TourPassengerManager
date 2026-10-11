import SwiftUI
import UIKit
import LinkPresentation

/// A file ready to be shared. Being Identifiable lets it drive `.sheet(item:)`, which —
/// unlike `.sheet(isPresented:)` plus a separate optional — guarantees the sheet is built
/// with the file already in hand (the two-variable version can present an empty sheet).
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Wraps UIActivityViewController so SwiftUI can present the system share sheet,
/// used here to let the user export/share CSV rosters and backup files.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // File URLs are wrapped so the share sheet is handed a ready-made title and icon
        // instead of trying to render a preview of the file itself. For a large backup
        // (which can embed photos) that preview work can leave the sheet blank for a long time.
        let items: [Any] = activityItems.map { item -> Any in
            if let url = item as? URL, url.isFileURL {
                return ShareFileItemSource(url: url)
            }
            return item
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Shares a file while supplying its own header (title + generic icon), so iOS never has
/// to open and render the file just to draw the top of the share sheet.
final class ShareFileItemSource: NSObject, UIActivityItemSource {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = url.lastPathComponent
        if let icon = UIImage(systemName: "doc.text.fill") {
            metadata.iconProvider = NSItemProvider(object: icon)
        }
        return metadata
    }
}
