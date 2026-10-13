export const H = 3600000;
export const D = 24 * H;

export const ME = { name: "Avery Chen", email: "avery@vrai.app" };
export const PEOPLE = {
  "Avery Chen": "avery@vrai.app",
  "Mira Okafor": "mira@vrai.app",
  "Jonas Lindqvist": "jonas@vrai.app",
  "Priya Raman": "priya@vrai.app",
  "Tomás Ferreira": "tomas@vrai.app",
  "Hana Sato": "hana@vrai.app"
};

export function hashOf(text) {
  let a = 2166136261, b = 5381, out = "";
  for (let round = 0; out.length < 40; round++) {
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i) + round * 31;
      a = Math.imul(a ^ c, 16777619) >>> 0;
      b = (Math.imul(b, 33) + c) >>> 0;
    }
    out += ((a ^ b) >>> 0).toString(16).padStart(8, "0");
  }
  return out.slice(0, 40);
}

const fullId = (short) => (short + hashOf(short)).slice(0, 40);

export function rng(seed) {
  let s = 0;
  for (let i = 0; i < seed.length; i++) s = (Math.imul(s, 31) + seed.charCodeAt(i)) >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const L = (t, text) => ({ t, text });

export function numberHunk(header, rows) {
  const m = header.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$/);
  let o = m ? Number(m[1]) : 1, nw = m ? Number(m[2]) : 1;
  const lines = rows.map((r) => {
    const line = { t: r.t, text: r.text };
    if (r.words) line.words = r.words;
    if (r.t === " ") { line.old = o++; line.new = nw++; }
    else if (r.t === "-") line.old = o++;
    else line.new = nw++;
    if (r.staged != null) line.staged = r.staged;
    return line;
  });
  const oldCount = lines.filter((l) => l.t !== "+").length;
  const newCount = lines.filter((l) => l.t !== "-").length;
  const start = m ? [m[1], m[2]] : ["1", "1"];
  const title = m ? m[3] : "";
  return { header: "@@ -" + start[0] + "," + oldCount + " +" + start[1] + "," + newCount + " @@" + title, lines };
}

export function statOf(hunks) {
  let additions = 0, deletions = 0;
  for (const h of hunks || []) for (const l of h.lines) { if (l.t === "+") additions++; else if (l.t === "-") deletions++; }
  return { additions, deletions };
}

const SWIFT_POOL = [
  "    @Published private(set) var state: {T}State = .idle",
  "    private let git: GitProcess",
  "    init(git: GitProcess) { self.git = git }",
  "    func refresh() async throws {",
  "        let output = try await git.run([\"status\", \"--porcelain=v2\", \"-z\"])",
  "        state = .loaded(try StatusParser.parse(output))",
  "    }",
  "        guard let repository else { return }",
  "        withAnimation(.Vrai.outBase) { isPresented = true }",
  "    var body: some View {",
  "        HStack(spacing: Vrai.Space.s8) {",
  "            Image(systemName: \"arrow.triangle.branch\")",
  "            Text(branch.name).font(.Vrai.body)",
  "        }",
  "        .foregroundStyle(Color.Vrai.textSecondary)",
  "        .padding(.horizontal, Vrai.Space.s10)",
  "    enum {T}State { case idle, loading, loaded([Entry]), failed(GitError) }",
  "    static let defaultLimit = 2_000",
  "        for (index, entry) in entries.enumerated() where entry.isVisible {",
  "            rows.append(Row(index: index, entry: entry))",
  "        return rows",
  "    @Environment(\\.expertMode) private var expertMode",
  "        if expertMode { CommandPreview(command: command) }",
  "        let arguments = [\"push\", remote.name, branch.name]",
  "        try await git.run(arguments, progress: progress)",
  "        let url = try XCTUnwrap(submodule.url)",
  "        XCTAssertEqual(model.rows.count, 3)",
  "    func cancel() { task?.cancel(); task = nil }",
  "        defer { isBusy = false }",
  "        isBusy = true",
  "    private var task: Task<Void, Never>?",
  "        let lines = output.split(separator: \"\\n\", omittingEmptySubsequences: false)",
  "        progress.completedUnitCount = Int64(received)",
  "        .accessibilityLabel(Text(\"\\(n) commits to push\"))",
  "        .keyboardShortcut(\"p\", modifiers: [.command, .shift])",
  "        .help(\"Push \\(ahead) commits\")",
  "    func select(_ id: Commit.ID) { selection = [id] }",
  "        if let index = rows.firstIndex(where: { $0.id == id }) { scrollTarget = index }",
  "    nonisolated func stream(_ arguments: [String]) -> AsyncThrowingStream<String, Error> {",
  "        continuation.yield(String(decoding: chunk, as: UTF8.self))",
  "    let maximumAge: TimeInterval = 14 * 24 * 60 * 60",
  "        try FileManager.default.createDirectory(at: undoDirectory, withIntermediateDirectories: true)"
];
const MD_POOL = [
  "Vrai draws each branch as a line in its own color and keeps that color for the branch's whole life.",
  "- Lane 1, ultramarine, is the main line.",
  "- Merge commits are hollow rings; HEAD wears a halo.",
  "## Lane colors",
  "Colors cycle after eight lanes. They mark identity, never status.",
  "- Faster graph layout on repositories with long histories.",
  "- Signed tags show who signed them and whether the key is trusted.",
  "- Stage single lines from the gutter.",
  "### Fixed",
  "- The sync button no longer overlaps the title in narrow windows.",
  "## 0.9.1",
  "Released Oct 5, 2026."
];
const METAL_POOL = [
  "struct LaneInstance { float2 from; float2 to; float4 color; float width; };",
  "vertex LaneVertexOut laneVertex(uint vid [[vertex_id]], uint iid [[instance_id]],",
  "                                constant LaneInstance *lanes [[buffer(0)]]) {",
  "    LaneInstance lane = lanes[iid];",
  "    float2 dir = normalize(lane.to - lane.from);",
  "    float2 normal = float2(-dir.y, dir.x) * lane.width * 0.5;",
  "    out.position = float4(corner, 0, 1);",
  "    return out;",
  "}",
  "fragment float4 laneFragment(LaneVertexOut in [[stage_in]]) { return in.color; }"
];

