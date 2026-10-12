import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const W = 640;
const H = 440;
const HORIZON = 300;
const SUN = { x: 320, y: 266, r: 36 };

function random(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const f = (n) => Math.round(n * 100) / 100;

function ridge({ seed, base, amplitude, peaks, step = 4, bottom = H, mirror = false }) {
  const rand = random(seed);
  const waves = Array.from({ length: 4 }, (_, i) => ({ freq: (i + 1) * (0.6 + rand()) * Math.PI * 2 / W * peaks, phase: rand() * Math.PI * 2, amp: amplitude / (i + 1.4) }));
  const points = [];
  for (let x = -8; x <= W + 8; x += step) {
    let y = base;
    for (const w of waves) y -= Math.sin(x * w.freq + w.phase) * w.amp;
    y -= Math.max(0, Math.sin(x * waves[0].freq * 0.5 + waves[1].phase)) * amplitude * 0.6;
    points.push([x, mirror ? 2 * HORIZON - y : y]);
  }
  const edge = mirror ? HORIZON : bottom;
  return "M" + points.map(([x, y]) => f(x) + " " + f(y)).join("L") + "L" + (W + 8) + " " + edge + "L-8 " + edge + "Z";
}

function stars() {
  const rand = random(7);
  let out = "";
  for (let i = 0; i < 90; i++) {
    const x = rand() * W;
    const y = Math.pow(rand(), 1.6) * 150;
    const r = 0.35 + rand() * 0.9;
    const o = 0.25 + rand() * 0.7 * (1 - y / 170);
    out += `<circle cx="${f(x)}" cy="${f(y)}" r="${f(r)}" fill="#fff" opacity="${f(o)}"/>`;
  }
  for (const [x, y, r] of [[88, 38, 1.6], [404, 22, 1.4], [556, 66, 1.7], [236, 74, 1.2]]) {
    out += `<circle cx="${x}" cy="${y}" r="${r * 4}" fill="url(#twinkle)"/><circle cx="${x}" cy="${y}" r="${r}" fill="#fff"/>`;
  }
  return out;
}

function sunPath() {
  const rand = random(11);
  let out = `<rect x="${SUN.x - 7}" y="${HORIZON + 2}" width="14" height="74" rx="7" fill="url(#pillar)" filter="url(#soft)" opacity="0.9"/>`;
  for (let i = 0; i < 18; i++) {
    const depth = i / 18;
    const y = HORIZON + 4 + depth * 70 + rand() * 3;
    const width = SUN.r * (1.5 - depth * 1.1) * (0.35 + rand() * 0.65);
    const shift = (rand() - 0.5) * (10 + depth * 24);
    out += `<rect x="${f(SUN.x - width / 2 + shift)}" y="${f(y)}" width="${f(width)}" height="${f(1.2 + rand() * 1.2)}" rx="1" fill="#ffe3c4" opacity="${f(0.7 * (1 - depth) * (0.5 + rand() * 0.5))}"/>`;
  }
  return `<g filter="url(#blur06)">${out}</g>`;
}

function shimmer() {
  const rand = random(23);
  let out = "";
  for (let i = 0; i < 46; i++) {
    const y = HORIZON + 8 + Math.pow(rand(), 0.8) * (H - HORIZON - 10);
    const x = rand() * W;
    if (Math.abs(x - SUN.x) < 60 && y < HORIZON + 80) continue;
    const width = 6 + rand() * 26 * (y - HORIZON) / (H - HORIZON);
    out += `<rect x="${f(x)}" y="${f(y)}" width="${f(width)}" height="1.2" rx="0.6" fill="#fff" opacity="${f(0.05 + rand() * 0.12)}"/>`;
  }
  return out;
}

function reeds(side) {
  const rand = random(side === "left" ? 31 : 37);
  let out = "";
  const anchor = side === "left" ? 0 : W;
  const dir = side === "left" ? 1 : -1;
  for (let i = 0; i < 16; i++) {
    const x = anchor + dir * (rand() * 64);
    const top = 268 + rand() * 56 + Math.abs(x - anchor) * 0.6;
    const lean = dir * (rand() * 14 - 4);
    const w = 1.2 + rand() * 1.4;
    out += `<path d="M${f(x - w)} ${H}Q${f(x + lean * 0.4)} ${f((top + H) / 2)} ${f(x + lean)} ${f(top)}Q${f(x + lean * 0.4 + w)} ${f((top + H) / 2)} ${f(x + w)} ${H}Z" fill="#0d1240"/>`;
    if (rand() < 0.45) {
      out += `<rect x="${f(x + lean - 2.4)}" y="${f(top + 4)}" width="4.8" height="${f(15 + rand() * 7)}" rx="2.4" fill="#0d1240" transform="rotate(${f(lean * 0.9)} ${f(x + lean)} ${f(top + 14)})"/>`;
    }
  }
  for (let i = 0; i < 22; i++) {
    const x = anchor + dir * (rand() * 92);
    const top = 318 + rand() * 40 + Math.abs(x - anchor) * 0.35;
    const lean = dir * (rand() * 22 - 6);
    out += `<path d="M${f(x - 1.6)} ${H}Q${f(x + lean * 0.3)} ${f((top + H) / 2)} ${f(x + lean)} ${f(top)}Q${f(x + lean * 0.3 + 1.2)} ${f((top + H) / 2)} ${f(x + 1.6)} ${H}Z" fill="#141a52"/>`;
  }
  return out;
}

function goose(x, y, scale) {
  return `<g transform="translate(${x} ${y}) scale(${scale})">
    <path d="M17 -49.5C24 -50 31 -48.5 34.5 -45.8C36 -44.6 35.4 -43 33.8 -42.8C29 -42.2 23 -42.4 17 -43.4Z" fill="#ff8f45"/>
    <path d="M-33 -3C-37 -12 -32 -21 -23 -17C-15 -21 -1 -21 9 -17C18 -14 25 -9 25 -2C25 4 15 6 0 6C-16 6 -29 4 -33 -3Z" fill="url(#gooseBody)"/>
    <path d="M15 -13C11 -23 11 -35 16.5 -45" fill="none" stroke="#fdfdff" stroke-width="8.5" stroke-linecap="round"/>
    <circle cx="18.5" cy="-46.5" r="8.4" fill="#ffffff"/>
    <circle cx="21.2" cy="-48.3" r="1.5" fill="#141625"/>
    <path d="M-24 -10C-15 -5 -1 -5 10 -10" fill="none" stroke="#cfd5ff" stroke-width="1.5" stroke-linecap="round"/>
    <path d="M-27 -14C-25 -11 -22 -10 -19 -10" fill="none" stroke="#cfd5ff" stroke-width="1.2" stroke-linecap="round"/>
  </g>`;
}

function arrow() {
  const start = [248, 142];
  const control = [320, 90];
  const end = [392, 140];
  const dx = end[0] - control[0];
  const dy = end[1] - control[1];
  const length = Math.hypot(dx, dy);
  const ux = dx / length;
  const uy = dy / length;
  const arm = (angle) => {
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    return [end[0] - 13 * (ux * c - uy * s), end[1] - 13 * (ux * s + uy * c)];
  };
  const [a, b] = [arm(0.62), arm(-0.62)];
  return `<path d="M${start}Q${control} ${end}" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-dasharray="0.1 9" opacity="0.95"/>
  <path d="M${f(a[0])} ${f(a[1])}L${end[0]} ${end[1]}L${f(b[0])} ${f(b[1])}" fill="none" stroke="#fff" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" opacity="0.95"/>`;
}

function svg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="${HORIZON}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#0f1650"/>
      <stop offset="0.28" stop-color="#2335b8"/>
      <stop offset="0.52" stop-color="#4f5fe6"/>
      <stop offset="0.72" stop-color="#9a86ea"/>
      <stop offset="0.88" stop-color="#f0a7a6"/>
      <stop offset="1" stop-color="#ffd7b0"/>
    </linearGradient>
    <radialGradient id="halo" cx="${SUN.x}" cy="${SUN.y}" r="210" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffe2bf" stop-opacity="0.9"/>
      <stop offset="0.25" stop-color="#ffbf91" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#ff9f80" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="sun" cx="${SUN.x}" cy="${SUN.y - 8}" r="${SUN.r}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#fffaf2"/>
      <stop offset="1" stop-color="#ffd9ad"/>
    </radialGradient>
    <radialGradient id="twinkle">
      <stop offset="0" stop-color="#fff" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="far" x1="0" y1="232" x2="0" y2="${HORIZON}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#c9b2f0"/>
      <stop offset="1" stop-color="#f1c1c6"/>
    </linearGradient>
    <linearGradient id="mid" x1="0" y1="258" x2="0" y2="${HORIZON}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#8f8ae4"/>
      <stop offset="1" stop-color="#b39fe6"/>
    </linearGradient>
    <linearGradient id="near" x1="0" y1="280" x2="0" y2="${HORIZON + 6}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#5a5fcc"/>
      <stop offset="1" stop-color="#6c6ed2"/>
    </linearGradient>
    <linearGradient id="lake" x1="0" y1="${HORIZON}" x2="0" y2="${H}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#9c8fe2"/>
      <stop offset="0.18" stop-color="#5f63d0"/>
      <stop offset="0.55" stop-color="#2f369e"/>
      <stop offset="1" stop-color="#141a5c"/>
    </linearGradient>
    <linearGradient id="gooseBody" x1="0" y1="-20" x2="0" y2="8" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="1" stop-color="#dfe3ff"/>
    </linearGradient>
    <radialGradient id="vignette" cx="320" cy="200" r="430" gradientUnits="userSpaceOnUse">
      <stop offset="0.6" stop-color="#05082a" stop-opacity="0"/>
      <stop offset="1" stop-color="#05082a" stop-opacity="0.45"/>
    </radialGradient>
    <filter id="soft" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="7"/></filter>
    <filter id="blur2"><feGaussianBlur stdDeviation="1.4"/></filter>
    <filter id="blur06"><feGaussianBlur stdDeviation="0.5"/></filter>
    <linearGradient id="pillar" x1="0" y1="${HORIZON}" x2="0" y2="${HORIZON + 76}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffd9b3" stop-opacity="0.8"/>
      <stop offset="1" stop-color="#ffd9b3" stop-opacity="0"/>
    </linearGradient>
    <filter id="grain" x="0" y="0" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="4" result="noise"/>
      <feColorMatrix in="noise" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.09 0"/>
    </filter>
    <clipPath id="water"><rect x="0" y="${HORIZON}" width="${W}" height="${H - HORIZON}"/></clipPath>
  </defs>

  <rect width="${W}" height="${HORIZON + 2}" fill="url(#sky)"/>
  ${stars()}
  <circle cx="${SUN.x}" cy="${SUN.y}" r="210" fill="url(#halo)"/>
  <g filter="url(#soft)" opacity="0.55">
    <ellipse cx="128" cy="200" rx="96" ry="7" fill="#ffd0c0"/>
    <ellipse cx="520" cy="188" rx="110" ry="6" fill="#f6b8c6"/>
    <ellipse cx="410" cy="246" rx="70" ry="5" fill="#ffe1c8"/>
    <ellipse cx="226" cy="250" rx="60" ry="4" fill="#ffe1c8"/>
  </g>
  <circle cx="${SUN.x}" cy="${SUN.y}" r="${SUN.r}" fill="url(#sun)"/>
  <path d="${ridge({ seed: 3, base: 266, amplitude: 13, peaks: 1.6 })}" fill="url(#far)"/>
  <path d="${ridge({ seed: 9, base: 284, amplitude: 9, peaks: 2.2 })}" fill="url(#mid)"/>
  <path d="${ridge({ seed: 17, base: 297, amplitude: 5, peaks: 3.1, bottom: HORIZON + 4 })}" fill="url(#near)"/>

  <rect y="${HORIZON}" width="${W}" height="${H - HORIZON}" fill="url(#lake)"/>
  <g clip-path="url(#water)" filter="url(#blur2)" opacity="0.32">
    <path d="${ridge({ seed: 9, base: 284, amplitude: 9, peaks: 2.2, mirror: true })}" fill="#8f8ae4"/>
    <path d="${ridge({ seed: 17, base: 297, amplitude: 5, peaks: 3.1, mirror: true })}" fill="#4a4fbf"/>
  </g>
  <ellipse cx="${SUN.x}" cy="${HORIZON + 30}" rx="90" ry="34" fill="#ffc9a0" opacity="0.22" filter="url(#soft)"/>
  ${sunPath()}
  ${shimmer()}

  <g>
    <g transform="translate(0 ${2 * 340}) scale(1 -1)" opacity="0.22" filter="url(#blur2)">${goose(112, 340, 0.86)}</g>
    <ellipse cx="108" cy="341.5" rx="38" ry="3.2" fill="none" stroke="#fff" stroke-width="1" opacity="0.28"/>
    <ellipse cx="106" cy="343" rx="54" ry="4.6" fill="none" stroke="#fff" stroke-width="0.8" opacity="0.14"/>
    ${goose(112, 340, 0.86)}
  </g>

  ${reeds("left")}
  ${reeds("right")}

  ${arrow()}

  <text x="${W / 2}" y="356" text-anchor="middle" font-family="-apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif" font-size="13.5" font-weight="600" letter-spacing="0.2" fill="#fff" opacity="0.9">Drag Vrai into Applications</text>

  <rect width="${W}" height="${H}" fill="url(#vignette)"/>
  <rect width="${W}" height="${H}" filter="url(#grain)" opacity="0.6"/>
</svg>`;
}

function findChrome() {
  if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN;
  const cache = path.join(os.homedir(), "Library/Caches/ms-playwright");
  if (fs.existsSync(cache)) {
    for (const dir of fs.readdirSync(cache).filter((d) => d.startsWith("chromium_headless_shell-")).sort().reverse()) {
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

async function render(file, outputs) {
  const bin = findChrome();
  const port = 9300 + Math.floor(Math.random() * 500);
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), "vrai-dmg-"));
  const chrome = spawn(bin, [...(/headless/i.test(path.basename(bin)) ? [] : ["--headless=new"]), "--remote-debugging-port=" + port, "--user-data-dir=" + profile, "--no-first-run", "--hide-scrollbars", "--force-color-profile=srgb", "about:blank"], { stdio: "ignore" });
  let target;
  for (let i = 0; i < 150 && !target; i++) {
    try { target = (await (await fetch("http://127.0.0.1:" + port + "/json/list")).json()).find((x) => x.type === "page"); } catch (error) {}
    if (!target) await new Promise((r) => setTimeout(r, 100));
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
  await send("Page.enable");
  for (const [scale, output] of outputs) {
    await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: scale, mobile: false });
    await send("Page.navigate", { url: pathToFileURL(file).href });
    await new Promise((r) => setTimeout(r, 600));
    const shot = await send("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width: W, height: H, scale: 1 } });
    fs.writeFileSync(output, Buffer.from(shot.result.data, "base64"));
    console.log("wrote " + path.relative(process.cwd(), output));
  }
  ws.close();
  chrome.kill("SIGKILL");
  fs.rmSync(profile, { recursive: true, force: true });
}

const file = path.join(os.tmpdir(), "vrai-dmg-background.svg");
fs.writeFileSync(file, svg());
await render(file, [[1, path.join(here, "background.png")], [2, path.join(here, "background@2x.png")]]);
fs.rmSync(file, { force: true });
