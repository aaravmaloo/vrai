import AppKit
import SwiftUI
import VraiCore
import VraiGit

enum ChecksCopy {
    static func state(_ state: CheckState) -> String {
        switch state {
        case .passed: String(localized: "Checks passed", bundle: .module)
        case .failed: String(localized: "Checks failed", bundle: .module)
        case .running: String(localized: "Checks running", bundle: .module)
        case .pending: String(localized: "Checks queued", bundle: .module)
        case .cancelled: String(localized: "Checks cancelled", bundle: .module)
        case .skipped: String(localized: "Checks skipped", bundle: .module)
        }
    }

    static func run(_ state: CheckState) -> String {
        switch state {
        case .passed: String(localized: "Passed", bundle: .module)
        case .failed: String(localized: "Failed", bundle: .module)
        case .running: String(localized: "Running", bundle: .module)
        case .pending: String(localized: "Queued", bundle: .module)
        case .cancelled: String(localized: "Cancelled", bundle: .module)
        case .skipped: String(localized: "Skipped", bundle: .module)
        }
    }

    static func summary(_ checks: CommitChecks) -> String {
        let total = checks.runs.count
        switch checks.state {
        case .failed?:
            let failed = checks.count(.failed)
            return failed == total ? String(localized: "\(n(total, "check")) failed", bundle: .module) : String(localized: "\(failed) of \(n(total, "check")) failed", bundle: .module)
        case .running?, .pending?:
            return checks.finishedCount == 0 ? String(localized: "\(n(total, "check")) running", bundle: .module) : String(localized: "\(checks.finishedCount) of \(n(total, "check")) done", bundle: .module)
        case .cancelled?:
            return String(localized: "Checks cancelled", bundle: .module)
        case .skipped?:
            return String(localized: "Checks skipped", bundle: .module)
        case .passed?:
            return String(localized: "\(n(total, "check")) passed", bundle: .module)
        case nil:
            return String(localized: "No checks", bundle: .module)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return String(localized: "\(total)s", bundle: .module) }
        if total < 3600 {
            let rest = total % 60
            return rest == 0 ? String(localized: "\(total / 60)m", bundle: .module) : String(localized: "\(total / 60)m \(rest)s", bundle: .module)
        }
        return String(localized: "\(total / 3600)h \((total % 3600) / 60)m", bundle: .module)
    }

    static func runDetail(_ run: CheckRun, now: Date) -> String? {
        if let seconds = run.duration(now: now), run.state != .pending { return Self.duration(seconds) }
        return run.state.isFinished ? nil : Self.run(run.state)
    }

    static func names(_ runs: [CheckRun]) -> String {
        let names = runs.map { $0.workflow ?? $0.name }
        var seen: Set<String> = []
        let unique = names.filter { seen.insert($0).inserted }
        let shown = unique.prefix(2).joined(separator: ", ")
        return unique.count > 2 ? String(localized: "\(shown) and \(unique.count - 2) more", bundle: .module) : shown
    }

    static func problem(_ problem: ChecksProblem?) -> String? {
        switch problem {
        case .signedOut?: String(localized: "GitHub didn't share checks for this repository. Sign in with the GitHub CLI, or save a token for github.com with git, then Vrai reads them.", bundle: .module)
        case .rateLimited?: String(localized: "GitHub's rate limit was reached. Checks refresh when it resets.", bundle: .module)
        case .offline?: String(localized: "GitHub can't be reached right now. Checks refresh when you're back online.", bundle: .module)
        case .server?: String(localized: "GitHub had a problem answering. Checks refresh shortly.", bundle: .module)
        case nil: nil
        }
    }
}

extension CheckState {
    var tone: Tone {
        switch self {
        case .passed: .success
        case .failed: .danger
        case .running, .pending: .warning
        case .cancelled, .skipped: .neutral
        }
    }
}

struct ChecksGlyph: View {
    let state: CheckState
    var size: CGFloat = Vrai.Size.iconSm - Vrai.Space.s4
    var vivid = false

    var body: some View {
        Group {
            switch state {
            case .running:
                IslandSpinner(tint: vivid ? IslandStyle.yellow : Color.Vrai.warning, line: max(Vrai.Size.line - Vrai.Space.s2 / 4, size / 7))
            case .passed:
                if vivid { IslandStyle.badge("checkmark.circle.fill", fill: IslandStyle.green) } else { Image(systemName: "checkmark.circle.fill").resizable().foregroundStyle(Color.Vrai.success) }
            case .failed:
                if vivid { IslandStyle.badge("xmark.circle.fill", fill: IslandStyle.red) } else { Image(systemName: "xmark.circle.fill").resizable().foregroundStyle(Color.Vrai.danger) }
            case .pending:
                Image(systemName: "circle.dashed").resizable().foregroundStyle(vivid ? IslandStyle.yellow : Color.Vrai.warning)
            case .cancelled:
                Image(systemName: "minus.circle").resizable().foregroundStyle(Color.Vrai.textSecondary)
            case .skipped:
                Image(systemName: "minus.circle").resizable().foregroundStyle(Color.Vrai.textTertiary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text(ChecksCopy.state(state)))
    }
}

struct ChecksPill: View {
    let id: OID
    let branch: String
    @Environment(WindowModel.self) private var window
    @State private var open = false

    var body: some View {
        let checks = window.checks
        if checks.isAvailable {
            let result = checks.results[id]
            Group {
                if let result, let state = result.state {
                    button {
                        ChecksGlyph(state: state)
                        Text(ChecksCopy.summary(result))
                    }
                    .help(ChecksCopy.state(state))
                } else if result != nil, checks.problem == .signedOut {
                    button {
                        Image(systemName: "lock")
                        Text("Checks need sign-in", bundle: .module)
                    }
                }
            }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ChecksPopover(id: id, branch: branch)
                    .environment(window)
                    .environment(window.toasts)
            }
            .task(id: id) { checks.request(id) }
        }
    }

    func button<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: Vrai.Space.s4) { label() }
                .font(Font.Vrai.callout)
                .padding(.horizontal, Vrai.Space.s6)
                .frame(height: Vrai.Space.s20)
                .background(Color.Vrai.fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("checks-pill")
    }
}

