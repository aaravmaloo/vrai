import SwiftUI
import UniformTypeIdentifiers
import VraiCore
import VraiGit

struct EditableStep: Identifiable, Hashable {
    var commit: OID
    var action: RebaseStep.Action
    var subject: String
    var original: String
    var author: String?
    var squashMessage = ""

    var id: OID { commit }
}

struct InteractiveRebaseSheet: View {
    let initialOnto: String
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var onto = ""
    @State private var ontoCommit: PreviewCommit?
    @State private var steps: [EditableStep] = []
    @State private var selected: Int?
    @State private var autosquash = true
    @State private var loaded = false
    @State private var dropTarget: Int?
    @State private var started = false
    @FocusState private var listFocused: Bool
    @State private var editing: Int?

    var body: some View {
        let head = window.headName
        let options = RewriteRefOptions.build(store.snapshot, includeRemotes: true, includeTags: true, exclude: store.snapshot?.head.branchName, commit: ontoCommit)
        let kept = steps.filter { $0.action != .drop }
        let firstBad = kept.first?.action.foldsIntoPrevious == true
        RewriteSheet(
            title: String(localized: "Interactive rebase", bundle: .module),
            description: String(localized: "Reorder, edit, squash or drop \(n(steps.count, "commit")) on \(head). Oldest first, like git's todo list.", bundle: .module),
            icon: "list.number",
            tone: .warning,
            width: Vrai.Size.sheetWide
        ) {
            HStack(alignment: .bottom, spacing: Vrai.Space.s8) {
                RewriteField(label: String(localized: "Onto", bundle: .module)) {
                    RewriteSelect(selection: $onto, options: options, label: String(localized: "Onto", bundle: .module))
                }
                RewriteCheckbox(String(localized: "Autosquash", bundle: .module), isOn: $autosquash, description: String(localized: "Folds fixup! commits in", bundle: .module))
                    .fixedSize()
                    .onChange(of: autosquash) { _, on in if on { steps = Self.autosquashed(steps) } }
            }
            if loaded, steps.isEmpty {
                RewriteCallout(tone: .info, title: String(localized: "Nothing to rebase", bundle: .module), message: String(localized: "\(head) has no commits that aren't on \(RewriteActions.shortName(onto)).", bundle: .module))
            } else {
                stepList
            }
            if firstBad {
                RewriteCallout(tone: .danger, title: String(localized: "The first step can't be squash or fixup", bundle: .module), message: String(localized: "There's no earlier commit in the list to fold it into. Pick it, or move it down.", bundle: .module))
            }
            Text("Drag to reorder, or select a step and press \u{2325}\u{2191} \u{2325}\u{2193}. Keys set the action: p pick, r reword, e edit, s squash, f fixup, d drop.", bundle: .module)
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            RewriteOptions(command: RewriteCommands.interactiveRebase(onto: onto.isEmpty ? "<onto>" : onto), risk: .rewrites)
        } footerStart: {
            Text(summary)
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.textTertiary)
                .lineLimit(1)
                .accessibilityIdentifier("rebase-summary")
        } actions: {
            RewriteFoot(label: String(localized: "Start rebase", bundle: .module), disabled: firstBad || steps.isEmpty || onto.isEmpty, identifier: "interactive-run", cancel: { window.sheets.dismiss() }, action: run)
        }
        .task {
            guard !started else { return }
            started = true
            if let oid = OID(initialOnto) {
                ontoCommit = PreviewCommit(id: oid, subject: await store.subject(of: oid) ?? "")
            }
            onto = initialOnto
        }
        .task(id: onto) {
            guard !onto.isEmpty else { return }
            let plan = (try? await store.rebasePlan(onto: onto)) ?? []
            var list = plan.map { EditableStep(commit: $0.commit, action: $0.action, subject: $0.subject, original: $0.subject, author: $0.author) }
            if autosquash { list = Self.autosquashed(list) }
            steps = list
            selected = list.isEmpty ? nil : list.count - 1
            loaded = true
        }
    }

    var stepList: some View {
        ScrollView {
            VStack(spacing: Vrai.Space.s4) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    VStack(spacing: Vrai.Space.s4) {
                        if dropTarget == index {
                            Capsule()
                                .fill(Color.Vrai.accent)
                                .frame(height: Vrai.Space.s2)
                        }
                        RebaseStepRow(
                            step: $steps[index],
                            index: index,
                            selected: selected == index,
                            onEditing: { now in
                                if now { editing = index } else if editing == index { editing = nil }
                            }
                        ) {
                            selected = index
                            if editing != index { listFocused = true }
                        }
                        .draggable(step.commit.rawValue) {
                            RebaseStepRow(step: .constant(step), index: index, selected: true, onEditing: { _ in }) {}
                                .frame(width: Vrai.Size.sheetWide - Vrai.Space.s48)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let from = steps.firstIndex(where: { $0.commit.rawValue == raw }) else { return false }
                            move(from: from, to: index)
                            return true
                        } isTargeted: { targeted in
                            if targeted { dropTarget = index } else if dropTarget == index { dropTarget = nil }
                        }
                    }
                }
            }
            .padding(Vrai.Space.s2)
        }
        .frame(maxHeight: Vrai.Space.s64 * 5)
        .fixedSize(horizontal: false, vertical: true)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(phases: .down) { press in handle(press) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Rebase steps", bundle: .module))
        .accessibilityIdentifier("rebase-steps")
    }

    func handle(_ press: KeyPress) -> KeyPress.Result {
        if editing != nil { return .ignored }
        guard let current = selected, steps.indices.contains(current) else { return .ignored }
        if press.key == .upArrow || press.key == .downArrow {
            let delta = press.key == .upArrow ? -1 : 1
            let target = max(0, min(steps.count - 1, current + delta))
            if press.modifiers.contains(.option) {
                move(from: current, to: target)
            } else {
                selected = target
            }
            return .handled
        }
        guard press.modifiers.isEmpty || press.modifiers == .shift, let character = press.characters.first, let action = RebaseStep.Action(key: character) else { return .ignored }
        steps[current].action = action
        return .handled
    }

    func move(from: Int, to: Int) {
        guard from != to, steps.indices.contains(from), steps.indices.contains(to) else {
            dropTarget = nil
            return
        }
        let item = steps.remove(at: from)
        steps.insert(item, at: to)
        selected = to
        dropTarget = nil
    }

    var summary: String {
        let reworded = steps.count { $0.action == .reword }
        let folded = steps.count { $0.action.foldsIntoPrevious }
        let edits = steps.count { $0.action == .edit }
        let dropped = steps.count { $0.action == .drop }
        var parts: [String] = []
        if reworded > 0 { parts.append(String(localized: "\(n(reworded, "commit")) reworded", bundle: .module)) }
        if folded > 0 { parts.append(String(localized: "\(n(folded, "commit")) folded in", bundle: .module)) }
        if edits > 0 { parts.append(String(localized: "\(n(edits, "stop")) to edit", bundle: .module)) }
        if dropped > 0 { parts.append(String(localized: "\(n(dropped, "commit")) dropped", bundle: .module)) }
        return parts.isEmpty ? String(localized: "Every commit picked as is", bundle: .module) : parts.joined(separator: ", ")
    }

    func run() {
        let current = steps
        let target = onto
        window.sheets.dismiss()
        Task { @MainActor in
            var plan: [RebaseStep] = []
            for step in current {
                var message: String?
                let subject = step.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                if step.action == .reword, !subject.isEmpty, subject != step.original {
                    let body = (try? await store.commitDetail(id: step.commit))?.commit.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    message = body.isEmpty ? subject : subject + "\n\n" + body
                }
                let squash = step.squashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                if step.action == .squash, !squash.isEmpty { message = squash }
                plan.append(RebaseStep(commit: step.commit, action: step.action, subject: step.original, author: step.author, message: message))
            }
            RewriteActions.interactiveRebase(window, onto: target, steps: plan)
        }
    }

    static func autosquashed(_ input: [EditableStep]) -> [EditableStep] {
        var list = input
        var index = 0
        while index < list.count {
            let step = list[index]
            if let match = step.original.firstMatch(of: /^(fixup|squash)! (.+)$/), let target = list.firstIndex(where: { $0.original == String(match.output.2) }), target != index - 1, target < index {
                var moved = list.remove(at: index)
                moved.action = match.output.1 == "fixup" ? .fixup : .squash
                list.insert(moved, at: target + 1)
            } else if let match = step.original.firstMatch(of: /^(fixup|squash)! (.+)$/), list.firstIndex(where: { $0.original == String(match.output.2) }) == index - 1, step.action == .pick {
                list[index].action = match.output.1 == "fixup" ? .fixup : .squash
            }
            index += 1
        }
        return list
    }
}

