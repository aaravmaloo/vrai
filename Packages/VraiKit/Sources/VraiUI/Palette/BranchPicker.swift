import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct BranchPicker: View {
    let context: PaletteContext
    @State private var query = ""
    @State private var search = PaletteSearch()
    @State private var highlighted: String?
    @FocusState private var focused: Bool

    static let width: CGFloat = Vrai.Size.inspector
    static let height: CGFloat = Vrai.Size.sheet * 0.8

    var window: WindowModel { context.window }

    var body: some View {
        let groups = PaletteSources(context: context, search: search, mode: .branches, query: query, narrow: false).groups()
        let flat = groups.flatMap(\.items)
        let current = highlighted.flatMap { id in flat.contains { $0.id == id } ? id : nil } ?? flat.first?.id
        VStack(spacing: 0) {
            TextField(String(localized: "Filter branches", bundle: .module), text: $query, prompt: Text("Switch to a branch, or name a new one", bundle: .module))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($focused)
                .onKeyPress(.downArrow) {
                    highlighted = Self.step(current, by: 1, in: flat)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = Self.step(current, by: -1, in: flat)
                    return .handled
                }
                .onSubmit {
                    guard let item = flat.first(where: { $0.id == current }) else { return }
                    run(item, option: NSEvent.modifierFlags.contains(.option))
                }
                .accessibilityIdentifier("branch-picker-filter")
                .padding(Vrai.Space.s10)
            Divider()
            ScrollViewReader { proxy in
                List(selection: Binding(get: { current }, set: { id in
                    guard let item = flat.first(where: { $0.id == id }) else { return }
                    run(item, option: NSEvent.modifierFlags.contains(.option))
                })) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        Section(group.kind.title) {
                            ForEach(group.items) { item in
                                BranchPickerRow(item: item)
                                    .tag(item.id)
                                    .id(item.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .onChange(of: current) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in highlighted = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("branch-picker")
    }

    static func step(_ current: String?, by delta: Int, in items: [PaletteItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let index = current.flatMap { id in items.firstIndex { $0.id == id } } ?? -1
        return items[min(items.count - 1, max(0, index + delta))].id
    }

    func run(_ item: PaletteItem, option: Bool) {
        window.branchPicker = false
        item.run(option)
    }
}

struct BranchPickerRow: View {
    let item: PaletteItem
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            Label {
                Text(item.label)
                    .fontWeight(item.current ? .semibold : nil)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                icon
            }
            Spacer(minLength: 0)
            if let detail = item.detail {
                Text(detail)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if item.current {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Current branch", bundle: .module))
            }
        }
        .help(item.label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.label)
        .accessibilityIdentifier("palette-item")
    }

    @ViewBuilder var icon: some View {
        switch item.glyph {
        case .symbol(let name):
            Image(systemName: name)
        case .lane(let name, let lane):
            if prominence == .increased {
                Image(systemName: name)
            } else {
                Image(systemName: name)
                    .foregroundStyle(Color.Vrai.lane(lane))
            }
        case .file(let status):
            FileStatusTile(status: status)
        }
    }
}
