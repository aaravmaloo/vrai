import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const prototypeHTML = path.join(root, "prototype_ui/app/dist/local.html");

export const SCENARIOS = ["everyday", "push-rejected", "conflict", "rebase", "detached", "bisect", "auth", "offline", "loading", "empty", "welcome"];
const KEEP_VIEW = new Set(["conflict", "empty", "welcome"]);
const SETTLE = { loading: 450, "push-rejected": 2200 };
export const VARIANTS = {
  light: { theme: "light", width: 1280, height: 800 },
  dark: { theme: "dark", width: 1280, height: 800 },
  w700: { theme: "light", width: 700, height: 800 },
  w460: { theme: "light", width: 460, height: 800 }
};

const NARROW_VIEWPORT = 760;
const DESKTOP_X = 64;
const DESKTOP_Y = 72;

function usage() {
  console.log([
    "usage: node Scripts/contact-sheet.mjs [capture|sheet|all] [options] [scenario...]",
    "  capture   render the prototype for each scenario and variant into --prototype",
    "  sheet     put prototype and native screenshots side by side into --out",
    "  all       capture, then sheet (the default)",
    "options:",
    "  --native <dir>     native screenshots (default build/screens)",
    "  --prototype <dir>  prototype screenshots (default build/prototype)",
    "  --out <dir>        contact sheets (default build/contact)",
    "  --variant <name>   only this variant (light, dark, w700, w460); repeatable",
    "  --crop x,y,w,h     also write a zoomed sheet of this region (in window points)",
    "  --prefix <name>    file name prefix: scenario (default) or history"
  ].join("\n"));
}

function parseArgs(argv) {
  const options = { mode: "all", native: path.join(root, "build/screens"), prototype: path.join(root, "build/prototype"), out: path.join(root, "build/contact"), scenarios: [], variants: [], crop: null, prefix: "scenario" };
  const rest = [...argv];
  if (rest[0] && ["capture", "sheet", "all"].includes(rest[0])) options.mode = rest.shift();
  while (rest.length) {
    const arg = rest.shift();
    if (arg === "--native") options.native = path.resolve(rest.shift());
    else if (arg === "--prototype") options.prototype = path.resolve(rest.shift());
    else if (arg === "--out") options.out = path.resolve(rest.shift());
    else if (arg === "--variant") options.variants.push(rest.shift());
    else if (arg === "--crop") options.crop = rest.shift().split(",").map(Number);
    else if (arg === "--prefix") options.prefix = rest.shift();
    else if (arg === "-h" || arg === "--help") { usage(); process.exit(0); }
    else options.scenarios.push(arg);
  }
  if (!options.scenarios.length) options.scenarios = SCENARIOS;
  if (!options.variants.length) options.variants = Object.keys(VARIANTS);
  return options;
}

function findChrome() {
  if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN;
  const caches = [process.env.PLAYWRIGHT_BROWSERS_PATH, path.join(os.homedir(), "Library/Caches/ms-playwright")].filter((p) => p && fs.existsSync(p));
  for (const cache of caches) {
    const dirs = fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort((a, b) => Number(b.split("-").pop()) - Number(a.split("-").pop()));
    for (const dir of dirs) {
      for (const sub of fs.readdirSync(path.join(cache, dir))) {
        const bin = path.join(cache, dir, sub, "chrome-headless-shell");
        if (fs.existsSync(bin)) return bin;
      }
    }
  }
  for (const bin of ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Chromium.app/Contents/MacOS/Chromium"]) {
    if (fs.existsSync(bin)) return bin;
  }
  throw new Error("No Chrome found. Set CHROME_BIN, or run: npx playwright install chromium-headless-shell");
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function openBrowser() {
  const bin = findChrome();
  const port = 9300 + Math.floor(Math.random() * 500);
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), "vrai-contact-"));
  const args = [...(/headless/i.test(path.basename(bin)) ? [] : ["--headless=new"]), "--remote-debugging-port=" + port, "--user-data-dir=" + profile, "--no-first-run", "--hide-scrollbars", "--allow-file-access-from-files", "--force-color-profile=srgb", "about:blank"];
  const chrome = spawn(bin, args, { stdio: "ignore" });
  let target;
  for (let i = 0; i < 150 && !target; i++) {
    try { target = (await (await fetch("http://127.0.0.1:" + port + "/json/list")).json()).find((x) => x.type === "page"); } catch (error) {}
    if (!target) await sleep(100);
  }
  if (!target) throw new Error("Chrome did not start");
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve) => ws.addEventListener("open", resolve));
  let seq = 0;
  const pending = new Map();
  ws.addEventListener("message", (m) => {
    const data = JSON.parse(m.data);
    if (data.id && pending.has(data.id)) { pending.get(data.id)(data); pending.delete(data.id); }
  });
  const send = (method, params) => new Promise((resolve) => { const id = ++seq; pending.set(id, resolve); ws.send(JSON.stringify({ id, method, params: params || {} })); });
  const evaluate = async (expression) => {
    const result = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
    if (result.result && result.result.exceptionDetails) throw new Error(JSON.stringify(result.result.exceptionDetails));
    return result.result && result.result.result ? result.result.result.value : undefined;
  };
  await send("Page.enable");
  await send("Runtime.enable");
  const close = async () => { ws.close(); chrome.kill("SIGKILL"); await sleep(150); fs.rmSync(profile, { recursive: true, force: true }); };
  return { send, evaluate, close };
}