struct RebaseStepRow: View {
    @Binding var step: EditableStep
    let index: Int
    let selected: Bool
    let onEditing: (Bool) -> Void
    let select: () -> Void
    @State private var hovering = false
    @Environment(\.expert) private var expert

    var body: some View {
        let folds = step.action.foldsIntoPrevious
        HStack(spacing: Vrai.Space.s10) {
            Symbol("line.3.horizontal", font: Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textTertiary)
                .frame(width: Vrai.Space.s16)
            Text(String(index + 1))
                .font(Font.Vrai.caption)
                .monospacedDigit()
                .foregroundStyle(Color.Vrai.textTertiary)
                .frame(width: Vrai.Space.s16, alignment: .trailing)
            ActionPill(action: $step.action, subject: step.original)
            Text(step.commit.short(expert: expert))
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.textTertiary)
                .fixedSize()
            subjectView
                .frame(maxWidth: .infinity, alignment: .leading)
            if let author = step.author {
                Text(author)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                    .frame(width: Vrai.Size.colAuthor - Vrai.Space.s40, alignment: .trailing)
            }
        }
        .padding(.leading, Vrai.Space.s6)
        .padding(.trailing, Vrai.Space.s12)
        .frame(height: Vrai.Size.row + Vrai.Space.s8)
        .background(selected ? Color.Vrai.accentSoft : Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous)
                .strokeBorder(selected ? Color.Vrai.accent : (hovering ? Color.Vrai.borderStrong : Color.Vrai.separator), lineWidth: selected ? Metrics.thinStroke : Metrics.hairline)
        }
        .overlay(alignment: .topLeading) {
            if folds {
                FoldConnector()
                    .stroke(Color.Vrai.statusRenamed.opacity(0.7), lineWidth: Vrai.Size.line)
                    .frame(width: Vrai.Space.s12, height: Vrai.Space.s20 + Vrai.Space.s16)
                    .offset(x: -Vrai.Space.s16, y: -Vrai.Space.s20)
                    .allowsHitTesting(false)
            }
        }
        .padding(.leading, folds ? Vrai.Space.s32 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Step \(index + 1), \(Self.label(step.action)) \(step.original)", bundle: .module))
        .accessibilityIdentifier("step-\(index + 1)")
    }

    @ViewBuilder var subjectView: some View {
        switch step.action {
        case .reword:
            StepField(text: $step.subject, placeholder: step.original, label: String(localized: "New commit message", bundle: .module), identifier: "reword-\(index + 1)", onEditing: onEditing)
        case .squash:
            StepField(text: $step.squashMessage, placeholder: String(localized: "Keep both messages", bundle: .module), label: String(localized: "Message for the combined commit", bundle: .module), identifier: "squash-\(index + 1)", onEditing: onEditing)
        default:
            Text(step.original)
                .font(Font.Vrai.body)
                .strikethrough(step.action == .drop)
                .foregroundStyle(step.action == .drop ? Color.Vrai.textTertiary : (step.action == .fixup ? Color.Vrai.textSecondary : Color.Vrai.text))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    static func label(_ action: RebaseStep.Action) -> String {
        switch action {
        case .pick: String(localized: "Pick", bundle: .module)
        case .reword: String(localized: "Reword", bundle: .module)
        case .edit: String(localized: "Edit", bundle: .module)
        case .squash: String(localized: "Squash", bundle: .module)
        case .fixup: String(localized: "Fixup", bundle: .module)
        case .drop: String(localized: "Drop", bundle: .module)
        }
    }

    static func help(_ action: RebaseStep.Action) -> String {
        switch action {
        case .pick: String(localized: "Use the commit as it is", bundle: .module)
        case .reword: String(localized: "Use the commit, edit its message", bundle: .module)
        case .edit: String(localized: "Stop after applying, to amend it", bundle: .module)
        case .squash: String(localized: "Meld into the commit above, keep both messages", bundle: .module)
        case .fixup: String(localized: "Meld into the commit above, drop this message", bundle: .module)
        case .drop: String(localized: "Remove the commit", bundle: .module)
        }
    }
}

struct FoldConnector: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(Vrai.Radius.md, rect.width)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct ActionPill: View {
    @Binding var action: RebaseStep.Action
    let subject: String

    var body: some View {
        Menu {
            Picker(selection: $action) {
                ForEach(RebaseStep.Action.allCases, id: \.self) { item in
                    Text(RebaseStepRow.label(item)).tag(item)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Vrai.Space.s2) {
                Text(RebaseStepRow.label(action))
                    .font(Font.Vrai.captionStrong)
                    .frame(width: Vrai.Space.s48 + Vrai.Space.s2, alignment: .leading)
                Symbol("chevron.up.chevron.down", font: Font.Vrai.overline)
            }
            .foregroundStyle(foreground)
            .padding(.leading, Vrai.Space.s8)
            .padding(.trailing, Vrai.Space.s6)
            .frame(height: Vrai.Space.s20)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(RebaseStepRow.help(action))
        .accessibilityLabel(Text("Action for \(subject)", bundle: .module))
        .accessibilityValue(RebaseStepRow.label(action))
    }

    var foreground: Color {
        switch action {
        case .pick: Color.Vrai.textSecondary
        case .reword: Color.Vrai.accentText
        case .edit: Color.Vrai.warning
        case .squash, .fixup: Color.Vrai.statusRenamed
        case .drop: Color.Vrai.danger
        }
    }

    var background: Color {
        switch action {
        case .pick: Color.Vrai.fill
        case .reword: Color.Vrai.accentSoft
        case .edit: Color.Vrai.warningSoft
        case .squash, .fixup: Color.Vrai.statusRenamed.opacity(0.12)
        case .drop: Color.Vrai.dangerSoft
        }
    }
}

struct StepField: View {
    @Binding var text: String
    let placeholder: String
    let label: String
    let identifier: String
    let onEditing: (Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text) {
            Text(placeholder).foregroundStyle(Color.Vrai.textTertiary)
        }
        .textFieldStyle(.plain)
        .font(Font.Vrai.body)
        .focused($focused)
        .onChange(of: focused) { _, now in onEditing(now) }
        .padding(.horizontal, Vrai.Space.s6)
        .frame(height: Vrai.Size.controlSm)
        .background(Color.Vrai.bg, in: RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.sm, style: .continuous).strokeBorder(focused ? Color.Vrai.focus : Color.Vrai.border, lineWidth: Metrics.hairline))
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