function synthHunks(path, adds, dels, seed) {
  const r = rng(seed + path);
  const base = path.split("/").pop().replace(/\.[a-z0-9]+$/i, "");
  const T = base.replace(/[^A-Za-z0-9]/g, "") || "Model";
  const ext = (path.match(/\.([a-z0-9]+)$/i) || [])[1] || "";
  const pool = ext === "md" ? MD_POOL : ext === "metal" ? METAL_POOL : SWIFT_POOL;
  const pick = () => pool[Math.floor(r() * pool.length)].replace(/\{T\}/g, T);
  const ctxTitle = ext === "md" ? "" : ext === "metal" ? " #include <metal_stdlib>" : " struct " + T + " {";
  if (dels === 0 && adds > 0 && /^(A|\?)$/.test(seed.split(":")[0])) {
    const rows = Array.from({ length: adds }, () => L("+", pick()));
    return [numberHunk("@@ -0,0 +1," + adds + " @@", rows)];
  }
  const chunks = adds + dels > 14 ? 2 : 1;
  const hunks = [];
  let start = 12 + Math.floor(r() * 30);
  let a = adds, d = dels;
  for (let c = 0; c < chunks; c++) {
    const ca = c === chunks - 1 ? a : Math.ceil(a / 2);
    const cd = c === chunks - 1 ? d : Math.ceil(d / 2);
    a -= ca; d -= cd;
    const rows = [];
    for (let i = 0; i < 3; i++) rows.push(L(" ", pick()));
    for (let i = 0; i < cd; i++) rows.push(L("-", pick()));
    for (let i = 0; i < ca; i++) rows.push(L("+", pick()));
    for (let i = 0; i < 3; i++) rows.push(L(" ", pick()));
    hunks.push(numberHunk("@@ -" + start + ",0 +" + start + ",0 @@" + ctxTitle, rows));
    start += 30 + Math.floor(r() * 40);
  }
  if (hunks[0]) hunks[0].collapsedBefore = Math.max(0, Number(hunks[0].header.match(/-(\d+)/)[1]) - 1);
  return hunks;
}

const DIFFS = {
  "e41c9a2:Sources/VraiGit/Graph/LaneLayout.swift": [
    numberHunk("@@ -42,9 +42,14 @@ struct LaneLayout {", [
      L(" ", "    func path(from a: Lane, to b: Lane, in row: CGRect) -> Path {"),
      L(" ", "        var path = Path()"),
      L(" ", "        path.move(to: point(for: a, y: row.minY))"),
      { t: "-", text: "        path.addLine(to: point(for: b, y: row.maxY))", words: [[13, 20]] },
      L("+", "        let mid = row.midY"),
      { t: "+", text: "        path.addCurve(", words: [[13, 21]] },
      L("+", "            to: point(for: b, y: row.maxY),"),
      L("+", "            control1: point(for: a, y: mid),"),
      L("+", "            control2: point(for: b, y: mid)"),
      L("+", "        )"),
      L(" ", "        return path"),
      L(" ", "    }"),
      L(" ", ""),
      L("-", "    // TODO: curves for lane changes"),
      L("+", "    /// Lanes keep their color from the branch tip down."),
      L(" ", "    var colors: [LaneColor] = LaneColor.palette")
    ]),
    numberHunk("@@ -88,6 +93,7 @@ extension LaneLayout {", [
      L(" ", "    static let laneWidth: CGFloat = 14"),
      L(" ", "    static let nodeSize: CGFloat = 9"),
      L("+", "    static let headHalo: CGFloat = 16"),
      L(" ", "}")
    ])
  ],
  "e41c9a2:Sources/VraiUI/History/GraphCell.swift": [
    numberHunk("@@ -18,11 +18,14 @@ struct GraphCell: View {", [
      L(" ", "    let row: GraphRow"),
      L(" ", "    let lanes: Int"),
      { t: "-", text: "    var height: CGFloat = 28", words: [[26, 28]] },
      { t: "+", text: "    var height: CGFloat = Vrai.Size.row", words: [[26, 40]] },
      L("+", "    var isHead = false"),
      L(" ", ""),
      L(" ", "    var body: some View {"),
      L(" ", "        Canvas { context, size in"),
      L(" ", "            for segment in row.segments {"),
      L("-", "                context.stroke(layout.line(segment, in: size), with: .color(segment.color))"),
      L("+", "                let path = layout.path(from: segment.from, to: segment.to, in: CGRect(origin: .zero, size: size))"),
      L("+", "                context.stroke(path, with: .color(Color.Vrai.lane(segment.color)), lineWidth: Vrai.Size.line)"),
      L(" ", "            }"),
      L("+", "            if isHead { context.stroke(layout.halo(at: row.lane, in: size), with: .color(Color.Vrai.lane(row.color).opacity(0.5))) }"),
      L(" ", "            context.fill(layout.node(at: row.lane, in: size), with: .color(Color.Vrai.lane(row.color)))"),
      L(" ", "        }")
    ])
  ],
  "7d1a5e9:Sources/VraiUI/Toolbar/SyncButton.swift": [
    numberHunk("@@ -4,14 +4,22 @@ struct SyncButton: View {", [
      L(" ", "struct SyncButton: View {"),
      L(" ", "    let ahead: Int"),
      L(" ", "    let behind: Int"),
      L("+", "    var isBusy = false"),
      L(" ", ""),
      L("-", "    var label: String { \"Sync\" }"),
      L("+", "    var label: String {"),
      L("+", "        ahead == 0 ? \"Push\" : \"Push \\(ahead) commits\""),
      L("+", "    }"),
      L(" ", ""),
      L(" ", "    var body: some View {"),
      L("-", "        Label(label, systemImage: \"arrow.triangle.2.circlepath\")"),
      L("+", "        Label(label, systemImage: \"arrow.up.to.line\")"),
      L("+", "            .badge(ahead)"),
      L("+", "            .help(ahead == 0 ? \"Nothing to push\" : \"Push \\(ahead) commits to \\(upstream)\")"),
      L("+", "            .keyboardShortcut(\"p\", modifiers: [.command, .shift])"),
      L(" ", "    }"),
      L(" ", "}")
    ])
  ],
  "9a2d6c4:Sources/VraiUI/Diff/DiffGutter.swift": [
    numberHunk("@@ -0,0 +1,22 @@", [
      L("+", "import SwiftUI"),
      L("+", ""),
      L("+", "/// Line numbers beside a hunk. Click a changed line to select it,"),
      L("+", "/// shift-click to extend, command-click to add or remove one line."),
      L("+", "struct DiffGutter: View {"),
      L("+", "    let hunk: Hunk"),
      L("+", "    @Binding var selection: LineSelection"),
      L("+", ""),
      L("+", "    var body: some View {"),
      L("+", "        VStack(spacing: 0) {"),
      L("+", "            ForEach(hunk.lines) { line in"),
      L("+", "                LineNumbers(line: line, isSelected: selection.contains(line.id))"),
      L("+", "                    .contentShape(Rectangle())"),
      L("+", "                    .onTapGesture { selection.toggle(line, extend: NSEvent.modifierFlags.contains(.shift)) }"),
      L("+", "                    .disabled(line.kind == .context)"),
      L("+", "            }"),
      L("+", "        }"),
      L("+", "        .font(.Vrai.codeSmall)"),
      L("+", "        .foregroundStyle(Color.Vrai.textTertiary)"),
      L("+", "        .accessibilityLabel(Text(\"Lines \\(hunk.newRange.lowerBound) to \\(hunk.newRange.upperBound)\"))"),
      L("+", "    }"),
      L("+", "}")
    ])
  ],
  "3e7b1f5:Sources/VraiUI/Banners/RebaseBanner.swift": [
    numberHunk("@@ -9,12 +9,19 @@ struct RebaseBanner: View {", [
      L(" ", "    let state: RebaseState"),
      L(" ", ""),
      L(" ", "    var body: some View {"),
      L("-", "        Banner(\"Rebasing \\(state.branch)\", tone: .warning) {"),
      L("+", "        Banner(\"Rebasing \\(state.branch) onto \\(state.onto)\", tone: .warning) {"),
      L("+", "            StepDots(current: state.step, total: state.total, stopped: state.isStopped)"),
      L("+", "            Text(\"\\(state.step) of \\(state.total)\").font(.Vrai.caption).monospacedDigit()"),
      L(" ", "            Button(\"Abort\", role: .destructive) { abort() }"),
      L(" ", "            Button(\"Continue\") { proceed() }"),
      L("+", "                .keyboardShortcut(.return, modifiers: .command)"),
      L(" ", "        }"),
      L(" ", "    }")
    ])
  ]
};

