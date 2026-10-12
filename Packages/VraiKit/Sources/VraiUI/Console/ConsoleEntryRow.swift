import AppKit
import SwiftUI
import VraiCore
import VraiGit

enum ConsoleFormat {
    static let shownOutputLimit = 32 * 1024

    static func duration(_ duration: Duration) -> String {
        let ms = Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
        if ms < 1000 { return String(localized: "\(ms) ms", bundle: .module) }
        let seconds = (Double(ms) / 100).rounded() / 10
        return String(localized: "\(seconds.formatted(.number.precision(.fractionLength(1)))) s", bundle: .module)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func meta(_ entry: ConsoleEntry) -> String {
        var text = duration(entry.duration)
        if entry.cancelled {
            text += String(localized: ", stopped", bundle: .module)
        } else if entry.failed {
            text += String(localized: ", exit \(entry.exitCode.map(String.init) ?? "?")", bundle: .module)
        }
        return text
    }

    static func shown(_ output: String) -> (text: String, cut: Bool) {
        guard output.utf8.count > shownOutputLimit else { return (output, false) }
        return (String(decoding: Data(output.utf8.prefix(shownOutputLimit)), as: UTF8.self), true)
    }
}

struct ConsoleStatusDisc: View {
    enum State {
        case ok
        case failed
        case running
    }

    let state: State

    var body: some View {
        ZStack {
            switch state {
            case .running:
                ProgressView()
                    .controlSize(.mini)
            case .ok:
                Circle().fill(Color.Vrai.successSoft)
                Symbol("checkmark", font: Font.Vrai.overline)
                    .foregroundStyle(Color.Vrai.success)
            case .failed:
                Circle().fill(Color.Vrai.dangerSoft)
                Symbol("xmark", font: Font.Vrai.overline)
                    .foregroundStyle(Color.Vrai.danger)
            }
        }
        .frame(width: Vrai.Space.s16, height: Vrai.Space.s16)
        .accessibilityHidden(true)
    }
}

struct ConsoleEntryRow: View {
    let entry: ConsoleEntry
    let open: Bool
    var quiet = false
    let toggle: () -> Void
    @Environment(WindowModel.self) private var window
    @Environment(\.widthClass) private var widthClass
    @Environment(\.expert) private var expert