struct ChecksPopover: View {
    let id: OID
    let branch: String
    @Environment(WindowModel.self) private var window
    @Environment(\.vraiNow) private var fixedNow
    @State private var busy = false

    var body: some View {
        let checks = window.checks
        let result = checks.results[id]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Vrai.Space.s10) {
                if let state = result?.state {
                    ChecksGlyph(state: state, size: Vrai.Size.icon)
                }
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    Text(result.map(ChecksCopy.summary) ?? String(localized: "No checks", bundle: .module))
                        .font(Font.Vrai.headline)
                    Text(verbatim: (checks.repository?.slug ?? "") + "  " + id.short)
                        .font(Font.Vrai.codeSmall)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await checks.refresh(id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Refresh checks", bundle: .module))
                .accessibilityLabel(Text("Refresh checks", bundle: .module))
            }
            .padding(Vrai.Space.s12)
            Divider()
            if let problem = ChecksCopy.problem(checks.problem), result?.runs.isEmpty != false {
                VStack(alignment: .leading, spacing: Vrai.Space.s8) {
                    Text(problem)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if checks.problem == .signedOut {
                        Button(String(localized: "Copy gh auth login", bundle: .module)) {
                            window.copy("gh auth login")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(Vrai.Space.s12)
            } else if let result, !result.runs.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(result.sorted) { run in
                            ChecksRunRow(run: run, now: fixedNow ?? Date())
                        }
                    }
                    .padding(.vertical, Vrai.Space.s4)
                }
                .frame(maxHeight: Vrai.Size.sheet * 0.6)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("GitHub has no checks for this commit. Push it, or add a workflow under .github/workflows.", bundle: .module)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Vrai.Space.s12)
            }
            Divider()
            HStack(spacing: Vrai.Space.s8) {
                if let url = result?.url ?? checks.repository?.commitURL(id.rawValue) {
                    Button(String(localized: "Open on GitHub", bundle: .module)) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer(minLength: 0)
                if let result, !result.rerunnable.isEmpty, result.isComplete, checks.canWrite {
                    Button(String(localized: "Re-run failed jobs", bundle: .module)) {
                        ChecksActions.rerun(window, id: id, branch: branch)
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("checks-rerun")
                }
            }
            .controlSize(.small)
            .padding(Vrai.Space.s12)
        }
        .frame(width: Vrai.Size.field + Vrai.Space.s64 + Vrai.Space.s16)
        .accessibilityIdentifier("checks-popover")
    }
}

struct ChecksRunRow: View {
    let run: CheckRun
    let now: Date
    @State private var hover = false

    var body: some View {
        Button {
            if let url = run.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Vrai.Space.s8) {
                ChecksGlyph(state: run.state)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Vrai.Space.s4 }
                VStack(alignment: .leading, spacing: Vrai.Space.s2) {
                    Text(run.title)
                        .font(Font.Vrai.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let summary = run.summary, !summary.isEmpty {
                        Text(summary)
                            .font(Font.Vrai.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Vrai.Space.s8)
                if let detail = ChecksCopy.runDetail(run, now: now) {
                    Text(detail)
                        .font(Font.Vrai.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right")
                    .font(Font.Vrai.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(hover && run.url != nil ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Vrai.Space.s12)
            .padding(.vertical, Vrai.Space.s6)
            .background(hover ? Color.Vrai.fillHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(run.url == nil ? run.title : String(localized: "Open \(run.title) on GitHub", bundle: .module))
        .accessibilityLabel(Text(verbatim: run.title + ", " + ChecksCopy.run(run.state)))
    }
}

@MainActor
enum ChecksActions {
    static func rerun(_ window: WindowModel, id: OID, branch: String) {
        let count = window.checks.results[id]?.failed.count ?? 0
        Task {
            do {
                try await window.checks.rerunFailed(id, branch: branch)
                window.toasts.show(Toast(message: String(localized: "Re-running \(n(count, "failed job"))", bundle: .module), detail: String(localized: "on \(branch)", bundle: .module), icon: "arrow.clockwise"))
            } catch {
                window.toasts.show(Toast(tone: .danger, message: String(localized: "GitHub didn't start the re-run", bundle: .module), detail: ChecksCopy.problem((error as? ChecksError)?.problem) ?? String(localized: "Check that your token can run workflows.", bundle: .module)))
            }
        }
    }

    static func label(for id: OID, in snapshot: RepositorySnapshot?) -> String {
        guard let snapshot else { return id.short }
        if let branch = snapshot.branches.first(where: { $0.tip == id && $0.isCurrent }) ?? snapshot.branches.first(where: { $0.tip == id }) { return branch.name }
        if let remote = snapshot.remoteBranches.first(where: { $0.tip == id }) { return remote.fullName }
        return id.short
    }
}
