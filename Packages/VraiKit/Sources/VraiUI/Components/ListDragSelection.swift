import AppKit
import SwiftUI

struct ListDragSelection: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.schedule()
    }

    final class Probe: NSView {
        private weak var table: NSTableView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            schedule()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func schedule() {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            if let table, table.window === window {
                if table.verticalMotionCanBeginDrag { table.verticalMotionCanBeginDrag = false }
                return
            }
            guard let window, let root = window.contentView else { return }
            let frame = convert(bounds, to: nil)
            let center = NSPoint(x: frame.midX, y: frame.midY)
            guard let found = Self.tables(in: root).first(where: { table in
                guard let scroll = table.enclosingScrollView else { return false }
                return scroll.convert(scroll.bounds, to: nil).contains(center)
            }) else { return }
            found.verticalMotionCanBeginDrag = false
            table = found
        }

        static func tables(in view: NSView) -> [NSTableView] {
            if let table = view as? NSTableView { return [table] }
            return view.subviews.flatMap { tables(in: $0) }
        }
    }
}

extension View {
    func dragSelectsRows() -> some View {
        background(ListDragSelection().accessibilityHidden(true))
    }
}
