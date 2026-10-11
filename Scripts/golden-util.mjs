import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { n, ago, highlight, parseCommand, langOf, fileIcon, splitPath } from "../prototype_ui/design-system/src/util.js";

if (process.env.TZ !== "UTC") {
  console.error("golden-util.mjs: run with TZ=UTC so dates match the Swift tests");
  process.exit(2);
}
const tokenizeSource = fs.readFileSync(new URL("../prototype_ui/design-system/src/actions.jsx", import.meta.url), "utf8");
const body = tokenizeSource.slice(tokenizeSource.indexOf("export function tokenizeCommand"), tokenizeSource.indexOf("export function CommandPreview"));
const tokenizeCommand = new Function(body.replace("export function tokenizeCommand", "return function tokenizeCommand"))();

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const NOW = 1791720000 * 1000;

const plural = [[0, "file"], [1, "file"], [2, "file"], [1234, "commit"], [1, "branch"], [3, "branch"], [2, "fix"], [5, "patch"], [4, "entry"], [2, "day"], [7, "key"], [2, "status"], [1000000, "line"], [3, "person", "people"], [12, "change"]];
const seconds = [0, 10, 44, 45, 60, 89, 90, 1799, 3540, 3599, 3600, 5399, 5400, 7200, 86399, 86400, 129600, 172800, 6 * 86400, 7 * 86400 - 1, 7 * 86400, 30 * 86400, 200 * 86400, 284 * 86400, 400 * 86400, 1000 * 86400, -30];
const commands = [
  "git push --force origin main", "git push -f", "git push --force-with-lease origin main", "git push origin --delete feature/x", "git push",
  "git reset --hard HEAD~1", "git reset --soft HEAD~1", "git reset HEAD~2", "git reset -- Sources/App.swift", "git reset", "git reset HEAD -- a/b.txt",
  "git clean -fd", "git clean -n", "git branch -D topic", "git branch -d --force topic", "git branch -d topic", "git filter-branch --tree-filter x",
  "git checkout -- file.txt", "git checkout -f main", "git checkout main", "git restore file.txt", "git restore --staged file.txt", "git restore -S file.txt",
  "git stash drop", "git stash clear", "git stash pop", "git worktree remove --force ../wt", "git worktree remove ../wt", "git tag -d v1",
  "git rebase main", "git rebase --continue", "git rebase --abort", "git history reword HEAD", "git replay --onto main topic", "git commit --amend",
  "git commit --fixup=amend:HEAD", "git commit --fixup=HEAD", "git commit -m \"Fix the thing\"", "$ git log --oneline", "  git status  ", "status", "",
  "git log; rm -rf x", "git commit -m 'single quoted message' --no-verify", "git cherry-pick --quit", "git merge --no-ff -m \"Merge it\" topic"
];
const tokenize = ["git push --force-with-lease origin main", "git commit -m \"Fix the thing\" --signoff", "git log --format='%H %s' -n 5", "git  switch   main", "-c core.quotepath=false status", "git"];
const highlightCases = [
  ["swift", "    func path(from a: Lane, to b: Lane, in row: CGRect) -> Path {"],
  ["swift", "        let mid = row.midY // the middle"],
  ["swift", "    @Environment(\\.accessibilityReduceMotion) private var reduceMotion"],
  ["swift", "        Text(\"Push \\(ahead) commits\").font(.Vrai.body)"],
  ["swift", "    static let laneWidth: CGFloat = 14.5_0"],
  ["swift", "let a1 = 1abc + 2. + 3.14 + x2"],
  ["swift", "/* block */ let s = 'x' + `y` /* open"],
  ["swift", "#if DEBUG"],
  ["swift", "let café = \"béziers\" // ünïcode"],
  ["swift", "let s = \"unterminated"],
  ["swift", "a\nb // comment after newline"],
  ["js", "export function n(count, word) { return count + \" \" + word; }"],
  ["js", "const x = await fetch(url) // go"],
  ["ts", "type A = { a: number }"],
  ["yaml", "name: vrai # comment"],
  ["sh", "echo hi # say hi"],
  ["md", "# Title with `code`"],
  ["text", "plain text"],
  ["swift", ""],
  ["swift", "\t\tspaces and tabs  "]
];
const paths = ["Sources/VraiGit/Graph/LaneLayout.swift", "README.md", "Package.json", "image.PNG", "script.sh", "Makefile", "a/b/c.yml", "notes.txt", "x.tsx", "noext"];

const golden = {
  now: NOW / 1000,
  plural: plural.map(([c, w, p]) => ({ count: c, word: w, plural: p ?? null, out: n(c, w, p) })),
  ago: seconds.map((s) => ({ seconds: s, out: ago(NOW - s * 1000, NOW) })),
  parseCommand: commands.map((c) => ({ input: c, out: parseCommand(c) })),
  tokenize: tokenize.map((c) => ({ input: c, out: tokenizeCommand(c).map((t) => ({ t: t.t, k: t.k ?? null })) })),
  highlight: highlightCases.map(([lang, text]) => ({ lang, text, out: highlight(text, lang).map((t) => ({ t: t.t, k: t.k ?? null })) })),
  paths: paths.map((p) => ({ path: p, lang: langOf(p), icon: fileIcon(p), split: splitPath(p) }))
};
const target = path.join(root, "Packages/VraiKit/Tests/VraiCoreTests/Fixtures/util-goldens.json");
fs.writeFileSync(target, JSON.stringify(golden, null, 1) + "\n");
console.log("golden util: " + Object.entries(golden).filter(([k]) => k !== "now").map(([k, v]) => k + " " + v.length).join(", "));
