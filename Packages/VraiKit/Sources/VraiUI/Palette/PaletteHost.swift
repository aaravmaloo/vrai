import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct PaletteHost: View {
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.vraiReduceMotion) private var reduceMotion

    var body: some View {
        let open = window.palette.open
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if open {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { window.palette.dismiss() }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    let narrow = geometry.size.width < Vrai.Size.palette + Vrai.Space.s32
                    let side = narrow ? Vrai.Space.s8 : Vrai.Space.s16
                    let top = narrow ? Vrai.Space.s8 : max(Vrai.Space.s8, geometry.size.height * 0.12)
                    PaletteView(context: context, room: geometry.size.height - top - side)
                        .id(window.palette.session)
                        .frame(width: max(0, min(Vrai.Size.palette, geometry.size.width - side * 2)))
                        .padding(.top, top)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -Vrai.Space.s8)).combined(with: .scale(scale: 0.985, anchor: .top)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .allowsHitTesting(open)
        .animation(reduceMotion ? Animation.Vrai.standardFast : Animation.Vrai.outSlow, value: open)
    }

    var context: PaletteContext {
        let openWindow = openWindow
        return PaletteContext(
            window: window,
            app: app,
            openWindowID: { openWindow(id: $0) },
            openRepository: { openWindow(value: $0) }
        )
    }
}

@MainActor
@Observable
final class PaletteCursor {
    var active = 0
    var count = 0

    func move(_ delta: Int) {
        guard count > 0 else { return }
        active = min(count - 1, max(0, active + delta))
    }
}

struct PaletteView: View {
    let context: PaletteContext
    let room: CGFloat
    @State private var search = PaletteSearch()
    @State private var cursor = PaletteCursor()
    @FocusState private var focused: Bool
    @Environment(\.widthClass) private var widthClass

    static let searchHeight = Vrai.Size.toolbar + Vrai.Space.s4
    static let rowHeight = Vrai.Size.control + Vrai.Space.s8
    static let listMax = Vrai.Space.s64 * 5 + Vrai.Space.s40

    var window: WindowModel { context.window }

