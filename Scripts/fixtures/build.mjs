import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { seedRepo, emptyRepo, recentRepos, rng, numberHunk } from "./seed.js";
import * as K from "./content.mjs";
import { writeKeys } from "./keys.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const vraiRoot = path.resolve(here, "..", "..");
const SANDBOX = process.env.VRAI_SANDBOX;
const NOW = Number(process.env.VRAI_FIXTURE_NOW || 1791720000);
const AUTH_PORT = Number(process.env.VRAI_AUTH_PORT || 47801);

if (!SANDBOX || process.env.HOME !== path.join(SANDBOX, "home") || process.env.GIT_CONFIG_GLOBAL !== path.join(SANDBOX, "gitconfig") || process.env.GIT_CONFIG_NOSYSTEM !== "1") {
  console.error("build.mjs: run through Scripts/make-fixtures.sh so the sandbox environment is set");
  process.exit(2);
}

const FIXTURES = path.join(SANDBOX, "fixtures");
const PEOPLE = {
  "Avery Chen": "avery@vrai.app",
  "Mira Okafor": "mira@vrai.app",
  "Jonas Lindqvist": "jonas@vrai.app",
  "Priya Raman": "priya@vrai.app",
  "Tomás Ferreira": "tomas@vrai.app",
  "Hana Sato": "hana@vrai.app"
};

function run(cmd, args, cwd, opts = {}) {
  const r = spawnSync(cmd, args, { cwd, env: { ...process.env, ...(opts.env || {}) }, input: opts.input, encoding: opts.binary ? "buffer" : "utf8", maxBuffer: 1 << 30 });
  if (r.error) throw r.error;
  if (r.status !== 0 && !opts.allowFail) {
    throw new Error(cmd + " " + args.join(" ") + "\n  in " + cwd + "\n  exit " + r.status + "\n" + r.stderr);
  }
  if (opts.allowFail) return r;
  return typeof r.stdout === "string" ? r.stdout.replace(/\n$/, "") : r.stdout;
}
const git = (cwd, args, opts) => run("git", args, cwd, opts);
const at = (hours) => Math.round(NOW - hours * 3600);
const ident = (name, time) => {
  const email = PEOPLE[name] || name.toLowerCase().replace(/[^a-z]+/g, ".") + "@example.com";
  const date = time + " +0000";
  return { GIT_AUTHOR_NAME: name, GIT_AUTHOR_EMAIL: email, GIT_AUTHOR_DATE: date, GIT_COMMITTER_NAME: name, GIT_COMMITTER_EMAIL: email, GIT_COMMITTER_DATE: date };
};
const fileURL = (p) => "file://" + p;
const text = (lines) => lines.join("\n") + "\n";

function hunkStarts(h) {
  const m = h.header.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
  return { oldStart: Number(m[1]), newStart: Number(m[2]) };
}
const oldSide = (h) => h.lines.filter((l) => l.t !== "+").map((l) => l.text);
const newSide = (h) => h.lines.filter((l) => l.t !== "-").map((l) => l.text);

function applyExact(base, hunks, label) {
  const out = [];
  let i = 0;
  for (const h of hunks) {
    const { oldStart } = hunkStarts(h);
    const old = oldSide(h);
    const start = old.length === 0 ? oldStart : oldStart - 1;
    if (start < i) throw new Error("overlapping hunks in " + label);
    while (i < start) out.push(base[i++]);
    for (const line of old) {
      if (base[i] !== line) throw new Error("hunk does not apply to " + label + " at line " + (i + 1) + ":\n  expected " + JSON.stringify(line) + "\n  found    " + JSON.stringify(base[i]));
      i++;
    }
    out.push(...newSide(h));
  }
  while (i < base.length) out.push(base[i++]);
  return out;
}

function invert(h) {
  const { oldStart, newStart } = hunkStarts(h);
  return { header: "@@ -" + newStart + " +" + oldStart + " @@", lines: h.lines.map((l) => ({ ...l, t: l.t === "+" ? "-" : l.t === "-" ? "+" : l.t })) };
}

function applyLoose(base, hunks) {
  const out = base.slice();
  let offset = 0;
  for (const h of hunks) {
    const { oldStart } = hunkStarts(h);
    let lead = 0;
    while (lead < h.lines.length && h.lines[lead].t === " ") lead++;
    const dels = h.lines.filter((l) => l.t === "-").length;
    const adds = h.lines.filter((l) => l.t === "+").map((l) => l.text);
    const pos = Math.min(Math.max(0, oldStart - 1 + lead + offset), out.length);
    const removed = Math.min(dels, out.length - pos);
    out.splice(pos, removed, ...adds);
    offset += adds.length - removed;
  }
  return out;
}

