import SwiftUI
import VraiCore
import VraiGit

struct CommitNoteEditor: View {
    let id: OID
    @Environment(WindowModel.self) private var window
    @Environment(RepositoryStore.self) private var store
    @State private var existing: String?
    @State private var text = ""
    @State private var editing = false
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Vrai.Space.s8) {
            if let existing, !editing {
                Text(existing)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Vrai.Space.s6) {
                    VraiButton(title: String(localized: "Edit note", bundle: .module), icon: "pencil", size: .small) {
                        text = existing
                        editing = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(120))
                            focused = true
                        }
                    }
                    .accessibilityIdentifier("note-edit")
                    VraiButton(title: String(localized: "Remove note", bundle: .module), icon: "trash", size: .small) { remove() }
                        .disabled(busy)
                        .accessibilityIdentifier("note-remove")
                }
            } else {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Add a note to this commit", bundle: .module)
                            .font(Font.Vrai.callout)
                            .foregroundStyle(Color.Vrai.textTertiary)
                            .padding(.horizontal, Vrai.Space.s4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(Font.Vrai.callout)
                        .foregroundStyle(Color.Vrai.text)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .accessibilityLabel(Text("Note", bundle: .module))
                        .accessibilityIdentifier("note-editor")
                }
                .padding(.vertical, Vrai.Space.s4)
                .padding(.horizontal, Vrai.Space.s4)
                .frame(height: Vrai.Space.s20 * 2 + Vrai.Space.s12)
                .background(focused ? Color.Vrai.bg : Color.Vrai.fill, in: RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.md, style: .continuous).strokeBorder(focused ? Color.Vrai.focus : Color.Vrai.border, lineWidth: Metrics.hairline))
                HStack(spacing: Vrai.Space.s6) {
                    VraiButton(title: existing == nil ? String(localized: "Add note", bundle: .module) : String(localized: "Save note", bundle: .module), size: .small) { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        .accessibilityIdentifier("note-save")
                    if editing {
                        VraiButton(title: String(localized: "Cancel", bundle: .module), size: .small) {
                            editing = false
                            text = ""
                        }
                    }
                }
            }
        }
        .task(id: id) {
            editing = false
            text = ""
            existing = await store.note(id: id)
        }
    }

    func save() {
        let message = text
        let replacing = existing != nil
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.addNote(id: id, message: message, replacing: replacing)
                existing = await store.note(id: id)
                editing = false
                text = ""
                window.toasts.show(Toast(message: String(localized: "Added a note to \(id.short)", bundle: .module), detail: String(localized: "Stored in refs/notes/commits.", bundle: .module), icon: "note.text"))
            } catch let error as GitError {
                window.alerts.present(error)
            } catch {}
        }
    }

    func remove() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.removeNote(id: id)
                existing = nil
                window.toasts.show(Toast(message: String(localized: "Removed the note from \(id.short)", bundle: .module), icon: "note.text"))
            } catch let error as GitError {
                window.alerts.present(error)
            } catch {}
        }
    }
}
