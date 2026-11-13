// alerts.ts: watchers that post to the brepl channel by themselves (Simon, 2026-10-24: "add alerts and things
// that automatically go to your channel ... and therefore automatically trigger your monitor"). Loaded by the
// brepl server as `alerts`; the Monitor on channel.jsonl wakes Claude for each one. Async only, so nothing here
// can freeze the brepl (dev.debt's sync-in-brepl check flags any *Sync call). Also the freeze watchdog (below).
//   alerts.list()                                  what's watching, and each alert's last state
//   alerts.add(name, everySec, async () => text | null, o?)   post when the text changes (null = all fine)
//   alerts.tail(name, shellCmd, /regex/)           post each matching line of a long-running command
//   alerts.off(name) / alerts.on(name)             pause / resume one
import { $ } from "bun";
import { stat, readdir } from "node:fs/promises";
import { join } from "node:path";

const HOME = process.env.HOME!;
const send = (source: string, text: string, images: string[] = []) => (globalThis as any).send(`⚠ ${source}`, text, images);

type Alert = {
  name: string; kind: "poll" | "tail"; on: boolean; last: string | null; fired: number; lastAt: number;
  every?: number; check?: () => Promise<string | null | undefined>; quietStart?: boolean; recovered?: string; started?: boolean;
  cmd?: string; match?: RegExp; proc?: ReturnType<typeof Bun.spawn>; timer?: ReturnType<typeof setTimeout>;
};
const all = new Map<string, Alert>();

// Same text again within a minute is dropped; anything else goes straight out.
const recent = new Map<string, number>();
function post(a: Alert, text: string) {
  const key = `${a.name}\u0000${text}`;
  if (Date.now() - (recent.get(key) ?? 0) < 60_000) return;
  recent.set(key, Date.now());
  if (recent.size > 500) for (const [k, t] of recent) if (Date.now() - t > 60_000) recent.delete(k);
  a.fired++; a.lastAt = Date.now();
  send(a.name, text);
}

// An alert posts when its MEANING changes, not its numbers: "load 17.7" and "load 18.2" are the same state. Masking
// digits here fixes the whole class of chatty alerts (any alert text may include live figures).
const shape = (t: string | null) => (t === null ? null : t.replace(/\d+(\.\d+)?/g, "#"));

async function runPoll(a: Alert) {
  if (!a.on) return;
  try {
    const now = (await a.check!()) ?? null;
    const first = !a.started;
    a.started = true;
    if (shape(now) !== shape(a.last)) {
      if (now !== null && !(first && a.quietStart)) post(a, now);
      else if (now === null && a.last !== null && !first && a.recovered !== "") post(a, a.recovered ?? `ok again (was: ${a.last})`);
    }
    a.last = now;
  } catch (e) {
    post(a, `check failed: ${e}`);
  }
  a.timer = setTimeout(() => runPoll(a), a.every! * 1000);
}