    var body: some View {
        let narrow = widthClass.isNarrow
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: Vrai.Space.s8) {
                    ConsoleStatusDisc(state: entry.failed ? .failed : .ok)
                    Text(entry.source == .you ? String(localized: "You", bundle: .module) : String(localized: "Vrai", bundle: .module))
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .frame(width: Vrai.Space.s32, alignment: .leading)
                    Text(verbatim: "$ " + entry.command)
                        .font(Font.Vrai.codeSmall)
                        .foregroundStyle(quiet ? Color.Vrai.textSecondary : Color.Vrai.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ConsoleFormat.meta(entry))
                        .font(Font.Vrai.caption)
                        .monospacedDigit()
                        .foregroundStyle(entry.failed ? Color.Vrai.danger : Color.Vrai.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                    if !narrow {
                        Text(ConsoleFormat.time(entry.startedAt))
                            .font(Font.Vrai.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.Vrai.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, Vrai.Space.s12)
                .frame(height: Vrai.Size.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(radius: 0, hoverFill: Color.Vrai.fill)
            .help(entry.command)
            .accessibilityLabel(accessibilityText)
            .accessibilityValue(open ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module))
            .accessibilityIdentifier("console-entry")
            if open {
                output(narrow: narrow)
            }
        }
        .hairline(.bottom)
        .contextMenu {
            Button(String(localized: "Copy command", bundle: .module), systemImage: "doc.on.doc") { window.copy(entry.command, label: String(localized: "command", bundle: .module)) }
            Button(String(localized: "Copy output", bundle: .module), systemImage: "doc.on.doc") { window.copy(window.store.console.output(of: entry), label: String(localized: "output", bundle: .module)) }
                .disabled(window.store.console.output(of: entry).isEmpty)
            if expert {
                Button(String(localized: "Run again", bundle: .module), systemImage: "arrow.clockwise") { window.runAgain(entry) }
            }
            if entry.stdoutTruncated || entry.stderrTruncated || window.store.console.spilled[entry.id] != nil {
                Button(String(localized: "Show all output", bundle: .module), systemImage: "doc.text") { showAll() }
            }
        }
    }

    var accessibilityText: String {
        let who = entry.source == .you ? String(localized: "You", bundle: .module) : String(localized: "Vrai", bundle: .module)
        let status = entry.failed ? String(localized: "failed", bundle: .module) : String(localized: "succeeded", bundle: .module)
        return [who, entry.command, status, ConsoleFormat.meta(entry)].joined(separator: ", ")
    }

    @ViewBuilder func output(narrow: Bool) -> some View {
        let full = window.store.console.output(of: entry)
        let shown = ConsoleFormat.shown(full)
        let truncated = shown.cut || entry.stdoutTruncated || entry.stderrTruncated
        VStack(alignment: .leading, spacing: Vrai.Space.s6) {
            if full.isEmpty {
                Text("No output", bundle: .module)
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
            } else {
                Text(verbatim: shown.text)
                    .font(Font.Vrai.codeSmall)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if truncated {
                HStack(spacing: Vrai.Space.s8) {
                    Text(shown.cut ? String(localized: "Showing the first 32 KB.", bundle: .module) : String(localized: "Vrai kept the first 1 MB of this output.", bundle: .module))
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.textTertiary)
                    Button(String(localized: "Show all", bundle: .module)) { showAll() }
                        .buttonStyle(VraiButtonStyle(variant: .plain, size: .small))
                }
            }
        }
        .padding(.leading, narrow ? Vrai.Space.s12 : Vrai.Space.s12 + Vrai.Space.s16 + Vrai.Space.s8 + Vrai.Space.s32 + Vrai.Space.s8)
        .padding(.trailing, Vrai.Space.s12)
        .padding(.top, Vrai.Space.s2)
        .padding(.bottom, Vrai.Space.s10)
    }

    func showAll() {
        let log = window.store.console
        if let url = log.spilled[entry.id] {
            NSWorkspace.shared.open(url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: log.spillFolder, withIntermediateDirectories: true)
            let url = log.spillFolder.appending(path: entry.id.uuidString + ".txt")
            try Data(log.output(of: entry).utf8).write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch {
            window.toasts.show(Toast(tone: .danger, message: String(localized: "Couldn't open the output", bundle: .module), detail: ErrorCopy.writing(error), icon: "exclamationmark.triangle"))
        }
    }
}

struct ConsoleRunningRow: View {
    let item: ConsoleLog.Running
    let stop: () -> Void

    var body: some View {
        HStack(spacing: Vrai.Space.s8) {
            ConsoleStatusDisc(state: .running)
            Text(item.source == .you ? String(localized: "You", bundle: .module) : String(localized: "Vrai", bundle: .module))
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.textTertiary)
                .frame(width: Vrai.Space.s32, alignment: .leading)
            Text(verbatim: "$ " + item.command)
                .font(Font.Vrai.codeSmall)
                .foregroundStyle(Color.Vrai.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("running", bundle: .module)
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.textTertiary)
                .fixedSize()
            IconButton(icon: "stop.circle", label: String(localized: "Stop", bundle: .module), small: true, action: stop)
        }
        .padding(.leading, Vrai.Space.s12)
        .padding(.trailing, Vrai.Space.s6)
        .frame(height: Vrai.Size.row)
        .hairline(.bottom)
        .accessibilityElement(children: .combine)
    }
}

struct ConsoleGroupRow: View {
    let entries: [ConsoleEntry]
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Vrai.Space.s8) {
                Symbol("chevron.right", font: Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: Vrai.Space.s16)
                Text(n(entries.count, "background command"))
                    .font(Font.Vrai.caption)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .lineLimit(1)
                if entries.contains(where: \.failed) {
                    Text("\(entries.filter(\.failed).count) failed", bundle: .module)
                        .font(Font.Vrai.caption)
                        .foregroundStyle(Color.Vrai.danger)
                        .lineLimit(1)
                }
                Spacer(minLength: Vrai.Space.s8)
                if let last = entries.last {
                    Text(ConsoleFormat.time(last.startedAt))
                        .font(Font.Vrai.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.Vrai.textTertiary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, Vrai.Space.s12)
            .frame(height: Vrai.Size.rowCompact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 0, hoverFill: Color.Vrai.fill)
        .hairline(.bottom)
        .accessibilityLabel(n(entries.count, "background command"))
        .accessibilityValue(open ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module))
    }
}
