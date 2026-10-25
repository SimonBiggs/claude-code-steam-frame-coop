// alerts.ts: watchers that post to the brepl channel by themselves (Simon, 2026-10-24: "add alerts and things
// that automatically go to your channel ... and therefore automatically trigger your monitor"). Loaded by the
// brepl server as `alerts`; the Monitor on channel.jsonl wakes Claude for each one. Async only, so nothing here
// can freeze the brepl.
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

/** Hot reload (brepl loads this module with start/stop): stop every watcher before the new copy starts. */
export function stop() {
  for (const name of [...all.keys()]) off(name);
  all.clear();
}
export function start() { startAll(); }

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
    // Simon: always schedule a wake-up for just after a limit reset, so work resumes by itself.
    const five = u.rate_limits?.five_hour;
    const r = five?.resets_at ?? five?.reset_at;
    const when = r ? new Date(typeof r === "number" ? (r < 1e12 ? r * 1000 : r) : r).toISOString() : "see claude-usage";
    const wake = (five?.used_percentage ?? 0) >= 75 ? ` → make sure a send_later wake-up exists for ~2 min after the reset (${when})` : "";
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
