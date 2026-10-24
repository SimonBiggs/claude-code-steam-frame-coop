// dev.ts: Claude's dev-loop helpers, preloaded in brepl as `dev` (Simon, 2026-10-24: "pull in a bunch of
// dev loop tooling into your brepl"). Everything returns data (or image paths, which the brepl MCP tool
// shows as pictures). dev.help() lists it all.
import { $ } from "bun";
import { mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";

const HOME = process.env.HOME!;
const GP = join(HOME, "GodotProjects");
const LIVE = join(GP, "duo-arena");
const STAGE = join(GP, ".duo-arena-stage");
const BIN = join(HOME, ".local/bin");
const DEPLOYED = ["core", "games", "arcade", "tests"];  // what duo-deploy copies stage -> live
const TOOL_COPIES: Record<string, string> = {  // installed file -> repo copy (keep in sync)
  [join(BIN, "gdev")]: "tools/gdev", [join(HOME, ".local/share/gdev/bridge.gd")]: "tools/gdev-bridge.gd",
  [join(HOME, ".local/share/gdev/control.gd")]: "tools/control.gd", [join(HOME, ".local/share/gdev/godot.ts")]: "tools/godot.ts",
  [join(BIN, "brepl")]: "tools/brepl", [join(BIN, "duo-deploy")]: "tools/duo-deploy", [join(BIN, "merge-game")]: "tools/merge-game",
  [join(BIN, "voice-bridge")]: "tools/voice-bridge", [join(BIN, "claude-watchdog")]: "tools/claude-watchdog",
  [join(HOME, ".local/share/gdev/recsheet.py")]: "tools/recsheet.py", [join(HOME, ".local/share/brepl/dev.ts")]: "tools/brepl-dev.ts",
  [join(HOME, ".local/share/brepl/mcp.ts")]: "tools/brepl-mcp.ts", [join(HOME, ".local/share/brepl/alerts.ts")]: "tools/brepl-alerts.ts",
  [join(HOME, ".config/systemd/user/brepl.service")]: "tools/systemd/brepl.service", [join(BIN, "frame-at")]: "tools/frame-at", [join(BIN, "duo-deploy-frame")]: "tools/duo-deploy-frame",
};

/** Run a shell command: {code, out} (stdout+stderr, trimmed). Never throws. */
export async function sh(cmd: string, cwd = HOME) {
  const r = await $`bash -c ${cmd}`.cwd(cwd).nothrow().quiet();
  return { code: r.exitCode, out: (r.stdout.toString() + r.stderr.toString()).trim() };
}
const lastPath = async (out: string) => {
  for (const l of out.split("\n").map(l => l.trim()).reverse()) if (/\.(jpe?g|png)$/i.test(l) && (await Bun.file(l).exists())) return l;
};

// --- Bot tests (headless, in the staging copy, at low priority) ------------------------------------

export const bots = {
  /** Game ids that have a bot test. */
  async list(): Promise<string[]> {
    return (await readdir(join(STAGE, "tests"))).filter(f => f.endsWith("_bot.tscn")).map(f => f.replace(/_bot\.tscn$/, "")).sort();
  },
  /** Run one bot test. net: also run it as host + client over a local port. Returns pass/fail, failed checks, errors. */
  async run(id: string, o: { net?: boolean; seconds?: number } = {}) {
    const t0 = Date.now();
    const scene = `res://tests/${id}_bot.tscn`;
    const one = async (env: Record<string, string>, extra = "") => {
      const r = await $`nice -n 19 timeout ${o.seconds ?? 150} godot --headless --path ${STAGE} ${{ raw: extra }} ${scene}`.env({ ...process.env, ...env }).nothrow().quiet();
      return { out: r.stdout.toString() + r.stderr.toString(), code: r.exitCode };
    };
    // Pass (docs/GAME_DEV_GUIDE.md "Testing"): it ran to the end (exit 0, not killed by timeout or a crash), no
    // SCRIPT ERROR, and no FAIL line. Only a few bots print "BOT RESULT: ..."; when one does, it must say PASS.
    const FAIL = /BOT ASSERT FAILED: (.*)|^Bot:? .*\bFAIL\b:? ?(.*)|BOT RESULT: FAIL(.*)/gm;
    const parse = ({ out, code }: { out: string; code: number }, mode: string) => ({
      mode,
      pass: code === 0 && !/SCRIPT ERROR(?!: BOT)/.test(out) && !out.match(FAIL) && (!/BOT RESULT:/.test(out) || /BOT RESULT: PASS/.test(out)),
      result: out.match(/BOT RESULT: .*/)?.[0] ?? (code === 0 ? "ran to the end" : code === 124 ? "timed out" : `exit ${code} (crashed?)`),
      failed: [...out.matchAll(FAIL)].map(m => (m[1] ?? m[2] ?? m[3] ?? m[0]).trim()),
      errors: [...new Set([...out.matchAll(/SCRIPT ERROR: (?!BOT )(.*)\n\s*at: (.*)/g)].map(m => `${m[1]} @ ${m[2]}`))].slice(0, 8),
    });
    const runs = [parse(await one({}, "--fixed-fps 60 --quit-after 3600"), "local")];
    if (o.net) {
      const port = String(27000 + Math.floor(Math.random() * 2000));
      const host = one({ DUO_PORT: port, DUO_HOST: "1" });
      await Bun.sleep(3000);
      const client = one({ DUO_PORT: port, DUO_JOIN: "127.0.0.1" });
      const [h, c] = await Promise.all([host, client]);
      runs.push(parse(h, "host"), parse(c, "client"));
    }
    return { id, pass: runs.every(r => r.pass), secs: Math.round((Date.now() - t0) / 1000), runs };
  },
  /** Run many (default all) bot tests, `concurrency` at a time. Returns {pass, fail: [...details], table}. */
  async all(o: { only?: string[]; net?: boolean; concurrency?: number } = {}) {
    const ids = o.only ?? (await bots.list());
    const results: any[] = [];
    let next = 0;
    await Promise.all(Array.from({ length: o.concurrency ?? 3 }, async () => {
      while (next < ids.length) results.push(await bots.run(ids[next++], { net: o.net }));
    }));
    results.sort((a, b) => a.id.localeCompare(b.id));
    return {
      pass: results.filter(r => r.pass).map(r => r.id),
      fail: results.filter(r => !r.pass),
      table: results.map(r => `${r.pass ? "ok  " : "FAIL"} ${r.id.padEnd(20)} ${r.secs}s`).join("\n"),
    };
  },
};

// --- Staging copy <-> live game ----------------------------------------------------------------

export const stage = {
  /** Files that differ between staging and live (deployed folders), split by which side is newer. */
  async diff() {
    const r = await sh(`for d in ${DEPLOYED.join(" ")}; do diff -rq --exclude='*.uid' ${STAGE}/$d ${LIVE}/$d; done; cmp -s ${STAGE}/arcade.tscn ${LIVE}/arcade.tscn || echo "Files ${STAGE}/arcade.tscn and ${LIVE}/arcade.tscn differ"`);
    const liveNewer: string[] = [], stageNewer: string[] = [], onlyLive: string[] = [], onlyStage: string[] = [];
    for (const l of r.out.split("\n").filter(Boolean)) {
      let m = l.match(/^Files (\S+) and (\S+) differ/);
      if (m) { ((await stat(m[2])).mtimeMs > (await stat(m[1])).mtimeMs ? liveNewer : stageNewer).push(m[1].slice(STAGE.length + 1)); continue; }
      m = l.match(/^Only in (\S+): (.*)/);
      if (m) (m[1].startsWith(STAGE) ? onlyStage : onlyLive).push(join(m[1], m[2]).replace(/^.*?(duo-arena-stage|duo-arena)\//, ""));
    }
    return { inSync: !liveNewer.length && !stageNewer.length && !onlyLive.length && !onlyStage.length, liveNewer, stageNewer, onlyLive, onlyStage };
  },
  /** Copy live -> staging (after merging agent work into live). */
  async pull() {
    return sh(DEPLOYED.map(d => `rsync -a --exclude '*.uid' ${LIVE}/${d}/ ${STAGE}/${d}/`).join(" && "));
  },
  /** duo-deploy: staging -> live + Frame, commit, push. */
  deploy(message: string) { return sh(`duo-deploy ${JSON.stringify(message)}`); },
};

// --- The game running on the TV (gdev) ---------------------------------------------------------------

export const live = {
  status: () => sh("gdev status"),
  start: (project = "duo-arena") => sh(`gdev start ${join(GP, project)}`),
  stop: () => sh("gdev stop"),
  restart: (hard = false) => sh(`gdev restart${hard ? " --hard" : ""}`),
  log: async (n = 40, errorsOnly = false) => (await sh(`gdev log -n ${n}${errorsOnly ? " -e" : ""}`)).out,
  /** Screenshot of the running game: image path. */
  shot: async () => (await lastPath((await sh("gdev shot")).out)) ?? (await sh("gdev shot")).out,
  /** Frames + change maps around TIME (HH:MM:SS or -30s). */
  at: async (time: string, o: { span?: number; count?: number } = {}) => {
    const r = await sh(`gdev at ${time}${o.span ? ` --span ${o.span}` : ""}${o.count ? ` --count ${o.count}` : ""}`);
    return (await lastPath(r.out)) ?? r.out;
  },
};

// --- Whole TV screen, Steam Frame, room ----------------------------------------------------------------

export const screen = {
  /** Contact sheet of the TV screen ending at TIME (HH:MM:SS or -10s). Needs screen-rec running. */
  at: async (time: string, n = 6) => { const r = await sh(`screen-rec at ${time} ${n}`); return (await lastPath(r.out)) ?? r.out; },
  range: async (from: string, to: string, every = "") => { const r = await sh(`screen-rec range ${from} ${to} ${every}`); return (await lastPath(r.out)) ?? r.out; },
};
export const frame = {
  /** What the Steam Frame headset showed around TIME. */
  at: async (time: string, o: { before?: number; after?: number; count?: number } = {}) => {
    const r = await sh(`frame-at ${time}${o.before ? ` --before ${o.before}` : ""}${o.after ? ` --after ${o.after}` : ""}${o.count ? ` --count ${o.count}` : ""}`);
    return (await lastPath(r.out)) ?? r.out;
  },
  online: async () => (await sh("ssh -o ConnectTimeout=3 -o BatchMode=yes -i ~/.config/steamos-devkit/devkit_rsa steamos@frame true")).code === 0,
};

const VOICE_LOG = join(LIVE, ".dev/voice.log");
export const voice = {
  /** Last n transcript lines. */
  tail: async (n = 20) => (await readFile(VOICE_LOG, "utf8")).trimEnd().split("\n").slice(-n),
  /** Transcript lines since HH:MM[:SS] today. */
  since: async (time: string) => (await readFile(VOICE_LOG, "utf8")).split("\n").filter(l => (l.match(/^\[(\d\d:\d\d:\d\d)\]/)?.[1] ?? "") >= time.padEnd(8, ":00").slice(0, 8)),
  /** Speak on the TV (text only unless audio). */
  say: (text: string, audio = false) => sh(`${audio ? "CLAUDE_SAY_AUDIO=1 " : ""}claude-say ${JSON.stringify(text)}`),
  /** Is a mic plugged in and is the bridge transcribing? */
  health: async () => ({
    mic: !!(await sh("arecord -l | grep -q card && echo y")).out,
    bridge: (await sh("systemctl --user is-active voice-bridge")).out,
    lastLine: (await voice.tail(1))[0],
  }),
};

// --- Usage pacing, backlog, history -----------------------------------------------------------------

/** claude-pace as data: used %, ideal %, recommended agents. */
export async function pace() {
  const out = (await sh("claude-pace")).out;
  const win = (name: string) => {
    const m = out.match(new RegExp(`${name}: (\\d+)% used, (\\d+) min to reset, ideal now (\\d+)%`));
    return m ? { used: +m[1], minToReset: +m[2], ideal: +m[3] } : null;
  };
  return { fiveHour: win("5-hour"), weekly: win("weekly"), agents: +(out.match(/RECOMMENDED AGENTS: (\d+)/)?.[1] ?? 0), raw: out };
}

const BACKLOG = join(GP, ".backlog.md");
export const backlog = {
  open: async () => (await readFile(BACKLOG, "utf8")).split("\n").filter(l => l.startsWith("- [ ]")).map((l, i) => `${i + 1}. ${l.slice(6)}`),
  /** Tick the first open item containing `match`, with a note. */
  async done(match: string, note = "") {
    const s = await readFile(BACKLOG, "utf8");
    const i = s.split("\n").findIndex(l => l.startsWith("- [ ]") && l.includes(match));
    if (i < 0) throw new Error(`no open item contains "${match}"`);
    const lines = s.split("\n");
    lines[i] = lines[i].replace("- [ ]", `- [x]${note ? ` (${new Date().toISOString().slice(0, 10)}: ${note})` : ""}`);
    await writeFile(BACKLOG, lines.join("\n"));
    return lines[i].slice(0, 160);
  },
  async add(text: string) { await writeFile(BACKLOG, (await readFile(BACKLOG, "utf8")).trimEnd() + `\n- [ ] ${text}\n`); return (await backlog.open()).length; },
};

/** Full-text search over every past Claude session on this machine. */
export const history = async (query: string, n = 10) => (await sh(`claude-history search ${JSON.stringify(query)} -n ${n}`)).out;

// --- Tech-debt scan (Simon's rule: fix debt the moment it's found) -----------------------------------

/** Everything that needs tidying: unmerged finished branches, stale worktrees, uncommitted work, staging drift,
 *  tool copies out of sync, broken services. Returns {clean, issues: [{kind, what, fix}]}. */
export async function debt() {
  const issues: { kind: string; what: string; fix: string }[] = [];
  const repos: string[] = [];
  for (const d of await readdir(GP)) if ((await stat(join(GP, d, ".git")).catch(() => null))?.isDirectory()) repos.push(d);
  for (const r of repos) {
    const dir = join(GP, r);
    const dirty = (await sh("git status --porcelain | grep -v '\\.uid$'", dir)).out;
    if (dirty) issues.push({ kind: "uncommitted", what: `${r}: ${dirty.split("\n").length} changed files (${dirty.split("\n").slice(0, 3).map(l => l.replace(/^\s*\S+\s+/, "")).join(", ")})`, fix: "commit or discard" });
    const ahead = (await sh("git rev-list --count @{u}..HEAD 2>/dev/null", dir)).out;
    if (+ahead > 0) issues.push({ kind: "unpushed", what: `${r}: ${ahead} commits not pushed`, fix: "git push" });
    const main = (await sh("git symbolic-ref --short HEAD", dir)).out;
    for (const b of (await sh(`git branch --format='%(refname:short)' --no-merged ${main}`, dir)).out.split("\n").filter(Boolean)) {
      const n = (await sh(`git rev-list --count ${main}..${b}`, dir)).out;
      const age = (await sh(`git log -1 --format=%cr ${b}`, dir)).out;
      issues.push({ kind: "unmerged", what: `${r}: branch ${b} is ${n} commits ahead (${age})`, fix: "merge if finished, else leave parked" });
    }
    for (const w of (await sh("git worktree list --porcelain", dir)).out.split("\n\n").slice(1)) {
      const path = w.match(/^worktree (.*)$/m)?.[1], br = w.match(/^branch refs\/heads\/(.*)$/m)?.[1];
      if (!path || !br) continue;
      const merged = (await sh(`git merge-base --is-ancestor ${br} ${main} && echo y`, dir)).out === "y";
      if (merged) issues.push({ kind: "stale-worktree", what: `${r}: worktree ${path} (branch ${br} already merged)`, fix: `git worktree remove --force ${path} && git branch -D ${br}` });
    }
  }
  const d = await stage.diff();
  if (d.liveNewer.length || d.onlyLive.length) issues.push({ kind: "stage-behind", what: `live has newer files than staging: ${[...d.liveNewer, ...d.onlyLive].slice(0, 5).join(", ")}`, fix: "dev.stage.pull()" });
  if (d.stageNewer.length || d.onlyStage.length) issues.push({ kind: "undeployed", what: `staging has changes not deployed: ${[...d.stageNewer, ...d.onlyStage].slice(0, 5).join(", ")}`, fix: "test, then dev.stage.deploy(msg)" });
  for (const [src, rel] of Object.entries(TOOL_COPIES)) {
    const repo = join(LIVE, rel);
    const [a, b] = await Promise.all([readFile(src).catch(() => null), readFile(repo).catch(() => null)]);
    if (a && b && !a.equals(b))
      issues.push({ kind: "tool-copy", what: `${rel} differs from ${src.replace(HOME, "~")}`, fix: `cp ${src} ${repo} and commit` });
  }
  for (const s of ["voice-bridge", "claude-watchdog.timer"]) {
    const st = (await sh(`systemctl --user is-active ${s}`)).out;
    if (st !== "active") issues.push({ kind: "service", what: `${s} is ${st}`, fix: `systemctl --user status ${s}` });
  }
  const oom = (await sh("journalctl --since today 2>/dev/null | grep -i earlyoom | grep -i -c -E 'sending SIG(TERM|KILL) to'")).out;
  if (+oom > 0) issues.push({ kind: "oom", what: `earlyoom killed ${oom} processes today`, fix: "journalctl | grep earlyoom" });
  const leftovers = (await sh("pgrep -f '^gamescope --[b]ackend headless' | wc -l")).out;
  const ours = ((globalThis as any).godot?.list ? (globalThis as any).godot : await import(`${HOME}/.local/share/gdev/godot.ts`)).list().length;  // the preloaded one (reload() makes a new module)
  if (+leftovers > ours) issues.push({ kind: "orphan", what: `${+leftovers - ours} offscreen game(s) not owned by this brepl`, fix: "pkill -f '[b]ackend headless'" });
  return { clean: issues.length === 0, issues };
}

export function help() {
  return `dev — Claude's dev loop (brepl). Image paths returned/shown come back as pictures via the brepl MCP tool.
  dev.debt()                         tech-debt scan: {clean, issues:[{kind, what, fix}]} (fix them straight away)
  dev.bots.list() / .run(id, {net}) / .all({only, net, concurrency})   headless bot tests in staging
  dev.stage.diff() / .pull() / .deploy(msg)                            staging <-> live game
  dev.live.status() / start(proj) / stop() / restart(hard) / log(n, errorsOnly) / shot() / at("-30s", {span})   game on the TV (gdev)
  dev.screen.at("-10s") / .range(a, b)     TV screen recorder     dev.frame.at(t) / .online()   Steam Frame
  dev.voice.tail(n) / .since("14:30") / .say(text, audio) / .health()
  dev.pace()  dev.backlog.open() / .done(match, note) / .add(text)  dev.history(query)  dev.sh(cmd, cwd)
  godot.launch(project) -> g: offscreen run (see godot.ts header): g.uiText() g.joy() g.eval() g.at() g.span() g.video()
  show(...paths)                     hand images back with the result`;
}

// --- Sweep: play every game offscreen and collect what's wrong (Simon, 2026-10-24: "use this to reliably
// debug the full set of games") ----------------------------------------------------------------------
const SWEEP = join(HOME, ".cache/sweep");
const MONKEY: [string, Record<string, number>?][] = [  // a scripted "kid with a controller": every input, in turn
  ["a"], ["lx", { value: 1, frames: 40 }], ["a"], ["ly", { value: -1, frames: 40 }], ["x"], ["lx", { value: -1, frames: 40 }],
  ["b"], ["rt", { value: 1, frames: 20 }], ["ly", { value: 1, frames: 40 }], ["y"], ["rx", { value: 1, frames: 30 }],
  ["lt", { value: 1, frames: 20 }], ["a"], ["rb"], ["lb"], ["ry", { value: -1, frames: 30 }], ["a", { frames: 30 }],
];
/** Offscreen runs of the games (default: all) from the staging copy, many in parallel (Simon: "headlessly test
 *  many of the games in parallel"): monkey inputs for `seconds` while recording at 30 fps, then per game
 *  {id, ok, problems[], errors[], fps, sound, frozen, sheets[]}, also written to ~/.cache/sweep/<id>.json and
 *  posted to the channel as each finishes. Long: run it in bg(). */
export async function sweep(o: { only?: string[]; seconds?: number; concurrency?: number; vr?: boolean } = {}) {
  const ids = o.only ?? (await readdir(join(STAGE, "games"))).filter(d => d !== "engine_template").sort();
  await mkdir(SWEEP, { recursive: true });
  const results: any[] = [];
  let next = 0;
  const n = o.concurrency ?? await parallelGames();
  (globalThis as any).send?.("sweep", `${ids.length} games, ${n} at a time`);
  await Promise.all(Array.from({ length: n }, async () => {
    while (next < ids.length) {
      const r = await sweepOne(ids[next++], o.seconds ?? 20, !!o.vr);
      results.push(r);
      await Bun.write(join(SWEEP, `${r.id}${o.vr ? "-vr" : ""}.json`), JSON.stringify(r, null, 1));
      (globalThis as any).send?.(`sweep ${r.id}`, (r.ok ? "ok" : r.problems.join("\n")) + `\nsheets: ${r.sheets.join(" ")}`);  // text only: show() the sheets when reviewing
    }
  }));
  results.sort((a, b) => a.id.localeCompare(b.id));
  return { ok: results.filter(r => r.ok).map(r => r.id), bad: results.filter(r => !r.ok).map(r => `${r.id}: ${r.problems.join("; ")}`) };
}

/** How many offscreen games fit at once: ~1 GB of free memory each (keeping 2 GB spare), at most one per 2 CPU
 *  threads, max 6; at most 2 while someone is playing a game on the TV so theirs stays smooth. */
export async function parallelGames() {
  const mem = Object.fromEntries((await readFile("/proc/meminfo", "utf8")).split("\n").map(l => l.split(/:\s+/)).map(([k, v]) => [k, parseInt(v) / 1048576]));
  let n = Math.max(1, Math.min(6, Math.floor(mem.MemAvailable - 2), Math.floor(navigator.hardwareConcurrency / 2)));
  // Someone playing on the TV (a game in Steam/Proton, or a Godot game not run by us): keep to 2.
  const tv = (await sh("pgrep -af 'godot|\\.exe|steamapps/common' | grep -v -e headless -e gamescope -e pgrep -e steamwebhelper")).out;
  if (tv) n = Math.min(n, 2);
  return n;
}

// vr: the game's VR player in fake VR too (BOT_VR=1): it looks around, swings both hands and pulls the trigger
// while the TV pad mashes, and the sheets include the headset view (span-vr-*).
async function sweepOne(id: string, seconds: number, vr = false) {
  const godot = (globalThis as any).godot;
  const r: any = { id, ok: false, problems: [] as string[], errors: [] as string[], fps: 0, sound: false, frozen: false, sheets: [] as string[] };
  let g: any;
  try {
    g = await godot.launch({ project: STAGE, scene: `res://games/${id}/main.tscn`, vr });
    const head = vr ? (await g.vr().catch(() => null))?.head : null;
    if (vr && !head) r.problems.push("no VR player in fake VR (BOT_VR=1)");
    await Bun.sleep(3000);
    const t0 = Date.now();
    for (let i = 0; Date.now() - t0 < seconds * 1000; i++) {
      const [name, opts] = MONKEY[i % MONKEY.length];
      if (g.child.exitCode !== null) break;
      await g.joy(name, opts ?? {}).catch(() => {});
      if (head && i % 2 === 0) {
        const k = i / 2;
        await g.vr({ look: [head[0] + Math.sin(k) * 3, head[1] + Math.cos(k * 1.3) * 0.5, head[2] - 3] }).catch(() => {});
        await g.vrSwing(k % 2 ? "left" : "right", [0, 0.2, -0.6], 0.15).catch(() => {});
        await g.vr({ trigger: k % 3 === 0 ? 1 : 0, a: k % 4 === 1, stick_l: [Math.sin(k), 0] }).catch(() => {});
        await g.vrSwing(k % 2 ? "left" : "right", [0, -0.2, 0.6], 0.15).catch(() => {});
      }
      await Bun.sleep(400);
    }
    const alive = g.child.exitCode === null;
    if (!alive) r.problems.push(`crashed (exit ${g.child.exitCode})`);
    const log = await Bun.file(g.logPath).text().catch(() => "");
    r.errors = [...new Set([...log.matchAll(/^(SCRIPT ERROR|ERROR|USER ERROR|Parse Error)[^\n]*(\n\s+at:[^\n]*)?/gm)].map(m => m[0].replace(/\s+/g, " ").slice(0, 240)))].slice(0, 12);
    if (r.errors.length) r.problems.push(`${r.errors.length} distinct error(s): ${r.errors[0]}`);
    const fpsLines = [...log.matchAll(/fps (\d+)/g)].map(m => +m[1]);
    r.fps = fpsLines.length ? Math.min(...fpsLines.slice(1)) || fpsLines[0] : 0;
    if (r.fps && r.fps < 45) r.problems.push(`slow: ${r.fps} fps`);
    // Sound: RMS of the Master bus recording after the first 2 s.
    const audio = new Float32Array(await Bun.file(join(g.recDir, "audio.f32")).arrayBuffer().catch(() => new ArrayBuffer(0)));
    const rateTxt = await Bun.file(join(g.recDir, "audio.rate")).text().catch(() => "44100");
    const a = audio.subarray(Math.min(audio.length, 2 * +rateTxt));
    let sum = 0; for (let i = 0; i < a.length; i += 16) sum += a[i] * a[i];
    r.sound = a.length > 0 && Math.sqrt(sum / (a.length / 16)) > 0.002;
    if (!r.sound) r.problems.push("silent (no sound on the Master bus)");
    if (alive) {
      // Text cut off by the screen edge (a classic: set_anchors_preset without resetting the offsets).
      const ui = await g.ui().catch(() => ({ items: [] }));
      const cut = (ui.items ?? []).filter((i: any) => i.text && String(i.text).trim() && i.rect && !String(i.path).includes("/GDev/")
        && (i.rect[0] < -4 || i.rect[1] < -4 || i.rect[0] + i.rect[2] > 1924 || i.rect[1] + i.rect[3] > 1084))
        .map((i: any) => `"${String(i.text).slice(0, 30)}" @${i.rect.map((v: number) => Math.round(v)).join(",")}`);
      if (cut.length) r.problems.push(`text off screen: ${[...new Set(cut)].slice(0, 4).join("; ")}`);
      // Text drawn over other text (e.g. a timer pill on top of a score card).
      // (Labels stretched over most of the screen just centre their text, so their box says nothing: skip them.)
      const labels = (ui.items ?? []).filter((i: any) => i.text && String(i.text).trim() && i.rect && i.rect[2] > 2 && i.rect[3] > 2
        && i.rect[2] * i.rect[3] < 0.25 * 1920 * 1080 && !String(i.path).includes("/GDev/"));
      const over: string[] = [];
      for (let x = 0; x < labels.length; x++) for (let y = x + 1; y < labels.length; y++) {
        const [a, b] = [labels[x], labels[y]];
        if (String(a.path).startsWith(b.path) || String(b.path).startsWith(a.path)) continue;
        const vp = (i: any) => String(i.path).match(/.*SubViewport[^/]*/)?.[0] ?? "";  // split views: own coordinates
        if (vp(a) !== vp(b)) continue;
        const w = Math.min(a.rect[0] + a.rect[2], b.rect[0] + b.rect[2]) - Math.max(a.rect[0], b.rect[0]);
        const h = Math.min(a.rect[1] + a.rect[3], b.rect[1] + b.rect[3]) - Math.max(a.rect[1], b.rect[1]);
        if (w > 0 && h > 0 && w * h > 0.3 * Math.min(a.rect[2] * a.rect[3], b.rect[2] * b.rect[3]))
          over.push(`"${String(a.text).slice(0, 20)}" / "${String(b.text).slice(0, 20)}"`);
      }
      if (over.length) r.problems.push(`overlapping text: ${[...new Set(over)].slice(0, 4).join("; ")}`);
      const fr = await g.frames();
      const end = fr.length ? fr[fr.length - 1].t : 0;
      r.sheets = await g.span(1, end, 12 / Math.max(1, end - 1)).catch((e: any) => { r.problems.push(`span failed: ${e}`); return []; });
      if (head) r.sheets.push(...await g.span(1, end, 12 / Math.max(1, end - 1), { vr: true }).catch(() => []));
      // Frozen: byte-identical JPEGs across the last 5 s mean nothing on screen moved at all.
      const tail = fr.filter((f: any) => f.t > end - 5);
      if (tail.length > 2) {
        const sizes = await Promise.all(tail.map(async (f: any) => (await stat(f.path)).size));
        r.frozen = new Set(sizes).size === 1;
        if (r.frozen) r.problems.push("frozen: nothing changed on screen for 5 s of input");
      }
    }
  } catch (e: any) {
    r.problems.push(`launch failed: ${String(e?.message ?? e).slice(0, 400)}`);
  } finally {
    await g?.quit().catch(() => {});
  }
  r.ok = !r.problems.length;
  return r;
}

/** Arcade card pictures: screenshot each game (default: all in arcade.gd GAMES) offscreen from the staging copy
 *  after a few seconds of play, saved as arcade/thumbs/<id>.jpg (480x270), which the lobby cards load. Run after
 *  adding a game or changing how one looks; deploy with duo-deploy. Long: run it in bg(). */
export async function thumbs(o: { only?: string[] } = {}) {
  const godot = (globalThis as any).godot;
  const src = await readFile(join(STAGE, "arcade/arcade.gd"), "utf8");
  const games = [...src.matchAll(/"id": "(\w+)".*?"scene": "(res:\/\/[^"]+)"/g)].map(m => ({ id: m[1], scene: m[2] }))
    .filter(g => !o.only || o.only.includes(g.id));
  const out = join(STAGE, "arcade/thumbs");
  await mkdir(out, { recursive: true });
  const done: string[] = [], failed: string[] = [];
  let next = 0;
  await Promise.all(Array.from({ length: await parallelGames() }, async () => {
    while (next < games.length) {
      const { id, scene } = games[next++];
      let g: any;
      try {
        g = await godot.launch({ project: STAGE, scene, record: false });
        await Bun.sleep(4000);
        for (const [b, opt] of [["a"], ["lx", { value: 0.7, frames: 30 }], ["a"], ["ly", { value: -0.7, frames: 30 }]] as [string, any?][]) { await g.joy(b, opt ?? {}); await Bun.sleep(600); }
        await Bun.sleep(2500);
        const png = await g.shot(join(out, `${id}.png`), 640);
        await sh(`uv run --quiet --with pillow python -c "from PIL import Image; import sys; Image.open(sys.argv[1]).convert('RGB').resize((480,270)).save(sys.argv[2], quality=82)" '${png}' '${join(out, id + ".jpg")}' && rm -f '${png}'`);
        done.push(id);
      } catch (e) { failed.push(`${id}: ${String(e).slice(0, 160)}`); }
      finally { await g?.quit().catch(() => {}); }
    }
  }));
  return { done: done.length, failed, dir: out };
}
