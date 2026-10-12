import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const SANDBOX = process.env.VRAI_SANDBOX;
if (!SANDBOX || process.env.HOME !== path.join(SANDBOX, "home") || process.env.GIT_CONFIG_NOSYSTEM !== "1") {
  console.error("large.mjs: run through Scripts/make-fixtures.sh so the sandbox environment is set");
  process.exit(2);
}

const NOW = Number(process.env.VRAI_FIXTURE_NOW || 1791720000);
const COMMITS = Number(process.env.VRAI_LARGE_COMMITS || 200000);
const BRANCHES = 40;
const TAGS = 2000;
const MODULES = 60;
const AREAS = 10;
const FILES_PER_AREA = 50;
const ACTIVE = 12;
const root = path.join(SANDBOX, "fixtures", "large");
const dir = path.join(root, "monorepo");

let seed = 0x5eed1234;
const rand = () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = (list) => list[Math.floor(rand() * list.length)];

const FIRST = ["Avery", "Mira", "Jonas", "Priya", "Tomás", "Hana", "Lena", "Omar", "Ines", "Kenji", "Sofia", "Malik", "Yara", "Felix", "Nora", "Ravi", "Elif", "Mateo", "Anya", "Theo"];
const LAST = ["Chen", "Okafor", "Lindqvist", "Raman", "Ferreira", "Sato", "Novak", "Haddad", "Costa", "Ito", "Rossi", "Mensah", "Nilsen", "Weber", "Kaur", "Silva", "Demir", "Moreau", "Park", "Varga"];
const PEOPLE = Array.from({ length: 40 }, (_, i) => {
  const first = FIRST[i % FIRST.length];
  const last = LAST[(i * 7) % LAST.length];
  return { name: first + " " + last, email: (first + "." + last).toLowerCase().normalize("NFD").replace(/[^a-z.]/g, "") + "@example.com" };
});
const VERBS = ["Fix", "Speed up", "Simplify", "Add", "Remove", "Rename", "Document", "Test", "Refactor", "Cache", "Guard", "Log"];
const NOUNS = ["lane layout", "status parsing", "diff rendering", "patch builder", "ref cache", "fetch progress", "rename detection", "blame lookup", "stash list", "index reads", "pack walk", "config reader", "hook runner", "credential prompt", "window restore"];

const moduleName = (m) => "Module" + String(m).padStart(2, "0");
const areaName = (a) => "Area" + a;
const filePath = (m, a, f) => "Sources/" + moduleName(m) + "/" + areaName(a) + "/File" + String(f).padStart(2, "0") + ".swift";

const files = new Map();
for (let m = 0; m < MODULES; m++) {
  for (let a = 0; a < AREAS; a++) {
    for (let f = 0; f < FILES_PER_AREA; f++) {
      const p = filePath(m, a, f);
      files.set(p, ["import Foundation", "", "struct " + moduleName(m) + areaName(a) + "File" + f + " {", "    var revision = 0", "    var name = \"" + p + "\"", "", "    func run() -> Int {", "        revision + " + f, "    }", "}"]);
    }
  }
}

function edit(lines) {
  const next = lines.slice();
  const rev = Number((next[3].match(/\d+/) || ["0"])[0]) + 1;
  next[3] = "    var revision = " + rev;
  if (next.length < 40 && rand() < 0.5) next.splice(next.length - 1, 0, "    func step" + rev + "() -> Int { revision * " + (rev % 13) + " }");
  else if (next.length >= 40) next.splice(10, 1);
  return next;
}
const blob = (lines) => {
  const data = Buffer.from(lines.join("\n") + "\n");
  return "data " + data.length + "\n" + data.toString() + "\n";
};

fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(dir, { recursive: true });
const run = (args, opts = {}) => {
  const r = spawnSync("git", args, { cwd: dir, encoding: "utf8", maxBuffer: 1 << 30, ...opts });
  if (r.status !== 0) throw new Error("git " + args.join(" ") + "\n" + r.stderr);
  return r.stdout.trim();
};
run(["init", "-q", "-b", "main"]);

