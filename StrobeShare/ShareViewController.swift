import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

#if os(iOS)
typealias PlatformViewController = UIViewController
#else
typealias PlatformViewController = NSViewController
#endif

/// The extension's principal class: hosts ``ShareView`` and closes the
/// share sheet when the person adds or cancels.
final class ShareViewController: PlatformViewController {
    private let model = ShareModel()

    #if os(macOS)
    override func loadView() {
        // No nib: the SwiftUI view is the whole interface.
        let hostingView = NSHostingView(rootView: ShareView(model: model))
        hostingView.appearance = NSAppearance(named: .darkAqua)
        view = hostingView
        preferredContentSize = hostingView.fittingSize
    }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()

        #if os(iOS)
        // Strobe is dark only; the sheet around the view follows it.
        overrideUserInterfaceStyle = .dark
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        #endif

        model.onFinish = { [weak self] added in
            self?.finish(added: added)
        }
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task {
            await model.load(items)
        }
    }

    private func finish(added: Bool) {
        if added {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
