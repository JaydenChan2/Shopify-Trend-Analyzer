#!/usr/bin/env node
// Headless layout check: no horizontal scroll at phone widths, no console errors
// (including Content-Security-Policy violations), and a count of small tap targets.
// No dependencies: drives a local Chrome over the DevTools protocol.
//
//   bin/rails server                       # in another terminal
//   node script/check_layout.mjs           # checks http://127.0.0.1:3000
//   node script/check_layout.mjs http://127.0.0.1:3001
//   CHROME=/path/to/chrome node script/check_layout.mjs
//
// Exits 1 if any page overflows or logs an error.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const BASE = (process.argv[2] || "http://127.0.0.1:3000").replace(/\/$/, "");
const WIDTHS = [320, 375, 414];
const PAGES = ["/", "/how-it-works", "/dashboard", "/dashboard?as_of=2017-06-12", "/discover",
               "/discover?as_of=2017-06-12", "/trend?article=Fidget+spinner&product=Fidget+Spinner&as_of=2017-06-12",
               "/trend", "/does-not-exist"];
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9300 + Math.floor(Math.random() * 500);
const SETTLE_MS = 2500; // lazy sections (cards, Discover) load after the page

const profile = mkdtempSync(join(tmpdir(), "layout-check-"));
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
                              "--no-first-run", "--disable-gpu", "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function devtoolsTarget() {
  for (let i = 0; i < 50; i++) {
    try {
      const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
      const page = targets.find((t) => t.type === "page");
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(200);
  }
  throw new Error("Chrome didn't start; set CHROME to its path");
}

function connect(url) {
  const ws = new WebSocket(url);
  let id = 0;
  const pending = new Map();
  const listeners = [];
  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    } else if (msg.method) {
      listeners.forEach((fn) => fn(msg));
    }
  };
  const ready = new Promise((resolve) => (ws.onopen = resolve));
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const msgId = ++id;
      pending.set(msgId, resolve);
      ws.send(JSON.stringify({ id: msgId, method, params }));
    });
  return { ready, send, on: (fn) => listeners.push(fn), close: () => ws.close() };
}

// Runs in the page: overflow and small tap targets. `vw` is the device width: with
// mobile emulation Chrome zooms out to fit wide content, so innerWidth can't be trusted.
const measure = (vw) => `(() => {
  const vw = ${vw};
  const describe = (el) => el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") +
    (el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\\s+/).join(".") : "");
  const visible = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== "hidden"; };
  const overflowing = [...document.querySelectorAll("body *")]
    .filter((el) => visible(el) && el.getBoundingClientRect().right > vw + 1 && !el.closest(".table-scroll, dialog"))
    .map(describe).slice(0, 5);
  // Inline links inside running text are exempt (WCAG 2.5.8).
  const small = [...document.querySelectorAll("a, button, summary, input, select")]
    .filter((el) => visible(el) && !el.closest("p, li.inline, dialog:not([open])"))
    .filter((el) => { const r = el.getBoundingClientRect(); return r.height < 24 || r.width < 24; })
    .map((el) => describe(el) + " '" + (el.textContent || el.value || "").trim().slice(0, 24) + "'");
  return JSON.stringify({ scrollWidth: document.documentElement.scrollWidth, vw, overflowing, small });
})()`;

let failures = 0;
try {
  const cdp = connect(await devtoolsTarget());
  await cdp.ready;
  let errors = [];
  cdp.on((msg) => {
    if (msg.method === "Runtime.exceptionThrown") errors.push(msg.params.exceptionDetails.exception?.description || msg.params.exceptionDetails.text);
    if (msg.method === "Runtime.consoleAPICalled" && msg.params.type === "error") errors.push(msg.params.args.map((a) => a.value ?? a.description).join(" "));
    if (msg.method === "Log.entryAdded" && msg.params.entry.level === "error" && !/status of 4\d\d/.test(msg.params.entry.text)) errors.push(msg.params.entry.text);
  });
  await cdp.send("Runtime.enable");
  await cdp.send("Log.enable");
  await cdp.send("Page.enable");

  for (const path of PAGES) {
    for (const width of WIDTHS) {
      errors = [];
      await cdp.send("Emulation.setDeviceMetricsOverride", { width, height: 800, deviceScaleFactor: 2, mobile: true });
      await cdp.send("Page.navigate", { url: BASE + path });
      await sleep(SETTLE_MS);
      const { result } = await cdp.send("Runtime.evaluate", { expression: measure(width), returnByValue: true });
      const m = JSON.parse(result.result.value);
      const overflow = m.scrollWidth > m.vw;
      const bad = overflow || errors.length > 0;
      if (bad) failures++;
      console.log(`${bad ? "FAIL" : "ok  "} ${String(width).padEnd(4)} ${path}` +
        (overflow ? `  overflow: scrollWidth ${m.scrollWidth} > ${m.vw} (${m.overflowing.join(", ")})` : "") +
        (errors.length ? `  console: ${[...new Set(errors)].join(" | ").slice(0, 300)}` : "") +
        (m.small.length ? `  [${m.small.length} tap targets < 24px${width === 375 ? ": " + m.small.slice(0, 4).join(", ") : ""}]` : ""));
    }
  }
  cdp.close();
} finally {
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
console.log(failures ? `\n${failures} check(s) failed.` : "\nAll pages fit at 320/375/414px with no console errors.");
process.exit(failures ? 1 : 0);