const C = [
  ["A1", "e41c9a2", "Graph: draw merge curves with cubic béziers", "Avery Chen", 2, ["A2"], 1, "verified", [["Sources/VraiGit/Graph/LaneLayout.swift", "M"], ["Sources/VraiUI/History/GraphCell.swift", "M"]], "Lane changes used straight segments, which crossed nodes on dense graphs.\nCurves use the row's vertical midpoint as both control points, so\nparallel lanes never touch."],
  ["R1", "4f9b2c7", "Graph: snap nodes to the pixel grid", "Mira Okafor", 5, ["A3"], 1, "verified", [["Sources/VraiUI/History/GraphCell.swift", "M", 4, 2], ["Sources/VraiGit/Graph/NodeShape.swift", "M", 7, 1]], "Nodes at fractional offsets looked blurry on non-Retina displays."],
  ["J1", "9a2d6c4", "Diff: stage individual lines from the gutter", "Jonas Lindqvist", 6, ["J2"], 2, "verified", [["Sources/VraiUI/Diff/DiffGutter.swift", "A"], ["Sources/VraiUI/Diff/HunkView.swift", "M", 21, 8], ["Sources/VraiGit/Staging/StagingService.swift", "M", 33, 5]], "Builds a patch from the selected lines and applies it to the index\nwith git apply --cached, so partial staging never touches the working tree."],
  ["A2", "c81d0e5", "Graph: keep the HEAD halo above merge rings", "Avery Chen", 27, ["A3"], 1, "verified", [["Sources/VraiUI/History/GraphCell.swift", "M", 5, 2]], ""],
  ["M0", "2b6e8f1", "Docs: explain lane colors in the README", "Tomás Ferreira", 29, ["M1"], 0, "verified", [["README.md", "M", 18, 2]], ""],
  ["A3", "b7f03d1", "Graph: assign lane colors from branch tips", "Mira Okafor", 31, ["M1"], 1, "verified", [["Sources/VraiGit/Graph/LaneLayout.swift", "M", 22, 9], ["Sources/VraiUI/History/Palette.swift", "M", 6, 0]], "A branch keeps one color from its tip down, so the same line reads\nas the same branch everywhere: graph, pills and sidebar."],
  ["J2", "5c8e1f3", "Diff: track selected line ranges per hunk", "Jonas Lindqvist", 34, ["M2"], 2, "unknown", [["Sources/VraiGit/Staging/LineSelection.swift", "A", 48, 0], ["Sources/VraiUI/Diff/HunkView.swift", "M", 12, 4]], ""],
  ["S1", "a8d3f60", "Metal: draw lanes with instanced quads", "Mira Okafor", 40, ["M2"], 6, "none", [["Sources/VraiUI/History/GraphRenderer.metal", "A", 46, 0], ["Sources/VraiUI/History/MetalGraphView.swift", "A", 71, 0], ["Sources/VraiGit/Graph/LaneLayout.swift", "M", 11, 7]], "Spike. Draws every lane segment as one instanced quad; 50,000 commits\nscroll at 120 fps on an M3. Not ready to merge: no curves yet."],
  ["M1", "0f4b8d2", "Merge branch 'fix/rebase-banner'", "Priya Raman", 48, ["M2", "H1"], 0, "verified", [["Sources/VraiUI/Banners/RebaseBanner.swift", "M"]], ""],
  ["M2", "7d1a5e9", "Toolbar: show the push count on the sync capsule", "Tomás Ferreira", 72, ["M3"], 0, "verified", [["Sources/VraiUI/Toolbar/SyncButton.swift", "M"], ["Sources/VraiUI/Toolbar/ToolbarModel.swift", "M", 8, 2]], "The capsule said Sync, which hid what would happen. It now says\nPush 2 commits, and the count updates after every fetch."],
  ["H1", "3e7b1f5", "Rebase: show step progress in the banner", "Hana Sato", 76, ["M3"], 3, "none", [["Sources/VraiUI/Banners/RebaseBanner.swift", "M"], ["Sources/VraiGit/Rebase/RebaseState.swift", "M", 9, 1]], ""],
  ["M3", "a1c5e9b", "Release 0.9.1", "Priya Raman", 144, ["M4"], 0, "verified", [["CHANGELOG.md", "M", 14, 0], ["Vrai/Info.plist", "M", 2, 2]], ""],
  ["M4", "c3e7a1f", "Sidebar: group branches by prefix", "Mira Okafor", 192, ["M5"], 0, "verified", [["Sources/VraiUI/Sidebar/SidebarModel.swift", "M", 27, 11], ["Sources/VraiUI/Sidebar/BranchTree.swift", "A", 58, 0]], ""],
  ["M5", "e5a9c3f", "Fix crash when a submodule has no URL", "Tomás Ferreira", 264, ["M6"], 0, "verified", [["Sources/VraiGit/Submodules/SubmoduleService.swift", "M", 6, 2], ["Tests/VraiGitTests/SubmoduleTests.swift", "M", 18, 0]], ""],
  ["M6", "f7b1d5a", "Console: stream git output line by line", "Hana Sato", 336, ["M7"], 0, "verified", [["Sources/VraiGit/Process/GitProcess.swift", "M", 34, 12], ["Sources/VraiUI/Console/ConsoleView.swift", "M", 9, 3]], ""],
  ["M7", "2d9c4a8", "Merge branch 'feature/conflict-view'", "Priya Raman", 384, ["M8", "C1"], 0, "verified", [["Sources/VraiUI/Conflicts/ConflictView.swift", "M", 16, 3]], ""],
  ["C1", "6e1b7d3", "Conflicts: accept both sides in one click", "Jonas Lindqvist", 408, ["C2"], 5, "verified", [["Sources/VraiUI/Conflicts/ConflictView.swift", "M", 16, 3]], ""],
  ["M8", "9b4f2e6", "Settings: move signing into its own pane", "Avery Chen", 432, ["M9"], 0, "verified", [["Sources/VraiUI/Settings/SigningPane.swift", "A", 62, 0], ["Sources/VraiUI/Settings/SettingsView.swift", "M", 4, 19]], ""],
  ["C2", "d0a7c5e", "Conflicts: show current and incoming side by side", "Jonas Lindqvist", 456, ["M9"], 5, "verified", [["Sources/VraiUI/Conflicts/ConflictView.swift", "A", 88, 0], ["Sources/VraiGit/Conflicts/ConflictParser.swift", "A", 54, 0]], ""],
  ["M9", "d9e3b7a", "Release 0.9.0", "Priya Raman", 504, ["M10"], 0, "verified", [["CHANGELOG.md", "M", 22, 0], ["Vrai/Info.plist", "M", 2, 2]], ""],
  ["M10", "5a2c8e1", "Clone: show objects and speed while receiving", "Tomás Ferreira", 552, ["M11"], 0, "verified", [["Sources/VraiGit/Clone/CloneProgress.swift", "M", 29, 6]], ""],
  ["M11", "8f3d1b9", "Palette: run any git command typed after git", "Avery Chen", 600, ["M12"], 0, "verified", [["Sources/VraiUI/Palette/CommandPalette.swift", "M", 41, 9], ["Sources/VraiGit/Process/CommandParser.swift", "A", 37, 0]], ""],
  ["M12", "1c7e5a4", "Stashes: create a branch from a stash", "Hana Sato", 648, ["M13"], 0, "verified", [["Sources/VraiUI/Stashes/StashList.swift", "M", 17, 2]], ""],
  ["M13", "4e8a2f7", "Merge branch 'feature/blame'", "Priya Raman", 696, ["M14", "B1"], 0, "verified", [["Sources/VraiUI/Blame/BlameView.swift", "M", 12, 1]], ""],
  ["B1", "7b2d9e4", "Blame: color lines by age", "Mira Okafor", 720, ["B2"], 4, "verified", [["Sources/VraiUI/Blame/BlameView.swift", "M", 12, 1]], ""],
  ["M14", "3a6f0c2", "History: filter by author and path", "Jonas Lindqvist", 744, ["M15"], 0, "verified", [["Sources/VraiUI/History/HistoryFilter.swift", "A", 52, 0]], ""],
  ["B2", "e2c4a6b", "Blame: step back to the commit before a change", "Mira Okafor", 792, ["M15"], 4, "verified", [["Sources/VraiUI/Blame/BlameView.swift", "A", 77, 0]], ""],
  ["M15", "6d0b3f8", "Worktrees: open each in its own window", "Avery Chen", 840, ["M16"], 0, "verified", [["Sources/VraiUI/Worktrees/WorktreeList.swift", "M", 23, 5]], ""],
  ["M16", "b5f1a9d", "Release 0.8.0", "Priya Raman", 912, ["M17"], 0, "verified", [["CHANGELOG.md", "M", 19, 0]], ""],
  ["M17", "0e9c7b5", "Undo: restore discarded changes from the reflog", "Hana Sato", 984, ["M18"], 0, "verified", [["Sources/VraiGit/Undo/UndoStore.swift", "A", 66, 0]], ""],
  ["M18", "f2a8d4c", "Graph: first lane layout", "Mira Okafor", 1080, ["M19"], 0, "verified", [["Sources/VraiGit/Graph/LaneLayout.swift", "A", 88, 0]], ""],
  ["M19", "9c1e6a3", "Create the Vrai app target", "Priya Raman", 1248, [], 0, "verified", [["Vrai.xcodeproj/project.pbxproj", "A", 214, 0], ["Vrai/VraiApp.swift", "A", 18, 0]], ""]
];

