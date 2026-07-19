import SwiftUI
import MessageUI

/// Pre-filled SMS composer — recipient and body filled, user's thumb presses Send.
/// iOS cannot report whether Send was actually tapped in a trustworthy way for our
/// purposes (nor read the 7275 confirmation), hence the honesty sheet after dismissal.
struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: () -> Void

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) { self.onFinish() }
        }
    }
}
