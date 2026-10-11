import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct PaletteHost: View {
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = window.palette.open
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if open {
                    Color.Vrai.scrim
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
    static let footerHeight = Vrai.Space.s32
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
        let showFooter = room > Self.searchHeight + Self.footerHeight + Self.rowHeight * 3 && widthClass != .compact
        let listRoom = max(Self.rowHeight * 2, min(Self.listMax, room - Self.searchHeight - (showFooter ? Self.footerHeight : 0)))
        VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s12) {
                Symbol(typing ? "terminal" : "magnifyingglass", font: Font.Vrai.title3.weight(.regular))
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .frame(width: Vrai.Size.icon)
                TextField(text: $palette.query) {
                    Text(placeholder(narrow: narrow)).foregroundStyle(Color.Vrai.textTertiary)
                }
                .textFieldStyle(.plain)
                .font(typing ? Font.Vrai.code : Font.Vrai.lead)
                .foregroundStyle(Color.Vrai.text)
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
                if window.preferences.expert {
                    Text("Expert", bundle: .module)
                        .font(Font.Vrai.captionStrong)
                        .foregroundStyle(Color.Vrai.accentText)
                        .padding(.horizontal, Vrai.Space.s8)
                        .frame(height: Vrai.Space.s20)
                        .background(Color.Vrai.accentSoft, in: Capsule())
                        .fixedSize()
                }
            }
            .padding(.leading, Vrai.Space.s20)
            .padding(.trailing, Vrai.Space.s16)
            .frame(height: Self.searchHeight)
            .hairline(.bottom)
            if flat.isEmpty {
                VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                    Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Nothing to show yet.", bundle: .module) : String(localized: "No actions match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}.", bundle: .module))
                        .font(Font.Vrai.body)
                        .foregroundStyle(Color.Vrai.textSecondary)
                    Text("Start with git to run any command, for example git log --oneline -5.", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Vrai.Space.s24)
                .padding(.horizontal, Vrai.Space.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PaletteList(groups: groups, cursor: cursor, maxHeight: listRoom) { item in
                    run(item, option: NSEvent.modifierFlags.contains(.option))
                }
            }
            if showFooter {
                HStack(spacing: Vrai.Space.s16) {
                    footerKey("\u{2191}\u{2193}", String(localized: "navigate", bundle: .module))
                    footerKey("\u{21A9}", String(localized: "run", bundle: .module))
                    footerKey("\u{2325}\u{21A9}", String(localized: "run with options", bundle: .module))
                    Spacer(minLength: Vrai.Space.s8)
                    footerKey("esc", String(localized: "close", bundle: .module))
                }
                .padding(.horizontal, Vrai.Space.s16)
                .frame(height: Self.footerHeight)
                .hairline(.top)
            }
        }
        .background(Color.Vrai.glassFill, in: RoundedRectangle(cornerRadius: Vrai.Radius.xl, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: Vrai.Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.xl, style: .continuous).strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Vrai.Radius.xl, style: .continuous))
        .shadow(color: Color.Vrai.glassEdge, radius: Vrai.Space.s24, y: Vrai.Space.s12)
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

    func footerKey(_ keys: String, _ label: String) -> some View {
        HStack(spacing: Vrai.Space.s4) {
            Text(verbatim: keys)
                .font(Font.Vrai.captionStrong)
            Text(label)
                .font(Font.Vrai.caption)
        }
        .foregroundStyle(Color.Vrai.textTertiary)
        .lineLimit(1)
        .fixedSize()
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
                                .overline()
                                .foregroundStyle(Color.Vrai.textTertiary)
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
                tile(active: active)
                Text(item.label)
                    .font(item.command ? Font.Vrai.code : Font.Vrai.body)
                    .foregroundStyle(item.danger ? Color.Vrai.danger : Color.Vrai.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: Vrai.Size.palette * 0.4, alignment: .trailing)
                }
                if let risk = item.risk {
                    RiskTag(risk: risk)
                }
                if let shortcut = item.shortcut {
                    Text(verbatim: shortcut)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, Vrai.Space.s6)
            .padding(.trailing, Vrai.Space.s10)
            .frame(height: PaletteView.rowHeight)
            .background(active ? Color.Vrai.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
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

    @ViewBuilder func tile(active: Bool) -> some View {
        let fill = item.command && item.id == "__run" ? Color.Vrai.accent : (active ? Color.Vrai.surfaceRaised : Color.Vrai.fill)
        let ink = item.command && item.id == "__run" ? Color.Vrai.onAccent : (active ? Color.Vrai.accentText : Color.Vrai.textSecondary)
        RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous)
            .fill(fill)
            .frame(width: Vrai.Size.iconLg, height: Vrai.Size.iconLg)
            .overlay {
                switch item.glyph {
                case .symbol(let name):
                    Symbol(name, font: Font.Vrai.callout)
                        .foregroundStyle(item.danger ? Color.Vrai.danger : ink)
                case .lane(let name, let lane):
                    Symbol(name, font: Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.lane(lane))
                case .file(let status):
                    FileStatusTile(status: status)
                }
            }
            .shadow(color: active ? Color.Vrai.separator : Color.clear, radius: Metrics.hairline, y: Metrics.hairline)
    }
}
