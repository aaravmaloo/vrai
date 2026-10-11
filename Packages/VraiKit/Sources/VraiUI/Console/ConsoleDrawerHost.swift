import AppKit
import SwiftUI
import VraiCore
import VraiGit

struct ConsoleDrawerHost: View {
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(spacing: 0) {
            if window.console.open {
                ConsoleDrawer()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: store.console.failures) { old, new in
            guard new > old, preferences.consoleOnFailure else { return }
            window.console.open = true
        }
    }
}

enum ConsoleLine: Identifiable {
    case entry(ConsoleEntry, quiet: Bool)
    case group(UUID, [ConsoleEntry])

    var id: String {
        switch self {
        case .entry(let entry, _): "e:" + entry.id.uuidString
        case .group(let id, _): "g:" + id.uuidString
        }
    }

    static func build(_ entries: [ConsoleEntry], filter: ConsoleFilter, needle: String, output: (ConsoleEntry) -> String) -> [ConsoleLine] {
        let lowered = needle.lowercased()
        let kept = entries.filter { entry in
            switch filter {
            case .all: break
            case .failed: if !entry.failed { return false }
            case .background: if !entry.background { return false }
            }
            guard !lowered.isEmpty else { return true }
            return entry.command.lowercased().contains(lowered) || output(entry).lowercased().contains(lowered)
        }
        guard filter == .all, lowered.isEmpty else { return kept.map { .entry($0, quiet: $0.background) } }
        var lines: [ConsoleLine] = []
        var run: [ConsoleEntry] = []
        func flush() {
            if run.count >= 2, let first = run.first {
                lines.append(.group(first.id, run))
            } else {
                lines.append(contentsOf: run.map { .entry($0, quiet: true) })
            }
            run.removeAll()
        }
        for entry in kept {
            if entry.background && !entry.failed {
                run.append(entry)
            } else {
                flush()
                lines.append(.entry(entry, quiet: entry.background))
            }
        }
        flush()
        return lines
    }
}

