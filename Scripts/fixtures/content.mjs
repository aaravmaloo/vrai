export const LANE_LAYOUT = "Sources/VraiGit/Graph/LaneLayout.swift";
export const GRAPH_CELL = "Sources/VraiUI/History/GraphCell.swift";
export const PALETTE = "Sources/VraiUI/History/Palette.swift";
export const ASSET_CONTENTS = "Resources/Graph.xcassets/Contents.json";

export const LANE_LAYOUT_HEAD = [
  "import CoreGraphics",
  "import SwiftUI",
  "",
  "/// Places each commit of the graph in a lane and draws the lines between them.",
  "/// Lanes are transit lines: a branch keeps its lane and its color from",
  "/// its tip down, merges are interchanges and HEAD wears a halo.",
  "///",
  "/// The layout is incremental: each page of history extends the lanes of",
  "/// the page before it, so scrolling never lays out the whole graph again.",
  "///",
  "struct LaneLayout {",
  "    var laneWidth: CGFloat = 14",
  "    var nodeSize: CGFloat = 9",
  "",
  "    func x(for lane: Int) -> CGFloat {",
  "        CGFloat(lane) * laneWidth + laneWidth / 2",
  "    }",
  "",
  "    func point(for lane: Lane, y: CGFloat) -> CGPoint {",
  "        CGPoint(x: x(for: lane.index), y: y)",
  "    }",
  "",
  "    func color(for row: GraphRow, at lane: Int) -> Int {",
  "        row.tipColor[lane] ?? colors.next(for: lane)",
  "    }",
  "",
  "    func width(for lanes: Int) -> CGFloat {",
  "        CGFloat(lanes) * laneWidth",
  "    }",
  "",
  "    func lanes(in row: GraphRow) -> Range<Int> {",
  "        0..<max(row.lane + 1, row.top.count, row.bottom.count)",
  "    }",
  "",
  "    func isVisible(_ segment: GraphRow.Segment, in rect: CGRect) -> Bool {",
  "        let from = x(for: segment.from)",
  "        let to = x(for: segment.to)",
  "        return max(from, to) >= rect.minX && min(from, to) <= rect.maxX",
  "    }",
  "",
  "    /// Joins two lanes across one row with a curve through the row's middle.",
  "    func path(from a: Lane, to b: Lane, in row: CGRect) -> Path {",
  "        var path = Path()",
  "        path.move(to: point(for: a, y: row.minY))",
  "        let mid = row.midY",
  "        path.addCurve(",
  "            to: point(for: b, y: row.maxY),",
  "            control1: point(for: a, y: mid),",
  "            control2: point(for: b, y: mid)",
  "        )",
  "        return path",
  "    }",
  "",
  "    /// Lanes keep their color from the branch tip down.",
  "    var colors: [LaneColor] = LaneColor.palette",
  "",
  "    func elbow(from a: Lane, to b: Lane, in row: CGRect) -> Path {",
  "        var path = Path()",
  "        let start = point(for: a, y: row.minY)",
  "        let end = point(for: b, y: row.maxY)",
  "        path.move(to: start)",
  "        path.addLine(to: CGPoint(x: start.x, y: row.midY))",
  "        path.addLine(to: end)",
  "        return path",
  "    }",
  "",
  "    func node(at lane: Int, in rect: CGRect, merge: Bool = false) -> Path {",
  "        let size = merge ? nodeSize - 0.5 : nodeSize",
  "        return Path(ellipseIn: CGRect(x: x(for: lane) - size / 2, y: rect.midY - size / 2, width: size, height: size))",
  "    }",
  "}",
  "",
  "extension LaneLayout {",
  "    struct Lane: Hashable {",
  "        var index: Int",
  "        var color: Int",
  "    }",
  "",
  "    struct LaneColor: Hashable {",
  "        var index: Int",
  "",
  "        static let palette = (0..<8).map(LaneColor.init(index:))",
  "",
  "        func next(for lane: Int) -> Int {",
  "            (index + lane) % LaneColor.palette.count",
  "        }",
  "    }",
  "",
  "    static let standard = LaneLayout()",
  "    static let compact = LaneLayout(laneWidth: 12, nodeSize: 8)",
  "    static let comfortable = LaneLayout(laneWidth: 16, nodeSize: 10)",
  "",
  "    static let laneWidth: CGFloat = 14",
  "    static let nodeSize: CGFloat = 9",
  "    static let headHalo: CGFloat = 16",
  "}"
];