function buildCommits(now) {
  const ids = Object.fromEntries(C.map((c) => [c[0], fullId(c[1])]));
  const commits = {};
  const order = [];
  for (const [key, short, subject, author, hours, parents, color, signature, files, body] of C) {
    const id = ids[key];
    const fl = files.map(([path, status, adds, dels]) => {
      const hand = DIFFS[short + ":" + path];
      const hunks = hand || synthHunks(path, adds != null ? adds : 12, dels != null ? dels : 3, status + ":" + short);
      const st = statOf(hunks);
      return { path, status, additions: st.additions, deletions: st.deletions, hunks };
    });
    commits[id] = { id, subject, body: body || "", author, email: PEOPLE[author], committer: author, date: now - hours * H, parents: parents.map((p) => ids[p]), color, signature, files: fl };
    order.push(id);
  }
  return { commits, order, ids };
}

const WORKING = () => [
  { path: "Sources/VraiUI/History/GraphCell.swift", status: "M", hunks: [
    numberHunk("@@ -24,9 +24,15 @@ struct GraphCell: View {", [
      L(" ", "    var body: some View {"),
      L(" ", "        Canvas { context, size in"),
      L(" ", "            let rect = CGRect(origin: .zero, size: size)"),
      L("+", "            if isHead {"),
      L("+", "                let halo = layout.halo(at: row.lane, in: rect, radius: HeadHalo.radius)"),
      L("+", "                context.stroke(halo, with: .color(Color.Vrai.lane(row.color).opacity(0.5)), lineWidth: 1.5)"),
      L("+", "            }"),
      L(" ", "            for segment in row.segments {"),
      { t: "-", text: "                context.stroke(layout.path(from: segment.from, to: segment.to, in: rect), with: .color(Color.Vrai.lane(segment.color)))", words: [[16, 30]] },
      L("+", "                let path = layout.path(from: segment.from, to: segment.to, in: rect)"),
      { t: "+", text: "                context.stroke(path, with: .color(Color.Vrai.lane(segment.color)), style: StrokeStyle(lineWidth: Vrai.Size.line, lineCap: .round))", words: [[83, 145]] },
      L(" ", "            }"),
      L("-", "            context.fill(layout.node(at: row.lane, in: rect), with: .color(Color.Vrai.lane(row.color)))"),
      L("+", "            let node = layout.node(at: row.lane, in: rect, merge: row.isMerge)"),
      L("+", "            row.isMerge ? context.stroke(node, with: .color(Color.Vrai.lane(row.color)), lineWidth: Vrai.Size.line) : context.fill(node, with: .color(Color.Vrai.lane(row.color)))"),
      L(" ", "        }"),
      L(" ", "        .frame(width: CGFloat(lanes) * Vrai.Size.lane + 12, height: height)"),
      L(" ", "        .accessibilityHidden(true)")
    ]),
    numberHunk("@@ -51,6 +57,11 @@ struct GraphCell: View {", [
      L(" ", "    private var layout: LaneLayout { LaneLayout(laneWidth: Vrai.Size.lane, nodeSize: Vrai.Size.node) }"),
      L(" ", "}"),
      L(" ", ""),
      L("+", "#Preview(\"Head on a merge\") {"),
      L("+", "    GraphCell(row: .preview(merge: true), lanes: 3, isHead: true)"),
      L("+", "        .padding()"),
      L("+", "}"),
      L("+", ""),
      L(" ", "extension GraphRow {"),
      L(" ", "    static func preview(merge: Bool = false) -> GraphRow {")
    ])
  ], stageAll: true },
  { path: "Sources/VraiGit/Graph/LaneLayout.swift", status: "M", hunks: [
    numberHunk("@@ -12,7 +12,8 @@ struct LaneLayout {", [
      L(" ", "    var laneWidth: CGFloat = 14"),
      L(" ", "    var nodeSize: CGFloat = 9"),
      L("+", "    var haloSize: CGFloat = 16"),
      L(" ", ""),
      L(" ", "    func x(for lane: Int) -> CGFloat {"),
      { t: "-", text: "        CGFloat(lane) * laneWidth + laneWidth / 2", words: [] },
      { t: "+", text: "        CGFloat(lane) * laneWidth + laneWidth / 2 + inset", words: [[49, 57]] },
      L(" ", "    }")
    ]),
    numberHunk("@@ -64,6 +65,14 @@ struct LaneLayout {", [
      L(" ", "        return path"),
      L(" ", "    }"),
      L(" ", ""),
      L("+", "    func halo(at lane: Int, in rect: CGRect, radius: CGFloat) -> Path {"),
      L("+", "        let center = CGPoint(x: x(for: lane), y: rect.midY)"),
      L("+", "        return Path(ellipseIn: CGRect(x: center.x - radius / 2, y: center.y - radius / 2, width: radius, height: radius))"),
      L("+", "    }"),
      L("+", ""),
      L("+", "    /// Space before the first lane, so the halo never clips."),
      L("+", "    var inset: CGFloat { (haloSize - nodeSize) / 2 }"),
      L("+", ""),
      L(" ", "    func node(at lane: Int, in rect: CGRect, merge: Bool = false) -> Path {"),
      L(" ", "        let size = merge ? nodeSize - 0.5 : nodeSize"),
      L(" ", "        return Path(ellipseIn: CGRect(x: x(for: lane) - size / 2, y: rect.midY - size / 2, width: size, height: size))")
    ])
  ], stageHunks: [0] },
  { path: "Sources/VraiUI/History/HeadHalo.swift", status: "?", hunks: [
    numberHunk("@@ -0,0 +1,24 @@", [
      "import SwiftUI", "", "/// The ring drawn around the commit HEAD points at.", "struct HeadHalo: View {", "    static let radius: CGFloat = 16", "",
      "    var color: Color", "    @Environment(\\.accessibilityReduceMotion) private var reduceMotion", "    @State private var appeared = false", "",
      "    var body: some View {", "        Circle()", "            .stroke(color.opacity(0.5), lineWidth: 1.5)", "            .frame(width: Self.radius, height: Self.radius)",
      "            .scaleEffect(appeared || reduceMotion ? 1 : 0.6)", "            .opacity(appeared ? 1 : 0)", "            .onAppear {",
      "                withAnimation(reduceMotion ? .Vrai.standardFast : .Vrai.springGraph) {", "                    appeared = true", "                }", "            }",
      "            .accessibilityHidden(true)", "    }", "}"
    ].map((t) => L("+", t)))
  ] },
  { path: "Sources/VraiUI/History/LaneColors.swift", oldPath: "Sources/VraiUI/History/Palette.swift", status: "R", hunks: [
    numberHunk("@@ -1,9 +1,9 @@", [
      L(" ", "import SwiftUI"),
      L(" ", ""),
      L("-", "/// Graph palette, in lane order."),
      L("-", "enum Palette {"),
      L("+", "/// Lane colors, in lane order. A branch keeps its color for its whole life."),
      L("+", "enum LaneColors {"),
      L(" ", "    static func color(for lane: Int) -> Color {"),
      L(" ", "        Color.Vrai.lane(lane)"),
      L(" ", "    }"),
      L(" ", ""),
      L("-", "    static let names = [\"blue\", \"orange\", \"green\", \"pink\", \"cyan\", \"yellow\", \"purple\", \"red\"]"),
      L("+", "    static let names = [\"ultramarine\", \"tangerine\", \"jade\", \"magenta\", \"teal\", \"mustard\", \"violet\", \"red\"]"),
      L(" ", "}")
    ])
  ], stageAll: true },
  { path: "Resources/Graph.xcassets/Contents.json", status: "D", hunks: [
    numberHunk("@@ -1,12 +0,0 @@", [
      "{", "  \"colors\" : [", "    {", "      \"color\" : {", "        \"color-space\" : \"srgb\",", "        \"components\" : { \"red\" : \"0.212\", \"green\" : \"0.357\", \"blue\" : \"0.949\", \"alpha\" : \"1.000\" }",
      "      },", "      \"idiom\" : \"universal\"", "    }", "  ],", "  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }", "}"
    ].map((t) => L("-", t)))
  ] },
  { path: "Notes/graph-perf.md", status: "?", hunks: [
    numberHunk("@@ -0,0 +1,13 @@", [
      "# Graph performance notes", "", "Measured on the vrai repository with 1,284 commits, M3 MacBook Air.", "",
      "| Change | First frame | Scroll, 60 rows |", "| --- | --- | --- |", "| Straight segments | 41 ms | 2.1 ms |", "| Cubic curves | 44 ms | 2.4 ms |", "| Cached paths per row | 29 ms | 1.2 ms |", "",
      "- Curves cost about 3 ms on the first frame; caching more than pays for it.", "- Lane colors are looked up once per row, not per segment.", "- Next: try Metal past 50,000 commits, see mira/spike/metal-graph."
    ].map((t) => L("+", t)))
  ] }
];

