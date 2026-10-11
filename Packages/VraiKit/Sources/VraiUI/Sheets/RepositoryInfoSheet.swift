import SwiftUI
import VraiCore
import VraiGit

struct RepositoryInfoSheet: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(AppModel.self) private var app
    @State private var info: RepositoryInfo?
    @State private var failure: String?

    var body: some View {
        LongTailSheet(
            title: info?.name ?? window.repositoryName,
            description: info.map { app.displayPath(URL(filePath: $0.path)) } ?? store.snapshot?.root.map { app.displayPath($0) },
            icon: "info.circle"
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "Vrai couldn't read the repository", bundle: .module), message: failure)
            } else if let info {
                VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                    rows(info)
                }
                .accessibilityIdentifier("repository-info")
            } else {
                HStack(spacing: Vrai.Space.s8) {
                    Spinner()
                    Text("Counting objects\u{2026}", bundle: .module)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.textSecondary)
                }
            }
        } footerStart: {
            VraiButton(title: "count-objects", icon: "terminal") {
                window.sheets.dismiss()
                window.console.open = true
            }
            .help(String(localized: "Open the console, where every command Vrai runs is logged", bundle: .module))
        } actions: {
            LongTailDone { window.sheets.dismiss() }
        }
        .task {
            do {
                info = try await store.repositoryInfo()
            } catch let error as GitError {
                failure = ErrorCopy(error).message
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    @ViewBuilder func rows(_ info: RepositoryInfo) -> some View {
        LongTailKeyValue(key: String(localized: "Commits", bundle: .module), value: String(localized: "\(info.commits.formatted()) on \(n(info.branches, "branch"))", bundle: .module))
        LongTailKeyValue(key: String(localized: "Contributors", bundle: .module), value: info.contributors.formatted())
        LongTailKeyValue(key: String(localized: "First commit", bundle: .module), value: firstCommit(info))
        LongTailKeyValue(key: String(localized: "Size on disk", bundle: .module), value: String(localized: "\(LongTailReveal.bytes(info.diskBytes)) in \(n(info.packs.count, "pack")), \(n(info.looseObjects, "loose object"))", bundle: .module))
        LongTailKeyValue(key: String(localized: "Remotes", bundle: .module), value: info.remotes.isEmpty ? String(localized: "None", bundle: .module) : info.remotes.joined(separator: ", "))
        LongTailKeyValue(key: String(localized: "Hooks", bundle: .module), value: info.hooks.isEmpty ? String(localized: "None", bundle: .module) : info.hooks.joined(separator: ", "))
        LongTailKeyValue(key: String(localized: "Git", bundle: .module), value: gitLine)
        if window.preferences.expert {
            LongTailKeyValue(key: String(localized: "Tags", bundle: .module), value: info.tags.formatted())
            LongTailKeyValue(key: String(localized: "Object format", bundle: .module), value: info.objectFormat, mono: true)
            LongTailKeyValue(key: String(localized: "Packs", bundle: .module), value: info.packs.isEmpty ? String(localized: "None", bundle: .module) : info.packs.map { String(localized: "\(n($0.objects, "object")), \(LongTailReveal.bytes($0.bytes))", bundle: .module) }.joined(separator: "\n"))
            if info.garbage > 0 {
                LongTailKeyValue(key: String(localized: "Garbage", bundle: .module), value: n(info.garbage, "file"))
            }
            LongTailKeyValue(key: String(localized: "Kind", bundle: .module), value: kind(info))
        }
    }

    func firstCommit(_ info: RepositoryInfo) -> String {
        guard let subject = info.firstSubject else { return String(localized: "None yet", bundle: .module) }
        guard let date = info.firstDate else { return subject }
        return subject + ", " + date.formatted(date: .abbreviated, time: .omitted)
    }

    func kind(_ info: RepositoryInfo) -> String {
        var parts: [String] = []
        if info.isBare { parts.append(String(localized: "bare", bundle: .module)) }
        if info.isShallow { parts.append(String(localized: "shallow", bundle: .module)) }
        if let filter = info.partialFilter { parts.append(String(localized: "partial clone (\(filter))", bundle: .module)) }
        if info.sparse { parts.append(String(localized: "sparse checkout", bundle: .module)) }
        return parts.isEmpty ? String(localized: "Full clone", bundle: .module) : parts.joined(separator: ", ")
    }

    var gitLine: String {
        guard let git = app.gitExecutable else { return String(localized: "Not found", bundle: .module) }
        return String(localized: "\(git.version.description) at \(git.path)", bundle: .module)
    }
}
