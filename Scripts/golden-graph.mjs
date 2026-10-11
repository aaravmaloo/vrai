import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { layoutGraph } from "../prototype_ui/design-system/src/util.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = path.join(root, "Packages/VraiKit/Tests/VraiGitTests/Fixtures/graph");
const SANDBOX = process.env.VRAI_SANDBOX;
if (!SANDBOX || process.env.GIT_CONFIG_NOSYSTEM !== "1") {
  console.error("golden-graph.mjs: source Scripts/sandbox-env.sh first, or run it through Scripts/make-goldens.sh");
  process.exit(2);
}

const git = (dir, args) => {
  const r = spawnSync("git", ["-c", "core.quotepath=false", ...args], { cwd: dir, encoding: "utf8", maxBuffer: 1 << 30 });
  if (r.status !== 0) throw new Error("git " + args.join(" ") + "\n" + r.stderr);
  return r.stdout;
};

function history(dir, scope, limit) {
  const args = ["log", "--topo-order", "-z", "--format=%H%x00%P"];
  if (limit) args.push("--max-count=" + limit);
  const fields = git(dir, [...args, ...scope, "--"]).split("\0");
  if (fields[fields.length - 1] === "") fields.pop();
  const commits = [];
  for (let i = 0; i + 1 < fields.length; i += 2) commits.push({ id: fields[i].replace(/^\n/, ""), parents: fields[i + 1] ? fields[i + 1].split(" ") : [] });
  return commits;
}

function tipColors(dir) {
  const refs = git(dir, ["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads", "refs/remotes"]).trim().split("\n").filter(Boolean);
  const colors = {};
  let next = 1;
  for (const line of refs) {
    const [ref, oid] = line.split(" ");
    const name = ref.replace(/^refs\/(heads|remotes\/[^/]+)\//, "");
    if (ref.endsWith("/HEAD")) continue;
    if (colors[oid] != null) continue;
    colors[oid] = ["main", "master", "trunk"].includes(name) ? 0 : 1 + ((next++ - 1) % 7);
  }
  return colors;
}

const cases = [
  { name: "everyday-all", repo: "everyday/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "everyday-current", repo: "everyday/vrai", scope: ["HEAD"] },
  { name: "conflict-all", repo: "conflict/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "rebase-all", repo: "rebase/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "bisect-all", repo: "bisect/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "edge-all", repo: "edge/edge", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "push-rejected-all", repo: "push-rejected/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "detached-all", repo: "detached/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "auth-all", repo: "auth/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "offline-all", repo: "offline/vrai", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "empty-all", repo: "empty/pocket-notes", scope: ["--branches", "--remotes", "--tags"] },
  { name: "welcome-collections", repo: "welcome/swift-collections", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "welcome-dotfiles", repo: "welcome/dotfiles", scope: ["--branches", "--remotes", "--tags", "HEAD"] },
  { name: "large-first-2000", repo: "large/monorepo", scope: ["--branches", "--remotes", "--tags", "HEAD"], limit: 2000, keepMissing: true }
];

fs.mkdirSync(out, { recursive: true });
for (const c of cases) {
  const dir = path.join(SANDBOX, "fixtures", c.repo);
  if (!fs.existsSync(dir)) { console.log("skip " + c.name + " (no fixture)"); continue; }
  const colors = tipColors(dir);
  const commits = history(dir, c.scope, c.limit).map((x) => (colors[x.id] != null ? { ...x, color: colors[x.id] } : x));
  const result = layoutGraph(commits, { keepMissing: !!c.keepMissing });
  const golden = { name: c.name, keepMissing: !!c.keepMissing, commits, lanes: result.lanes, rows: result.rows };
  fs.writeFileSync(path.join(out, c.name + ".json"), JSON.stringify(golden) + "\n");
  console.log("golden " + c.name.padEnd(22) + commits.length + " commits, " + result.lanes + (result.lanes === 1 ? " lane" : " lanes"));
}