export function prepareWorking(list) {
  return list.map((f) => {
    const hunks = f.hunks.map((h, hi) => ({ ...h, lines: h.lines.map((l) => (l.t === " " ? { ...l } : { ...l, staged: !!(f.stageAll || (f.stageHunks && f.stageHunks.includes(hi))) })) }));
    const out = { path: f.path, status: f.status, hunks };
    if (f.oldPath) out.oldPath = f.oldPath;
    return out;
  });
}

export const CONFLICTS = () => [
  { path: "Sources/VraiGit/Graph/LaneLayout.swift", blocks: [
    { type: "context", lines: ["struct LaneLayout {", "    var laneWidth: CGFloat = 14", "    var nodeSize: CGFloat = 9"] },
    { type: "conflict", index: 1, ours: { label: "HEAD, feature/graph-renderer", lines: ["    var haloSize: CGFloat = 16"] }, theirs: { label: "mira/spike/metal-graph", lines: ["    var instanceBuffer: MTLBuffer?", "    var usesMetal: Bool { instanceBuffer != nil }"] }, resolution: null },
    { type: "context", lines: ["", "    func x(for lane: Int) -> CGFloat {"] },
    { type: "conflict", index: 2, ours: { label: "HEAD, feature/graph-renderer", lines: ["        CGFloat(lane) * laneWidth + laneWidth / 2 + inset"] }, theirs: { label: "mira/spike/metal-graph", lines: ["        (CGFloat(lane) + 0.5) * laneWidth"] }, resolution: null },
    { type: "context", lines: ["    }", "", "    func path(from a: Lane, to b: Lane, in row: CGRect) -> Path {"] }
  ] },
  { path: "Sources/VraiUI/History/GraphCell.swift", blocks: [
    { type: "context", lines: ["struct GraphCell: View {", "    let row: GraphRow", "    let lanes: Int", "", "    var body: some View {"] },
    { type: "conflict", index: 1, ours: { label: "HEAD, feature/graph-renderer", lines: ["        Canvas { context, size in", "            draw(in: &context, size: size)", "        }"] }, theirs: { label: "mira/spike/metal-graph", lines: ["        MetalGraphView(row: row, lanes: lanes)"] }, resolution: null },
    { type: "context", lines: ["        .frame(width: width, height: height)", "        .accessibilityHidden(true)", "    }", "}"] }
  ] }
];

