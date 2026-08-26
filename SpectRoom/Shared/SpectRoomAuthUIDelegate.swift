import UIKit
import FirebaseAuth

/// Presents Firebase Auth reCAPTCHA / Safari UI from the key window.
final class SpectRoomAuthUIDelegate: NSObject, AuthUIDelegate {
    static let shared = SpectRoomAuthUIDelegate()

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        guard let presenter = Self.topViewController() else {
            completion?()
            return
        }
        presenter.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        Self.topViewController()?.dismiss(animated: flag, completion: completion)
    }

    private static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