    var body: some View {
        @Bindable var palette = window.palette
        let query = palette.query
        let narrow = widthClass.isNarrow
        let groups = PaletteSources(context: context, search: search, mode: palette.mode, query: query, narrow: narrow).groups()
        let flat = groups.flatMap(\.items)
        let typing = query.hasPrefix("git") && CommandParser.parse(query) != nil
        let listRoom = max(Self.rowHeight * 2, min(Self.listMax, room - Self.searchHeight))
        VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s12) {
                Image(systemName: typing ? "terminal" : "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: Vrai.Size.iconLg)
                    .accessibilityHidden(true)
                TextField(text: $palette.query) {
                    Text(placeholder(narrow: narrow))
                }
                .textFieldStyle(.plain)
                .font(typing ? .system(.title2, design: .monospaced) : .title2)
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
                .onKeyPress(keys: [.return], phases: .down) { press in
                    run(flat, option: press.modifiers.contains(.option))
                    return .handled
                }
                .onKeyPress(.escape) {
                    if palette.query.isEmpty { window.palette.dismiss() } else { palette.query = "" }
                    return .handled
                }
                .onExitCommand { window.palette.dismiss() }
                .accessibilityLabel(Text("Search or run a command", bundle: .module))
                .accessibilityIdentifier("palette-field")
            }
            .padding(.leading, Vrai.Space.s20)
            .padding(.trailing, Vrai.Space.s16)
            .frame(height: Self.searchHeight)
            Divider()
            if flat.isEmpty {
                Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Nothing to show yet.", bundle: .module) : String(localized: "No actions match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}.", bundle: .module))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Vrai.Space.s20)
                    .padding(.horizontal, Vrai.Space.s20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(String(localized: "Start with git to run any command, for example git log --oneline -5.", bundle: .module))
            } else {
                PaletteList(groups: groups, cursor: cursor, maxHeight: listRoom) { item in
                    run(item, option: NSEvent.modifierFlags.contains(.option))
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Vrai.Space.s24))
        .onChange(of: flat.count, initial: true) { _, count in
            cursor.count = count
            if cursor.active >= count { cursor.active = max(0, count - 1) }
        }
        .onChange(of: query) { _, next in
            cursor.active = 0
            search.update(next, store: window.store)
        }
        .defaultFocus($focused, true)
        .task {
            focused = true
            for delay in [60, 120, 240] {
                try? await Task.sleep(for: .milliseconds(delay))
                if focused { break }
                focused = true
            }
        }
        .task {
            search.update(query, store: window.store)
            await search.start(window: window)
        }
        .onDisappear { search.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Command palette", bundle: .module))
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("command-palette")
    }

    func placeholder(narrow: Bool) -> String {
        let branches = window.palette.mode == .branches
        if narrow { return branches ? String(localized: "Switch to a branch", bundle: .module) : String(localized: "Search", bundle: .module) }
        if branches { return String(localized: "Switch to a branch, or name a new one", bundle: .module) }
        return window.preferences.expert ? String(localized: "Search, or type a git command", bundle: .module) : String(localized: "Search actions, branches, commits and files", bundle: .module)
    }

    func run(_ flat: [PaletteItem], option: Bool) {
        guard flat.indices.contains(cursor.active) else { return }
        run(flat[cursor.active], option: option)
    }

    func run(_ item: PaletteItem, option: Bool) {
        window.palette.dismiss()
        item.run(option)
    }
}

struct PaletteList: View {
    let groups: [PaletteGroup<PaletteItem>]
    let cursor: PaletteCursor
    let maxHeight: CGFloat
    let run: (PaletteItem) -> Void
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let offsets = Self.offsets(groups)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, Vrai.Space.s10)
                                .padding(.top, Vrai.Space.s8)
                                .padding(.bottom, Vrai.Space.s4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                                let index = offsets[groupIndex] + itemIndex
                                PaletteRow(item: item, index: index, cursor: cursor) { run(item) }
                                    .id(index)
                            }
                        }
                    }
                }
                .padding(Vrai.Space.s8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(contentHeight > maxHeight ? .automatic : .never)
            .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : min(maxHeight, PaletteView.rowHeight * 4))
            .onChange(of: cursor.active) { _, active in
                proxy.scrollTo(active)
            }
        }
    }

    static func offsets(_ groups: [PaletteGroup<PaletteItem>]) -> [Int] {
        var out: [Int] = []
        var running = 0
        for group in groups {
            out.append(running)
            running += group.items.count
        }
        return out
    }
}

struct PaletteRow: View {
    let item: PaletteItem
    let index: Int
    let cursor: PaletteCursor
    let run: () -> Void

    var body: some View {
        let active = cursor.active == index
        Button(action: run) {
            HStack(spacing: Vrai.Space.s10) {
                icon(active: active)
                    .frame(width: Vrai.Size.iconLg)
                Text(item.label)
                    .font(item.command ? Font.Vrai.code : Font.Vrai.body)
                    .foregroundStyle(active ? Color.white : (item.danger ? Color.Vrai.danger : Color.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(active ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: Vrai.Size.palette * 0.4, alignment: .trailing)
                }
                if let risk = item.risk {
                    RiskTag(risk: risk)
                }
                if let shortcut = item.shortcut {
                    Text(verbatim: shortcut)
                        .font(Font.Vrai.body)
                        .foregroundStyle(active ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, Vrai.Space.s6)
            .padding(.trailing, Vrai.Space.s10)
            .frame(height: PaletteView.rowHeight)
            .background(active ? Color.Vrai.accent : Color.clear, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside, cursor.active != index { cursor.active = index }
        }
        .accessibilityLabel([item.label, item.detail, item.risk.flatMap { RiskTag.tag($0)?.label }].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("palette-item")
    }

    @ViewBuilder func icon(active: Bool) -> some View {
        switch item.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .foregroundStyle(active ? Color.white : (item.danger ? Color.Vrai.danger : Color.secondary))
        case .lane(let name, let lane):
            Image(systemName: name)
                .foregroundStyle(active ? Color.white : Color.Vrai.lane(lane))
        case .file(let status):
            FileStatusTile(status: status)
        }
    }
}
