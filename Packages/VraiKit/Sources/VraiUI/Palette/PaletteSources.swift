import SwiftUI
import VraiCore
import VraiGit

@MainActor
struct PaletteSources {
    let context: PaletteContext
    let search: PaletteSearch
    let mode: PaletteMode
    let query: String
    let narrow: Bool

    var window: WindowModel { context.window }
    var store: RepositoryStore { window.store }
    var expert: Bool { window.preferences.expert }

    static let common: [Regex<Substring>] = [#/^Fetch$/#, #/^New branch…$/#, #/^Merge into /#, #/^Rebase \S+…$/#, #/^Undo history…$/#, #/^Expert mode$/#]
    static let fileCandidates = 200
    static let commitCandidates = 5000

    func groups() -> [PaletteGroup<PaletteItem>] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let locals = branchItems()
        let remotes = remoteItems()
        var groups: [PaletteGroup<PaletteItem>] = []
        let exists = store.snapshot?.branches.contains { $0.name == q } == true || store.snapshot?.remoteBranches.contains { $0.fullName == q } == true
        let canCreate = !q.isEmpty && !q.contains(where: \.isWhitespace) && !exists && q.firstMatch(of: #/^git\b/#) == nil
        let create = PaletteItem(id: "create", label: String(localized: "Create branch \u{201C}\(q)\u{201D}\u{2026}", bundle: .module), glyph: .symbol("plus"), keywords: q) { _ in
            window.sync.newBranch(name: q)
        }
        if mode == .branches {
            groups.append(PaletteGroup(.branches, q.isEmpty ? locals : locals.filter { PaletteRanking.relevant($0, q) }, limit: q.isEmpty ? 50 : 8))
            groups.append(PaletteGroup(.remoteBranches, q.isEmpty ? remotes : remotes.filter { PaletteRanking.relevant($0, q) }, limit: q.isEmpty ? 50 : 6))
            if canCreate { groups.append(PaletteGroup(.newBranch, [create])) }
        } else if q.isEmpty {
            let suggestions = suggestionItems()
            if !suggestions.isEmpty { groups.append(PaletteGroup(.suggestions, suggestions, limit: 6)) }
            let recent = Array(locals.filter { !$0.current }.prefix(4))
            if !recent.isEmpty { groups.append(PaletteGroup(.recentBranches, recent, limit: 4)) }
            let actions = actionItems()
            let common = Self.common.compactMap { pattern in actions.first { $0.label.wholeMatch(of: pattern) != nil || $0.label.prefixMatch(of: pattern) != nil } }
            groups.append(PaletteGroup(.actions, common, limit: 6))
        } else {
            let actions = actionItems()
            let labels = Set(actions.map(\.label))
            let suggestions = suggestionItems().filter { !labels.contains($0.label) && PaletteRanking.match($0.label, q) >= 50 }
            if !suggestions.isEmpty { groups.append(PaletteGroup(.suggestions, suggestions, limit: 3)) }
            groups.append(PaletteGroup(.actions, actions, limit: 6))
            groups.append(PaletteGroup(.branches, locals, limit: 5))
            groups.append(PaletteGroup(.remoteBranches, remotes, limit: 3))
            if canCreate, q.contains("/") { groups.append(PaletteGroup(.newBranch, [create])) }
            groups.append(PaletteGroup(.tags, tagItems(), limit: 3))
            groups.append(PaletteGroup(.commits, commitItems(q), limit: 5))
            groups.append(PaletteGroup(.files, fileItems(q), limit: 5))
            groups.append(PaletteGroup(.code, codeItems(q), limit: 5))
            groups = PaletteRanking.filterRelevant(groups, q)
            if q.firstMatch(of: #/^git\b/#) == nil {
                groups = PaletteRanking.promoteTopHit(groups, q) { $0.id == $1.id }
            }
        }
        var arranged = PaletteRanking.arrange(groups, q)
        if let run = runItem(q) { arranged.insert(PaletteGroup(.run, [run], limit: 1), at: 0) }
        return arranged
    }

    func runItem(_ q: String) -> PaletteItem? {
        guard q.hasPrefix("git"), let parsed = CommandParser.parse(q), !parsed.subcommand.isEmpty else { return nil }
        let text = parsed.text
        return PaletteItem(id: "__run", label: text, glyph: .symbol("terminal"), shortcut: "\u{21A9}", risk: parsed.risk, command: true) { _ in
            window.runTyped(text)
        }
    }

    func actionItems() -> [PaletteItem] {
        var seen = Set<String>()
        var out: [PaletteItem] = []
        let all = CorePaletteActions.actions(context) + PaletteCatalog.actions(window)
        for action in all where action.enabled && (!action.expertOnly || expert) {
            let key = action.title.replacingOccurrences(of: "\u{2026}", with: "").lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let alternate = action.alternate
            let perform = action.perform
            out.append(PaletteItem(
                id: action.id,
                label: action.title,
                glyph: .symbol(action.icon),
                detail: action.detail,
                keywords: action.keywords.isEmpty ? nil : action.keywords.joined(separator: " "),
                shortcut: action.shortcut,
                danger: action.danger
            ) { option in
                if option, let alternate { alternate() } else { perform() }
            })
        }
        return out
    }

    func orderedBranches() -> [Branch] {
        guard let snapshot = store.snapshot else { return [] }
        let byName = Dictionary(snapshot.branches.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [Branch] = []
        var seen = Set<String>()
        if let current = snapshot.currentBranch {
            out.append(current)
            seen.insert(current.name)
        }
        for name in search.recent where !seen.contains(name) {
            if let branch = byName[name] {
                out.append(branch)
                seen.insert(name)
            }
        }
        for branch in snapshot.branches.sorted(by: { $0.name < $1.name }) where !seen.contains(branch.name) {
            out.append(branch)
            seen.insert(branch.name)
        }
        return out
    }

    func branchItems() -> [PaletteItem] {
        orderedBranches().map { branch in
            let current = branch.isCurrent
            let detail: String
            if current {
                detail = String(localized: "Current branch", bundle: .module)
            } else if branch.upstreamGone {
                detail = String(localized: "Upstream is gone", bundle: .module)
            } else if branch.ahead > 0 || branch.behind > 0 {
                var parts: [String] = []
                if branch.ahead > 0 { parts.append(String(localized: "\(branch.ahead) ahead", bundle: .module)) }
                if branch.behind > 0 { parts.append(String(localized: "\(branch.behind) behind", bundle: .module)) }
                detail = parts.joined(separator: ", ")
            } else if branch.upstream != nil {
                detail = String(localized: "Up to date", bundle: .module)
            } else {
                detail = String(localized: "Not published", bundle: .module)
            }
            let last = branch.name.split(separator: "/").last.map(String.init) ?? branch.name
            let name = branch.name
            return PaletteItem(id: "b:" + name, label: name, glyph: .lane("arrow.triangle.branch", branch.colorIndex), detail: detail, keywords: last + " " + (branch.upstream ?? ""), current: current) { option in
                if current {
                    window.store.showRef(name)
                } else {
                    window.sync.switchTo(name, carry: option ? .bring : .none)
                }
            }
        }
    }

    func remoteItems() -> [PaletteItem] {
        guard let snapshot = store.snapshot else { return [] }
        let current = snapshot.currentBranch?.name
        return snapshot.remoteBranches.filter { $0.name != "HEAD" }.map { remote in
            let local = snapshot.branches.contains { $0.name == remote.name }
            let isUpstream = local && current == remote.name
            let detail = isUpstream ? String(localized: "Upstream of \(remote.name)", bundle: .module) : local ? String(localized: "Switch to \(remote.name)", bundle: .module) : String(localized: "Check out as \(remote.name)", bundle: .module)
            return PaletteItem(id: "rb:" + remote.fullName, label: remote.fullName, glyph: .lane("cloud", remote.colorIndex), detail: detail) { _ in
                if isUpstream {
                    window.store.showRef(remote.fullName)
                } else if local {
                    window.sync.switchTo(remote.name)
                } else {
                    window.sync.checkOut(remote: remote)
                }
            }
        }
    }

    func tagItems() -> [PaletteItem] {
        guard let snapshot = store.snapshot else { return [] }
        return snapshot.tags.sorted { $0.name > $1.name }.map { tag in
            var detail = tag.target.short(expert: expert)
            if let index = store.history.index[tag.target] {
                detail += " " + store.history.commits[index].subject
            } else if let message = tag.message?.split(separator: "\n").first {
                detail += " " + message
            }
            let name = tag.name
            let target = tag.target
            return PaletteItem(id: "t:" + name, label: name, glyph: .symbol("tag"), detail: detail) { option in
                if option { window.sync.confirmDetach(target, subject: nil) } else { window.store.showRef(name) }
            }
        }
    }

    func commitItem(_ commit: Commit) -> PaletteItem {
        let id = commit.id
        let detail = id.short(expert: expert) + ", " + commit.authorName + ", " + RelativeDate.text(commit.authorDate, now: window.now)
        return PaletteItem(id: "c:" + id.rawValue, label: commit.subject, glyph: .symbol("smallcircle.filled.circle"), detail: detail, keywords: id.rawValue + " " + commit.authorName) { _ in
            window.show(.history)
            window.store.showRef(id.rawValue)
            if window.widthClass == .compact { window.pane = .detail }
        }
    }

    func commitItems(_ q: String) -> [PaletteItem] {
        var out: [PaletteItem] = []
        var seen = Set<OID>()
        if search.commitQuery == q {
            for commit in search.commits where !seen.contains(commit.id) {
                seen.insert(commit.id)
                var item = commitItem(commit)
                item.keywords = (item.keywords ?? "") + " " + q
                out.append(item)
            }
        }
        for commit in store.history.commits.prefix(Self.commitCandidates) where !seen.contains(commit.id) {
            if PaletteRanking.match(commit.subject, q) > 0 || commit.id.rawValue.hasPrefix(q.lowercased()) || PaletteRanking.match(commit.authorName, q) >= 50 {
                seen.insert(commit.id)
                out.append(commitItem(commit))
            }
        }
        return out
    }

    func fileItems(_ q: String) -> [PaletteItem] {
        let working = store.snapshot?.working ?? []
        var seen = Set<String>()
        var scored: [(item: PaletteItem, score: Double)] = []
        func consider(_ path: String, item: () -> PaletteItem) {
            guard !seen.contains(path) else { return }
            seen.insert(path)
            let parts = PathParts.split(path)
            let label = parts.name
            let directory = String(parts.directory.dropLast())
            let score = max(PaletteRanking.match(label, q), PaletteRanking.match(path, q) * 0.9, PaletteRanking.match(directory, q) * 0.6)
            guard score > 0 else { return }
            scored.append((item(), score))
        }
        for file in working where file.status != .conflicted {
            consider(file.path) {
                let parts = PathParts.split(file.path)
                let path = file.path
                let blame = file.status != .untracked && file.status != .added
                let side: LineSelection.Side = file.staged == .full ? .staged : .unstaged
                return PaletteItem(id: "f:" + path, label: parts.name, glyph: .file(ChangeGroups.statusLetter(file, side: side)), detail: parts.directory.isEmpty ? String(localized: "Repository root", bundle: .module) : String(parts.directory.dropLast()), keywords: path) { option in
                    if option, blame {
                        window.openBlame(path: path)
                    } else {
                        window.show(.changes)
                        window.changes.select(ChangesPick(path: path, side: side), store: window.store, narrow: window.widthClass.isNarrow)
                    }
                }
            }
        }
        for path in search.files {
            consider(path) {
                let parts = PathParts.split(path)
                return PaletteItem(id: "f:" + path, label: parts.name, glyph: .symbol(PaletteFileIcon.symbol(for: path)), detail: parts.directory.isEmpty ? String(localized: "Repository root", bundle: .module) : String(parts.directory.dropLast()), keywords: path) { option in
                    if option { window.openBlame(path: path) } else { window.openFileHistory(path: path) }
                }
            }
        }
        return scored.sorted { $0.score > $1.score }.prefix(Self.fileCandidates).map(\.item)
    }

    func codeItems(_ q: String) -> [PaletteItem] {
        guard search.codeQuery == q else { return [] }
        return search.code.map { match in
            let path = match.path
            let text = match.text.trimmingCharacters(in: .whitespaces)
            return PaletteItem(id: "g:" + match.id, label: text.isEmpty ? path : text, glyph: .symbol("text.magnifyingglass"), detail: path + ":" + String(match.line), keywords: q + " " + path, command: true) { option in
                if option { window.openFileHistory(path: path) } else { window.openBlame(path: path) }
            }
        }
    }

    func suggestionItems() -> [PaletteItem] {
        guard let snapshot = store.snapshot else { return [] }
        let head = window.headName
        let details = store.stateDetails
        var out: [PaletteItem] = []
        let conflicts = snapshot.working.filter { $0.status == .conflicted }
        switch snapshot.state {
        case .merging(let source):
            if let first = conflicts.first {
                out.append(PaletteItem(id: "s:resolve", label: String(localized: "Resolve \(n(conflicts.count, "conflict"))", bundle: .module), glyph: .symbol("exclamationmark.triangle"), detail: String(localized: "Merging \(source ?? "")", bundle: .module)) { _ in
                    window.show(.changes)
                    window.changes.select(ChangesPick(path: first.path, side: .unstaged, conflict: true), store: window.store, narrow: window.widthClass.isNarrow)
                })
            } else {
                out.append(PaletteItem(id: "s:merge", label: String(localized: "Commit the merge", bundle: .module), glyph: .symbol("checkmark.circle"), detail: String(localized: "\(source ?? "") into \(head)", bundle: .module)) { _ in window.focusComposer() })
            }
            out.append(PaletteItem(id: "s:abort", label: String(localized: "Abort the merge", bundle: .module), glyph: .symbol("xmark.circle.fill"), detail: String(localized: "\(head) goes back to where it was", bundle: .module)) { _ in RewriteActions.abort(window) })
        case .rebasing(_, _, let stopped, _, _, _):
            out.append(PaletteItem(id: "s:continue", label: String(localized: "Continue the rebase", bundle: .module), glyph: .symbol("play.fill"), detail: stopped.map { String(localized: "Stopped at \($0.short)", bundle: .module) }) { _ in RewriteActions.continueOperation(window) })
            if let stopped {
                out.append(PaletteItem(id: "s:skip", label: String(localized: "Skip \(stopped.short)", bundle: .module), glyph: .symbol("forward.end"), detail: details.subject) { _ in RewriteActions.continueOperation(window, skip: true) })
            }
            out.append(PaletteItem(id: "s:abort", label: String(localized: "Abort the rebase", bundle: .module), glyph: .symbol("xmark.circle.fill"), detail: String(localized: "\(head) goes back to where it was", bundle: .module)) { _ in RewriteActions.abort(window) })
        case .bisecting(_, _, let current, _):
            if let found = details.bisect?.found {
                out.append(PaletteItem(id: "s:found", label: String(localized: "Show \(found.short), the first bad commit", bundle: .module), glyph: .symbol("scope")) { _ in window.store.showRef(found.rawValue) })
            } else if let current {
                let steps = details.bisect.map { max(1, $0.steps - $0.done) } ?? 1
                let left = String(localized: "About \(n(steps, "step")) left", bundle: .module)
                out.append(PaletteItem(id: "s:good", label: String(localized: "Mark \(current.short) as good", bundle: .module), glyph: .symbol("checkmark.circle"), detail: left) { _ in RewriteActions.markBisect(window, .good) })
                out.append(PaletteItem(id: "s:bad", label: String(localized: "Mark \(current.short) as bad", bundle: .module), glyph: .symbol("xmark.circle.fill"), detail: left) { _ in RewriteActions.markBisect(window, .bad) })
                out.append(PaletteItem(id: "s:skip", label: String(localized: "Skip \(current.short)", bundle: .module), glyph: .symbol("forward.end"), detail: String(localized: "Can't test this one", bundle: .module)) { _ in RewriteActions.markBisect(window, .skip) })
            }
            out.append(PaletteItem(id: "s:end", label: String(localized: "End bisect", bundle: .module), glyph: .symbol("flag.checkered"), detail: details.previousBranch.map { String(localized: "Back to \($0)", bundle: .module) }) { _ in RewriteActions.endBisect(window) })
        case .detached(let id, _):
            out.append(PaletteItem(id: "s:branch-here", label: String(localized: "Create branch here\u{2026}", bundle: .module), glyph: .symbol("arrow.triangle.branch"), detail: String(localized: "Keeps what you commit at \(id.short)", bundle: .module)) { _ in window.sync.newBranch(from: id.rawValue, checkout: true) })
            if let previous = details.previousBranch {
                out.append(PaletteItem(id: "s:back", label: String(localized: "Switch back to \(previous)", bundle: .module), glyph: .symbol("arrow.uturn.backward")) { _ in window.sync.switchTo(previous) })
            }
        default:
            break
        }
        let operating = snapshot.state.isOperationInProgress
        let rebasing: Bool = {
            if case .rebasing = snapshot.state { return true }
            return false
        }()
        if !operating || rebasing {
            let staged = window.changeGroups.staged.count
            if staged > 0 {
                out.append(PaletteItem(id: "s:commit", label: String(localized: "Commit \(n(staged, "staged file"))", bundle: .module), glyph: .symbol("checkmark.circle"), detail: String(localized: "On \(head)", bundle: .module), shortcut: "\u{2318}\u{21A9}") { _ in window.focusComposer() })
            } else if !snapshot.working.isEmpty {
                out.append(PaletteItem(id: "s:review", label: String(localized: "Review \(n(snapshot.working.count, "change"))", bundle: .module), glyph: .symbol("square.and.pencil"), shortcut: "\u{2318}2") { _ in window.show(.changes) })
            }
        }
        if let branch = snapshot.currentBranch, !operating {
            if branch.behind > 0, let upstream = branch.upstream {
                out.append(PaletteItem(id: "s:pull", label: String(localized: "Pull \(n(branch.behind, "commit"))", bundle: .module), glyph: .symbol("arrow.down.to.line"), detail: String(localized: "From \(upstream)", bundle: .module), shortcut: "\u{21E7}\u{2318}L") { option in
                    if option { window.sync.openSync(.pull) } else { window.sync.pull() }
                })
            }
            if branch.ahead > 0, let upstream = branch.upstream {
                out.append(PaletteItem(id: "s:push", label: String(localized: "Push \(n(branch.ahead, "commit"))", bundle: .module), glyph: .symbol("arrow.up.to.line"), detail: String(localized: "To \(upstream)", bundle: .module), shortcut: "\u{21E7}\u{2318}P") { option in
                    if option { window.sync.openSync(.push) } else { window.sync.push() }
                })
            }
            if branch.upstream == nil, !snapshot.remotes.isEmpty {
                out.append(PaletteItem(id: "s:publish", label: String(localized: "Publish \(branch.name)\u{2026}", bundle: .module), glyph: .symbol("arrow.up.to.line"), detail: String(localized: "Push it and track it", bundle: .module)) { _ in window.sync.openSync(.push, publish: true) })
            }
        }
        if !operating, snapshot.headOID != nil, snapshot.working.contains(where: { $0.status != .conflicted }) {
            out.append(PaletteItem(id: "s:stash", label: String(localized: "Stash \(n(snapshot.working.count, "change"))\u{2026}", bundle: .module), glyph: .symbol("tray.and.arrow.down"), shortcut: "\u{21E7}\u{2318}S") { _ in RewriteActions.openStash(window) })
        }
        if !operating, snapshot.working.isEmpty, let latest = snapshot.stashes.first {
            out.append(PaletteItem(id: "s:apply", label: String(localized: "Apply the latest stash", bundle: .module), glyph: .symbol("tray.and.arrow.up"), detail: latest.message) { _ in RewriteActions.applyStash(window, index: 0, pop: false) })
        }
        return out
    }
}
