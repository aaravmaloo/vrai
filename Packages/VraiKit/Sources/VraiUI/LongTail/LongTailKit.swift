import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VraiCore
import VraiGit

enum LongTailMetrics {
    static let headerChrome = Vrai.Size.toolbar + Vrai.Space.s24
    static let minimumRoom = Vrai.Size.controlLg * 3
    static let editorLines = 8
    static let referenceHeight = Vrai.Size.sheetWide - Vrai.Space.s64
    static let listMax = Vrai.Space.s64 * 3
    static let welcomeHeight = Vrai.Size.sheet - Vrai.Space.s16
    static let welcomeTitlebar = Vrai.Space.s32
    static let welcomeContentHeight = welcomeHeight - welcomeTitlebar
    static let welcomeSheetRoom = welcomeHeight + Vrai.Space.s48
    static let welcomeWidth = Vrai.Size.sheetWide + Vrai.Space.s64 * 2
    static let welcomeRight = Vrai.Size.sheet - Vrai.Space.s24
    static let welcomeActions = Vrai.Size.field - Vrai.Space.s24
    static let repoTime = Vrai.Space.s64
    static let repoText = Vrai.Space.s64 + Vrai.Space.s48
    static let onboardingWidth = Vrai.Size.sheet
}

struct LongTailRoomKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var longTailRoom: CGFloat? {
        get { self[LongTailRoomKey.self] }
        set { self[LongTailRoomKey.self] = newValue }
    }
}

struct LongTailSheet<Content: View, Start: View, Actions: View>: View {
    let title: String
    var description: String?
    let icon: String
    var tone: Tone = .neutral
    var width: CGFloat = Vrai.Size.sheet
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footerStart: () -> Start
    @ViewBuilder let actions: () -> Actions
    @Environment(WindowModel.self) private var window: WindowModel?
    @Environment(\.longTailRoom) private var explicitRoom
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var total: CGFloat {
        if let explicitRoom { return explicitRoom }
        if let height = window?.sync.windowHeight, height > 0 { return height }
        return (NSScreen.main?.visibleFrame.height ?? Vrai.Size.sheetWide) - Vrai.Space.s64 * 2
    }

    var room: CGFloat? {
        guard headerHeight > 0, footerHeight > 0 else { return nil }
        let chrome = LongTailMetrics.headerChrome + headerHeight + footerHeight + Vrai.Space.s20 * 2 + Vrai.Space.s16 * 2
        return max(total - chrome, LongTailMetrics.minimumRoom)
    }