export const BLAME_FILE = "Sources/VraiGit/Graph/LaneLayout.swift";
export function blameLines(ids, now) {
  const src = [
    ["M18", "import CoreGraphics"], ["M18", "import SwiftUI"], ["M18", ""], ["A3", "/// Places each commit of the graph in a lane and draws the lines between them."],
    ["M18", "struct LaneLayout {"], ["M18", "    var laneWidth: CGFloat = 14"], ["M18", "    var nodeSize: CGFloat = 9"], ["M18", ""],
    ["M18", "    func x(for lane: Int) -> CGFloat {"], ["M18", "        CGFloat(lane) * laneWidth + laneWidth / 2"], ["M18", "    }"], ["M18", ""],
    ["A3", "    func color(for row: GraphRow, at lane: Int) -> Int {"], ["A3", "        row.tipColor[lane] ?? colors.next(for: lane)"], ["A3", "    }"], ["A3", ""],
    ["M18", "    func point(for lane: Lane, y: CGFloat) -> CGPoint {"], ["M18", "        CGPoint(x: x(for: lane.index), y: y)"], ["M18", "    }"], ["M18", ""],
    ["M1", "    func path(from a: Lane, to b: Lane, in row: CGRect) -> Path {"], ["M1", "        var path = Path()"], ["M1", "        path.move(to: point(for: a, y: row.minY))"],
    ["A1", "        let mid = row.midY"], ["A1", "        path.addCurve("], ["A1", "            to: point(for: b, y: row.maxY),"], ["A1", "            control1: point(for: a, y: mid),"], ["A1", "            control2: point(for: b, y: mid)"], ["A1", "        )"],
    ["M4", "        return path"], ["M4", "    }"], ["M4", ""],
    ["A1", "    /// Lanes keep their color from the branch tip down."], ["A3", "    var colors: [LaneColor] = LaneColor.palette"], ["M18", ""],
    ["M18", "    func node(at lane: Int, in rect: CGRect, merge: Bool = false) -> Path {"], ["M2", "        let size = merge ? nodeSize - 0.5 : nodeSize"],
    ["M18", "        return Path(ellipseIn: CGRect(x: x(for: lane) - size / 2, y: rect.midY - size / 2, width: size, height: size))"], ["M18", "    }"], ["M18", "}"]
  ];
  return src.map(([k, text], i) => ({ no: i + 1, text, key: k, hash: ids[k] }));
}