function runTail(a: Alert) {
  if (!a.on) return;
  a.proc = Bun.spawn(["bash", "-c", a.cmd!], { stdout: "pipe", stderr: "ignore" });
  (async () => {
    let buf = "";
    const dec = new TextDecoder();
    for await (const chunk of a.proc!.stdout as any) {
      buf += dec.decode(chunk, { stream: true });
      let i;
      while ((i = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (line && a.match!.test(line)) { a.last = line; post(a, line.slice(0, 300)); }
      }
    }
    if (a.on) a.timer = setTimeout(() => runTail(a), 5000);  // the command died: restart it
  })().catch((e) => post(a, `tail failed: ${e}`));
}

export function add(name: string, everySec: number, check: () => Promise<string | null | undefined>, o: { quietStart?: boolean; recovered?: string /* "" = none */ } = {}) {
  off(name);
  const a: Alert = { name, kind: "poll", on: true, last: null, fired: 0, lastAt: 0, every: everySec, check, ...o };
  all.set(name, a);
  runPoll(a);
  return `watching ${name} every ${everySec}s`;
}

export function tail(name: string, cmd: string, match: RegExp = /./) {
  off(name);
  const a: Alert = { name, kind: "tail", on: true, last: null, fired: 0, lastAt: 0, cmd, match };
  all.set(name, a);
  runTail(a);
  return `tailing ${name}: ${cmd}`;
}

export function off(name: string) {
  const a = all.get(name);
  if (!a) return `no alert ${name}`;
  a.on = false;
  clearTimeout(a.timer);
  a.proc?.kill();
  return `${name} off`;
}

export function on(name: string) {
  const a = all.get(name);
  if (!a) return `no alert ${name}`;
  if (a.on) return `${name} already on`;
  a.on = true; a.started = false;
  a.kind === "poll" ? runPoll(a) : runTail(a);
  return `${name} on`;
}

export function list() {
  return [...all.values()].map((a) =>
    `${a.on ? "on " : "off"} ${a.name.padEnd(16)} ${a.kind === "poll" ? `every ${a.every}s` : "tail"}  fired ${a.fired}x${a.lastAt ? ` (last ${new Date(a.lastAt).toTimeString().slice(0, 8)})` : ""}  ${a.last ? "now: " + a.last.slice(0, 60) : ""}`).join("\n");
}

/** Post one test alert (checks the whole path to the Monitor). */
export function test(text = "test alert") { send("test", text); return "sent"; }

// --- Log watching: new error lines in Godot logs, each distinct message once -----------------------
const offsets = new Map<string, number>();
const seenErr = new Map<string, Set<string>>();
// What Godot prints while being killed or quitting; not a game bug.
const EXIT_NOISE = /Unreferenced static string|Pages in use exist at exit|ObjectDB instances leaked|resources still in use at exit|RID allocations .* were leaked|Condition "!_initialized"|BUG: /;
const GODOT_ERR = /^(SCRIPT ERROR|ERROR|Parse Error|USER ERROR|FATAL)|handle_crash|Program crashed/;
async function newErrors(path: string): Promise<string[]> {
  let size: number;
  try { size = (await stat(path)).size; } catch { return []; }
  const from = offsets.get(path);
  offsets.set(path, size);
  if (from === undefined || size < from) { seenErr.set(path, new Set()); if (from === undefined) return []; }
  const text = await Bun.file(path).slice(from ?? 0, size).text();
  const seen = seenErr.get(path) ?? new Set<string>();
  seenErr.set(path, seen);
  const out: string[] = [];
  const lines = text.split("\n");
  lines.forEach((l, i) => {
    if (!GODOT_ERR.test(l) || l.includes("BOT ") || EXIT_NOISE.test(l) || seen.has(l)) return;
    seen.add(l);
    const at = lines[i + 1]?.trim().startsWith("at:") ? ` ${lines[i + 1].trim()}` : "";
    if (at.includes("gdscript://")) return;  // an error in a test tool's own g.eval() snippet, not in the game
    out.push(l.trim().slice(0, 200) + at);
  });
  return out;
}

// --- Built-in alerts ----------------------------------------------------------------------------
const meminfo = async () => Object.fromEntries((await Bun.file("/proc/meminfo").text()).split("\n").map((l) => l.split(/:\s+/)).map(([k, v]) => [k, parseInt(v) / 1024 / 1024]));

// --- Freeze watchdog: say WHAT blocked the event loop -------------------------------------------------------
// brepl is one process for every agent: synchronous code anywhere (spawnSync, execSync, readFileSync over a big
// tree, a long CPU loop) freezes all of them. JS can't look at itself while it's blocked, so a Worker thread
// watches a heartbeat in shared memory and, while the main thread is stuck, records: the main thread's state
// (S + wchan do_wait = waiting on a child, i.e. spawnSync/execSync; R = busy running JS), the child processes
// started during the freeze (names the command), the timer callback running (setTimeout / setInterval are
// wrapped to label each callback with where it was registered) and the running jobs. After it unfreezes, the
// report goes to the channel and ~/.cache/brepl/freezes.log.
// System suspend (2026-11-12 17:57 and 11-13 07:04, the only two "freezes" so far: the suspend key / powerdevil)
// freezes user.slice and every process with it; that is not a brepl bug, so it's only logged (suspend_stats).
const FREEZE_LOG = join(HOME, ".cache/brepl/freezes.log");
const FREEZE_MS = 2000;
const suspends = async () => {
  let n = 0;
  for (const f of ["success", "fail"]) n += parseInt(await Bun.file(`/sys/power/suspend_stats/${f}`).text().catch(() => "0")) || 0;
  return n;
};
const WORKER_SRC = `
const fs = require("fs");
let hb, lab, len, pid, snapped = false;
const read = (p) => { try { return fs.readFileSync(p, "utf8").trim(); } catch { return ""; } };  // sync-ok: the watchdog Worker thread
self.onmessage = (e) => {
  hb = new Float64Array(e.data.sab, 0, 1); len = new Int32Array(e.data.sab, 8, 1); lab = new Uint8Array(e.data.sab, 16); pid = e.data.pid;
  setInterval(() => {
    const age = Date.now() - hb[0];
    if (age < 1500) { snapped = false; return; }
    if (snapped) return;
    snapped = true;
    const ps = Bun.spawnSync(["ps", "-o", "pid=,etimes=,args=", "--ppid", String(pid)]).stdout.toString().split("\\n")  // sync-ok: Worker thread
      .map((l) => l.trim()).filter((l) => l && Number(l.split(/\\s+/)[1]) <= Math.ceil(age / 1000) + 1 && !/ ps -o pid=/.test(l));
    const state = read("/proc/" + pid + "/task/" + pid + "/stat").replace(/^.*\\) /, "").split(" ")[0];
    postMessage({ age, state, wchan: read("/proc/" + pid + "/task/" + pid + "/wchan"), children: ps,
      label: new TextDecoder().decode(lab.slice(0, len[0])) });
  }, 250);
};`;
let fw: { worker: Worker; tick: any; snap: any; origST: any; origSI: any; send: any } | null = null;
function startFreezeWatch() {
  const sab = new SharedArrayBuffer(16 + 1024);
  const hb = new Float64Array(sab, 0, 1), len = new Int32Array(sab, 8, 1), lab = new Uint8Array(sab, 16);
  const enc = new TextEncoder();
  const setLabel = (s: string) => { const b = enc.encode(s).slice(0, lab.length); lab.set(b); len[0] = b.length; };
  let base = "", inTimer = "";
  const label = () => setLabel([inTimer && `timer callback from ${inTimer}`, base].filter(Boolean).join("; "));
  // Label every timer callback with where it was set (the first stack frame outside this file).
  const site = () => (new Error().stack ?? "").split("\n").slice(2).map((l) => l.trim()).find((l) => !l.includes("alerts.ts") && !l.includes("native")) ?? "?";
  const wrap = (fn: any, at: string) => typeof fn !== "function" ? fn : function (this: any, ...a: any[]) {
    const prev = inTimer; inTimer = at; label();
    try { return fn.apply(this, a); } finally { inTimer = prev; label(); }
  };
  const origST = globalThis.setTimeout, origSI = globalThis.setInterval;
  (globalThis as any).setTimeout = Object.assign((fn: any, ms?: number, ...a: any[]) => origST(wrap(fn, site()), ms, ...a), origST);
  (globalThis as any).setInterval = Object.assign((fn: any, ms?: number, ...a: any[]) => origSI(wrap(fn, site()), ms, ...a), origSI);
  const worker = new Worker(URL.createObjectURL(new Blob([WORKER_SRC], { type: "application/javascript" })));
  worker.unref?.();
  let snap: any = null;
  worker.onmessage = (e) => { snap = e.data; };
  worker.postMessage({ sab, pid: process.pid });
  let last = Date.now(), susp: Promise<number> = suspends(), suspAt = last;
  const tick = origSI(async () => {
    const now = Date.now(), lag = now - last - 250;
    last = now; hb[0] = now;
    if (lag < FREEZE_MS && now - suspAt > 30_000) { susp = suspends(); suspAt = now; }  // fresh baseline
    const running = ((globalThis as any).jobs?.() ?? []).filter((j: any) => j.status === "running").map((j: any) => `#${j.id} ${j.name}`);
    const b = running.length ? `running jobs: ${running.join(", ").slice(0, 600)}` : "";
    if (b !== base) { base = b; label(); }
    if (lag < FREEZE_MS) return;
    const was = await susp;
    susp = suspends();
    await Bun.sleep(300);  // the worker's report arrives on the next turns of the loop
    const s = snap; snap = null;
    const suspended = (await susp) !== was;
    const what = !s ? "no snapshot from the watchdog thread"
      : [s.label || "no timer callback or job was running",
         s.state === "R" ? "main thread was busy running JS (a CPU loop, big JSON / regex / sort, or a sync fs call)"
           : `main thread was waiting (${s.state} in ${s.wchan || "?"}${s.wchan === "do_wait" ? ": a spawnSync / execSync child" : ""})`,
         s.children.length ? `started during the freeze: ${s.children.join(" | ").slice(0, 400)}` : ""].filter(Boolean).join("\n");
    const { appendFile } = await import("node:fs/promises");
    await appendFile(FREEZE_LOG, JSON.stringify({ at: new Date(now).toISOString(), lagMs: lag, suspended, ...(s ?? {}) }) + "\n").catch(() => {});
    if (suspended) return;  // the machine slept (suspend key / powerdevil): every process stopped, not a brepl bug
    fw?.send("⚠ brepl frozen", `the event loop was blocked for ${(lag / 1000).toFixed(1)}s (use async versions, e.g. Bun.spawn / fs.promises, not spawnSync / readFileSync). Culprit:\n${what}`);
  }, 250);
  (tick as any).unref?.();
  // A brepl core from before 2026-11-13 runs its own vague freeze check (and posts on suspend): drop its posts.
  const g = globalThis as any, origSend = g.send;
  if (g.__breplCore !== 2) g.send = (src: any, text: any, ...r: any[]) =>
    src === "⚠ brepl frozen" && /use async versions, e\.g\. Bun\.spawn not spawnSync\)$/.test(String(text)) ? 0 : origSend(src, text, ...r);
  fw = { worker, tick, snap, origST, origSI, send: origSend };
}
function stopFreezeWatch() {
  if (!fw) return;
  clearInterval(fw.tick);
  fw.worker.terminate();
  (globalThis as any).setTimeout = fw.origST;
  (globalThis as any).setInterval = fw.origSI;
  (globalThis as any).send = fw.send;
  fw = null;
}