const started = Date.now();
const importer = spawn("git", ["fast-import", "--quiet", "--done"], { cwd: dir, stdio: ["pipe", "inherit", "inherit"] });
let buffered = [];
let bufferedBytes = 0;
async function emit(chunk) {
  buffered.push(chunk);
  bufferedBytes += chunk.length;
  if (bufferedBytes > 1 << 20) await flush();
}
async function flush() {
  if (!buffered.length) return;
  const data = buffered.join("");
  buffered = [];
  bufferedBytes = 0;
  if (!importer.stdin.write(data)) await new Promise((r) => importer.stdin.once("drain", r));
}

let mark = 0;
let time = NOW - COMMITS * 900;
const branches = new Map();
const merged = [];
const mainTips = [];
let mainTip = 0;
let topicSeq = 0;

async function commit(ref, from, merge, message, changes, author) {
  mark += 1;
  time += 600 + Math.floor(rand() * 600);
  const who = author || pick(PEOPLE);
  let out = "commit " + ref + "\nmark :" + mark + "\n";
  out += "author " + who.name + " <" + who.email + "> " + time + " +0000\n";
  out += "committer " + who.name + " <" + who.email + "> " + time + " +0000\n";
  const msg = Buffer.from(message + "\n");
  out += "data " + msg.length + "\n" + message + "\n";
  if (from) out += "from :" + from + "\n";
  if (merge) out += "merge :" + merge + "\n";
  for (const [p, lines] of changes) out += "M 100644 inline " + p + "\n" + blob(lines);
  out += "\n";
  await emit(out);
  return mark;
}

const initial = [...files.entries()];
mainTip = await commit("refs/heads/main", 0, 0, "Import the monorepo", initial, PEOPLE[0]);
mainTips.push(mainTip);

const claimed = new Set();
const freeArea = () => {
  for (let tries = 0; tries < 50; tries++) {
    const key = Math.floor(rand() * MODULES) + "/" + Math.floor(rand() * AREAS);
    if (!claimed.has(key)) return key;
  }
  return null;
};

for (let n = 1; n < COMMITS; n++) {
  const roll = rand();
  if (branches.size < ACTIVE && roll < 0.03) {
    const area = freeArea();
    if (area) {
      claimed.add(area);
      topicSeq += 1;
      const [m, a] = area.split("/").map(Number);
      const name = pick(["feature", "fix", "perf", "docs"]) + "/" + moduleName(m).toLowerCase() + "-" + areaName(a).toLowerCase() + "-" + topicSeq;
      branches.set(name, { tip: mainTip, area: [m, a], overlay: new Map(), commits: 0, target: 20 + Math.floor(rand() * 400) });
    }
  }
  const ready = [...branches.entries()].find(([, b]) => b.commits >= b.target);
  if (ready && rand() < 0.2) {
    const [name, b] = ready;
    for (const [p, lines] of b.overlay) files.set(p, lines);
    mainTip = await commit("refs/heads/main", mainTip, b.tip, "Merge branch '" + name + "'", [...b.overlay.entries()]);
    mainTips.push(mainTip);
    branches.delete(name);
    claimed.delete(b.area.join("/"));
    merged.push([name, b.tip]);
    continue;
  }
  const onTopic = branches.size && rand() < 0.45;
  if (onTopic) {
    const [name, b] = pick([...branches.entries()]);
    const [m, a] = b.area;
    const changes = [];
    const count = 1 + Math.floor(rand() * 3);
    for (let i = 0; i < count; i++) {
      const p = filePath(m, a, Math.floor(rand() * FILES_PER_AREA));
      const next = edit(b.overlay.get(p) || files.get(p));
      b.overlay.set(p, next);
      changes.push([p, next]);
    }
    b.tip = await commit("refs/heads/" + name, b.tip, 0, areaName(a) + ": " + pick(VERBS).toLowerCase() + " " + pick(NOUNS), changes);
    b.commits += 1;
  } else {
    const changes = [];
    const count = 1 + Math.floor(rand() * 3);
    for (let i = 0; i < count; i++) {
      let m, a;
      do {
        m = Math.floor(rand() * MODULES);
        a = Math.floor(rand() * AREAS);
      } while (claimed.has(m + "/" + a));
      const p = filePath(m, a, Math.floor(rand() * FILES_PER_AREA));
      const next = edit(files.get(p));
      files.set(p, next);
      changes.push([p, next]);
    }
    mainTip = await commit("refs/heads/main", mainTip, 0, changes[0][0].split("/")[1] + ": " + pick(VERBS).toLowerCase() + " " + pick(NOUNS), changes);
    mainTips.push(mainTip);
  }
}

