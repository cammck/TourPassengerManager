import UIKit
import Combine
import MessageUI

/// Presents the system SMS composer directly via UIKit, rather than embedding it as
/// the content of a SwiftUI `.sheet(...)`.
///
/// Why: MFMessageComposeViewController is designed to be presented imperatively
/// (`someViewController.present(composeVC, animated: true)`). When it's instead
/// wrapped in a `UIViewControllerRepresentable` and handed to SwiftUI's `.sheet`,
/// it can come up on screen with no recipients and no body text on real devices —
/// the compose screen itself renders, but the fields never get filled in. Presenting
/// it directly, from the actual top-most view controller currently on screen, avoids
/// that entirely.
@MainActor
final class MessageComposerPresenter: NSObject, ObservableObject, MFMessageComposeViewControllerDelegate {
    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    private var completion: ((MessageComposeResult) -> Void)?

    /// Presents the SMS composer pre-filled with the given recipients and body.
    /// Does nothing if the device can't send text messages or no view controller
    /// is available to present from (both should be checked/guarded by the caller
    /// via `canSendText` before calling this).
    func present(recipients: [String], body: String, completion: @escaping (MessageComposeResult) -> Void) {
        guard MFMessageComposeViewController.canSendText(),
              let presenter = TopMostViewControllerFinder.find() else {
            return
        }

        self.completion = completion

        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = self

        presenter.present(controller, animated: true)
    }

    func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true) { [weak self] in
            self?.completion?(result)
            self?.completion = nil
        }
    }
}
