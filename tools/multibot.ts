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
//   options: -n/--joiners N (1..6, default 3)  --seconds S (per-process timeout, default 120)  --project DIR (default:
//   this repo)  --env K=V (every machine)  --host-env K=V  --join-env K=V  --stagger MS (between starts, default 1500)
//   --json (machine-readable result on the last line)  --copies (each machine runs its OWN copy of the project, in
//   /tmp/multibot-<port>/p<k>, like real machines: a bot may change files in it to simulate a deploy reaching that
//   machine; env BOT_OWN_COPY=1 tells the bot it may)
//
// What each machine gets (env): DUO_PORT (shared), DUO_HOST=1 (machine 0) or DUO_JOIN=127.0.0.1 (the rest),
// BOT_MACHINE=k (0 = host), BOT_MACHINES=N+1, BOT_GROUP_T0=<unix ms> (a shared clock: every machine has been started
// and has had a few seconds to load by then, so bots can schedule inputs on the same timeline), XDG_DATA_HOME (own
// user://), DUO_MACHINE_KIND=tv unless given.
//
// Pass per machine (the same rule as brepl dev.bots.run, docs/GAME_DEV_GUIDE.md "Testing"): exit 0 (the bot quit by
// itself: not the timeout, not a crash), no SCRIPT ERROR, no "BOT ASSERT FAILED" / "BOT RESULT: FAIL" / "Bot ... FAIL"
// line, and a "BOT RESULT:" line (if any) says PASS.
// Group check: a bot may print "BOT AGREE <key>=<value>" lines; every machine must print each key, with the SAME
// value as every other machine (e.g. the arcade selection all machines settled on, the game they all started).
// Logs: /tmp/multibot-<port>/m<k>.log (kept). Exit code 0 when every machine and every AGREE key passes.
import { spawn } from "node:child_process";
import { createSocket } from "node:dgram";
import { createServer } from "node:net";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

export type MachineResult = { machine: string; pass: boolean; code: number; result: string; failed: string[]; errors: string[];
  agree: Record<string, string>; log: string };
export type GroupResult = { pass: boolean; port: number; scene: string; machines: MachineResult[]; agree: Record<string, { ok: boolean; values: string[] }>;
  table: string };

// The one shared pass rule for a bot's output (brepl dev.bots.run imports it too).
const FAIL = /BOT ASSERT FAILED: (.*)|^Bot:? .*\bFAIL\b:? ?(.*)|BOT RESULT: FAIL(.*)/gm;
export function verdict(out: string, code: number) {
  return {
    pass: code === 0 && !/SCRIPT ERROR(?!: BOT)/.test(out) && !out.match(FAIL) && (!/BOT RESULT:/.test(out) || /BOT RESULT: PASS/.test(out)),
    result: out.match(/BOT RESULT: .*/)?.[0] ?? (code === 0 ? "ran to the end" : code === 124 ? "timed out" : `exit ${code} (crashed?)`),
    failed: [...out.matchAll(FAIL)].map(m => (m[1] ?? m[2] ?? m[3] ?? m[0]).trim()),
    errors: [...new Set([...out.matchAll(/SCRIPT ERROR: (?!BOT )(.*)\n\s*at: (.*)/g)].map(m => `${m[1]} @ ${m[2]}`))].slice(0, 8),
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
  hostEnv?: Record<string, string>; joinEnv?: Record<string, string>; stagger?: number; quiet?: boolean; copies?: boolean };

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
  const t0 = Date.now() + joiners * stagger + 5000;
  const names = ["host", ...Array.from({ length: joiners }, (_, i) => `join${i + 1}`)];
  const log = (s: string) => { if (!o.quiet) console.error(s); };
  log(`multibot: ${scene}, host + ${joiners} on DUO_PORT ${port}, logs in ${dir}`);
  const runs: Promise<MachineResult>[] = [];
  for (let k = 0; k <= joiners; k++) {
    if (k > 0) await Bun.sleep(stagger);
    const data = join(dir, `m${k}`);
    await mkdir(data, { recursive: true });
    const env: Record<string, string> = {
      ...(process.env as Record<string, string>), DUO_MACHINE_KIND: "tv", ...o.env, ...(k === 0 ? o.hostEnv : o.joinEnv),
      DUO_PORT: String(port), BOT_MACHINE: String(k), BOT_MACHINES: String(joiners + 1), BOT_GROUP_T0: String(t0),
      XDG_DATA_HOME: data,
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
      const p = spawn("timeout", [String(o.seconds ?? 120), "godot-test", "--headless", "--path", path, scene], { env });
      let out = "";
      p.stdout.on("data", d => { out += d; });
      p.stderr.on("data", d => { out += d; });
      p.on("close", async code => {
        await writeFile(file, out);
        const v = verdict(out, code ?? 1);
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
    else if (x === "-h" || x === "--help") { console.log((await readFile(import.meta.path, "utf8")).split("\nimport")[0]); process.exit(0); }
    else o.scene = x;
  }
  if (!o.scene) { console.error("usage: tools/multibot.ts [-n joiners] [--seconds S] [--env K=V] res://tests/<bot>.tscn"); process.exit(2); }
  const r = await runGroup(o);
  console.log(r.table);
  if (json) console.log(JSON.stringify({ pass: r.pass, port: r.port, machines: r.machines, agree: r.agree }));
  process.exit(r.pass ? 0 : 1);
}