export function laneLayoutBeforeColors(a3) {
  const start = a3.indexOf("    func color(for row: GraphRow, at lane: Int) -> Int {");
  const end = a3.indexOf("    /// Joins two lanes across one row with a curve through the row's middle.");
  return [...a3.slice(0, start), ...a3.slice(end)];
}

export function laneLayoutMetal(base) {
  const out = [];
  for (const line of base) {
    if (line === "import CoreGraphics") {
      out.push(line, "import Metal");
    } else if (line === "    var nodeSize: CGFloat = 9") {
      out.push(line, "    var instanceBuffer: MTLBuffer?", "    var usesMetal: Bool { instanceBuffer != nil }");
    } else if (line === "        CGFloat(lane) * laneWidth + laneWidth / 2") {
      out.push("        (CGFloat(lane) + 0.5) * laneWidth");
    } else if (line === "    func node(at lane: Int, in rect: CGRect, merge: Bool = false) -> Path {") {
      out.push("    func node(at lane: Int, in rect: CGRect, merge: Bool = false, instanced: Bool = false) -> Path {");
    } else {
      out.push(line);
    }
  }
  return out;
}

export const GRAPH_CELL_BASE = [
  "import SwiftUI",
  "",
  "/// One row of the commit graph: the lanes passing through it and the",
  "/// node for the row's own commit.",
  "struct GraphCell: View {",
  "    let row: GraphRow",
  "    let lanes: Int",
  "    var height: CGFloat = 28",
  "",
  "    var width: CGFloat { CGFloat(lanes) * Vrai.Size.lane + 12 }",
  "",
  "    var body: some View {",
  "        Canvas { context, size in",
  "            for segment in row.segments {",
  "                context.stroke(layout.line(segment, in: size), with: .color(segment.color))",
  "            }",
  "            context.fill(layout.node(at: row.lane, in: size), with: .color(Color.Vrai.lane(row.color)))",
  "        }",
  "        .frame(width: width, height: height)",
  "        .accessibilityHidden(true)",
  "    }",
  "",
  "    private var layout: LaneLayout { LaneLayout(laneWidth: Vrai.Size.lane, nodeSize: Vrai.Size.node) }",
  "}",
  "",
  "extension GraphRow {",
  "    static func preview(merge: Bool = false) -> GraphRow {",
  "        GraphRow(lane: 0, color: 0, top: [], bottom: [], isMerge: merge)",
  "    }",
  "}"
];

export function graphCellMetal(base) {
  const start = base.indexOf("        Canvas { context, size in");
  const end = base.indexOf("        .frame(width: width, height: height)");
  return [...base.slice(0, start), "        MetalGraphView(row: row, lanes: lanes)", ...base.slice(end)];
}

export const GRAPH_CELL_HEAD = [
  "import SwiftUI",
  "import VraiGit",
  "",
  "/// One row of the commit graph: the lanes passing through it, the",
  "/// segments that join them and the node for the row's own commit.",
  "struct GraphCell: View {",
  "    let row: GraphRow",
  "    let lanes: Int",
  "    var height: CGFloat = Vrai.Size.row",
  "    var isHead = false",
  "",
  "    @Environment(\\.accessibilityReduceMotion) private var reduceMotion",
  "",
  "    init(row: GraphRow, lanes: Int, height: CGFloat = Vrai.Size.row, isHead: Bool = false) {",
  "        self.row = row",
  "        self.lanes = lanes",
  "        self.height = height",
  "        self.isHead = isHead",
  "    }",
  "",
  "    var width: CGFloat { CGFloat(lanes) * Vrai.Size.lane + 12 }",
  "    var isEmpty: Bool { lanes == 0 }",
  "",
  "    var body: some View {",
  "        Canvas { context, size in",
  "            let rect = CGRect(origin: .zero, size: size)",
  "            for segment in row.segments {",
  "                context.stroke(layout.path(from: segment.from, to: segment.to, in: rect), with: .color(Color.Vrai.lane(segment.color)))",
  "            }",
  "            context.fill(layout.node(at: row.lane, in: rect), with: .color(Color.Vrai.lane(row.color)))",
  "        }",
  "        .frame(width: CGFloat(lanes) * Vrai.Size.lane + 12, height: height)",
  "        .accessibilityHidden(true)",
  "    }",
  "",
  "    func segments(crossing lane: Int) -> [GraphRow.Segment] {",
  "        row.segments.filter { $0.from == lane || $0.to == lane }",
  "    }",
  "",
  "    func hasNode(at lane: Int) -> Bool {",
  "        row.lane == lane",
  "    }",
  "",
  "    var accessibilityText: Text {",
  "        Text(row.isMerge ? \"Merge commit\" : \"Commit\")",
  "    }",
  "",
  "    var haloAnimation: Animation { reduceMotion ? .Vrai.standardFast : .Vrai.springGraph }",
  "    var showsHalo: Bool { isHead && !isEmpty }",
  "",
  "    private var layout: LaneLayout { LaneLayout(laneWidth: Vrai.Size.lane, nodeSize: Vrai.Size.node) }",
  "}",
  "",
  "extension GraphRow {",
  "    static func preview(merge: Bool = false) -> GraphRow {",
  "        GraphRow(lane: 0, color: 0, top: [], bottom: [], isMerge: merge)",
  "    }",
  "}"
];

