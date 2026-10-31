#!/usr/bin/env -S bun
// multibot: ONE shared test game / lobby with a host plus N joining bot machines, all headless on this computer
// (Simon, 2026-10-24: "When testing you should be able to have multiple test bots join a single game with each
// other"). Each machine is its own `godot-test` process (real controllers hidden, idle priority via test-throttle)
// with its own user data, all on one private random DUO_PORT (never 7777: the lobby's and games' LAN beacons stay
// on the private port too). Every machine runs the SAME scene (so node paths match) and its own copy of the bot.
//
//   tools/multibot.ts res://tests/arcade_lobby_bot.tscn               # host + 3 joiners
//   tools/multibot.ts -n 5 --seconds 150 res://tests/balloon_pop_bot.tscn
//   tools/multibot.ts -n 3 --env BOT_PLAYERS=2 --host-env DUO_FLAT_HOST=1 res://tests/engine_template_bot.tscn
//   options: -n/--joiners N (1..6, default 3)  --seconds S (per-process timeout, default 180: bots end by themselves, tests/bot_end.gd)  --project DIR (default:
//   this repo)  --env K=V (every machine)  --host-env K=V  --join-env K=V  --stagger MS (between starts, default 1500)
//   --json (machine-readable result on the last line)  --copies (each machine runs its OWN copy of the project, in
//   /tmp/multibot-<port>/p<k>, like real machines: a bot may change files in it to simulate a deploy reaching that
//   machine; env BOT_OWN_COPY=1 tells the bot it may)  --late S (the LAST joiner starts S seconds after the others: a
//   machine joining a game already running; it gets BOT_LATE=S and a deadline S shorter, so it still leaves before
//   the host)  --expect-late KIND,KIND (default with --late: story) the late joiner must catch up on these sticky
//   events (core/net.gd sticky_event: "Net: got <kind> <ms> ms after joining" within 4 s), or it FAILs. Needs a bot
//   whose host stays long enough (bubble_bath_bot's host finishes at 38 s, before a late joiner's checks: use
//   snowball_blitz / dragon_rider / rocket_workshop bots)
//
// What each machine gets (env): DUO_PORT (shared), DUO_HOST=1 (machine 0) or DUO_JOIN=127.0.0.1 (the rest),
// BOT_MACHINE=k (0 = host), BOT_MACHINES=N+1, BOT_GROUP_T0=<unix ms> (a shared clock: every machine has been started
// and has had a few seconds to load by then, so bots can schedule inputs on the same timeline), XDG_DATA_HOME (own
// user://), DUO_MACHINE_KIND=tv unless given, BOT_DEADLINE=<--seconds> (tests/bot_end.gd ends a bot early enough for it).
//
// Pass per machine (the same rule as brepl dev.bots.run, docs/GAME_DEV_GUIDE.md "Testing"): exit 0 (the bot quit by
// itself: not the timeout, not a crash), no SCRIPT ERROR, no "BOT ASSERT FAILED" / "BOT RESULT: FAIL" / "Bot ... FAIL"
// line, and a "BOT RESULT:" line (if any) says PASS.
// Group check: a bot may print "BOT AGREE <key>=<value>" lines; every machine must print each key, with the SAME
// value as every other machine (e.g. the arcade selection all machines settled on, the game they all started).
// Logs: /tmp/multibot-<port>/m<k>.log (kept for 2 days: each run prunes older ones; 291 had piled up by 2026-10-30). Exit code 0 when every machine and every AGREE key passes.
import { spawn } from "node:child_process";
import { createSocket } from "node:dgram";
import { createServer } from "node:net";
import { access, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

export type MachineResult = { machine: string; pass: boolean; code: number; result: string; failed: string[]; errors: string[];
  agree: Record<string, string>; log: string };
export type GroupResult = { pass: boolean; port: number; scene: string; machines: MachineResult[]; agree: Record<string, { ok: boolean; values: string[] }>;
  table: string };

// The one shared pass rule for a bot's output (brepl dev.bots.run imports it too).
const FAIL = /BOT ASSERT FAILED: (.*)|^Bot:? .*\bFAIL\b:? ?(.*)|BOT RESULT: FAIL(.*)/gm;
/** Engine errors our own scripts caused (the GDScript backtrace starts in res://, not an addon), e.g. reading
 *  global_transform of a node outside the tree: they print "ERROR:" not "SCRIPT ERROR" but are bugs all the same. */
const ENGINE_ERR = /^ERROR: ([^\n]*)\n\s+at: [^\n]*\n\s+GDScript backtrace[^\n]*\n\s+\[0\] ([^\n]*\(res:\/\/(?!addons\/)[^\n]*\))/gm;
export function engineErrors(out: string): string[] {
  return [...new Set([...out.matchAll(ENGINE_ERR)].map(m => `${m[1].trim()} @ ${m[2].trim()}`))];
}
export function verdict(out: string, code: number) {
  const engine = engineErrors(out);
  return {
    pass: code === 0 && !/SCRIPT ERROR(?!: BOT)/.test(out) && !engine.length && !out.match(FAIL) && (!/BOT RESULT:/.test(out) || /BOT RESULT: PASS/.test(out)),
    result: out.match(/BOT RESULT: .*/)?.[0] ?? (code === 0 ? "ran to the end with NO BOT RESULT (cut off at the frame limit: tests/bot_kit.gd reports at --quit-after; others need a short mode)" : code === 124 ? "timed out: the bot never ended by itself (arm tests/bot_end.gd in its _ready, or bot_kit finish()) or needs more --seconds" : `exit ${code} (crashed?)`),
    failed: [...out.matchAll(FAIL)].map(m => (m[1] ?? m[2] ?? m[3] ?? m[0]).trim()),
    errors: [...new Set([...out.matchAll(/SCRIPT ERROR: (?!BOT )(.*)\n\s*at: (.*)/g)].map(m => `${m[1]} @ ${m[2]}`)), ...engine.map(e => `ERROR: ${e}`)].slice(0, 8),
  };
}

const udpFree = (port: number) => new Promise<boolean>(res => {
  const s = createSocket("udp4");
  s.once("error", () => res(false));
  s.bind(port, () => s.close(() => res(true)));
});
const tcpFree = (port: number) => new Promise<boolean>(res => {
  const s = createServer();
  s.once("error", () => res(false));
  s.listen(port, () => s.close(() => res(true)));
});

/** A random private port in 20000-29999 whose port, port+1 (arcade lobby) and port+2 (LAN beacons) are free. */
export async function freePort(): Promise<number> {
  for (let i = 0; i < 200; i++) {
    const p = 20000 + Math.floor(Math.random() * 9990);
    let ok = true;
    for (const q of [p, p + 1, p + 2]) ok = ok && (await udpFree(q)) && (await tcpFree(q));
    if (ok) return p;
  }
  throw new Error("no free port");
}

async function waitForMemory(gb: number) {
  for (let i = 0; i < 90; i++) {
    const mem = await readFile("/proc/meminfo", "utf8");
    if (parseInt(mem.match(/MemAvailable:\s+(\d+)/)?.[1] ?? "0") / 1048576 >= gb) return;
    if (i === 0) console.error(`multibot: waiting for ${gb} GB of free memory (family games first)`);
    await Bun.sleep(2000);
  }
  throw new Error(`not enough free memory for ${gb} GB of test games`);
}

export type GroupOpts = { scene: string; joiners?: number; seconds?: number; project?: string; env?: Record<string, string>;
  hostEnv?: Record<string, string>; joinEnv?: Record<string, string>; stagger?: number; quiet?: boolean; copies?: boolean;
  late?: number; expectLate?: string[] };

/** A machine that joins late must get each expected sticky event (core/net.gd) this soon after joining. */
export const LATE_CATCHUP_MS = 4000;
/** Why a late joiner's log fails the catch-up check (empty: it passed). */
export function lateCheck(out: string, kinds: string[]): string[] {
  if (!/Net: joined the host/.test(out)) return ["late joiner never joined the host"];
  const bad: string[] = [];
  for (const k of kinds) {
    const ms = out.match(new RegExp(`Net: got ${k} (-?\\d+) ms after joining`))?.[1];
    if (ms === undefined) bad.push(`late joiner never got the "${k}" event (sticky replay, core/net.gd)`);
    else if (Number(ms) > LATE_CATCHUP_MS) bad.push(`late joiner got "${k}" only ${ms} ms after joining (a re-send, not the join replay)`);
  }
  return bad;
}

/** Remove /tmp/multibot-* run folders older than 2 days (logs + --copies project copies), so they never pile up. */
async function pruneOldRuns(maxAgeMs = 2 * 86400_000) {
  for (const f of await readdir("/tmp").catch(() => [] as string[])) {
    if (!/^multibot-\d+$/.test(f)) continue;
    const p = join("/tmp", f);
    const st = await stat(p).catch(() => null);
    if (st && Date.now() - st.mtimeMs > maxAgeMs) await rm(p, { recursive: true, force: true }).catch(() => {});
  }
}

export async function runGroup(o: GroupOpts): Promise<GroupResult> {
  const joiners = Math.max(1, Math.min(6, o.joiners ?? 3));
  const project = resolve(o.project ?? join(dirname(import.meta.path), ".."));
  const scene = o.scene.startsWith("res://") ? o.scene : `res://${o.scene}`;
  const stagger = o.stagger ?? 1500;
  await waitForMemory(0.6 * (joiners + 1) + 1.5);
  if (!(await access(join(project, ".godot/imported")).then(() => true, () => false)))
    throw new Error(`${project} was never imported: run  godot-test --headless --path ${project} --import  first`);
  const port = await freePort();
  const dir = `/tmp/multibot-${port}`;
  await mkdir(dir, { recursive: true });
  await pruneOldRuns();
  const t0 = Date.now() + joiners * stagger + 5000;
  const late = Math.max(0, o.late ?? 0);
  const seconds = o.seconds ?? 180;
  if (late && seconds - late < 60) throw new Error(`--late ${late} leaves the late joiner under 60 s of its --seconds ${seconds}`);
  const expectLate = late ? (o.expectLate?.length ? o.expectLate : ["story"]) : [];
  const names = ["host", ...Array.from({ length: joiners }, (_, i) => `join${i + 1}${late && i + 1 === joiners ? "(late)" : ""}`)];
  const log = (s: string) => { if (!o.quiet) console.error(s); };
  log(`multibot: ${scene}, host + ${joiners} on DUO_PORT ${port}, logs in ${dir}`);
  const runs: Promise<MachineResult>[] = [];
  for (let k = 0; k <= joiners; k++) {
    if (k > 0) await Bun.sleep(stagger);
    const isLate = late > 0 && k === joiners;
    if (isLate) { log(`multibot: join${k} joins ${late} s late`); await Bun.sleep(late * 1000); }
    const mySeconds = isLate ? seconds - late : seconds;
    const data = join(dir, `m${k}`);
    await mkdir(data, { recursive: true });
    const env: Record<string, string> = {
      ...(process.env as Record<string, string>), DUO_MACHINE_KIND: "tv", ...o.env, ...(k === 0 ? o.hostEnv : o.joinEnv),
      DUO_PORT: String(port), BOT_DEADLINE: String(mySeconds), BOT_MACHINE: String(k), BOT_MACHINES: String(joiners + 1), BOT_GROUP_T0: String(t0),
      XDG_DATA_HOME: data, ...(isLate ? { BOT_LATE: String(late) } : {}),
    };
    delete env.DUO_SOLO;
    if (k === 0) { env.DUO_HOST = "1"; delete env.DUO_JOIN; } else { env.DUO_JOIN = "127.0.0.1"; delete env.DUO_HOST; }
    const file = join(dir, `m${k}.log`);
    let path = project;
    if (o.copies) {
      path = join(dir, `p${k}`);
      const cp = Bun.spawnSync(["rsync", "-a", "--exclude", ".git", "--exclude", ".dev", `${project}/`, `${path}/`]);
      if (cp.exitCode !== 0) throw new Error(`copying the project for machine ${k} failed: ${cp.stderr}`);
      env.BOT_OWN_COPY = "1";
    }
    runs.push(new Promise(res => {
      const p = spawn("timeout", [String(mySeconds), "godot-test", "--headless", "--path", path, scene], { env, cwd: path });  // never a deleted cwd
      let out = "";
      p.stdout.on("data", d => { out += d; });
      p.stderr.on("data", d => { out += d; });
      p.on("close", async code => {
        await writeFile(file, out);
        const v = verdict(out, code ?? 1);
        if (isLate) {
          const bad = lateCheck(out, expectLate);
          if (bad.length) { v.pass = false; v.failed.push(...bad); v.result += " (late-join catch-up FAILED)"; }
          else v.result += ` (late join: got ${expectLate.join(", ")})`;
        }
        const agree: Record<string, string> = {};
        for (const m of out.matchAll(/^BOT AGREE (\S+?)=(.*)$/gm)) agree[m[1]] = m[2].trim();
        log(`multibot: ${names[k]} ${v.pass ? "ok" : "FAIL"} (${v.result})`);
        res({ machine: names[k], code: code ?? 1, ...v, agree, log: file });
      });
    }));
  }
  const machines = await Promise.all(runs);
  const keys = new Set(machines.flatMap(m => Object.keys(m.agree)));
  const agree: GroupResult["agree"] = {};
  for (const key of keys) {
    const values = machines.map(m => m.agree[key] ?? "(missing)");
    agree[key] = { ok: values.every(v => v === values[0] && v !== "(missing)"), values };
  }
  const pass = machines.every(m => m.pass) && Object.values(agree).every(a => a.ok);
  const lines = machines.map(m => `${m.pass ? "ok  " : "FAIL"} ${m.machine.padEnd(6)} ${m.result}` +
    (m.failed.length ? `\n       failed: ${m.failed.join(" | ")}` : "") + (m.errors.length ? `\n       errors: ${m.errors.join(" | ")}` : "") +
    `\n       log: ${m.log}`);
  for (const [k, a] of Object.entries(agree)) lines.push(`${a.ok ? "ok  " : "FAIL"} agree  ${k}: ${a.values.join(" / ")}`);
  lines.push(pass ? "MULTIBOT PASS" : "MULTIBOT FAIL");
  return { pass, port, scene, machines, agree, table: lines.join("\n") };
}

if (import.meta.main) {
  const a = process.argv.slice(2);
  const o: GroupOpts = { scene: "", env: {}, hostEnv: {}, joinEnv: {} };
  let json = false;
  const kv = (s: string, into: Record<string, string>) => { const i = s.indexOf("="); into[s.slice(0, i)] = s.slice(i + 1); };
  for (let i = 0; i < a.length; i++) {
    const x = a[i];
    if (x === "-n" || x === "--joiners") o.joiners = Number(a[++i]);
    else if (x === "--seconds") o.seconds = Number(a[++i]);
    else if (x === "--project") o.project = a[++i];
    else if (x === "--stagger") o.stagger = Number(a[++i]);
    else if (x === "--env") kv(a[++i], o.env!);
    else if (x === "--host-env") kv(a[++i], o.hostEnv!);
    else if (x === "--join-env") kv(a[++i], o.joinEnv!);
    else if (x === "--json") json = true;
    else if (x === "--copies") o.copies = true;
    else if (x === "--late") o.late = Number(a[++i]);
    else if (x === "--expect-late") o.expectLate = a[++i].split(",").filter(Boolean);
    else if (x === "-h" || x === "--help") { console.log((await readFile(import.meta.path, "utf8")).split("\nimport")[0]); process.exit(0); }
    else o.scene = x;
  }
  if (!o.scene) { console.error("usage: tools/multibot.ts [-n joiners] [--seconds S] [--env K=V] res://tests/<bot>.tscn"); process.exit(2); }
  const r = await runGroup(o);
  console.log(r.table);
  if (json) console.log(JSON.stringify({ pass: r.pass, port: r.port, machines: r.machines, agree: r.agree }));
  process.exit(r.pass ? 0 : 1);
}
