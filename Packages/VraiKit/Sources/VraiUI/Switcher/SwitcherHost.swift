import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct SwitcherHost: View {
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiReduceMotion) private var reduceMotion

    var body: some View {
        let open = window.switcher.open
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if open {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { window.switcher.dismiss() }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    let side = geometry.size.width < SwitcherView.width + Vrai.Space.s32 ? Vrai.Space.s8 : Vrai.Space.s12
                    let room = min(geometry.size.height - side * 2, (geometry.size.height + Vrai.Size.toolbar) * SwitcherView.heightShare)
                    SwitcherView(room: max(0, room))
                        .id(window.switcher.session)
                        .frame(width: max(0, min(SwitcherView.width, geometry.size.width - side * 2)))
                        .padding(.top, side)
                        .padding(.leading, side)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -Vrai.Space.s8)).combined(with: .scale(scale: 0.985, anchor: .topLeading)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(open)
        .animation(reduceMotion ? Animation.Vrai.standardFast : Animation.Vrai.outSlow, value: open)
    }
}

struct SwitcherLayout: Equatable {
    var query: String
    var keys: [String]
}

struct SwitcherView: View {
    let room: CGFloat
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var cursor = PaletteCursor()
    @FocusState private var focused: Bool

    static let width = Vrai.Size.inspector
    static let heightShare: CGFloat = 0.7
    static let headerHeight = Vrai.Size.control + Vrai.Space.s16
    static let rowHeight = Vrai.Size.rowComfortable