export const PALETTE_NOTES = [
  "",
  "/// Colors repeat after eight lanes. The graph, branch pills and the",
  "/// sidebar dot all read the color from here, so a branch looks the",
  "/// same everywhere it appears: identity, never status.",
  "/// Keep the order stable; people learn which color is which branch."
];

export const PALETTE_ROOT = [
  "import SwiftUI",
  "",
  "/// Graph palette, in lane order.",
  "enum Palette {",
  "    static let names = [\"blue\", \"orange\", \"green\", \"pink\", \"cyan\", \"yellow\", \"purple\", \"red\"]",
  "}",
  ...PALETTE_NOTES
];

export const FILLER = [
  "    private let git: GitProcess",
  "    init(git: GitProcess) { self.git = git }",
  "    func refresh() async throws {",
  "        let output = try await git.run([\"status\", \"--porcelain=v2\", \"-z\"])",
  "    }",
  "        guard let repository else { return }",
  "    var body: some View {",
  "        HStack(spacing: Vrai.Space.s8) {",
  "            Text(branch.name).font(.Vrai.body)",
  "        }",
  "        .foregroundStyle(Color.Vrai.textSecondary)",
  "    static let defaultLimit = 2_000",
  "        for (index, entry) in entries.enumerated() where entry.isVisible {",
  "            rows.append(Row(index: index, entry: entry))",
  "        return rows",
  "    func cancel() { task?.cancel(); task = nil }",
  "        defer { isBusy = false }",
  "        isBusy = true",
  "    private var task: Task<Void, Never>?",
  "        progress.completedUnitCount = Int64(received)",
  "    func select(_ id: Commit.ID) { selection = [id] }",
  "",
  "}"
];

export const EXTRA_ROOT_FILES = {
  "Docs/Design notes/Lane colors.md": [
    "# Lane colors",
    "",
    "Lane 1 is the main line. A branch keeps its lane color for its whole life,",
    "in the graph, in its pill and in the sidebar."
  ],
  "Docs/Résumé des branches.md": [
    "# Résumé des branches",
    "",
    "Notes in French, so paths with accents stay covered."
  ]
};

export const HOOKS = {
  "pre-commit": { enabled: true, body: "#!/bin/sh\nif [ -f \"$(git rev-parse --git-dir)/vrai-fail-pre-commit\" ]; then\n  echo \"swift-format lint --strict: 2 problems\" >&2\n  echo \"Sources/VraiUI/History/GraphCell.swift:31:1: Line is too long\" >&2\n  exit 1\nfi\nexit 0\n" },
  "commit-msg": { enabled: true, body: "#!/bin/sh\nsubject=\"$(head -n 1 \"$1\")\"\nif [ \"${#subject}\" -gt 72 ]; then\n  echo \"The summary is ${#subject} characters. Keep it to 72 or fewer.\" >&2\n  exit 1\nfi\nexit 0\n" },
  "pre-push": { enabled: false, body: "#!/bin/sh\nswift test --parallel\n" }
};
