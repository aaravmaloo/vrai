import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VraiCore
import VraiGit

enum CloneHistoryChoice: String, Hashable, CaseIterable {
    case full
    case blobless
    case shallow

    var history: CloneHistory {
        switch self {
        case .full: .full
        case .blobless: .blobless
        case .shallow: .shallow(depth: 50)
        }
    }
}

@MainActor
@Observable
final class CloneRunner {
    var progress: CloneProgress?
    var failure: (title: String, message: String)?
    var running = false
    var hidden = false
    @ObservationIgnored var handle: CloneHandle?

    func start(_ request: CloneRequest, app: AppModel, context: AppSheetContext, name: String, folder: String) {
        failure = nil
        progress = nil
        running = true
        hidden = false
        let handle = app.startClone(request)
        self.handle = handle
        Task { @MainActor in
            for await event in handle.progress { self.progress = event }
        }
        Task { @MainActor in
            do {
                let reference = try await handle.value
                self.running = false
                if request.opensWindow {
                    if !self.hidden { context.dismiss() }
                    context.toasts?.show(Toast(message: String(localized: "Cloned \(name)", bundle: .module), detail: String(localized: "Into \(folder).", bundle: .module), icon: "square.and.arrow.down"))
                    context.opened(reference)
                } else {
                    if !self.hidden { context.dismiss() }
                    context.toasts?.show(Toast(message: String(localized: "Cloned \(name)", bundle: .module), detail: request.mirror ? String(localized: "A mirror, with every ref, in \(folder).", bundle: .module) : String(localized: "A bare repository in \(folder).", bundle: .module), icon: "square.and.arrow.down"))
                    LongTailReveal.show([reference.url])
                }
            } catch {
                self.running = false
                if let error = error as? GitError, error.code == .cancelled {
                    if !self.hidden { context.dismiss() }
                    return
                }
                let copy = LongTailCopy.cloneFailure(error, url: request.url, folder: folder)
                if self.hidden {
                    context.toasts?.show(Toast(tone: .danger, message: copy.title, detail: copy.message))
                } else {
                    self.failure = copy
                }
            }
        }
    }

    func cancel() {
        handle?.cancel()
    }
}

struct CloneSheet: View {
    let initialURL: String?
    let context: AppSheetContext
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var preferences
    @State private var url = ""
    @State private var path = ""
    @State private var branch = ""
    @State private var submodules = true
    @State private var history = CloneHistoryChoice.full
    @State private var bare = false
    @State private var mirror = false
    @State private var scalar = false
    @State private var heads: RemoteHeads?
    @State private var headsNote: String?
    @State private var loadingHeads = false
    @State private var suggestion: String?
    @State private var runner = CloneRunner()

    init(initialURL: String?, context: AppSheetContext) {
        self.initialURL = initialURL
        self.context = context
        _url = State(initialValue: initialURL ?? "")
    }

    var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    var valid: Bool { AppModel.isCloneURL(trimmedURL) }
    var name: String { AppModel.repositoryName(fromURL: trimmedURL) }
    var isBundle: Bool { AppModel.isBundlePath(trimmedURL) }
    var destination: String { path.isEmpty ? (trimmedURL.isEmpty ? "" : "~/Developer/" + name) : path }

    var sourceURL: String {
        guard isBundle, trimmedURL.hasPrefix("~") else { return trimmedURL }
        return app.expandingTilde(trimmedURL, directory: false).path(percentEncoded: false)
    }

    var request: CloneRequest {
        let target = app.expandingTilde(destination.isEmpty ? "~/Developer/repository" : destination)
        let chosen = branch.isEmpty ? nil : (branch == heads?.defaultBranch ? nil : branch)
        let expert = preferences.expert
        return CloneRequest(url: sourceURL.isEmpty ? "<url>" : sourceURL, destination: target, branch: chosen, history: isBundle ? .full : history.history, recurseSubmodules: submodules, bare: expert && bare, mirror: expert && mirror, scalar: expert && scalar && !isBundle)
    }

