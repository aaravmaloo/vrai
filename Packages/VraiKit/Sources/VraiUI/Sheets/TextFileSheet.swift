import SwiftUI
import VraiCore
import VraiGit

struct TextFileSheet: View {
    let kind: TextFileKind
    @Environment(RepositoryStore.self) private var store
    @Environment(WindowModel.self) private var window
    @State private var original: String?
    @State private var text = ""
    @State private var mapped: [(from: String, to: String)] = []
    @State private var busy = false
    @State private var failure: String?

    var description: String {
        switch kind {
        case .gitignore: String(localized: "Files git should never track.", bundle: .module)
        case .gitattributes: String(localized: "How git diffs, merges and stores particular paths.", bundle: .module)
        case .mailmap: String(localized: "Maps the names and emails in history to one person each.", bundle: .module)
        }
    }

    var icon: String {
        switch kind {
        case .gitignore: "eye.slash"
        case .gitattributes: "doc.text"
        case .mailmap: "person.2"
        }
    }

    var placeholder: String {
        switch kind {
        case .gitignore: ".DS_Store\n.build/\nDerivedData/"
        case .gitattributes: "*.pbxproj merge=union\n*.png binary"
        case .mailmap: "Mira Okafor <mira@vrai.app> <mira.okafor@users.noreply.github.com>"
        }
    }

    var body: some View {
        LongTailSheet(
            title: String(localized: "Edit \(kind.fileName)", bundle: .module),
            description: description,
            icon: icon
        ) {
            if let failure {
                SyncForm.Callout(tone: .danger, title: String(localized: "Vrai couldn't save \(kind.fileName)", bundle: .module), message: failure)
            }
            if original == nil {
                Spinner()
            } else {
                ZStack(alignment: .topLeading) {
                    LongTailCodeEditor(label: kind.fileName, text: $text, maxHeight: LongTailMetrics.listMax * 1.5)
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Font.Vrai.code)
                            .foregroundStyle(Color.Vrai.textTertiary)
                            .padding(.vertical, Vrai.Space.s6)
                            .padding(.horizontal, Vrai.Space.s8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                if kind == .mailmap {
                    mailmapPreview
                }
            }
        } actions: {
            LongTailFoot(label: String(localized: "Save", bundle: .module), enabled: original != nil, busy: busy, identifier: "textfile-save", cancel: { window.sheets.dismiss() }) { save() }
        }
        .task {
            do {
                let loaded = try await store.readTextFile(kind)
                text = loaded
                original = loaded
            } catch {
                original = ""
                failure = error.localizedDescription
            }
        }
        .task(id: kind == .mailmap ? text : "") {
            guard kind == .mailmap, original != nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            mapped = await store.mailmapPreview(contents: text)
        }
    }

    @ViewBuilder var mailmapPreview: some View {
        if mapped.isEmpty {
            Text("No one in history is renamed yet.", bundle: .module)
                .font(Font.Vrai.caption)
                .foregroundStyle(Color.Vrai.textTertiary)
        } else {
            Text("History shows these people as:", bundle: .module)
                .font(Font.Vrai.callout)
                .foregroundStyle(Color.Vrai.textSecondary)
            LongTailBox(maxHeight: LongTailMetrics.listMax / 1.5) {
                ForEach(Array(mapped.enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: Vrai.Space.s6) {
                        Text(pair.from)
                            .foregroundStyle(Color.Vrai.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Symbol("arrow.right", font: Font.Vrai.caption)
                            .foregroundStyle(Color.Vrai.textTertiary)
                        Text(pair.to)
                            .foregroundStyle(Color.Vrai.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(Font.Vrai.caption)
                    .padding(.horizontal, Vrai.Space.s4)
                    .frame(minHeight: Vrai.Space.s20)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    func save() {
        guard !busy else { return }
        guard text != original else {
            window.sheets.dismiss()
            return
        }
        busy = true
        failure = nil
        let contents = text
        Task {
            defer { busy = false }
            do {
                try await store.writeTextFile(kind, contents: contents)
                window.sheets.dismiss()
                window.toasts.show(Toast(message: String(localized: "Saved \(kind.fileName)", bundle: .module), detail: String(localized: "It's in Changes, ready to commit.", bundle: .module), icon: "doc.text", action: String(localized: "Show changes", bundle: .module)) {
                    window.show(.changes)
                })
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