    var body: some View {
        @Bindable var switcher = window.switcher
        let query = switcher.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = RepositoryDirectory.sections(app.recents, current: window.reference.path, query: query)
        let flat = RepositoryDirectory.flatten(sections)
        let keys = sections.flatMap { section in section.entries.map { section.id + "\n" + $0.path } }
        let listRoom = max(Self.rowHeight * 2, room - Self.headerHeight)
        VStack(spacing: 0) {
            HStack(spacing: Vrai.Space.s8) {
                TextField(text: $switcher.query, prompt: Text("Filter", bundle: .module)) {
                    Text("Filter repositories", bundle: .module)
                }
                .textFieldStyle(.roundedBorder)
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
                    chooseActive(flat, newWindow: press.modifiers.contains(.command))
                    return .handled
                }
                .onKeyPress(.escape) {
                    if switcher.query.isEmpty { switcher.dismiss() } else { switcher.query = "" }
                    return .handled
                }
                .onExitCommand { switcher.dismiss() }
                .accessibilityLabel(Text("Filter repositories", bundle: .module))
                .accessibilityIdentifier("switcher-field")
                addMenu
            }
            .padding(.horizontal, Vrai.Space.s8)
            .frame(height: Self.headerHeight)
            Divider()
            if flat.isEmpty {
                empty(query)
            } else {
                SwitcherList(sections: sections, current: window.reference.path, cursor: cursor, maxHeight: listRoom, choose: choose, remove: remove)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: Vrai.Radius.xl))
        .background {
            Button {
                chooseActive(flat, newWindow: true)
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.plain)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: SwitcherLayout(query: query, keys: keys), initial: true) { old, new in
            cursor.count = new.keys.count
            if old.query != new.query || old == new {
                cursor.active = (new.query.isEmpty ? RepositoryDirectory.index(of: window.reference.path, in: sections) : RepositoryDirectory.bestIndex(sections, query: new.query)) ?? 0
            } else if old.keys.indices.contains(cursor.active) {
                let key = old.keys[cursor.active]
                cursor.active = new.keys.firstIndex(of: key) ?? min(cursor.active, max(0, new.keys.count - 1))
            }
            if cursor.active >= new.keys.count { cursor.active = max(0, new.keys.count - 1) }
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
        .task { app.refreshDirectory() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Switch repository", bundle: .module))
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("repository-switcher")
    }

    var addMenu: some View {
        Menu {
            Button {
                add(.open)
            } label: {
                Label(String(localized: "Open\u{2026}", bundle: .module), systemImage: "folder")
            }
            Button {
                add(.clone(url: nil))
            } label: {
                Label(String(localized: "Clone\u{2026}", bundle: .module), systemImage: "square.and.arrow.down")
            }
            Button {
                add(.newRepository(folder: nil))
            } label: {
                Label(String(localized: "New repository\u{2026}", bundle: .module), systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                window.switcher.dismiss()
                openWindow(id: "welcome")
            } label: {
                Label(String(localized: "Welcome window", bundle: .module), systemImage: "macwindow")
            }
        } label: {
            Text("Add", bundle: .module)
        }
        .menuStyle(.button)
        .fixedSize()
        .accessibilityLabel(Text("Add a repository", bundle: .module))
        .accessibilityIdentifier("switcher-add")
    }

    @ViewBuilder func empty(_ query: String) -> some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s4) {
            Text(query.isEmpty ? String(localized: "No recent repositories", bundle: .module) : String(localized: "No repositories match \u{201C}\(query)\u{201D}.", bundle: .module))
                .font(Font.Vrai.body)
                .foregroundStyle(Color.Vrai.textSecondary)
            if query.isEmpty {
                Text("Repositories you open, clone or create show up here.", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Vrai.Space.s20)
        .padding(.horizontal, Vrai.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func add(_ kind: AppSheetKind) {
        window.switcher.dismiss()
        AppSheets.present(kind, window: window, app: app, openWindow: openWindow)
    }

    func chooseActive(_ flat: [DirectoryEntry], newWindow: Bool) {
        guard flat.indices.contains(cursor.active) else { return }
        choose(flat[cursor.active], newWindow: newWindow)
    }

    func choose(_ entry: DirectoryEntry, newWindow: Bool) {
        window.switcher.dismiss()
        let reference = RepositoryReference(path: entry.path)
        if reference == window.reference, !newWindow { return }
        if app.directoryStatus[entry.path]?.missing == true || !FileManager.default.fileExists(atPath: entry.path) {
            locate(entry)
            return
        }
        app.noteOpened(reference)
        app.request(reference)
        if newWindow || app.isOpen(reference) {
            openWindow(value: reference)
            return
        }
        PerfLog.begin("open")
        window.switchRequest = reference
    }

    func remove(_ entry: DirectoryEntry) {
        Self.remove(entry, from: app)
    }

    static func remove(_ entry: DirectoryEntry, from app: AppModel) {
        guard let recent = app.recents.first(where: { $0.path == entry.path }) else { return }
        app.removeRecent(recent)
    }

    func locate(_ entry: DirectoryEntry) {
        let window = window
        let app = app
        let openWindow = openWindow
        window.alerts.present(AlertRequest(
            title: String(localized: "\(entry.name) isn't where it used to be", bundle: .module),
            message: String(localized: "Vrai can't find a repository at \(app.displayPath(URL(filePath: entry.path))). It may have been moved, renamed or deleted.", bundle: .module),
            actions: [
                AlertAction(title: String(localized: "Locate\u{2026}", bundle: .module)) { AppSheets.present(.open, window: window, app: app, openWindow: openWindow) },
                AlertAction(title: String(localized: "Remove from list", bundle: .module)) { Self.remove(entry, from: app) },
                AlertAction(title: String(localized: "Cancel", bundle: .module), role: .cancel)
            ]
        ))
    }
}

struct SwitcherList: View {
    let sections: [DirectorySection]
    let current: String
    let cursor: PaletteCursor
    let maxHeight: CGFloat
    let choose: (DirectoryEntry, Bool) -> Void
    let remove: (DirectoryEntry) -> Void
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let offsets = Self.offsets(sections)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.title(section))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, Vrai.Space.s8)
                                .padding(.top, Vrai.Space.s6)
                                .padding(.bottom, Vrai.Space.s4)
                                .accessibilityAddTraits(.isHeader)
                                .id(section.id)
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { entryIndex, entry in
                                let index = offsets[sectionIndex] + entryIndex
                                SwitcherRow(entry: entry, index: index, current: entry.path == current, cursor: cursor, choose: choose, remove: remove)
                                    .id(index)
                            }
                        }
                    }
                }
                .padding(Vrai.Space.s6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(contentHeight > maxHeight ? .automatic : .never)
            .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : min(maxHeight, SwitcherView.rowHeight * 6))
            .onChange(of: cursor.active) { old, active in
                if active < old, let first = sections.indices.first(where: { offsets[$0] == active }) {
                    proxy.scrollTo(sections[first].id)
                } else {
                    proxy.scrollTo(active)
                }
            }
            .task {
                proxy.scrollTo(cursor.active, anchor: .center)
            }
        }
    }

    static func title(_ section: DirectorySection) -> String {
        switch section.kind {
        case .recent: String(localized: "Recent", bundle: .module)
        case .owner(let name): name
        case .other: String(localized: "Other", bundle: .module)
        }
    }

    static func offsets(_ sections: [DirectorySection]) -> [Int] {
        var out: [Int] = []
        var running = 0
        for section in sections {
            out.append(running)
            running += section.entries.count
        }
        return out
    }
}