function applyBest(base, hunks, label) {
  try {
    return applyExact(base, hunks, label);
  } catch {
    return applyLoose(base, hunks);
  }
}

function baseFromHunks(p, hunks) {
  const pick = rng("base:" + p);
  const filler = () => K.FILLER[Math.floor(pick() * K.FILLER.length)];
  const lines = [];
  for (const h of hunks) {
    const { oldStart } = hunkStarts(h);
    const old = oldSide(h);
    const start = old.length === 0 ? oldStart : oldStart - 1;
    while (lines.length < start) lines.push(filler());
    lines.push(...old);
  }
  for (let i = 0; i < 4; i++) lines.push(filler());
  lines.push("}");
  return lines;
}

class Repo {
  constructor(dir, { bare = false } = {}) {
    this.dir = dir;
    this.bare = bare;
    this.blobs = new Map();
  }
  get gitDir() {
    return this.bare ? this.dir : path.join(this.dir, ".git");
  }
  git(args, opts) {
    return git(this.dir, args, opts);
  }
  blob(content) {
    const buf = Buffer.isBuffer(content) ? content : Buffer.from(content);
    const key = crypto.createHash("sha1").update(buf).digest("hex");
    if (!this.blobs.has(key)) this.blobs.set(key, this.git(["hash-object", "-w", "--stdin"], { input: buf }));
    return this.blobs.get(key);
  }
  tree(snapshot) {
    const env = { GIT_INDEX_FILE: path.join(this.gitDir, "vrai-fixture-index") };
    this.git(["read-tree", "--empty"], { env });
    const rows = [];
    for (const [p, entry] of [...snapshot.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
      if (entry.gitlink) rows.push("160000 commit " + entry.gitlink + "\t" + p);
      else rows.push((entry.mode || "100644") + " blob " + this.blob(entry.binary || text(entry.lines)) + "\t" + p);
    }
    if (rows.length) this.git(["update-index", "--index-info"], { env, input: rows.join("\n") + "\n" });
    const tree = this.git(["write-tree"], { env });
    fs.rmSync(env.GIT_INDEX_FILE, { force: true });
    return tree;
  }
  commit(tree, parents, message, env, signingKey) {
    const args = ["-c", "gpg.format=ssh"];
    if (signingKey) args.push("-c", "user.signingKey=" + signingKey);
    args.push("commit-tree", tree, ...parents.flatMap((p) => ["-p", p]), signingKey ? "-S" : "--no-gpg-sign");
    return this.git(args, { env, input: message.endsWith("\n") ? message : message + "\n" });
  }
}

function buildUpstream(dir, name, branch, subjects, startHours, author) {
  fs.mkdirSync(dir, { recursive: true });
  git(dir, ["init", "-q", "--bare", "-b", branch]);
  const repo = new Repo(dir, { bare: true });
  const snap = new Map([["README.md", { lines: ["# " + name, "", "A vendored dependency of Vrai, served from a local bare repository."] }]]);
  const oids = [];
  let parent = null;
  subjects.forEach((subject, i) => {
    snap.set("CHANGES.md", { lines: ["# Changes", "", ...subjects.slice(0, i + 1).map((s) => "- " + s)] });
    snap.set("src/" + name.replace(/[^a-z0-9]+/gi, "_") + ".c", { lines: ["int " + name.replace(/[^a-z0-9]+/gi, "_") + "_version(void) { return " + (i + 1) + "; }"] });
    const oid = repo.commit(repo.tree(snap), parent ? [parent] : [], subject, ident(author, at(startHours - i * 24)), null);
    oids.push(oid);
    parent = oid;
  });
  repo.git(["update-ref", "refs/heads/" + branch, parent]);
  return oids;
}

function seedModel() {
  const repo = seedRepo(NOW * 1000);
  const keyOf = Object.fromEntries(Object.entries(repo.ids).map(([k, id]) => [id, k]));
  const commits = {};
  for (const id of repo.order) {
    const c = repo.commits[id];
    commits[keyOf[id]] = { ...c, key: keyOf[id], parents: c.parents.map((p) => keyOf[p]), hours: (NOW * 1000 - c.date) / (3600 * 1000) };
  }
  const order = repo.order.map((id) => keyOf[id]).reverse();
  return { repo, commits, order, keyOf };
}

function designs(model) {
  const { commits } = model;
  const a1Lane = commits.A1.files.find((f) => f.path === K.LANE_LAYOUT).hunks;
  const laneA3 = applyExact(K.LANE_LAYOUT_HEAD, a1Lane.map(invert), "LaneLayout A1 reversed");
  const laneM18 = K.laneLayoutBeforeColors(laneA3);
  const working = model.repo.working;
  const rename = working.find((f) => f.status === "R");
  const deleted = working.find((f) => f.status === "D");
  return {
    root: {
      [K.GRAPH_CELL]: K.GRAPH_CELL_BASE,
      [K.PALETTE]: K.PALETTE_ROOT,
      [deleted.path]: oldSide(deleted.hunks[0])
    },
    by: {
      M18: { [K.LANE_LAYOUT]: laneM18 },
      A3: { [K.LANE_LAYOUT]: laneA3, [K.PALETTE]: [...oldSide(rename.hunks[0]), ...K.PALETTE_NOTES] },
      S1: { [K.LANE_LAYOUT]: K.laneLayoutMetal(laneM18), [K.GRAPH_CELL]: K.graphCellMetal(K.GRAPH_CELL_BASE) },
      A1: { [K.LANE_LAYOUT]: K.LANE_LAYOUT_HEAD, [K.GRAPH_CELL]: K.GRAPH_CELL_HEAD }
    }
  };
}

function ancestors(commits, key, memo = new Map()) {
  if (memo.has(key)) return memo.get(key);
  const set = new Set([key]);
  for (const p of commits[key].parents) for (const a of ancestors(commits, p, memo)) set.add(a);
  memo.set(key, set);
  return set;
}

function buildHistory(repo, model, keys, submodules) {
  const { commits, order } = model;
  const design = designs(model);
  const seen = new Set();
  const rootBase = new Map();
  for (const key of order) {
    const c = commits[key];
    if (c.parents.length > 1) continue;
    for (const f of c.files) {
      if (seen.has(f.path)) continue;
      seen.add(f.path);
      if (f.status === "M" || f.status === "D") rootBase.set(f.path, { lines: baseFromHunks(f.path, f.hunks) });
    }
  }
  for (const [p, lines] of Object.entries(design.root)) rootBase.set(p, { lines });
  for (const [p, lines] of Object.entries(K.EXTRA_ROOT_FILES)) rootBase.set(p, { lines });
  rootBase.set("Resources/AppIcon.png", { binary: fs.readFileSync(path.join(vraiRoot, "Scripts/fixtures/assets/icon_128.png")) });
  rootBase.set(".gitmodules", { lines: submodules.flatMap((s) => ["[submodule \"" + s.path + "\"]", "\tpath = " + s.path, "\turl = " + s.url, "\tbranch = " + s.branch]) });
  for (const s of submodules) rootBase.set(s.path, { gitlink: s.recorded });

  const snaps = {};
  const oids = {};
  const memo = new Map();
  for (const key of order) {
    const c = commits[key];
    let snap;
    if (c.parents.length === 0) {
      snap = new Map(rootBase);
    } else if (c.parents.length === 1) {
      snap = new Map(snaps[c.parents[0]]);
    } else {
      const [p1, p2] = c.parents;
      const a1 = ancestors(commits, p1, memo);
      const base = order.slice().reverse().find((k) => a1.has(k) && ancestors(commits, p2, memo).has(k));
      snap = new Map(snaps[p1]);
      const s2 = snaps[p2];
      const sb = snaps[base];
      for (const p of new Set([...s2.keys(), ...sb.keys()])) {
        const v2 = s2.get(p);
        const vb = sb.get(p);
        if (JSON.stringify(v2) === JSON.stringify(vb)) continue;
        if (v2) snap.set(p, v2);
        else snap.delete(p);
      }
    }
    if (c.parents.length < 2) {
      for (const f of c.files) {
        if (f.status === "D") {
          snap.delete(f.path);
        } else if (f.status === "A" || !snap.has(f.path)) {
          snap.set(f.path, { lines: f.hunks.flatMap((h) => h.lines.filter((l) => l.t !== "-").map((l) => l.text)) });
        } else {
          snap.set(f.path, { lines: applyBest(snap.get(f.path).lines, f.hunks, key + ":" + f.path) });
        }
      }
    }
    for (const [p, lines] of Object.entries(design.by[key] || {})) snap.set(p, { lines });
    snaps[key] = snap;
    const message = c.subject + (c.body ? "\n\n" + c.body : "");
    const signingKey = c.signature === "verified" ? keys.byName[c.author] : c.signature === "unknown" ? keys.stranger : null;
    const parents = c.parents.map((p) => oids[p]);
    oids[key] = repo.commit(repo.tree(snap), parents, message, ident(c.author, at(c.hours)), signingKey);
  }
  return { snaps, oids };
}

function writeFile(root, rel, content) {
  const p = path.join(root, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
}

function makeStash(repo, model, built, spec) {
  const baseKey = model.keyOf[spec.base];
  const baseOid = built.oids[baseKey];
  const base = built.snaps[baseKey];
  const work = new Map(base);
  for (const f of spec.files) work.set(f.path, { lines: applyLoose(base.get(f.path)?.lines || [], f.hunks) });
  const branch = spec.branch;
  const short = baseOid.slice(0, 7);
  const subject = model.commits[baseKey].subject;
  const env = ident("Avery Chen", at((NOW * 1000 - spec.date) / 3600000));
  const indexCommit = repo.commit(repo.tree(base), [baseOid], "index on " + branch + ": " + short + " " + subject, env, null);
  const message = spec.message.startsWith("WIP on ") ? "WIP on " + branch + ": " + short + " " + subject : spec.message;
  const stash = repo.commit(repo.tree(work), [baseOid, indexCommit], message, env, null);
  repo.git(["stash", "store", "-m", message, stash], { env });
}

function buildEveryday(root, keys) {
  fs.mkdirSync(root, { recursive: true });
  const remotes = path.join(root, "remotes");
  const model = seedModel();
  const subs = [
    { name: "libgit2", path: "Vendor/libgit2", branch: "v1.9.1", subjects: ["Import libgit2 1.9.0", "Fix a leak in the packfile indexer", "Release 1.9.1", "Speed up status on large trees", "Read commit-graph chains lazily"], recordedIndex: 2, author: "Edward Thomson" },
    { name: "cmark-gfm", path: "Vendor/cmark-gfm", branch: "master", subjects: ["Import cmark-gfm 0.29.0", "Support footnotes in tables", "Release 0.29.0.gfm.13"], recordedIndex: 2, author: "Phill MV" },
    { name: "swift-argument-parser", path: "Vendor/swift-argument-parser", branch: "main", subjects: ["Import swift-argument-parser 1.5.0", "Add completion for zsh", "Release 1.6.1"], recordedIndex: 2, author: "Nate Cook" }
  ];
  for (const s of subs) {
    s.oids = buildUpstream(path.join(remotes, s.name + ".git"), s.name, s.branch, s.subjects, 1400, s.author);
    s.recorded = s.oids[s.recordedIndex];
    s.url = "../" + s.name + ".git";
  }

  const dir = path.join(root, "vrai");
  fs.mkdirSync(dir, { recursive: true });
  git(dir, ["init", "-q", "-b", "main"]);
  const repo = new Repo(dir);
  const built = buildHistory(repo, model, keys, subs);
  const { oids } = built;
  const tip = (fakeId) => oids[model.keyOf[fakeId]];

  for (const [name, b] of Object.entries(model.repo.branches)) repo.git(["update-ref", "refs/heads/" + name, tip(b.tip)]);
  repo.git(["symbolic-ref", "HEAD", "refs/heads/feature/graph-renderer"]);

  for (const t of Object.values(model.repo.tags)) {
    if (!t.annotated) {
      repo.git(["tag", t.name, tip(t.target)]);
      continue;
    }
    const env = ident(t.tagger, at((NOW * 1000 - t.date) / 3600000));
    repo.git(["-c", "gpg.format=ssh", "-c", "user.signingKey=" + keys.byName[t.tagger], "tag", t.signed ? "-s" : "-a", t.name, "-F", "-", tip(t.target)], { env, input: t.message + "\n" });
  }

  const originDir = path.join(remotes, "origin.git");
  const miraDir = path.join(remotes, "mira.git");
  git(remotes, ["init", "-q", "--bare", "-b", "main", originDir]);
  git(remotes, ["init", "-q", "--bare", "-b", "spike/metal-graph", miraDir]);
  const originRefs = Object.entries(model.repo.remotes.origin.branches).map(([b, id]) => tip(id) + ":refs/heads/" + b);
  repo.git(["push", "-q", fileURL(originDir), ...originRefs, "refs/tags/*:refs/tags/*"]);
  const miraRefs = Object.entries(model.repo.remotes.mira.branches).map(([b, id]) => tip(id) + ":refs/heads/" + b);
  repo.git(["push", "-q", fileURL(miraDir), ...miraRefs]);
  repo.git(["remote", "add", "origin", fileURL(originDir)]);
  repo.git(["remote", "add", "mira", fileURL(miraDir)]);
  repo.git(["config", "remote.origin.prune", "true"]);
  repo.git(["fetch", "-q", "origin"]);
  repo.git(["fetch", "-q", "mira"]);
  repo.git(["remote", "set-head", "origin", "main"]);
  repo.git(["remote", "set-head", "mira", "spike/metal-graph"]);
  for (const [name, b] of Object.entries(model.repo.branches)) {
    if (!b.upstream) continue;
    const slash = b.upstream.indexOf("/");
    repo.git(["config", "branch." + name + ".remote", b.upstream.slice(0, slash)]);
    repo.git(["config", "branch." + name + ".merge", "refs/heads/" + b.upstream.slice(slash + 1)]);
  }

  repo.git(["reset", "-q", "--hard"]);
  repo.git(["submodule", "-q", "init", "Vendor/libgit2", "Vendor/cmark-gfm"]);
  repo.git(["submodule", "-q", "update", "Vendor/libgit2", "Vendor/cmark-gfm"]);
  git(path.join(dir, "Vendor/libgit2"), ["checkout", "-q", "--detach", subs[0].oids[4]]);

  const jonasReview = tip(model.repo.ids.J1);
  repo.git(["worktree", "add", "-q", path.join(root, "vrai-release"), "release/0.9"]);
  repo.git(["worktree", "add", "-q", "--detach", path.join(root, "vrai-review"), jonasReview]);
  repo.git(["worktree", "lock", "--reason", "Reviewing line staging with Jonas", path.join(root, "vrai-review")]);

  for (const s of model.repo.stashes.slice().reverse()) makeStash(repo, model, built, s);

  const pending = model.repo.pendingFetch[0];
  const scratch = path.join(root, ".pending-clone");
  git(root, ["clone", "-q", "--no-checkout", fileURL(originDir), scratch]);
  const pendingRepo = new Repo(scratch);
  const lsBase = built.snaps.J1;
  const pendingSnap = new Map(lsBase);
  const lsPath = pending.commit.files[0][0];
  pendingSnap.set(lsPath, { lines: applyLoose(lsBase.get(lsPath).lines, [numberHunk("@@ -20,0 +20,0 @@ struct LineSelection {", [{ t: " ", text: "    var ranges: [Range<Int>] = []" }, ...Array.from({ length: 3 }, () => ({ t: "-", text: "    func reset() { ranges.removeAll() }" })), ...["    func preserve(across reload: DiffReload) {", "        ranges = ranges.compactMap { reload.map($0) }", "    }", "    /// Keeps lines selected when the file changes on disk."].map((t) => ({ t: "+", text: t })), { t: " ", text: "}" }])]) });
  const pendingOid = pendingRepo.commit(pendingRepo.tree(pendingSnap), [oids.J1], pending.commit.subject, ident(pending.commit.author, at(pending.commit.hours)), keys.byName[pending.commit.author]);
  pendingRepo.git(["push", "-q", "origin", pendingOid + ":refs/heads/" + pending.branch]);
  fs.rmSync(scratch, { recursive: true, force: true });

  const hooks = repo.git(["rev-parse", "--git-path", "hooks"]);
  const hooksDir = path.resolve(dir, hooks);
  for (const [name, h] of Object.entries(K.HOOKS)) fs.writeFileSync(path.join(hooksDir, name), h.body, { mode: h.enabled ? 0o755 : 0o644 });

  const head = built.snaps.A1;
  for (const f of model.repo.working) {
    if (f.status === "?") {
      writeFile(dir, f.path, text(newSide(f.hunks[0])));
    } else if (f.status === "D") {
      fs.rmSync(path.join(dir, f.path));
    } else if (f.status === "R") {
      const next = applyExact(head.get(f.oldPath).lines, f.hunks, "working " + f.path);
      repo.git(["mv", f.oldPath, f.path]);
      writeFile(dir, f.path, text(next));
      repo.git(["add", "--", f.path]);
    } else {
      const all = applyExact(head.get(f.path).lines, f.hunks, "working " + f.path);
      const stagedHunks = f.hunks.filter((h) => h.lines.some((l) => l.t !== " " && l.staged));
      const staged = applyExact(head.get(f.path).lines, stagedHunks, "staged " + f.path);
      if (stagedHunks.length) {
        const oid = repo.blob(text(staged));
        repo.git(["update-index", "--cacheinfo", "100644," + oid + "," + f.path]);
      }
      writeFile(dir, f.path, text(all));
    }
  }

  const manifest = {
    root,
    repository: dir,
    remotes: { origin: originDir, mira: miraDir },
    commits: Object.fromEntries(Object.entries(oids)),
    pendingOnOrigin: pendingOid,
    submodules: Object.fromEntries(subs.map((s) => [s.path, { recorded: s.recorded, checkedOut: s.path === "Vendor/libgit2" ? s.oids[4] : s.path === "Vendor/cmark-gfm" ? s.recorded : null }]))
  };
  fs.writeFileSync(path.join(root, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  return { repo, dir, model, built, manifest, originDir };
}

function cleanWorktree(dir) {
  git(dir, ["reset", "-q", "--hard"]);
  git(dir, ["clean", "-q", "-fd"]);
}

const scenarios = {
  everyday(root, keys) {
    return buildEveryday(root, keys);
  },
  "push-rejected"(root, keys) {
    const ctx = buildEveryday(root, keys);
    const scratch = path.join(root, ".second-clone");
    git(root, ["clone", "-q", "--branch", "feature/graph-renderer", fileURL(ctx.originDir), scratch]);
    const shapePath = "Sources/VraiGit/Graph/NodeShape.swift";
    const file = path.join(scratch, shapePath);
    fs.appendFileSync(file, "\nextension NodeShape {\n    static let cachedPaths = NSCache<NSNumber, CGPath>()\n}\n");
    git(scratch, ["add", "--", shapePath]);
    git(scratch, ["-c", "user.signingKey=" + keys.byName["Mira Okafor"], "-c", "gpg.format=ssh", "commit", "-q", "-S", "-m", "Graph: cache node paths per row"], { env: ident("Mira Okafor", at(0.5)) });
    git(scratch, ["push", "-q", "origin", "feature/graph-renderer"]);
    fs.rmSync(scratch, { recursive: true, force: true });
    return ctx;
  },
  conflict(root, keys) {
    const ctx = buildEveryday(root, keys);
    git(ctx.dir, ["add", "-A", "--", ".", ":(exclude)Vendor"]);
    git(ctx.dir, ["commit", "-q", "-m", "Graph: draw the HEAD halo"], { env: ident("Avery Chen", at(0.5)) });
    const r = git(ctx.dir, ["merge", "mira/spike/metal-graph"], { allowFail: true, env: ident("Avery Chen", at(0.25)) });
    if (r.status !== 1 || !/CONFLICT/.test(r.stdout)) throw new Error("conflict scenario: expected a conflicted merge\n" + r.stdout + r.stderr);
    return ctx;
  },
  rebase(root, keys) {
    const ctx = buildEveryday(root, keys);
    const env = { ...ident("Avery Chen", at(0.25)), GIT_SEQUENCE_EDITOR: "sed -i '' -e '2s/^pick /edit /'", GIT_EDITOR: "true" };
    const r = git(ctx.dir, ["rebase", "-i", "--autostash", "origin/main"], { env, allowFail: true });
    if (r.status !== 0 || !fs.existsSync(path.join(ctx.dir, ".git/rebase-merge/amend"))) throw new Error("rebase scenario: expected a stop for edit\n" + r.stdout + r.stderr);
    return ctx;
  },
  detached(root, keys) {
    const ctx = buildEveryday(root, keys);
    cleanWorktree(ctx.dir);
    git(ctx.dir, ["switch", "-q", "--detach", "v0.9.1"]);
    return ctx;
  },
  bisect(root, keys) {
    const ctx = buildEveryday(root, keys);
    cleanWorktree(ctx.dir);
    git(ctx.dir, ["bisect", "start", "feature/graph-renderer", "v0.9.0"]);
    return ctx;
  },
  auth(root, keys) {
    const ctx = buildEveryday(root, keys);
    const url = "http://127.0.0.1:" + AUTH_PORT + "/vrai.git";
    git(ctx.dir, ["remote", "set-url", "origin", url]);
    git(ctx.dir, ["credential", "approve"], { input: "protocol=http\nhost=127.0.0.1:" + AUTH_PORT + "\nusername=avery\npassword=vrai_expired_token\n\n" });
    return ctx;
  },
  offline(root, keys) {
    const ctx = buildEveryday(root, keys);
    git(ctx.dir, ["remote", "set-url", "origin", "https://127.0.0.1:9/vrai.git"]);
    return ctx;
  },
  edge(root) {
    const dir = path.join(root, "edge");
    fs.mkdirSync(dir, { recursive: true });
    git(dir, ["init", "-q", "-b", "main"]);
    const commit = (message, hours) => git(dir, ["commit", "-q", "--no-gpg-sign", "-m", message], { env: ident("Avery Chen", at(hours)) });
    writeFile(dir, "a b.txt", "one\ntwo\nthree\nfour\nfive\nsix\n");
    writeFile(dir, "Résumé.md", "# Résumé\n\nNaïve café notes.\n");
    writeFile(dir, "quote\"d.txt", "quoted name\n");
    writeFile(dir, "script.sh", "#!/bin/sh\necho hi\n");
    writeFile(dir, "link-target.txt", "plain file that becomes a symlink\n");
    writeFile(dir, "conflict.txt", "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\n");
    writeFile(dir, "deleted-by-them.txt", "keep me\n");
    fs.writeFileSync(path.join(dir, "image.png"), fs.readFileSync(path.join(vraiRoot, "Scripts/fixtures/assets/icon_16.png")));
    git(dir, ["add", "-A"]);
    commit("Add the edge cases", 30);
    git(dir, ["switch", "-q", "-c", "other"]);
    writeFile(dir, "conflict.txt", "line 1\nline 2 from other\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8 from other\nline 9\n");
    fs.rmSync(path.join(dir, "deleted-by-them.txt"));
    writeFile(dir, "both-added.txt", "added on other\n");
    git(dir, ["add", "-A"]);
    commit("Change things on other", 20);
    git(dir, ["switch", "-q", "main"]);
    writeFile(dir, "conflict.txt", "line 1\nline 2 from main\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8 from main\nline 9\n");
    writeFile(dir, "deleted-by-them.txt", "keep me, changed on main\n");
    writeFile(dir, "both-added.txt", "added on main\n");
    git(dir, ["add", "-A"]);
    commit("Change things on main", 10);
    const merge = git(dir, ["-c", "merge.conflictStyle=diff3", "merge", "other"], { allowFail: true, env: ident("Avery Chen", at(5)) });
    if (merge.status !== 1) throw new Error("edge fixture: expected conflicts\n" + merge.stdout + merge.stderr);
    git(dir, ["mv", "a b.txt", "c d.txt"]);
    fs.appendFileSync(path.join(dir, "c d.txt"), "seven\n");
    fs.chmodSync(path.join(dir, "script.sh"), 0o755);
    fs.rmSync(path.join(dir, "link-target.txt"));
    fs.symlinkSync("Résumé.md", path.join(dir, "link-target.txt"));
    fs.writeFileSync(path.join(dir, "image.png"), fs.readFileSync(path.join(vraiRoot, "Scripts/fixtures/assets/icon_32.png")));
    writeFile(dir, "staged new.txt", "staged\n");
    git(dir, ["add", "--", "staged new.txt"]);
    writeFile(dir, "staged new.txt", "staged\nthen changed\n");
    writeFile(dir, "new file ünicode.txt", "untracked\n");
    writeFile(dir, "Résumé.md", "# Résumé\n\nNaïve café notes, edited.\n");
    fs.writeFileSync(path.join(root, "manifest.json"), JSON.stringify({ root, repository: dir }, null, 2) + "\n");
    return { dir };
  },
  empty(root) {
    const dir = path.join(root, "pocket-notes");
    fs.mkdirSync(dir, { recursive: true });
    git(dir, ["init", "-q", "--initial-branch=main"]);
    for (const f of emptyRepo(NOW * 1000).working) writeFile(dir, f.path, text(newSide(f.hunks[0])));
    fs.writeFileSync(path.join(root, "manifest.json"), JSON.stringify({ root, repository: dir }, null, 2) + "\n");
    return { dir };
  },
  welcome(root) {
    fs.mkdirSync(root, { recursive: true });
    const collections = path.join(root, "swift-collections");
    const collectionsRemote = path.join(root, "remotes", "swift-collections.git");
    const subjects = Array.from({ length: 15 }, (_, i) => ["Add BitSet.isDisjoint", "Speed up Deque.append", "Document OrderedSet", "Fix TreeDictionary equality", "Add Heap.popMax"][i % 5] + (i >= 5 ? " (" + (i + 1) + ")" : ""));
    const oids = buildUpstream(collectionsRemote, "swift-collections", "main", subjects, 900, "Karoy Lorentey");
    git(root, ["clone", "-q", fileURL(collectionsRemote), collections]);
    git(collections, ["reset", "-q", "--hard", oids[2]]);
    const dotfiles = path.join(root, "dotfiles");
    const dotRemote = path.join(root, "remotes", "dotfiles.git");
    buildUpstream(dotRemote, "dotfiles", "main", ["Add zshrc", "Use starship for the prompt"], 400, "Avery Chen");
    git(root, ["clone", "-q", fileURL(dotRemote), dotfiles]);
    writeFile(dotfiles, ".zshrc", "export EDITOR=nvim\nalias gs='git status'\n");
    git(dotfiles, ["add", ".zshrc"]);
    git(dotfiles, ["commit", "-q", "-m", "Add zshrc aliases"], { env: ident("Avery Chen", at(9 * 24)) });
    writeFile(dotfiles, ".zshrc", "export EDITOR=nvim\nalias gs='git status'\nalias gl='git log --oneline'\n");
    writeFile(dotfiles, ".config/ghostty/config", "font-family = SF Mono\n");
    const now = NOW * 1000;
    const paths = {
      vrai: path.join(FIXTURES, "everyday", "vrai"),
      libgit2: path.join(FIXTURES, "everyday", "vrai", "Vendor", "libgit2"),
      "pocket-notes": path.join(FIXTURES, "empty", "pocket-notes"),
      "swift-collections": collections,
      dotfiles
    };
    const recents = {
      version: 1,
      repositories: recentRepos(now).map((r) => ({ path: paths[r.id], name: r.name, lastOpened: Math.round(r.opened / 1000) }))
    };
    fs.writeFileSync(path.join(root, "recents.json"), JSON.stringify(recents, null, 2) + "\n");
    fs.writeFileSync(path.join(SANDBOX, "recents.json"), JSON.stringify(recents, null, 2) + "\n");
    return { dir: root };
  }
};

function writeSandboxConfig(keys) {
  const config = [
    "[user]",
    "\tname = Avery Chen",
    "\temail = avery@vrai.app",
    "\tsigningkey = " + keys.team,
    "[gpg]",
    "\tformat = ssh",
    "[gpg \"ssh\"]",
    "\tallowedSignersFile = " + keys.allowedSigners,
    "[commit]",
    "\tgpgsign = true",
    "[pull]",
    "\trebase = false",
    "[init]",
    "\tdefaultBranch = main",
    "[rerere]",
    "\tenabled = true",
    "[protocol \"file\"]",
    "\tallow = always",
    "[credential]",
    "\thelper = store --file=" + path.join(SANDBOX, "git-credentials"),
    "[advice]",
    "\tdetachedHead = false",
    ""
  ].join("\n");
  fs.writeFileSync(path.join(SANDBOX, "gitconfig"), config);
  if (!fs.existsSync(path.join(SANDBOX, "git-credentials"))) fs.writeFileSync(path.join(SANDBOX, "git-credentials"), "", { mode: 0o600 });
}

const wanted = process.argv.slice(2).filter((a) => !a.startsWith("-"));
const keys = writeKeys(path.join(SANDBOX, "home", ".ssh"), PEOPLE);
writeSandboxConfig(keys);
fs.mkdirSync(FIXTURES, { recursive: true });
const order = ["everyday", "push-rejected", "conflict", "rebase", "detached", "bisect", "auth", "offline", "empty", "edge", "welcome"];
for (const name of order) {
  if (wanted.length && !wanted.includes(name)) continue;
  const root = path.join(FIXTURES, name);
  fs.rmSync(root, { recursive: true, force: true });
  const started = Date.now();
  scenarios[name](root, keys);
  console.log("fixture " + name.padEnd(14) + (Date.now() - started) + " ms  " + root);
}