async function capturePrototype(options) {
  if (!fs.existsSync(prototypeHTML)) throw new Error("Missing " + prototypeHTML + "; copy prototype_ui into the worktree first");
  fs.mkdirSync(options.prototype, { recursive: true });
  const browser = await openBrowser();
  const url = pathToFileURL(prototypeHTML).href;
  try {
    for (const scenario of options.scenarios) {
      for (const variantName of options.variants) {
        if (scenario === "welcome" && VARIANTS[variantName].width < NARROW_VIEWPORT) continue;
        const variant = VARIANTS[variantName];
        const narrow = variant.width < NARROW_VIEWPORT;
        const viewport = narrow ? { width: variant.width, height: variant.height } : { width: variant.width + DESKTOP_X, height: variant.height + DESKTOP_Y };
        await browser.send("Emulation.setDeviceMetricsOverride", { width: viewport.width, height: viewport.height, deviceScaleFactor: 2, mobile: false });
        await browser.send("Page.navigate", { url });
        await sleep(400);
        await browser.evaluate("localStorage.setItem('vrai.prototype.v1', " + JSON.stringify(JSON.stringify({ scenario, theme: variant.theme })) + ")");
        await browser.send("Page.reload", { ignoreCache: true });
        await sleep(SETTLE[scenario] ?? 1200);
        if (!KEEP_VIEW.has(scenario) && scenario !== "loading") await browser.evaluate("(() => { const item = [...document.querySelectorAll('.vr-sbitem')].find((e) => e.textContent.trim() === 'History'); if (item) { if (!item.classList.contains('is-selected')) item.click(); } else { document.body.dispatchEvent(new KeyboardEvent('keydown', { key: '1', code: 'Digit1', metaKey: true, bubbles: true })); } })()");
        if (!KEEP_VIEW.has(scenario) && scenario !== "loading") await sleep(500);
        const selector = scenario === "welcome" ? ".wel-window" : ".app-mainwin > .vr-window";
        const rect = await browser.evaluate("(() => { const w = document.querySelector('" + selector + "'); const r = w.getBoundingClientRect(); return { x: r.left, y: r.top, width: r.width, height: r.height }; })()");
        const shot = await browser.send("Page.captureScreenshot", { format: "png", clip: { ...rect, scale: 1 }, captureBeyondViewport: false });
        const file = path.join(options.prototype, options.prefix + "-" + scenario + "-" + variantName + ".png");
        fs.writeFileSync(file, Buffer.from(shot.result.data, "base64"));
        console.log("  " + path.relative(root, file) + "  " + Math.round(rect.width) + "x" + Math.round(rect.height));
      }
    }
  } finally {
    await browser.close();
  }
}

function pngSize(file) {
  const data = fs.readFileSync(file);
  return { width: data.readUInt32BE(16), height: data.readUInt32BE(20) };
}

