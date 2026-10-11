import SwiftUI
import VraiCore
import VraiGit

struct OpenSheet: View {
    let context: AppSheetContext
    @Environment(AppModel.self) private var app
    @State private var path = ""
    @State private var found: [FoundRepository] = []
    @State private var problem: OpenInspection?
    @State private var busy = false

    var body: some View {
        LongTailSheet(
            title: String(localized: "Open a repository", bundle: .module),
            description: String(localized: "Pick a folder with a git repository. Vrai also finds the repository from any folder inside it.", bundle: .module),
            icon: "folder"
        ) {
            LongTailPathField(label: String(localized: "Folder", bundle: .module), text: $path, placeholder: "~/Developer/vrai", kind: .folder, home: app.homeFolder, autofocus: true)
            switch problem {
            case .notARepository(let url):
                SyncForm.Callout(tone: .warning, title: String(localized: "\(url.lastPathComponent) isn't a git repository", bundle: .module), message: String(localized: "Create a repository in it, or pick the folder that holds the .git folder.", bundle: .module))
                HStack {
                    Spacer(minLength: 0)
                    VraiButton(title: String(localized: "Create a repository here\u{2026}", bundle: .module), icon: "folder.badge.plus") {
                        context.switchTo(.newRepository(folder: app.displayPath(url)))
                    }
                }
            case .missing(let url):
                SyncForm.Callout(tone: .danger, title: String(localized: "Vrai can't find \(app.displayPath(url))", bundle: .module), message: String(localized: "Check the path, or choose the folder instead.", bundle: .module))
            default:
                EmptyView()
            }
            if !found.isEmpty {
                Text("Repositories in ~/Developer", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                LongTailBox {
                    ForEach(found) { repository in
                        Button {
                            path = app.displayPath(repository.url)
                            open()
                        } label: {
                            HStack(spacing: Vrai.Space.s10) {
                                Symbol("folder", font: Font.Vrai.title3)
                                    .foregroundStyle(Color.Vrai.accentText)
                                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                                    Text(app.displayPath(repository.url))
                                        .font(Font.Vrai.headline)
                                        .foregroundStyle(Color.Vrai.text)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(repository.isWorktree ? String(localized: "Worktree, \(repository.detail)", bundle: .module) : repository.detail)
                                        .font(Font.Vrai.caption)
                                        .foregroundStyle(Color.Vrai.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Vrai.Space.s8)
                            .padding(.vertical, Vrai.Space.s6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverHighlight(radius: Vrai.Radius.sm)
                        .accessibilityIdentifier("open-" + repository.url.lastPathComponent)
                    }
                }
            }
        } actions: {
            LongTailFoot(label: String(localized: "Open", bundle: .module), enabled: !path.trimmingCharacters(in: .whitespaces).isEmpty, busy: busy, identifier: "open-run", cancel: context.dismiss) { open() }
        }
        .task {
            found = await app.nearbyRepositories(in: app.developerFolder)
        }
        .onChange(of: path) { problem = nil }
    }

    func open() {
        let typed = path.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            let inspection = await app.inspect(path: typed)
            guard case .repository = inspection else {
                problem = inspection
                return
            }
            do {
                let reference = try await app.open(path: app.expandingTilde(typed).path(percentEncoded: false))
                context.dismiss()
                context.opened(reference)
            } catch {
                problem = .notARepository(app.expandingTilde(typed))
            }
        }
    }
}