// One brepl server per user. A second one (2026-11-11: `brepl` auto-started one while systemd restarted brepl.service)
// loses ~/.cache/brepl.sock but kept every watcher running, so each alert and "reloaded" line came twice. Whoever
// answers on the socket owns the watchers; a duplicate stays quiet and says so.
async function socketOwner(): Promise<number | null> {
  return await new Promise((ok) => {
    let buf = "";
    const t = setTimeout(() => ok(null), 2000);
    Bun.connect({ unix: join(HOME, ".cache/brepl.sock"), socket: {
      open(s) { s.write("process.pid\0"); }, data(_, d) { buf += d.toString(); },
      close() { clearTimeout(t); ok(parseInt(buf) || null); }, error() { clearTimeout(t); ok(null); }, connectError() { clearTimeout(t); ok(null); },
    } }).catch(() => { clearTimeout(t); ok(null); });
  });
}
export let duplicate = false;

/** Hot reload (brepl loads this module with start/stop): stop every watcher before the new copy starts. */
export function stop() {
  stopFreezeWatch();
  for (const name of [...all.keys()]) off(name);
  all.clear();
}
export async function start() {
  const owner = await socketOwner();
  duplicate = owner !== null && owner !== process.pid;
  if (duplicate) {
    send("brepl", `duplicate brepl server pid ${process.pid}: pid ${owner} owns ~/.cache/brepl.sock, so this one's watchers stay off. Stop it: kill ${process.pid}`);
    return;
  }
  startAll();
  startFreezeWatch();
}