struct SwitcherRow: View {
    let entry: DirectoryEntry
    let index: Int
    let current: Bool
    let cursor: PaletteCursor
    let choose: (DirectoryEntry, Bool) -> Void
    let remove: (DirectoryEntry) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let active = cursor.active == index
        let status = app.directoryStatus[entry.path]
        let missing = status?.missing == true
        Button {
            choose(entry, false)
        } label: {
            HStack(spacing: Vrai.Space.s8) {
                Image(systemName: "folder")
                    .foregroundStyle(active ? Color.white : (missing ? Color.Vrai.textDisabled : (current ? Color.Vrai.accent : Color.secondary)))
                    .frame(width: Vrai.Size.iconSm)
                Text(entry.name)
                    .fontWeight(current ? .semibold : nil)
                    .foregroundStyle(active ? Color.white : (missing ? Color.secondary : Color.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                if missing {
                    Text("Missing", bundle: .module)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(active ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                        .fixedSize()
                } else if let status {
                    AheadBehind(ahead: status.ahead, behind: status.behind)
                        .fixedSize()
                        .environment(\.backgroundProminence, active ? .increased : .standard)
                    if status.changes > 0 {
                        Circle()
                            .fill(active ? Color.white : Color.Vrai.accent)
                            .frame(width: Vrai.Space.s8, height: Vrai.Space.s8)
                            .help(n(status.changes, "change"))
                    }
                }
                if current {
                    Image(systemName: "checkmark")
                        .font(Font.Vrai.caption)
                        .foregroundStyle(active ? Color.white : Color.Vrai.accent)
                }
            }
            .foregroundStyle(active ? Color.white : Color.primary)
            .padding(.horizontal, Vrai.Space.s8)
            .frame(height: SwitcherView.rowHeight)
            .background(active ? Color.Vrai.accent : Color.clear, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside, cursor.active != index { cursor.active = index }
        }
        .contextMenu {
            Button(String(localized: "Open in new window", bundle: .module)) { choose(entry, true) }
                .disabled(missing)
            Button(String(localized: "Show in Finder", bundle: .module)) { LongTailReveal.show([URL(filePath: entry.path)]) }
                .disabled(missing)
            Divider()
            Button(String(localized: "Remove from list", bundle: .module)) { remove(entry) }
        }
        .help(app.displayPath(URL(filePath: entry.path)))
        .accessibilityLabel(accessibilityText(status))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("switcher-row")
    }

    func accessibilityText(_ status: RecentStatus?) -> String {
        var parts = [entry.name]
        if let owner = entry.owner { parts.append(owner) }
        if current { parts.append(String(localized: "current repository", bundle: .module)) }
        if let status {
            if status.missing {
                parts.append(String(localized: "missing", bundle: .module))
            } else {
                let sync = AheadBehind.help(ahead: status.ahead, behind: status.behind)
                if !sync.isEmpty { parts.append(sync) }
                if status.changes > 0 { parts.append(n(status.changes, "change")) }
            }
        }
        return parts.joined(separator: ", ")
    }
}
