import SwiftUI
import VraiCore
import VraiGit

struct CommitComposerView: View {
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @Environment(\.expert) private var expert
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case summary
        case description
    }

    var body: some View {
        @Bindable var changes = window.changes
        let staged = window.composerStaged
        let ready = (staged > 0 || changes.amend) && !changes.subject.trimmedForCommit.isEmpty
        let reason = reason(staged: staged)
        VStack(alignment: .leading, spacing: Vrai.Space.s10) {
            if let failure = changes.hookFailure {
                HookFailureView(failure: failure) { changes.hookFailure = nil }
            }
            fields(changes)
            FlowLayout(spacing: Vrai.Space.s16, lineSpacing: Vrai.Space.s8) {
                ComposerSwitch(title: String(localized: "Amend last commit", bundle: .module), isOn: Binding(get: { changes.amend }, set: { changes.setAmend($0, store: store) }))
                    .disabled(store.snapshot?.headOID == nil || window.mergeSource != nil)
                    .accessibilityIdentifier("commit-amend")
                if expert {
                    ComposerSwitch(title: String(localized: "Sign off", bundle: .module), isOn: $changes.signoff)
                    ComposerSwitch(title: String(localized: "Skip hooks", bundle: .module), isOn: $changes.noVerify)
                        .accessibilityIdentifier("commit-skip-hooks")
                    CoAuthorMenu()
                }
            }
            .padding(.horizontal, Vrai.Space.s2)
            if expert {
                ComposerCommandLine(command: CommitService.command(CommitMessage(subject: changes.subject.isEmpty ? String(localized: "Summary", bundle: .module) : changes.subject, body: changes.body), amend: changes.amend, signoff: changes.signoff, noVerify: changes.noVerify))
            }
            Button {
                window.commitNow(andPush: window.optionDown)
            } label: {
                HStack(spacing: Vrai.Space.s8) {
                    if changes.committing { Spinner() }
                    Text(changes.amend ? String(localized: "Amend last commit", bundle: .module) : String(localized: "Commit to \(window.headName)", bundle: .module))
                        .lineLimit(1)
                    Text(verbatim: "\u{2318}\u{21A9}")
                        .opacity(0.72)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(VraiButtonStyle(variant: .primary, size: .large, full: true))
            .disabled(!ready || changes.committing)
            .help(reason ?? "")
            .accessibilityIdentifier("commit-button")
        }
        .padding(Vrai.Space.s12)
        .hairline(.top)
        .onChange(of: changes.focusRequest, initial: true) { _, _ in claimFocus() }
    }

    func claimFocus() {
        let changes = window.changes
        guard changes.focusRequest != changes.focusHandled else { return }
        Task { @MainActor in
            changes.focusHandled = changes.focusRequest
            focus = .summary
        }
    }

    func reason(staged: Int) -> String? {
        let changes = window.changes
        if changes.subject.trimmedForCommit.isEmpty { return String(localized: "Write a summary to commit", bundle: .module) }
        if staged == 0, !changes.amend { return String(localized: "Stage at least one file to commit", bundle: .module) }
        return nil
    }

    @ViewBuilder func fields(_ changes: ChangesModel) -> some View {
        @Bindable var changes = changes
        let count = changes.subject.count
        let tone: AnyShapeStyle = count > ChangesMetrics.summaryHardLimit ? AnyShapeStyle(Color.Vrai.danger) : (count > ChangesMetrics.summaryLimit ? AnyShapeStyle(Color.Vrai.warning) : AnyShapeStyle(.secondary))
        let editing = focus == .description
        VStack(spacing: Vrai.Space.s8) {
            HStack(spacing: Vrai.Space.s8) {
                TextField(text: $changes.subject, prompt: Text(changes.amend ? String(localized: "Summary of the amended commit", bundle: .module) : String(localized: "Summary (required)", bundle: .module))) {
                    Text("Commit summary", bundle: .module)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .summary)
                .onSubmit { focus = .description }
                .accessibilityIdentifier("commit-summary")
                Text(verbatim: "\(count)/\(ChangesMetrics.summaryLimit)")
                    .font(Font.Vrai.caption)
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .help(String(localized: "Keep the summary under 50 characters. git log --oneline cuts at 72.", bundle: .module))
                    .accessibilityLabel(Text("\(count) of \(ChangesMetrics.summaryLimit) characters", bundle: .module))
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $changes.body)
                    .font(Font.Vrai.body)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .description)
                    .accessibilityLabel(Text("Commit description", bundle: .module))
                    .accessibilityIdentifier("commit-description")
                if changes.body.isEmpty {
                    Text("Description", bundle: .module)
                        .font(Font.Vrai.body)
                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                        .padding(.leading, Vrai.Space.s4 + Metrics.hairline)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Vrai.Space.s4)
            .padding(.horizontal, Vrai.Space.s2)
            .frame(height: ChangesMetrics.bodyHeight)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: Metrics.hairline)
            }
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: Vrai.Radius.sm + Vrai.Size.focusHalo, style: .continuous)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: Vrai.Size.focusHalo)
                        .padding(-Vrai.Size.focusHalo)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct ComposerSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.text)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .fixedSize()
    }
}

struct HookFailureView: View {
    let failure: CommitHookFailure
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s8) {
            HStack(alignment: .top, spacing: Vrai.Space.s10) {
                Symbol(Tone.danger.symbol, font: Font.Vrai.title3)
                    .foregroundStyle(Color.Vrai.danger)
                Text("The \(failure.name) hook stopped the commit", bundle: .module)
                    .font(Font.Vrai.headline)
                    .foregroundStyle(Color.Vrai.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(String(localized: "Your message is kept. Fix what the hook reports, then commit again.", bundle: .module))
                Spacer(minLength: 0)
                IconButton(icon: "xmark", label: String(localized: "Dismiss", bundle: .module), small: true, action: dismiss)
            }
            if !failure.output.isEmpty {
                ScrollView {
                    Text(verbatim: failure.output)
                        .font(Font.Vrai.codeSmall)
                        .foregroundStyle(Color.Vrai.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Vrai.Space.s8)
                }
                .frame(maxHeight: ChangesMetrics.hookOutputHeight)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.Vrai.bgSunken, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
                .accessibilityIdentifier("commit-hook-output")
            }
        }
        .padding(Vrai.Space.s12)
        .background(Color.Vrai.dangerSoft, in: RoundedRectangle(cornerRadius: Vrai.Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("commit-hook-failure")
    }
}
