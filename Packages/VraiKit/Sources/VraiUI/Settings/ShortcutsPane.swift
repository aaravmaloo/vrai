import SwiftUI
import VraiCore
import VraiGit

struct ShortcutItem: Identifiable, Hashable {
    let label: String
    let keys: [String]

    var id: String { label }
}

struct ShortcutGroup: Identifiable, Hashable {
    let title: String
    var footer: String?
    var items: [ShortcutItem]

    var id: String { title }
}

enum ShortcutCatalog {
    static func item(_ label: String, _ keys: String...) -> ShortcutItem {
        ShortcutItem(label: label, keys: keys)
    }

    static var groups: [ShortcutGroup] {
        [
            ShortcutGroup(title: String(localized: "Repository", bundle: .module), footer: String(localized: "Hold \u{2325} in a menu or over the toolbar to see the alternates.", bundle: .module), items: [
                item(String(localized: "Command palette", bundle: .module), "\u{2318}K"),
                item(String(localized: "Fetch", bundle: .module), "\u{21E7}\u{2318}F"),
                item(String(localized: "Fetch all remotes and prune", bundle: .module), "\u{2325}\u{21E7}\u{2318}F"),
                item(String(localized: "Pull", bundle: .module), "\u{21E7}\u{2318}L"),
                item(String(localized: "Pull with rebase", bundle: .module), "\u{2325}\u{21E7}\u{2318}L"),
                item(String(localized: "Push", bundle: .module), "\u{21E7}\u{2318}P"),
                item(String(localized: "Force push with lease", bundle: .module), "\u{2325}\u{21E7}\u{2318}P"),
                item(String(localized: "Stash changes", bundle: .module), "\u{21E7}\u{2318}S"),
                item(String(localized: "Undo", bundle: .module), "\u{2318}Z"),
                item(String(localized: "Open a repository", bundle: .module), "\u{2318}O"),
                item(String(localized: "Clone a repository", bundle: .module), "\u{21E7}\u{2318}O"),
                item(String(localized: "New repository", bundle: .module), "\u{2325}\u{2318}N")
            ]),
            ShortcutGroup(title: String(localized: "Branch", bundle: .module), items: [
                item(String(localized: "Switch branch", bundle: .module), "\u{2318}B"),
                item(String(localized: "New branch", bundle: .module), "\u{21E7}\u{2318}B"),
                item(String(localized: "Merge", bundle: .module), "\u{21E7}\u{2318}M"),
                item(String(localized: "Rebase", bundle: .module), "\u{21E7}\u{2318}R"),
                item(String(localized: "Interactive rebase", bundle: .module), "\u{2325}\u{21E7}\u{2318}R")
            ]),
            ShortcutGroup(title: String(localized: "Commit", bundle: .module), items: [
                item(String(localized: "Commit", bundle: .module), "\u{2318}\u{21A9}"),
                item(String(localized: "Commit and push", bundle: .module), "\u{2325}\u{2318}\u{21A9}"),
                item(String(localized: "Stage all", bundle: .module), "\u{21E7}\u{2318}A"),
                item(String(localized: "Stage all, including untracked", bundle: .module), "\u{2325}\u{21E7}\u{2318}A"),
                item(String(localized: "Copy hash", bundle: .module), "\u{2318}C"),
                item(String(localized: "Copy full hash", bundle: .module), "\u{2325}\u{2318}C")
            ]),
            ShortcutGroup(title: String(localized: "View", bundle: .module), items: [
                item(String(localized: "History", bundle: .module), "\u{2318}1"),
                item(String(localized: "Changes", bundle: .module), "\u{2318}2"),
                item(String(localized: "Stashes", bundle: .module), "\u{2318}3"),
                item(String(localized: "Reflog, in Expert mode", bundle: .module), "\u{2318}4"),
                item(String(localized: "Show or hide the sidebar", bundle: .module), "\u{2303}\u{2318}S"),
                item(String(localized: "Show or hide the inspector", bundle: .module), "\u{2325}\u{2318}0"),
                item(String(localized: "Show or hide the console", bundle: .module), "\u{2318}J"),
                item(String(localized: "Find in history", bundle: .module), "\u{2318}F"),
                item(String(localized: "Expert mode", bundle: .module), "\u{2325}\u{2318}E"),
                item(String(localized: "Settings", bundle: .module), "\u{2318},"),
                item(String(localized: "Welcome window", bundle: .module), "\u{21E7}\u{2318}1")
            ]),
            ShortcutGroup(title: String(localized: "Navigation", bundle: .module), items: [
                item(String(localized: "Next commit", bundle: .module), "J", "\u{2193}"),
                item(String(localized: "Previous commit", bundle: .module), "K", "\u{2191}"),
                item(String(localized: "Run a palette item with options", bundle: .module), "\u{2325}\u{21A9}"),
                item(String(localized: "Close a sheet, menu or the palette", bundle: .module), "Esc")
            ]),
            ShortcutGroup(title: String(localized: "Changes", bundle: .module), items: [
                item(String(localized: "Stage or unstage the selected file", bundle: .module), "Space"),
                item(String(localized: "Discard changes to the selected file", bundle: .module), "Delete"),
                item(String(localized: "Next file", bundle: .module), "\u{2193}"),
                item(String(localized: "Previous file", bundle: .module), "\u{2191}")
            ]),
            ShortcutGroup(title: String(localized: "Interactive rebase", bundle: .module), items: [
                item(String(localized: "Pick", bundle: .module), "P"),
                item(String(localized: "Reword", bundle: .module), "R"),
                item(String(localized: "Edit", bundle: .module), "E"),
                item(String(localized: "Squash", bundle: .module), "S"),
                item(String(localized: "Fixup", bundle: .module), "F"),
                item(String(localized: "Drop", bundle: .module), "D"),
                item(String(localized: "Move the step up", bundle: .module), "\u{2325}\u{2191}"),
                item(String(localized: "Move the step down", bundle: .module), "\u{2325}\u{2193}")
            ]),
            ShortcutGroup(title: String(localized: "Window", bundle: .module), footer: String(localized: "macOS reserves these; they work in every window.", bundle: .module), items: [
                item(String(localized: "Close window", bundle: .module), "\u{2318}W"),
                item(String(localized: "Minimize", bundle: .module), "\u{2318}M"),
                item(String(localized: "Hide Vrai", bundle: .module), "\u{2318}H"),
                item(String(localized: "Quit Vrai", bundle: .module), "\u{2318}Q")
            ])
        ]
    }