export function seedRepo(now) {
  const { commits, order, ids } = buildCommits(now);
  return {
    id: "vrai",
    name: "vrai",
    path: "~/Developer/vrai",
    commits,
    order,
    ids,
    head: { type: "branch", name: "feature/graph-renderer" },
    branches: {
      "feature/graph-renderer": { name: "feature/graph-renderer", tip: ids.A1, color: 1, upstream: "origin/feature/graph-renderer" },
      "main": { name: "main", tip: ids.M1, color: 0, upstream: "origin/main" },
      "feature/line-staging": { name: "feature/line-staging", tip: ids.J1, color: 2, upstream: "origin/feature/line-staging" },
      "fix/rebase-banner": { name: "fix/rebase-banner", tip: ids.H1, color: 3, upstream: null },
      "release/0.9": { name: "release/0.9", tip: ids.M3, color: 4, upstream: "origin/release/0.9" },
      "mira/spike/metal-graph": { name: "mira/spike/metal-graph", tip: ids.S1, color: 6, upstream: "mira/spike/metal-graph" }
    },
    remotes: {
      origin: { name: "origin", url: "git@github.com:vrai-app/vrai.git", pushUrl: "", head: "main", prune: true, branches: { "main": ids.M0, "feature/graph-renderer": ids.R1, "feature/line-staging": ids.J1, "release/0.9": ids.M3 } },
      mira: { name: "mira", url: "git@github.com:miraokafor/vrai.git", pushUrl: "", head: "spike/metal-graph", prune: false, branches: { "spike/metal-graph": ids.S1 } }
    },
    tags: {
      "v0.9.1": { name: "v0.9.1", target: ids.M3, annotated: true, signed: "verified", tagger: "Priya Raman", date: now - 144 * H, message: "Vrai 0.9.1\n\nFaster graph layout, signed tags in the sidebar, and a fix for\nsubmodules without a URL." },
      "v0.9.0": { name: "v0.9.0", target: ids.M9, annotated: true, signed: "verified", tagger: "Priya Raman", date: now - 504 * H, message: "Vrai 0.9.0\n\nConflict view, blame by age, and the command palette." },
      "v0.8.0": { name: "v0.8.0", target: ids.M16, annotated: false }
    },
    stashes: [
      { message: "On feature/graph-renderer: halo experiments", branch: "feature/graph-renderer", base: ids.A1, date: now - 3 * H, files: [{ path: "Sources/VraiUI/History/GraphCell.swift", status: "M", hunks: synthHunks("Sources/VraiUI/History/GraphCell.swift", 4, 1, "M:stash0") }] },
      { message: "On main: release notes draft", branch: "main", base: ids.M1, date: now - 74 * H, files: [{ path: "CHANGELOG.md", status: "M", hunks: synthHunks("CHANGELOG.md", 9, 0, "M:stash1") }] },
      { message: "WIP on feature/line-staging: 9a2d6c4 Diff: stage individual lines from the gutter", branch: "feature/line-staging", base: ids.J1, date: now - 5 * D, files: [{ path: "Sources/VraiUI/Diff/DiffGutter.swift", status: "M", hunks: synthHunks("Sources/VraiUI/Diff/DiffGutter.swift", 6, 3, "M:stash2") }, { path: "Sources/VraiUI/Diff/HunkView.swift", status: "M", hunks: synthHunks("Sources/VraiUI/Diff/HunkView.swift", 2, 2, "M:stash2b") }] }
    ].map((s) => ({ ...s, files: s.files.map((f) => ({ ...f, ...statOf(f.hunks) })) })),
    worktrees: [
      { path: "~/Developer/vrai", branch: "feature/graph-renderer", main: true, locked: false, changes: 6 },
      { path: "~/Developer/vrai-release", branch: "release/0.9", main: false, locked: false, changes: 0 },
      { path: "~/Developer/vrai-review", branch: null, detached: ids.J1, main: false, locked: true, lockReason: "Reviewing line staging with Jonas", changes: 0 }
    ],
    submodules: [
      { path: "Vendor/libgit2", url: "https://github.com/libgit2/libgit2.git", branch: "v1.9.1", recorded: "4c7d1f2a9e3b", checkedOut: "8b2e0c6d1f4a", state: "ahead", ahead: 2 },
      { path: "Vendor/cmark-gfm", url: "https://github.com/github/cmark-gfm.git", branch: "master", recorded: "587a12bb5e4d", checkedOut: "587a12bb5e4d", state: "clean", ahead: 0 },
      { path: "Vendor/swift-argument-parser", url: "https://github.com/apple/swift-argument-parser.git", branch: "main", recorded: "41982a3a0b2c", checkedOut: null, state: "uninitialized", ahead: 0 }
    ],
    working: prepareWorking(WORKING()),
    conflicts: [],
    reflog: [
      { sel: 0, id: ids.A1, action: "commit: Graph: draw merge curves with cubic béziers", date: now - 2 * H },
      { sel: 1, id: ids.A2, action: "commit: Graph: keep the HEAD halo above merge rings", date: now - 27 * H },
      { sel: 2, id: ids.A3, action: "rebase (finish): returning to refs/heads/feature/graph-renderer", date: now - 30 * H },
      { sel: 3, id: ids.A3, action: "rebase (pick): Graph: assign lane colors from branch tips", date: now - 30 * H },
      { sel: 4, id: ids.M1, action: "rebase (start): checkout main", date: now - 30 * H },
      { sel: 5, id: hashOf("old-a3"), action: "checkout: moving from main to feature/graph-renderer", date: now - 31 * H },
      { sel: 6, id: ids.M1, action: "pull: Fast-forward", date: now - 47 * H },
      { sel: 7, id: ids.M2, action: "checkout: moving from feature/graph-renderer to main", date: now - 47 * H },
      { sel: 8, id: hashOf("old-a3"), action: "reset: moving to HEAD~1", date: now - 52 * H },
      { sel: 9, id: hashOf("wip-debug"), action: "commit: WIP debug colors", date: now - 53 * H },
      { sel: 10, id: hashOf("old-a3"), action: "commit: Graph: assign lane colors from branch tips", date: now - 54 * H }
    ],
    undo: [
      { id: "u1", label: "Discarded changes to SyncButton.swift", detail: "3 lines, kept as a blob in Undo history", date: now - 28 * H, kind: "discard", snap: null },
      { id: "u2", label: "Rebased feature/graph-renderer onto main", detail: "ORIG_HEAD 7f3a0c1", date: now - 30 * H, kind: "rebase", snap: null },
      { id: "u3", label: "Deleted branch fix/old-sidebar", detail: "Was at 5e0d7b2, merged into main", date: now - 4 * D, kind: "branch", snap: null }
    ],
    state: null,
    pendingFetch: [
      { remote: "origin", branch: "feature/line-staging", commit: { short: "1d7f4b8", subject: "Diff: keep the selection when the file reloads", author: "Jonas Lindqvist", hours: 1, parents: [ids.J1], color: 2, signature: "verified", files: [["Sources/VraiGit/Staging/LineSelection.swift", "M", 14, 3]] } }
    ],
    network: "ok",
    hooks: [
      { name: "pre-commit", path: ".git/hooks/pre-commit", enabled: true, detail: "swift-format lint --strict" },
      { name: "commit-msg", path: ".git/hooks/commit-msg", enabled: true, detail: "Checks the summary is 72 characters or fewer" },
      { name: "pre-push", path: ".git/hooks/pre-push", enabled: false, detail: "swift test --parallel" }
    ],
    config: [
      ["global", "user.name", "Avery Chen"], ["global", "user.email", "avery@vrai.app"], ["global", "gpg.format", "ssh"], ["global", "user.signingkey", "~/.ssh/id_ed25519.pub"],
      ["global", "commit.gpgsign", "true"], ["global", "pull.rebase", "false"], ["global", "init.defaultBranch", "main"], ["global", "rerere.enabled", "true"],
      ["local", "core.hooksPath", ".git/hooks"], ["local", "remote.origin.url", "git@github.com:vrai-app/vrai.git"], ["local", "branch.feature/graph-renderer.remote", "origin"],
      ["local", "branch.feature/graph-renderer.merge", "refs/heads/feature/graph-renderer"], ["local", "fetch.prune", "true"], ["system", "credential.helper", "osxkeychain"]
    ]
  };
}

