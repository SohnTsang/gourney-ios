import SwiftUI
import WebKit

/// Installs a global tap that dismisses the keyboard, but NEVER triggers when the tap
/// is on interactive controls (UITextField, UITextView, UIControl, WKWebView, etc.).
struct InstallGlobalTapToDismissKeyboard: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InstallerController { InstallerController() }
    func updateUIViewController(_ vc: InstallerController, context: Context) {}

    final class InstallerController: UIViewController, UIGestureRecognizerDelegate {
        private var installed = false
        private weak var recognizer: UITapGestureRecognizer?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !installed else { return }
            installed = true

            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.numberOfTapsRequired = 1
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.recognizer = tap
        }

        @objc private func handleTap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = touch.view else { return true }
            // Skip taps on any interactive UIKit control or text inputs
            if isInteractive(view) { return false }
            return true
        }

        private func isInteractive(_ view: UIView) -> Bool {
            // treat any ancestor that is a control / input / web content as interactive
            var v: UIView? = view
            while let current = v {
                if current is UIControl { return true }               // buttons, toggles, sliders, etc.
                if current is UITextField || current is UITextView { return true }
                if current is WKWebView { return true }
                // If you have map views or custom controls, add them here:
                // if current is MKMapView { return true }
                v = current.superview
            }
            return false
        }
    }
}
