import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct BranchPicker: View {
    let context: PaletteContext
    @State private var query = ""
    @State private var search = PaletteSearch()
    @State private var cursor = PaletteCursor()
    @State private var contentHeight: CGFloat = 0
    @FocusState private var focused: Bool

    static let width: CGFloat = Vrai.Size.inspector
    static let listMax: CGFloat = Vrai.Size.sheet * 0.75

    var window: WindowModel { context.window }

    var body: some View {
        let groups = PaletteSources(context: context, search: search, mode: .branches, query: query, narrow: false).groups()
        let flat = groups.flatMap(\.items)
        VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(String(localized: "Filter branches", bundle: .module), text: $query, prompt: Text("Switch to a branch, or name a new one", bundle: .module))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onKeyPress(.downArrow) {
                        cursor.move(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        cursor.move(-1)
                        return .handled
                    }
                    .onSubmit {
                        guard flat.indices.contains(cursor.active) else { return }
                        run(flat[cursor.active], option: NSEvent.modifierFlags.contains(.option))
                    }
                    .accessibilityIdentifier("branch-picker-filter")
            }
            .padding(.horizontal, Vrai.Space.s12)
            .frame(height: Vrai.Size.controlLg + Vrai.Space.s6)
            Divider()
            if flat.isEmpty {
                Text("Nothing to show yet.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .padding(Vrai.Space.s16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                list(groups)
            }
        }
        .frame(width: Self.width)
        .onChange(of: flat.count, initial: true) { _, count in
            cursor.count = count
            if cursor.active >= count { cursor.active = max(0, count - 1) }
        }
        .onChange(of: query) { _, _ in cursor.active = 0 }
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("branch-picker")
    }

    func list(_ groups: [PaletteGroup<PaletteItem>]) -> some View {
        let offsets = PaletteList.offsets(groups)
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, Vrai.Space.s8)
                                .padding(.top, Vrai.Space.s6)
                                .padding(.bottom, Vrai.Space.s2)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                                let index = offsets[groupIndex] + itemIndex
                                BranchPickerRow(item: item, index: index, cursor: cursor) {
                                    run(item, option: NSEvent.modifierFlags.contains(.option))
                                }
                                .id(index)
                            }
                        }
                    }
                }
                .padding(Vrai.Space.s6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(contentHeight > Self.listMax ? .automatic : .never)
            .frame(height: contentHeight > 0 ? min(contentHeight, Self.listMax) : Vrai.Size.row * 6)
            .onChange(of: cursor.active) { _, active in
                proxy.scrollTo(active)
            }
        }
    }

    func run(_ item: PaletteItem, option: Bool) {
        window.branchPicker = false
        item.run(option)
    }
}

struct BranchPickerRow: View {
    let item: PaletteItem
    let index: Int
    let cursor: PaletteCursor
    let run: () -> Void

    var body: some View {
        let active = cursor.active == index
        Button(action: run) {
            HStack(spacing: Vrai.Space.s8) {
                icon(active: active)
                    .frame(width: Vrai.Size.icon)
                Text(item.label)
                    .fontWeight(item.current ? .semibold : nil)
                    .foregroundStyle(active ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.current {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(active ? Color.white : Color.Vrai.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Vrai.Space.s8)
            .frame(height: Vrai.Size.row)
            .background(active ? Color.Vrai.accent : Color.clear, in: RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside, cursor.active != index { cursor.active = index }
        }
        .help(item.detail.map { item.label + "\n" + $0 } ?? item.label)
        .accessibilityLabel([item.label, item.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("palette-item")
    }

    @ViewBuilder func icon(active: Bool) -> some View {
        switch item.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .foregroundStyle(active ? Color.white : Color.secondary)
        case .lane(let name, let lane):
            Image(systemName: name)
                .foregroundStyle(active ? Color.white : Color.Vrai.lane(lane))
        case .file(let status):
            FileStatusTile(status: status)
        }
    }
}
