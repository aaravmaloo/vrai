import AppKit
import SwiftUI

enum HostScope {
    case window
    case column
    case any
}

struct HostAccessibilityLabel: NSViewRepresentable {
    var label: String?
    var scope: HostScope

    func makeNSView(context: Context) -> LabelingView {
        let view = LabelingView()
        view.label = label
        view.scope = scope
        return view
    }

    func updateNSView(_ view: LabelingView, context: Context) {
        view.label = label
        view.scope = scope
        view.apply()
    }

    final class LabelingView: NSView {
        var label: String?
        var scope = HostScope.window

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            Task { @MainActor [weak self] in
                for delay in [100, 400, 1200] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    self?.apply()
                }
            }
        }

        override func isAccessibilityElement() -> Bool { false }

        var host: NSView? {
            var candidate = superview
            while let view = candidate {
                if NSStringFromClass(type(of: view)).contains("HostingView") { return view }
                candidate = view.superview
            }
            return nil
        }

        func apply() {
            guard let window, let host else { return }
            switch scope {
            case .window: guard host === window.contentView else { return }
            case .column: guard host !== window.contentView else { return }
            case .any: break
            }
            guard (host.accessibilityLabel() ?? "").isEmpty, let text = resolved(host, window: window) else { return }
            host.setAccessibilityLabel(text)
        }

        func resolved(_ host: NSView, window: NSWindow) -> String? {
            if let label, !label.isEmpty { return label }
            for child in host.accessibilityChildren() ?? [] {
                guard let element = child as? NSObject, element.responds(to: #selector(NSAccessibilityProtocol.accessibilityLabel)) else { continue }
                if let text = element.value(forKey: "accessibilityLabel") as? String, !text.isEmpty { return text }
            }
            return window.title.isEmpty ? nil : window.title
        }
    }
}

extension View {
    func accessibilityHostLabel(_ label: String? = nil, scope: HostScope = .window) -> some View {
        background(HostAccessibilityLabel(label: label, scope: scope).accessibilityHidden(true))
    }
}