    static func filter(_ groups: [ShortcutGroup], query raw: String) -> [ShortcutGroup] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.title.lowercased().contains(query) { return group }
            var filtered = group
            filtered.items = group.items.filter { $0.label.lowercased().contains(query) || $0.keys.contains { $0.lowercased() == query } }
            return filtered.items.isEmpty ? nil : filtered
        }
    }

    static func caps(_ keys: String) -> [String] {
        let modifiers: Set<Character> = ["\u{2303}", "\u{2325}", "\u{21E7}", "\u{2318}"]
        var caps: [String] = []
        var rest = Substring(keys)
        while let first = rest.first, modifiers.contains(first), rest.count > 1 {
            caps.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { caps.append(String(rest)) }
        return caps
    }

    static func spoken(_ keys: String) -> String {
        caps(keys).map { cap in
            switch cap {
            case "\u{2303}": String(localized: "Control", bundle: .module)
            case "\u{2325}": String(localized: "Option", bundle: .module)
            case "\u{21E7}": String(localized: "Shift", bundle: .module)
            case "\u{2318}": String(localized: "Command", bundle: .module)
            case "\u{21A9}": String(localized: "Return", bundle: .module)
            case "\u{2191}": String(localized: "Up Arrow", bundle: .module)
            case "\u{2193}": String(localized: "Down Arrow", bundle: .module)
            default: cap
            }
        }.joined(separator: " ")
    }
}

struct KeyCaps: View {
    let keys: String

    var body: some View {
        HStack(spacing: Vrai.Space.s2) {
            ForEach(Array(ShortcutCatalog.caps(keys).enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textSecondary)
                    .padding(.horizontal, Vrai.Space.s4)
                    .frame(minWidth: Vrai.Space.s20, minHeight: Vrai.Space.s20)
                    .background(Color.Vrai.surface, in: RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Vrai.Radius.xs, style: .continuous).strokeBorder(Color.Vrai.border, lineWidth: Metrics.hairline))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShortcutCatalog.spoken(keys))
    }
}

struct ShortcutsPane: View {
    @State private var query = ""

    var body: some View {
        let groups = ShortcutCatalog.filter(ShortcutCatalog.groups, query: query)
        VStack(spacing: 0) {
            SearchField(text: $query, placeholder: String(localized: "Search shortcuts", bundle: .module), small: false)
                .accessibilityIdentifier("settings.shortcuts.search")
                .padding(.horizontal, Vrai.Space.s20)
                .padding(.top, Vrai.Space.s16)
                .padding(.bottom, Vrai.Space.s4)
            if groups.isEmpty {
                Text(String(localized: "No shortcut matches \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}.", bundle: .module))
                    .font(Font.Vrai.callout)
                    .foregroundStyle(Color.Vrai.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Vrai.Space.s24)
                    .padding(.vertical, Vrai.Space.s12)
                Spacer(minLength: 0)
            } else {
                SettingsForm {
                    ForEach(groups) { group in
                        SettingsSection(group.title, footer: group.footer) {
                            ForEach(group.items) { item in
                                LabeledContent {
                                    HStack(spacing: Vrai.Space.s6) {
                                        ForEach(Array(item.keys.enumerated()), id: \.offset) { index, keys in
                                            if index > 0 {
                                                Text("or", bundle: .module)
                                                    .font(Font.Vrai.caption)
                                                    .foregroundStyle(Color.Vrai.textTertiary)
                                            }
                                            KeyCaps(keys: keys)
                                        }
                                    }
                                } label: {
                                    Text(item.label)
                                        .font(Font.Vrai.body)
                                        .foregroundStyle(Color.Vrai.text)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
    }
}