for (const [name, b] of branches) await emit("reset refs/heads/" + name + "\nfrom :" + b.tip + "\n\n");
const kept = merged.slice(Math.max(0, merged.length - (BRANCHES - 1 - branches.size)));
for (const [name, tip] of kept) await emit("reset refs/heads/" + name + "\nfrom :" + tip + "\n\n");
const step = Math.max(1, Math.floor(mainTips.length / TAGS));
let tagCount = 0;
for (let i = step; i < mainTips.length && tagCount < TAGS; i += step) {
  tagCount += 1;
  const name = "v" + Math.floor(tagCount / 100) + "." + Math.floor((tagCount % 100) / 10) + "." + (tagCount % 10);
  if (tagCount % 10 === 0) {
    const msg = "Release " + name;
    await emit("tag " + name + "\nfrom :" + mainTips[i] + "\ntagger " + PEOPLE[1].name + " <" + PEOPLE[1].email + "> " + (NOW - (mainTips.length - i) * 900) + " +0000\ndata " + Buffer.byteLength(msg) + "\n" + msg + "\n");
  } else {
    await emit("reset refs/tags/" + name + "\nfrom :" + mainTips[i] + "\n\n");
  }
}
const TABLE_LINES = 5000;
const table = ["import Foundation", "", "enum LexerTable {", "    static let entries: [(token: String, weight: Int, next: Int)] = ["];
for (let i = 0; table.length < TABLE_LINES - 2; i++) {
  table.push("        (token: \"" + pick(NOUNS).replace(/ /g, "_") + "_" + i + "\", weight: " + ((i * 7919) % 1000) + ", next: " + ((i * 104729) % TABLE_LINES) + "),");
}
table.push("    ]", "}");
mainTip = await commit("refs/heads/main", mainTip, 0, "Generated: add the lexer tables", [["Sources/Generated/LexerTable.swift", table]], PEOPLE[2]);
await emit("done\n");
await flush();
importer.stdin.end();
const code = await new Promise((r) => importer.on("close", r));
if (code !== 0) throw new Error("git fast-import failed with " + code);

const keep = new Set(["refs/heads/main", ...[...branches.keys()].map((n) => "refs/heads/" + n), ...kept.map(([n]) => "refs/heads/" + n)]);
const stale = run(["for-each-ref", "--format=%(refname)", "refs/heads"]).split("\n").filter((r) => r && !keep.has(r));
if (stale.length) run(["update-ref", "--stdin"], { input: stale.map((r) => "delete " + r + "\n").join("") });
run(["checkout", "-q", "-f", "main"]);
for (let i = 0; i < 12; i++) {
  const p = path.join(dir, filePath(i * 3, i % AREAS, i * 4));
  fs.appendFileSync(p, "// local edit " + i + "\n");
}
for (let i = 0; i < 3; i++) fs.writeFileSync(path.join(dir, "Notes-" + i + ".md"), "# Scratch " + i + "\n");
run(["pack-refs", "--all"]);
run(["commit-graph", "write", "--reachable"]);

const heads = run(["for-each-ref", "--format=%(refname)", "refs/heads"]).split("\n").length;
const tags = run(["for-each-ref", "--format=%(refname)", "refs/tags"]).split("\n").length;
const total = run(["rev-list", "--count", "--all"]);
const tracked = run(["ls-files"]).split("\n").length;
fs.writeFileSync(path.join(root, "manifest.json"), JSON.stringify({ root, repository: dir, commits: Number(total), branches: heads, tags, files: tracked }, null, 2) + "\n");
console.log("fixture large         " + (Date.now() - started) + " ms  " + root + "  (" + total + " commits, " + heads + " branches, " + tags + " tags, " + tracked + " files)");