export function emptyRepo(now) {
  return {
    id: "pocket-notes", name: "pocket-notes", path: "~/Developer/pocket-notes",
    commits: {}, order: [], ids: {},
    head: { type: "branch", name: "main", unborn: true },
    branches: {}, remotes: {}, tags: {}, stashes: [], worktrees: [{ path: "~/Developer/pocket-notes", branch: "main", main: true, locked: false, changes: 4 }], submodules: [],
    working: prepareWorking([
      { path: "README.md", status: "?", hunks: [numberHunk("@@ -0,0 +1,5 @@", ["# Pocket Notes", "", "Plain-text notes that sync through git.", "", "Open the folder in Vrai to see every change."].map((t) => L("+", t)))] },
      { path: ".gitignore", status: "?", hunks: [numberHunk("@@ -0,0 +1,6 @@", [".DS_Store", ".build/", "/Packages", "xcuserdata/", "DerivedData/", ".swiftpm/"].map((t) => L("+", t)))] },
      { path: "Package.swift", status: "?", hunks: [numberHunk("@@ -0,0 +1,10 @@", ["// swift-tools-version: 6.0", "import PackageDescription", "", "let package = Package(", "    name: \"PocketNotes\",", "    platforms: [.macOS(.v15)],", "    targets: [", "        .executableTarget(name: \"PocketNotes\")", "    ]", ")"].map((t) => L("+", t)))] },
      { path: "Sources/PocketNotes/App.swift", status: "?", hunks: [numberHunk("@@ -0,0 +1,9 @@", ["import SwiftUI", "", "@main", "struct PocketNotesApp: App {", "    var body: some Scene {", "        WindowGroup { NotesList() }", "            .defaultSize(width: 720, height: 480)", "    }", "}"].map((t) => L("+", t)))] }
    ]),
    conflicts: [], reflog: [], undo: [], state: null, pendingFetch: [], network: "ok", hooks: [], config: [["global", "user.name", "Avery Chen"], ["global", "user.email", "avery@vrai.app"], ["global", "init.defaultBranch", "main"]]
  };
}

export function recentRepos(now) {
  return [
    { id: "vrai", name: "vrai", path: "~/Developer/vrai", branch: "feature/graph-renderer", branchLane: 1, lane: 0, changes: 6, ahead: 2, behind: 1, opened: now - 20 * 60000 },
    { id: "libgit2", name: "libgit2", path: "~/Developer/vrai/Vendor/libgit2", branch: "v1.9.1", branchLane: 4, lane: 4, changes: 0, ahead: 0, behind: 0, opened: now - 3 * H },
    { id: "pocket-notes", name: "pocket-notes", path: "~/Developer/pocket-notes", branch: "main", branchLane: 0, lane: 2, changes: 4, ahead: 0, behind: 0, opened: now - 26 * H },
    { id: "swift-collections", name: "swift-collections", path: "~/Developer/oss/swift-collections", branch: "main", branchLane: 0, lane: 5, changes: 0, ahead: 0, behind: 12, opened: now - 2 * D },
    { id: "dotfiles", name: "dotfiles", path: "~/dotfiles", branch: "main", branchLane: 0, lane: 6, changes: 2, ahead: 1, behind: 0, opened: now - 9 * D }
  ];
}

export function seedConsole(now, ids) {
  const t = (ms) => { const d = new Date(now - ms); return [d.getHours(), d.getMinutes(), d.getSeconds()].map((x) => String(x).padStart(2, "0")).join(":"); };
  return [
    { id: 1, command: "git fetch --prune origin", source: "vrai", time: t(41 * 60000), duration: 842, exit: 0, output: "From github.com:vrai-app/vrai\n   " + ids.R1.slice(0, 7) + "..." + ids.R1.slice(0, 7) + "  feature/graph-renderer -> origin/feature/graph-renderer\n - [deleted]         (none)     -> origin/spike/old-sidebar" },
    { id: 2, command: "git status --porcelain=v2 --branch -z", source: "vrai", time: t(40 * 60000), duration: 31, exit: 0, output: "# branch.oid " + ids.A1 + "\n# branch.head feature/graph-renderer\n# branch.upstream origin/feature/graph-renderer\n# branch.ab +2 -1" },
    { id: 3, command: "git log --oneline --graph -6", source: "you", time: t(22 * 60000), duration: 38, exit: 0, output: "* " + ids.A1.slice(0, 7) + " Graph: draw merge curves with cubic béziers\n* " + ids.A2.slice(0, 7) + " Graph: keep the HEAD halo above merge rings\n| * " + ids.R1.slice(0, 7) + " Graph: snap nodes to the pixel grid\n|/\n* " + ids.A3.slice(0, 7) + " Graph: assign lane colors from branch tips\n*   " + ids.M1.slice(0, 7) + " Merge branch 'fix/rebase-banner'" }
  ];
}
