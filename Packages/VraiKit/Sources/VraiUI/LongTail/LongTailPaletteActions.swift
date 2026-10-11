import SwiftUI
import VraiCore
import VraiGit

enum LongTailPaletteActions {
    @MainActor static func actions(_ window: WindowModel) -> [PaletteAction] {
        let store = window.store
        let snapshot = store.snapshot
        let selected = store.selection?.commitID
        let hasHead = snapshot?.headOID != nil
        let maintenance = String(localized: "Maintenance", bundle: .module)
        var out: [PaletteAction] = [
            PaletteAction(id: "longtail.new", title: String(localized: "New repository\u{2026}", bundle: .module), icon: "folder.badge.plus", shortcut: "\u{2325}\u{2318}N", keywords: ["init", "create"]) {
                AppSheets.present(.newRepository(folder: nil), window: window)
            },
            PaletteAction(id: "longtail.open", title: String(localized: "Open\u{2026}", bundle: .module), icon: "folder", shortcut: "\u{2318}O", keywords: ["repository"]) {
                AppSheets.present(.open, window: window)
            },
            PaletteAction(id: "longtail.clone", title: String(localized: "Clone\u{2026}", bundle: .module), icon: "square.and.arrow.down", shortcut: "\u{21E7}\u{2318}O", keywords: ["clone", "download", "scalar", "bundle"]) {
                AppSheets.present(.clone(url: nil), window: window)
            },
            PaletteAction(id: "longtail.am", title: String(localized: "Apply patches\u{2026}", bundle: .module), icon: "doc.on.doc", keywords: ["am", "mbox", "mail", "patch"], enabled: snapshot != nil) {
                LongTailActions.openApplyPatches(window)
            },
            PaletteAction(id: "longtail.bundle", title: String(localized: "Create bundle\u{2026}", bundle: .module), icon: "archivebox", keywords: ["bundle"], enabled: hasHead) {
                LongTailActions.openBundle(window)
            },
            PaletteAction(id: "longtail.sparse", title: String(localized: "Sparse checkout\u{2026}", bundle: .module), icon: "folder", keywords: ["sparse-checkout", "cone"], enabled: hasHead, expertOnly: true) {
                LongTailActions.openSparse(window)
            },
            PaletteAction(id: "longtail.gc", title: maintenance + " \u{203A} " + String(localized: "Clean up", bundle: .module), icon: "wrench.and.screwdriver", keywords: ["gc", "garbage"]) {
                LongTailActions.maintenance(window, .gc)
            },
            PaletteAction(id: "longtail.fsck", title: maintenance + " \u{203A} " + String(localized: "Verify integrity", bundle: .module), icon: "stethoscope", keywords: ["fsck", "verify-pack", "health"]) {
                LongTailActions.verifyIntegrity(window)
            },
            PaletteAction(id: "longtail.gc-aggressive", title: maintenance + " \u{203A} " + String(localized: "Clean up thoroughly", bundle: .module), icon: "wrench.and.screwdriver", keywords: ["gc", "aggressive"], expertOnly: true) {
                LongTailActions.maintenance(window, .gcAggressive)
            },
            PaletteAction(id: "longtail.gc-prune", title: maintenance + " \u{203A} " + String(localized: "Clean up and prune now", bundle: .module), icon: "wrench.and.screwdriver", keywords: ["gc", "prune"], expertOnly: true) {
                LongTailActions.maintenance(window, .gcPruneNow)
            },
            PaletteAction(id: "longtail.pack-refs", title: maintenance + " \u{203A} " + String(localized: "Pack refs", bundle: .module), icon: "wrench.and.screwdriver", keywords: ["pack-refs"], expertOnly: true) {
                LongTailActions.maintenance(window, .packRefs)
            },
            PaletteAction(id: "longtail.prune", title: maintenance + " \u{203A} " + String(localized: "Prune unreachable objects", bundle: .module), icon: "trash", keywords: ["prune"], expertOnly: true) {
                LongTailActions.maintenance(window, .prune)
            },
            PaletteAction(id: "longtail.repack", title: maintenance + " \u{203A} " + String(localized: "Repack", bundle: .module), icon: "archivebox", keywords: ["repack", "pack-objects"], expertOnly: true) {
                LongTailActions.maintenance(window, .repack)
            },
            PaletteAction(id: "longtail.commit-graph", title: maintenance + " \u{203A} " + String(localized: "Write commit graph", bundle: .module), icon: "point.3.connected.trianglepath.dotted", keywords: ["commit-graph"], expertOnly: true) {
                LongTailActions.maintenance(window, .commitGraph)
            },
            PaletteAction(id: "longtail.info", title: String(localized: "Repository info\u{2026}", bundle: .module), icon: "info.circle", keywords: ["count-objects", "size", "repo"], enabled: snapshot != nil) {
                LongTailActions.openInfo(window)
            },
            PaletteAction(id: "longtail.gitignore", title: String(localized: "Edit .gitignore", bundle: .module), icon: "eye.slash", keywords: ["ignore"], enabled: snapshot?.root != nil) {
                LongTailActions.openTextFile(window, .gitignore)
            },
            PaletteAction(id: "longtail.gitattributes", title: String(localized: "Edit .gitattributes", bundle: .module), icon: "doc.text", keywords: ["attributes", "lfs"], enabled: snapshot?.root != nil, expertOnly: true) {
                LongTailActions.openTextFile(window, .gitattributes)
            },
            PaletteAction(id: "longtail.mailmap", title: String(localized: "Edit .mailmap", bundle: .module), icon: "person.2", keywords: ["mailmap", "authors"], enabled: snapshot?.root != nil, expertOnly: true) {
                LongTailActions.openTextFile(window, .mailmap)
            },
            PaletteAction(id: "longtail.terminal", title: String(localized: "Open in Terminal", bundle: .module), icon: "terminal", keywords: ["shell", "iterm", "ghostty", "warp"], enabled: snapshot?.root != nil) {
                LongTailActions.openInTerminal(window)
            },
            PaletteAction(id: "longtail.compare", title: String(localized: "Compare branches\u{2026}", bundle: .module), icon: "arrow.left.arrow.right", keywords: ["diff", "cherry", "left-right"], enabled: hasHead) {
                LongTailActions.openCompare(window)
            },
            PaletteAction(id: "longtail.reword", title: String(localized: "Reword selected in place\u{2026}", bundle: .module), icon: "pencil", keywords: ["history", "reword"], enabled: selected != nil, expertOnly: true) {
                if let selected { LongTailActions.openReword(window, id: selected) }
            },
            PaletteAction(id: "longtail.split", title: String(localized: "Split selected\u{2026}", bundle: .module), icon: "rectangle.split.2x1", keywords: ["history", "split"], enabled: selected != nil, expertOnly: true) {
                if let selected { LongTailActions.openSplit(window, id: selected) }
            },
            PaletteAction(id: "longtail.fixup", title: String(localized: "Create fixup commit for selected", bundle: .module), icon: "bandage", keywords: ["fixup", "autosquash"], enabled: selected != nil, expertOnly: true) {
                if let selected { LongTailActions.fixup(window, id: selected) }
            },
            PaletteAction(id: "longtail.patch", title: String(localized: "Save selected as patch\u{2026}", bundle: .module), icon: "square.and.arrow.down", keywords: ["format-patch", "send-email", "imap-send"], enabled: selected != nil) {
                if let selected { LongTailActions.savePatch(window, id: selected) }
            },
            PaletteAction(id: "longtail.archive", title: String(localized: "Export archive\u{2026}", bundle: .module), icon: "archivebox", keywords: ["archive", "zip", "tar"], enabled: hasHead) {
                LongTailActions.openArchive(window, ref: selected?.rawValue ?? "HEAD", label: selected?.short)
            },
            PaletteAction(id: "longtail.clean-ignored", title: String(localized: "Remove untracked and ignored files\u{2026}", bundle: .module), icon: "trash", keywords: ["clean", "-x"], enabled: snapshot?.root != nil, expertOnly: true) {
                LongTailActions.openClean(window, ignored: true)
            },
            PaletteAction(id: "longtail.bugreport", title: String(localized: "Report a git problem\u{2026}", bundle: .module), icon: "stethoscope", keywords: ["bugreport", "diagnose"]) {
                AppSheets.present(.bugReport, window: window)
            }
        ]
        if let branch = snapshot?.currentBranch {
            out.append(PaletteAction(id: "longtail.request-pull", title: String(localized: "Copy pull request summary", bundle: .module), icon: "envelope", keywords: ["request-pull"], expertOnly: true) {
                LongTailActions.copyPullRequestSummary(window, branch: branch.name)
            })
        }
        if store.hasPromisorPacks {
            out.append(PaletteAction(id: "longtail.backfill", title: maintenance + " \u{203A} " + String(localized: "Download missing files", bundle: .module), icon: "arrow.down.to.line", keywords: ["backfill", "partial"], expertOnly: true) {
                LongTailActions.maintenance(window, .backfill)
            })
        }
        for command in AppModel.referenceCommands {
            out.append(PaletteAction(id: "longtail.reference." + command, title: String(localized: "Git reference", bundle: .module) + " \u{203A} git " + command, icon: "doc.text", keywords: ["help", "man", command]) {
                AppSheets.present(.reference(command), window: window)
            })
        }
        return out
    }
}