    var urlError: String? {
        guard !trimmedURL.isEmpty, !valid else { return nil }
        return String(localized: "That doesn't look like a git URL. Try git@host:owner/repo.git or https://host/owner/repo.git.", bundle: .module)
    }

    var body: some View {
        if runner.running || runner.progress != nil, runner.failure == nil {
            progressView
        } else {
            form
        }
    }

    var progressView: some View {
        let event = runner.progress
        return LongTailSheet(
            title: String(localized: "Cloning \(name)", bundle: .module),
            description: String(localized: "Into \(destination)", bundle: .module),
            width: Vrai.Size.sheetWide
        ) {
            VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                LongTailProgress(label: phaseLabel(event), detail: event?.fraction.map { "\(Int(($0 * 100).rounded()))%" }, fraction: event?.stage == .connecting ? nil : event?.fraction)
                Text(detailLine(event))
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("clone-detail")
            }
            .accessibilityIdentifier("clone-progress")
            if preferences.expert { SyncForm.CommandPreview(command: request.command) }
        } actions: {
            Button {
                runner.cancel()
            } label: {
                Text("Stop", bundle: .module)
            }
            .buttonStyle(VraiButtonStyle(variant: .secondary))
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("clone-stop")
            Button {
                runner.hidden = true
                context.dismiss()
                context.toasts?.show(Toast(message: String(localized: "Clone keeps going in the background", bundle: .module), detail: String(localized: "Vrai opens it when it's done.", bundle: .module), icon: "square.and.arrow.down"))
            } label: {
                Text("Hide", bundle: .module)
            }
            .buttonStyle(VraiButtonStyle(variant: .secondary))
        }
    }

    var form: some View {
        LongTailSheet(
            title: String(localized: "Clone a repository", bundle: .module),
            description: String(localized: "Copies a repository and its whole history to this Mac.", bundle: .module),
            width: Vrai.Size.sheetWide
        ) {
            if let failure = runner.failure {
                SyncForm.Callout(tone: .danger, title: failure.title, message: failure.message)
            }
            SyncForm.Input(label: String(localized: "URL", bundle: .module), text: $url, placeholder: String(localized: "git@github.com:owner/repo.git or https://\u{2026}", bundle: .module), error: urlError, mono: true, autofocus: true) { go() }
            if trimmedURL.isEmpty, let suggestion {
                HStack(spacing: Vrai.Space.s4) {
                    Text("From the clipboard:", bundle: .module)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                    Button {
                        url = suggestion
                    } label: {
                        Text(suggestion)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
                }
            }
            LongTailPathField(label: String(localized: "Where", bundle: .module), text: Binding(get: { destination }, set: { path = $0 }), placeholder: "~/Developer/repo", kind: .folder, home: app.homeFolder)
            SyncForm.Field(label: String(localized: "Branch", bundle: .module), hint: headsHint) {
                SyncForm.Select(selection: $branch, options: branchOptions, label: String(localized: "Branch", bundle: .module))
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(heads == nil || mirror)
            }
            SyncForm.Options(commands: [request.command], detail: String(localized: "History, submodules", bundle: .module)) {
                SyncForm.Checkbox(isOn: $submodules, label: String(localized: "Clone submodules too", bundle: .module), description: "--recurse-submodules", enabled: !bare && !mirror)
                SyncForm.Radios(selection: $history, choices: [
                    SyncForm.Choice(value: .full, label: String(localized: "Full history", bundle: .module)),
                    SyncForm.Choice(value: .blobless, label: String(localized: "All commits, file contents on demand", bundle: .module), description: String(localized: "Partial clone, --filter=blob:none. Fast for big repositories.", bundle: .module)),
                    SyncForm.Choice(value: .shallow, label: String(localized: "Last 50 commits", bundle: .module), description: String(localized: "--depth 50. Fetch more later.", bundle: .module))
                ], label: String(localized: "History", bundle: .module))
                .disabled(isBundle)
                if preferences.expert {
                    SyncForm.Checkbox(isOn: $bare, label: String(localized: "Bare repository", bundle: .module), description: String(localized: "No working tree, for servers and mirrors.", bundle: .module))
                    SyncForm.Checkbox(isOn: $mirror, label: String(localized: "Mirror every ref", bundle: .module), description: String(localized: "A bare copy that fetch keeps identical, --mirror.", bundle: .module))
                    SyncForm.Checkbox(isOn: $scalar, label: String(localized: "Large repository", bundle: .module), description: String(localized: "Clones with scalar: sparse, blobless, background maintenance.", bundle: .module), enabled: !isBundle)
                }
            }
        } footerStart: {
            Button {
                if let picked = LongTailPanels.pick(.openFile([UTType(filenameExtension: "bundle") ?? .data]), start: "~/Desktop", home: app.homeFolder) { url = picked }
            } label: {
                Label(String(localized: "Use a bundle file\u{2026}", bundle: .module), systemImage: "archivebox")
            }
            .buttonStyle(VraiButtonStyle(variant: .plain))
        } actions: {
            LongTailFoot(label: String(localized: "Clone", bundle: .module), enabled: valid && !destination.isEmpty, identifier: "clone-run", cancel: context.dismiss) { go() }
        }
        .task {
            if let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), text.count < 300, AppModel.isCloneURL(text), !text.hasPrefix("/") {
                suggestion = text
            }
        }
        .task(id: trimmedURL) { await loadHeads() }
    }

    var branchOptions: [SyncForm.Option<String>] {
        guard let heads, !heads.branches.isEmpty else {
            return [SyncForm.Option(value: "", label: String(localized: "Default branch", bundle: .module), icon: "arrow.triangle.branch")]
        }
        return heads.branches.map { name in
            SyncForm.Option(value: name, label: name == heads.defaultBranch ? String(localized: "\(name) (default)", bundle: .module) : name, icon: "arrow.triangle.branch")
        }
    }

    var headsHint: String? {
        if loadingHeads { return String(localized: "Reading branches\u{2026}", bundle: .module) }
        return headsNote
    }

    func loadHeads() async {
        heads = nil
        headsNote = nil
        branch = ""
        guard valid else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        loadingHeads = true
        defer { loadingHeads = false }
        do {
            let found = try await app.remoteHeads(url: sourceURL)
            guard !Task.isCancelled else { return }
            heads = found
            branch = found.defaultBranch ?? found.branches.first ?? ""
            if found.branches.isEmpty { headsNote = String(localized: "It has no branches yet.", bundle: .module) }
        } catch {
            guard !Task.isCancelled else { return }
            headsNote = String(localized: "Couldn't read its branches. Vrai clones the default branch.", bundle: .module)
        }
    }

    func go() {
        guard valid, !destination.isEmpty else { return }
        runner.start(request, app: app, context: context, name: name, folder: destination)
    }

    func phaseLabel(_ event: CloneProgress?) -> String {
        guard let event else { return String(localized: "Connecting", bundle: .module) }
        switch event.stage {
        case .connecting: return String(localized: "Connecting to \(host)", bundle: .module)
        case .submodules: return event.submodule.map { String(localized: "Cloning submodule \($0)", bundle: .module) } ?? String(localized: "Cloning submodules", bundle: .module)
        case .finished: return String(localized: "Opening \(name)", bundle: .module)
        default: return event.submodule.map { event.phase + " (" + $0 + ")" } ?? event.phase
        }
    }

    var host: String {
        if let match = trimmedURL.firstMatch(of: /@([^:\/]+)[:\/]/) { return String(match.output.1) }
        if let match = trimmedURL.firstMatch(of: /:\/\/(?:[^@\/]+@)?([^\/:]+)/) { return String(match.output.1) }
        return String(localized: "the remote", bundle: .module)
    }

    func detailLine(_ event: CloneProgress?) -> String {
        guard let event else { return " " }
        var parts: [String] = []
        if let current = event.current, let total = event.total {
            parts.append(String(localized: "\(current.formatted()) of \(total.formatted()) objects", bundle: .module))
        }
        if let transferred = event.transferred {
            parts.append(event.speed.map { String(localized: "\(transferred) at \($0)", bundle: .module) } ?? transferred)
        }
        return parts.isEmpty ? " " : parts.joined(separator: ", ")
    }
}