    var body: some View {
        let limit = room
        let scrolls = limit.map { contentHeight > $0 } ?? false
        VStack(alignment: .leading, spacing: Vrai.Space.s16) {
            HStack(alignment: .top, spacing: Vrai.Space.s12) {
                RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                    .fill(tone == .neutral ? Color.Vrai.fill : tone.soft)
                    .frame(width: Vrai.Space.s40, height: Vrai.Space.s40)
                    .overlay {
                        Symbol(icon, font: Font.Vrai.title1.weight(.regular))
                            .foregroundStyle(tone == .neutral ? Color.Vrai.textSecondary : tone.color)
                    }
                VStack(alignment: .leading, spacing: Vrai.Space.s4) {
                    Text(title)
                        .font(Font.Vrai.title2)
                        .foregroundStyle(Color.Vrai.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .accessibilityAddTraits(.isHeader)
                    if let description {
                        Text(description)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(Color.Vrai.textSecondary)
                            .lineLimit(4)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, Vrai.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Vrai.Space.s16) {
                    content()
                }
                .padding(Vrai.Size.focusHalo)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(scrolls ? .automatic : .never)
            .frame(height: contentHeight > 0 ? min(contentHeight, (limit ?? contentHeight) + Vrai.Size.focusHalo * 2) : nil)
            .padding(-Vrai.Size.focusHalo)
            HStack(spacing: Vrai.Space.s12) {
                HStack(spacing: Vrai.Space.s8) { footerStart() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Vrai.Space.s8) { actions() }
                    .fixedSize()
            }
            .padding(.top, Vrai.Space.s4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .padding(Vrai.Space.s20)
        .frame(width: width)
        .background(Color.Vrai.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension LongTailSheet where Start == EmptyView {
    init(title: String, description: String? = nil, icon: String, tone: Tone = .neutral, width: CGFloat = Vrai.Size.sheet, @ViewBuilder content: @escaping () -> Content, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title: title, description: description, icon: icon, tone: tone, width: width, content: content, footerStart: { EmptyView() }, actions: actions)
    }
}

struct LongTailFoot: View {
    let label: String
    var enabled = true
    var busy = false
    var danger = false
    var identifier: String?
    var cancelTitle: String?
    let cancel: @MainActor () -> Void
    let submit: @MainActor () -> Void

    var body: some View {
        Button(action: cancel) {
            Text(cancelTitle ?? String(localized: "Cancel", bundle: .module))
        }
        .buttonStyle(VraiButtonStyle(variant: .secondary))
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("longtail-cancel")
        Button {
            if enabled, !busy { submit() }
        } label: {
            HStack(spacing: Vrai.Space.s6) {
                if busy { Spinner() }
                Text(label)
            }
        }
        .buttonStyle(VraiButtonStyle(variant: danger ? .danger : .primary))
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled || busy)
        .accessibilityIdentifier(identifier ?? label)
    }
}

struct LongTailDone: View {
    var title: String?
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Text(title ?? String(localized: "Done", bundle: .module))
        }
        .buttonStyle(VraiButtonStyle(variant: .primary))
        .keyboardShortcut(.defaultAction)
    }
}

struct LongTailProgress: View {
    let label: String
    var detail: String?
    var fraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s6) {
            HStack(spacing: Vrai.Space.s8) {
                Text(label)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Vrai.Space.s8)
                if let detail {
                    Text(detail)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.Vrai.fillStrong)
                    if let fraction {
                        Capsule()
                            .fill(Color.Vrai.accent)
                            .frame(width: max(Vrai.Space.s4, geometry.size.width * min(max(fraction, 0), 1)))
                            .animation(reduceMotion ? nil : Animation.Vrai.standardBase, value: fraction)
                    } else {
                        Capsule()
                            .fill(Color.Vrai.accent)
                            .frame(width: geometry.size.width * 0.35)
                            .offset(x: sweep ? geometry.size.width * 0.65 : 0)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: Vrai.Space.s4)
            .onAppear {
                guard fraction == nil, !reduceMotion else { return }
                withAnimation(Animation.Vrai.standardSlow.repeatForever(autoreverses: true)) { sweep = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded())) percent" } ?? (detail ?? ""))
    }
}

struct LongTailKeyValue: View {
    let key: String
    let value: String
    var mono = false
    @Environment(\.widthClass) private var widthClass

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Vrai.Space.s12) {
            Text(key)
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textTertiary)
                .frame(width: widthClass.isNarrow ? Metrics.kvKeyNarrow : Metrics.kvKey, alignment: .leading)
            Text(value)
                .font(mono ? Font.Vrai.codeSmall : Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LongTailBox<Content: View>: View {
    var maxHeight: CGFloat? = LongTailMetrics.listMax
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                content()
            }
            .padding(Vrai.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(Color.Vrai.separator, lineWidth: Metrics.hairline))
    }
}

struct LongTailLine<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    let text: String
    var path = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            leading()
            if path {
                PathBar(path: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing()
        }
        .padding(.horizontal, Vrai.Space.s4)
        .frame(minHeight: Vrai.Size.controlSm)
    }
}

extension LongTailLine where Trailing == EmptyView {
    init(text: String, path: Bool = false, @ViewBuilder leading: @escaping () -> Leading) {
        self.init(leading: leading, text: text, path: path, trailing: { EmptyView() })
    }
}

struct LongTailCodeEditor: View {
    let label: String
    @Binding var text: String
    var lines = LongTailMetrics.editorLines
    var maxHeight: CGFloat?
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(Font.Vrai.code)
            .foregroundStyle(Color.Vrai.text)
            .scrollContentBackground(.hidden)
            .autocorrectionDisabled(true)
            .focused($focused)
            .accessibilityLabel(label)
            .accessibilityIdentifier("longtail-editor")
            .padding(.vertical, Vrai.Space.s6)
            .padding(.horizontal, Vrai.Space.s4)
            .frame(height: min(Vrai.Space.s20 * CGFloat(lines) + Vrai.Space.s12, maxHeight ?? .infinity))
            .background(focused ? Color.Vrai.bg : Color.Vrai.fill, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                    .strokeBorder(focused ? Color.Vrai.focus : Color.Vrai.border, lineWidth: Metrics.hairline)
            }
            .background {
                if focused {
                    RoundedRectangle(cornerRadius: Vrai.Radius.md + Vrai.Size.focusHalo, style: .continuous)
                        .fill(Color.Vrai.accentSoftStrong)
                        .padding(-Vrai.Size.focusHalo)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                focused = true
            }
    }
}

struct LongTailPathField: View {
    enum Kind {
        case folder
        case saveFile(String)
        case openFile([UTType])
    }

