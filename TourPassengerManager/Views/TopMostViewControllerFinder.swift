import UIKit

/// Walks down from the key window's root view controller through any navigation
/// stack, tab bar, and currently-presented sheets to find whatever is actually on
/// screen right now — so system compose screens (Messages, Mail, etc.) present
/// from the right place regardless of how deep the current navigation/sheet stack
/// goes.
enum TopMostViewControllerFinder {
    static func find(from base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController

        if let nav = root as? UINavigationController {
            return find(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return find(from: selected)
        }
        if let presented = root?.presentedViewController {
            return find(from: presented)
        }
        return root
    }
}