export function startAll() {
  // Microphone plugged in / unplugged (voice only works with one).
  add("mic", 5, async () => {
    const out = (await $`pactl list short sources`.nothrow().quiet()).stdout.toString();
    const mics = out.split("\n").map((l) => l.split("\t")[1]).filter((n) => n && !n.endsWith(".monitor"));
    return mics.length ? `mic plugged in: ${mics.join(", ")}` : "no mic plugged in: voice can't hear anyone";
  }, { quietStart: true });

  add("voice-bridge", 30, async () => {
    if ((await $`systemctl --user cat voice-bridge`.nothrow().quiet()).exitCode !== 0) return null;  // not on this machine (e.g. a Deck)
    const s = (await $`systemctl --user is-active voice-bridge`.nothrow().quiet()).stdout.toString().trim();
    return s === "active" ? null : `voice-bridge service is ${s}`;
  }, { recovered: "voice-bridge is running again" });

  add("memory", 10, async () => {
    const m = await meminfo();
    return m.MemAvailable < 1.5 ? `low memory: ${m.MemAvailable.toFixed(1)} GB free of ${m.MemTotal.toFixed(0)} GB` : null;
  }, { recovered: "memory ok again" });

  // CPU / memory (Simon, 2026-10-24: "keep an eye on the RAM and cpu usage"). Live figures in the text are fine:
  // runPoll compares the text with digits masked, so these post only when the state changes.
  let hot = 0;
  add("cpu", 30, async () => {
    const load = parseFloat((await Bun.file("/proc/loadavg").text()).split(" ")[0]);
    const threads = navigator.hardwareConcurrency;
    hot = load > threads ? hot + 1 : 0;
    if (hot < 2) return null;
    const top = (await $`ps -eo pcpu,comm --sort=-pcpu`.nothrow().quiet()).stdout.toString().split("\n").slice(1).filter(l => !/ ps$/.test(l.trim())).slice(0, 3).map(l => l.trim().replace(/\s+/, "% ")).join(", ");
    return `CPU overloaded: load ${load.toFixed(1)} on ${threads} threads (top: ${top.replace(/\d/g, "")})`;
  }, { recovered: "CPU load back to normal" });
  add("memory-trend", 30, async () => {
    const m = await meminfo();
    return m.MemAvailable < 3 ? `memory getting tight: ${m.MemAvailable.toFixed(1)} GB free (new test games wait below 2.5 GB)` : null;
  }, { recovered: "memory headroom back above 3 GB" });

  add("disk", 300, async () => {
    const out = (await $`df -BG --output=avail ${HOME}`.nothrow().quiet()).stdout.toString();
    const gb = parseInt(out.split("\n")[1]);
    return gb < 20 ? `low disk: ${gb} GB free` : null;
  });

  // Steam Frame (VR headset) online / offline: when it comes back, duo-catch-up (timer) deploys anything it missed.
  add("frame", 60, async () => {
    const r = await $`ssh -o ConnectTimeout=4 -o BatchMode=yes -i ${HOME}/.config/steamos-devkit/devkit_rsa steamos@frame true`.nothrow().quiet();
    return r.exitCode === 0 ? "Steam Frame is online (duo-catch-up deploys anything it missed)" : null;
  }, { recovered: "Steam Frame went offline" });

  // Usage limits: post when a window crosses 50 / 75 / 90 %.
  add("usage", 60, async () => {
    const u = await Bun.file(join(HOME, ".claude/usage.json")).json().catch(() => null);
    if (!u) return null;
    const band = (p: number) => (p >= 90 ? 90 : p >= 75 ? 75 : p >= 50 ? 50 : 0);
    const parts = [["5-hour", u.rate_limits?.five_hour?.used_percentage], ["weekly", u.rate_limits?.seven_day?.used_percentage]]
      .filter(([, p]) => band(p ?? 0)).map(([n, p]) => `${n} ${band(p)}%+ used (${p}%)`);
    if (!parts.length) return null;
    // Simon: always wake back up just after a limit reset. Cloud send_later is refused for the main (Remote Control)
    // session, so claude-wake does it locally (run by claude-watchdog every 2 min; state in ~/.claude/wake-state.json).
    const at = (r: any) => r ? new Date(typeof r === "number" ? (r < 1e12 ? r * 1000 : r) : r).toLocaleTimeString("en-IE", { hour: "2-digit", minute: "2-digit" }) : "?";
    const ws = await Bun.file(join(HOME, ".claude/wake-state.json")).json().catch(() => ({} as any));
    const top = Math.max(u.rate_limits?.five_hour?.used_percentage ?? 0, u.rate_limits?.seven_day?.used_percentage ?? 0);
    const wake = ws.armed && ws.armed !== ws.fired ? ` → local wake-up armed for ${at(ws.armed + 120)}`
      : top >= 75 ? " → local wake-up (claude-wake) arms itself at 95% or on a rate-limit stop" : "";
    return `usage: ${parts.join(", ")}${wake}`;
  });

  // Any process crashing (kwin, Godot, Steam...), and the kernel killing things for memory.
  tail("crash", "journalctl -f -n0 -o cat -t systemd-coredump", /dumped core/);
  tail("oom", "journalctl -k -f -n0 -o cat", /Out of memory|oom-kill|Killed process/i);
  tail("watchdog", `tail -n0 -F ${HOME}/.claude/watchdog.log`, /./);

  // Errors in the live game (gdev) and in offscreen test runs.
  add("game-errors", 3, async () => {
    const logs: string[] = [];
    const last = (await Bun.file(join(HOME, ".cache/gdev/last")).text().catch(() => "")).trim();
    if (last) logs.push(join(last, ".dev/game.log"));
    const off = join(HOME, ".cache/gdev-offscreen");
    for (const d of await readdir(off).catch(() => [] as string[])) {
      const p = join(off, d, "game.log");
      const st = await stat(p).catch(() => null);
      if (st && Date.now() - st.mtimeMs < 10 * 60_000) logs.push(p);
    }
    const found: string[] = [];
    for (const p of logs) for (const e of await newErrors(p)) found.push(`${p.includes("offscreen") ? "offscreen" : "live"}: ${e}`);
    // A fresh value each time there's something new, so every batch posts; null in between.
    return found.length ? found.slice(0, 6).join("\n") + (found.length > 6 ? `\n(+${found.length - 6} more)` : "") : null;
  }, { recovered: "" });  // "" = no "ok again" post between batches
}