    let label: String
    @Binding var text: String
    var placeholder = ""
    var hint: String?
    var error: String?
    let kind: Kind
    var home: URL?
    var autofocus = false

    var body: some View {
        HStack(alignment: .bottom, spacing: Vrai.Space.s8) {
            SyncForm.Input(label: label, text: $text, placeholder: placeholder, hint: hint, error: error, mono: true, autofocus: autofocus)
            Button {
                if let picked = LongTailPanels.pick(kind, start: text, home: home) { text = picked }
            } label: {
                Text("Choose\u{2026}", bundle: .module)
            }
            .buttonStyle(VraiButtonStyle(variant: .secondary))
            .padding(.bottom, error != nil || hint != nil ? Vrai.Space.s20 : 0)
        }
    }
}

enum LongTailPanels {
    @MainActor static func pick(_ kind: LongTailPathField.Kind, start: String, home: URL?) -> String? {
        let expanded = expand(start, home: home)
        switch kind {
        case .folder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = existingFolder(expanded)
            panel.prompt = String(localized: "Choose", bundle: .module)
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return abbreviate(url, home: home)
        case .saveFile(let name):
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = expanded.map { $0.lastPathComponent } ?? name
            panel.directoryURL = existingFolder(expanded?.deletingLastPathComponent())
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return abbreviate(url, home: home)
        case .openFile(let types):
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            if !types.isEmpty { panel.allowedContentTypes = types }
            panel.directoryURL = existingFolder(expanded?.deletingLastPathComponent())
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return abbreviate(url, home: home)
        }
    }

    @MainActor static func pickFiles(home: URL?) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = home?.appending(path: "Downloads", directoryHint: .isDirectory)
        panel.prompt = String(localized: "Choose", bundle: .module)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    static func expand(_ text: String, home: URL?) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/"), let home { return home.appending(path: String(trimmed.dropFirst(2))) }
        return URL(filePath: trimmed)
    }

    static func existingFolder(_ url: URL?) -> URL? {
        var candidate = url
        while let current = candidate, current.path(percentEncoded: false) != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue { return current }
            candidate = current.deletingLastPathComponent()
        }
        return nil
    }

    static func abbreviate(_ url: URL, home: URL?) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlash()
        guard let home else { return path }
        let base = home.standardizedFileURL.path(percentEncoded: false).trimmingTrailingSlash()
        if path == base { return "~" }
        if path.hasPrefix(base + "/") { return "~" + path.dropFirst(base.count) }
        return path
    }
}

extension String {
    func trimmingTrailingSlash() -> String {
        var value = self
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

@MainActor
enum LongTailReveal {
    static func show(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

enum LongTailCopy {
    static func cloneFailure(_ error: Error, url: String, folder: String) -> (title: String, message: String) {
        guard let error = error as? GitError else {
            return (String(localized: "The clone didn't finish", bundle: .module), String(describing: error))
        }
        switch error.code {
        case .pathExists:
            return (String(localized: "\(folder) already exists", bundle: .module), String(localized: "It isn't empty, so git won't clone into it. Pick another folder or name.", bundle: .module))
        case .remoteNotFound:
            return (String(localized: "There's no repository at that address", bundle: .module), String(localized: "git couldn't find \(url). Check the URL, then try again.", bundle: .module))
        case .invalidURL:
            return (String(localized: "git doesn't understand that address", bundle: .module), String(localized: "Use git@host:owner/repo.git or https://host/owner/repo.git.", bundle: .module))
        case .authFailed(let host):
            return (String(localized: "\(host ?? "The server") didn't accept your credentials", bundle: .module), String(localized: "Sign in with a personal access token in Settings, Accounts, then clone again.", bundle: .module))
        case .networkUnreachable(let host):
            return (String(localized: "Can't reach \(host ?? "the server")", bundle: .module), String(localized: "Check your connection, then clone again.", bundle: .module))
        case .cancelled:
            return (String(localized: "Clone cancelled", bundle: .module), String(localized: "Nothing was left behind.", bundle: .module))
        default:
            let copy = ErrorCopy(error)
            return (String(localized: "The clone didn't finish", bundle: .module), copy.message)
        }
    }
}