struct ConsoleDrawer: View {
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.widthClass) private var widthClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStart: CGFloat?
    @FocusState private var promptFocused: Bool

    static let barHeight = Vrai.Size.control + Vrai.Space.s6
    static let minimumHeight = barHeight * 2 + Vrai.Size.row
    static let contentReserve = Vrai.Size.toolbar + Vrai.Space.s64 * 2 + Vrai.Space.s32

    var height: CGFloat {
        let wanted = max(Self.minimumHeight, window.console.height)
        let total = window.sync.windowHeight
        guard total > 0 else { return wanted }
        let room = total - Self.contentReserve - (widthClass.isNarrow ? Vrai.Space.s40 : 0)
        return max(Self.minimumHeight, min(wanted, room))
    }

    var body: some View {
        @Bindable var console = window.console
        VStack(spacing: 0) {
            header(console)
            list(console)
            if let notice = console.notice {
                HStack(alignment: .top, spacing: Vrai.Space.s8) {
                    Symbol("info.circle", font: Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                    Text(notice)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconButton(icon: "xmark", label: String(localized: "Dismiss", bundle: .module), small: true) { console.notice = nil }
                }
                .padding(.horizontal, Vrai.Space.s12)
                .padding(.vertical, Vrai.Space.s6)
                .background(Color.Vrai.bg)
                .hairline(.top)
            }
            prompt(console)
        }
        .frame(height: height)
        .background(Color.Vrai.bgSubtle)
        .hairline(.top)
        .overlay(alignment: .top) { resizeHandle }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Console", bundle: .module))
        .accessibilityIdentifier("console")
    }

    var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: Vrai.Space.s6)
            .contentShape(Rectangle())
            .offset(y: -Vrai.Space.s2)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? height
                        if dragStart == nil { dragStart = start }
                        window.console.height = max(Self.minimumHeight, start - value.translation.height)
                    }
                    .onEnded { _ in
                        window.console.height = height
                        dragStart = nil
                    }
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder func header(_ console: ConsoleModel) -> some View {
        @Bindable var console = console
        let log = store.console
        let failed = log.entries.filter(\.failed).count
        let narrow = widthClass.isNarrow
        HStack(spacing: Vrai.Space.s8) {
            Text("Console", bundle: .module)
                .font(Font.Vrai.headline)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, Vrai.Space.s4)
                .accessibilityAddTraits(.isHeader)
            if !narrow {
                SearchField(text: $console.query, placeholder: String(localized: "Filter", bundle: .module))
                    .frame(maxWidth: Vrai.Space.s64 * 3)
                    .accessibilityLabel(Text("Filter commands and output", bundle: .module))
            }
            SegmentedControl(selection: $console.filter, items: [
                SegmentItem(value: ConsoleFilter.all, title: String(localized: "All", bundle: .module), label: String(localized: "All", bundle: .module)),
                SegmentItem(value: ConsoleFilter.failed, title: failed > 0 ? String(localized: "Failed \(failed)", bundle: .module) : String(localized: "Failed", bundle: .module), label: String(localized: "Failed", bundle: .module)),
                SegmentItem(value: ConsoleFilter.background, title: String(localized: "Background", bundle: .module), label: String(localized: "Background", bundle: .module))
            ])
            .accessibilityLabel(Text("Show", bundle: .module))
            Spacer(minLength: 0)
            Button {
                log.clear()
                console.openGroups.removeAll()
            } label: {
                HStack(spacing: Vrai.Space.s4) {
                    Symbol("trash", font: Font.Vrai.callout)
                    if widthClass != .compact { Text("Clear", bundle: .module) }
                }
            }
            .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
            .disabled(log.entries.isEmpty)
            .help(String(localized: "Clear", bundle: .module))
            .accessibilityLabel(Text("Clear", bundle: .module))
            IconButton(icon: "xmark", label: String(localized: "Hide console", bundle: .module), small: true) {
                withAnimation(reduceMotion ? Animation.Vrai.standardFast : Animation.Vrai.standardBase) { console.open = false }
            }
        }
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s6)
        .frame(height: Self.barHeight)
        .hairline(.bottom)
    }

    @ViewBuilder func list(_ console: ConsoleModel) -> some View {
        let log = store.console
        let needle = widthClass.isNarrow ? "" : console.query.trimmingCharacters(in: .whitespaces)
        let lines = ConsoleLine.build(log.entries, filter: console.filter, needle: needle) { log.output(of: $0) }
        let running = console.filter == .failed ? [] : log.running
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        switch line {
                        case .entry(let entry, let quiet):
                            ConsoleEntryRow(entry: entry, open: log.isExpanded(entry.id), quiet: quiet) { log.toggle(entry.id) }
                        case .group(let id, let entries):
                            ConsoleGroupRow(entries: entries, open: console.openGroups.contains(id)) {
                                if console.openGroups.contains(id) { console.openGroups.remove(id) } else { console.openGroups.insert(id) }
                            }
                            if console.openGroups.contains(id) {
                                ForEach(entries) { entry in
                                    ConsoleEntryRow(entry: entry, open: log.isExpanded(entry.id), quiet: true) { log.toggle(entry.id) }
                                }
                            }
                        }
                    }
                    ForEach(running) { item in
                        ConsoleRunningRow(item: item) { window.console.cancelAll() }
                    }
                    Color.clear
                        .frame(height: Metrics.hairline)
                        .id("console-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if lines.isEmpty, running.isEmpty {
                    Text(emptyText(log: log, console: console, needle: needle))
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(Vrai.Space.s16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.Vrai.bg)
            .frame(maxHeight: .infinity)
            .onChange(of: log.revision, initial: true) { _, _ in proxy.scrollTo("console-bottom", anchor: .bottom) }
            .onChange(of: console.filter) { _, _ in proxy.scrollTo("console-bottom", anchor: .bottom) }
            .onChange(of: log.running.count) { _, _ in proxy.scrollTo("console-bottom", anchor: .bottom) }
        }
    }

    func emptyText(log: ConsoleLog, console: ConsoleModel, needle: String) -> String {
        if log.entries.isEmpty { return String(localized: "No commands yet. Every git command Vrai runs shows up here, with its output.", bundle: .module) }
        if !needle.isEmpty { return String(localized: "No commands match \u{201C}\(needle)\u{201D}.", bundle: .module) }
        switch console.filter {
        case .failed: return String(localized: "No failed commands.", bundle: .module)
        case .background: return String(localized: "No background commands.", bundle: .module)
        case .all: return String(localized: "No commands yet. Every git command Vrai runs shows up here, with its output.", bundle: .module)
        }
    }

    @ViewBuilder func prompt(_ console: ConsoleModel) -> some View {
        @Bindable var console = console
        Group {
            if preferences.expert {
                HStack(spacing: Vrai.Space.s8) {
                    Text(verbatim: "$")
                        .font(Font.Vrai.code)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .accessibilityHidden(true)
                    TextField(text: $console.prompt) {
                        Text(verbatim: "git status").foregroundStyle(Color.Vrai.textTertiary)
                    }
                    .textFieldStyle(.plain)
                    .font(Font.Vrai.code)
                    .foregroundStyle(Color.Vrai.text)
                    .autocorrectionDisabled()
                    .focused($promptFocused)
                    .onSubmit { submit(console) }
                    .onKeyPress(.upArrow) { console.recall(store.console.history, older: true) ? .handled : .ignored }
                    .onKeyPress(.downArrow) { console.recall(store.console.history, older: false) ? .handled : .ignored }
                    .onKeyPress(.escape) {
                        promptFocused = false
                        return .handled
                    }
                    .onChange(of: console.prompt) { _, _ in
                        if console.notice != nil, !console.prompt.isEmpty { console.notice = nil }
                    }
                    .accessibilityLabel(Text("Run a git command", bundle: .module))
                    .accessibilityIdentifier("console-prompt")
                    if !store.console.running.isEmpty {
                        Spinner()
                    }
                }
                .padding(.horizontal, Vrai.Space.s12)
                .contentShape(Rectangle())
                .onTapGesture { promptFocused = true }
                .onChange(of: console.focusPrompt, initial: true) { _, value in
                    guard value else { return }
                    promptFocused = true
                    console.focusPrompt = false
                }
            } else {
                HStack(spacing: Vrai.Space.s8) {
                    Symbol("terminal", font: Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textTertiary)
                    Text("Run your own git commands here.", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(ConsoleCopy.turnOnExpert) { window.toggleExpert() }
                        .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
                        .fixedSize()
                }
                .padding(.horizontal, Vrai.Space.s12)
            }
        }
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background(Color.Vrai.bg)
        .hairline(.top)
    }

    func submit(_ console: ConsoleModel) {
        let text = console.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        console.prompt = ""
        console.resetRecall()
        if text.lowercased() == "clear" {
            store.console.clear()
            console.openGroups.removeAll()
            return
        }
        window.runTyped(text)
        promptFocused = true
    }
}