function sheetHTML(pairs, columns, crop) {
  const cells = pairs.map((p) => {
    const frame = (label, file, size) => {
      if (!file) return "<figure><figcaption>" + label + "</figcaption><div class=missing>missing</div></figure>";
      const src = pathToFileURL(file).href;
      if (!crop) return "<figure><figcaption>" + label + " " + size.width / 2 + "x" + size.height / 2 + "</figcaption><img src='" + src + "' style='width:" + p.width + "px'></figure>";
      const [x, y, w, h] = crop;
      const scale = p.width / (size.width / 2);
      return "<figure><figcaption>" + label + "</figcaption><div class=crop style='width:" + w * 2 + "px;height:" + h * 2 + "px'><img src='" + src + "' style='width:" + p.width * 2 + "px;transform:translate(" + -x * 2 * scale + "px," + -y * 2 * scale + "px)'></div></figure>";
    };
    return "<section><h2>" + p.name + "</h2><div class=pair>" + frame("Prototype", p.prototype, p.prototypeSize) + frame("Native", p.native, p.nativeSize) + "</div></section>";
  }).join("");
  return "<!doctype html><meta charset=utf-8><style>body{margin:0;padding:24px;background:#808088;font:13px -apple-system,system-ui;color:#fff}section{margin:0 0 32px}h2{margin:0 0 8px;font-size:16px}.pair{display:flex;gap:24px;align-items:flex-start;flex-direction:" + (columns ? "row" : "column") + "}figure{margin:0}figcaption{margin:0 0 6px;opacity:.85}img{display:block;transform-origin:0 0}.crop{overflow:hidden;position:relative}.missing{width:200px;height:120px;display:grid;place-items:center;background:#555}</style>" + cells;
}

async function renderSheet(browser, html, file) {
  const tmp = path.join(path.dirname(file), "." + path.basename(file) + ".html");
  fs.writeFileSync(tmp, html);
  await browser.send("Emulation.setDeviceMetricsOverride", { width: 800, height: 600, deviceScaleFactor: 1, mobile: false });
  await browser.send("Page.navigate", { url: pathToFileURL(tmp).href });
  await sleep(500);
  const size = await browser.evaluate("(() => { const r = document.body.getBoundingClientRect(); return { width: Math.ceil(Math.max(document.body.scrollWidth, r.width)) + 48, height: Math.ceil(document.body.scrollHeight) }; })()");
  await browser.send("Emulation.setDeviceMetricsOverride", { width: size.width, height: size.height, deviceScaleFactor: 1, mobile: false });
  await sleep(300);
  const shot = await browser.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
  fs.writeFileSync(file, Buffer.from(shot.result.data, "base64"));
  fs.rmSync(tmp);
}

async function buildSheets(options) {
  fs.mkdirSync(options.out, { recursive: true });
  const browser = await openBrowser();
  const written = [];
  try {
    for (const scenario of options.scenarios) {
      for (const variantName of options.variants) {
        if (scenario === "welcome" && VARIANTS[variantName].width < NARROW_VIEWPORT) continue;
        const variant = VARIANTS[variantName];
        const name = options.prefix + "-" + scenario + "-" + variantName;
        const prototype = path.join(options.prototype, name + ".png");
        const native = path.join(options.native, name + ".png");
        const pair = {
          name, width: variant.width,
          prototype: fs.existsSync(prototype) ? prototype : null,
          native: fs.existsSync(native) ? native : null
        };
        pair.prototypeSize = pair.prototype ? pngSize(pair.prototype) : null;
        pair.nativeSize = pair.native ? pngSize(pair.native) : null;
        const columns = variant.width < NARROW_VIEWPORT;
        const file = path.join(options.out, name + (options.crop ? "-crop" : "") + ".png");
        await renderSheet(browser, sheetHTML([pair], columns || !!options.crop, options.crop), file);
        written.push(file);
        console.log("  " + path.relative(root, file) + (pair.prototype ? "" : "  (no prototype)") + (pair.native ? "" : "  (no native)"));
      }
    }
  } finally {
    await browser.close();
  }
  return written;
}

const options = parseArgs(process.argv.slice(2));
if (options.mode === "capture" || options.mode === "all") {
  console.log("prototype:");
  await capturePrototype(options);
}
if (options.mode === "sheet" || options.mode === "all") {
  console.log("contact sheets:");
  await buildSheets(options);
}
