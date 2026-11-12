// dev.ts: Claude's dev-loop helpers, preloaded in brepl as `dev` (Simon, 2026-10-24: "pull in a bunch of
// dev loop tooling into your brepl"). Everything returns data (or image paths, which the brepl MCP tool
// shows as pictures). dev.help() lists it all.
import { $ } from "bun";
import { mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
// Fresh copy on every dev (re)load: brepl cache-busts only top-level modules, so a static import kept the OLD
// multibot after it changed (2026-10-31: "Export named 'engineErrors' not found").
const { runGroup, verdict, engineErrors } = await import(`./multibot.ts?t=${Date.now()}`);  // installed next to this file (TOOL_COPIES)

const HOME = process.env.HOME!;
const GP = join(HOME, "GodotProjects");
const LIVE = join(GP, "duo-arena");
const STAGE = join(GP, ".duo-arena-stage");
const BIN = join(HOME, ".local/bin");
const DEPLOYED = ["core", "games", "arcade", "tests"];  // what duo-deploy copies stage -> live
const TOOL_COPIES: Record<string, string> = {  // installed file -> repo copy (keep in sync)
  [join(BIN, "gdev")]: "tools/gdev", [join(HOME, ".local/share/gdev/bridge.gd")]: "tools/gdev-bridge.gd",
  [join(HOME, ".local/share/gdev/control.gd")]: "tools/control.gd",
  [join(HOME, ".local/share/gdev/gdev_main.gd")]: "addons/gdev/gdev_main.gd", [join(HOME, ".local/share/gdev/caption.gd")]: "tools/caption.gd", [join(HOME, ".local/share/gdev/godot.ts")]: "tools/godot.ts",
  [join(BIN, "brepl")]: "tools/brepl", [join(BIN, "duo-deploy")]: "tools/duo-deploy", [join(BIN, "merge-game")]: "tools/merge-game",
  [join(BIN, "voice-bridge")]: "tools/voice-bridge", [join(BIN, "claude-watchdog")]: "tools/claude-watchdog",
  [join(HOME, ".local/share/gdev/recsheet.py")]: "tools/recsheet.py", [join(HOME, ".local/share/brepl/dev.ts")]: "tools/brepl-dev.ts",
  [join(HOME, ".local/share/brepl/mcp.ts")]: "tools/brepl-mcp.ts", [join(HOME, ".local/share/brepl/multibot.ts")]: "tools/multibot.ts", [join(HOME, ".local/share/brepl/alerts.ts")]: "tools/brepl-alerts.ts",
  [join(HOME, ".local/share/brepl/peers.ts")]: "tools/brepl-peers.ts", [join(BIN, "brepl-tunnel")]: "tools/brepl-tunnel",
  [join(HOME, ".config/systemd/user/brepl-tunnel@.service")]: "tools/systemd/brepl-tunnel@.service",
  [join(BIN, "test-throttle")]: "tools/test-throttle", [join(BIN, "duo-nightly-tests")]: "tools/duo-nightly-tests",
  [join(HOME, ".config/systemd/user/duo-nightly-tests.service")]: "tools/systemd/duo-nightly-tests.service", [join(HOME, ".config/systemd/user/duo-nightly-tests.timer")]: "tools/systemd/duo-nightly-tests.timer", [join(BIN, "duo-deploy-deck")]: "tools/duo-deploy-deck",
  [join(HOME, "GodotProjects/duo-arena-deck-build/run.sh")]: "tools/deck-run.sh", [join(HOME, "GodotProjects/duo-arena-deck-build/claude-rc.sh")]: "tools/deck/claude-rc.sh",
  [join(HOME, ".config/systemd/user/brepl.service")]: "tools/systemd/brepl.service", [join(BIN, "frame-at")]: "tools/frame-at", [join(BIN, "duo-deploy-frame")]: "tools/duo-deploy-frame",
};

/** Run a shell command: {code, out} (stdout+stderr, trimmed). Never throws. */
export async function sh(cmd: string, cwd = HOME) {
  const { safeCwd } = await import(`${HOME}/.local/share/gdev/godot.ts`);
  const r = await $`bash -c ${cmd}`.cwd(safeCwd(cwd)).nothrow().quiet();  // a deleted cwd (removed worktree) falls back to HOME
  return { code: r.exitCode, out: (r.stdout.toString() + r.stderr.toString()).trim() };
}
const lastPath = async (out: string) => {
  for (const l of out.split("\n").map(l => l.trim()).reverse()) if (/\.(jpe?g|png)$/i.test(l) && (await Bun.file(l).exists())) return l;
};

// --- Bot tests (headless, in the staging copy, at low priority) ------------------------------------

/** Bots whose runs may end without a BOT RESULT line (multibot verdict allowNoResult). Every other bot run, local, host
 *  or joining, FAILs without one: a run without a verdict tests nothing (2026-11-11: penalty_shootout's networked runs
 *  "passed" that way; tests/bot_end.gd now gives every bot one). Keep this short, with a reason for each. */
export const NET_NO_RESULT_OK: Record<string, string> = {
};

export const bots = {
  /** Game ids that have a bot test. */
  async list(): Promise<string[]> {
    return (await readdir(join(STAGE, "tests"))).filter(f => f.endsWith("_bot.tscn")).map(f => f.replace(/_bot\.tscn$/, "")).sort();
  },
  /** Run one bot test. net: also run it as ONE shared game: a host + `joiners` (default 1, up to 6) joining machines,
   *  each its own process (tools/multibot.ts). Returns pass/fail, failed checks, errors, per machine. */
  async run(id: string, o: { net?: boolean; joiners?: number; seconds?: number; project?: string } = {}) {
    const t0 = Date.now();
    const proj = o.project ?? STAGE;  // staging by default; a worktree path tests a branch before it lands
    const scene = `res://tests/${id}_bot.tscn`;
    const one = async (env: Record<string, string>, extra = "") => {
      const r = await $`nice -n 19 timeout ${o.seconds ?? 150} godot-test --headless --path ${proj} ${{ raw: extra }} ${scene}`.env({ ...process.env, ...env }).nothrow().quiet();
      return { out: r.stdout.toString() + r.stderr.toString(), code: r.exitCode };
    };
    // Pass (docs/GAME_DEV_GUIDE.md "Testing"): multibot.verdict, the one shared rule.
    const allowNoResult = NET_NO_RESULT_OK[id];
    const parse = ({ out, code }: { out: string; code: number }, mode: string) => ({ mode, ...verdict(out, code, { allowNoResult }) });
    const runs: any[] = [parse(await one({}, "--fixed-fps 60 --quit-after 3600"), "local")];
    if (o.net) {
      const g = await runGroup({ scene, project: proj, joiners: o.joiners ?? 1, seconds: o.seconds ?? 180, quiet: true, allowNoResult });
      runs.push(...g.machines.map(m => ({ mode: m.machine, ...m })));
      for (const [k, a] of Object.entries(g.agree)) if (!a.ok) runs.push({ mode: `agree ${k}`, pass: false, result: a.values.join(" / "), failed: [], errors: [] });
    }
    return { id, pass: runs.every(r => r.pass), secs: Math.round((Date.now() - t0) / 1000), runs };
  },
  /** Run many (default all) bot tests, `concurrency` at a time. Returns {pass, fail: [...details], table}. */
  async all(o: { only?: string[]; net?: boolean; concurrency?: number } = {}) {
    // Bots that change game files refuse plain runs ("run it with tools/multibot.ts --copies" / tools/hot-everything-test):
    // they have their own runners, so a sweep skips them instead of reporting two FAILs every time.
    const own = new Set<string>();
    // (So do bots that are one half of a tools/ runner: "## Own runner: tools/<name>" in their header, e.g. lan_update
    // and telemetry_push, which FAIL on purpose without their runner's receiver / update server, 2026-11-11.)
    if (!o.only) for (const id of await bots.list()) if (/this bot changes game files|^## Own runner: /m.test(await Bun.file(join(STAGE, "tests", id + "_bot.gd")).text().catch(() => ""))) own.add(id);
    const ids = (o.only ?? (await bots.list())).filter(id => !own.has(id));
    const results: any[] = [];
    let next = 0;
    await Promise.all(Array.from({ length: o.concurrency ?? 3 }, async () => {
      while (next < ids.length) results.push(await bots.run(ids[next++], { net: o.net }));
    }));
    results.sort((a, b) => a.id.localeCompare(b.id));
    return {
      pass: results.filter(r => r.pass).map(r => r.id),
      fail: results.filter(r => !r.pass),
      ownRunner: [...own],
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

// --- Real play from every machine (core/telemetry_push.gd -> tools/duo-telemetry-recv) --------------------------
const TELEMETRY_STORE = join(HOME, ".cache/duo-arena/telemetry");

/** Every machine's real RUN lines, as the Steam Machine received them: [{device, recv, ...run}] (test lines never
 *  arrive; "push_test" is the receiver's own test game and is left out). */
export async function playRuns(o: { since?: string; game?: string } = {}) {
  const out: any[] = [];
  for (const f of await readdir(TELEMETRY_STORE).catch(() => [] as string[])) {
    if (!f.endsWith(".jsonl")) continue;
    for (const l of (await readFile(join(TELEMETRY_STORE, f), "utf8").catch(() => "")).split("\n")) {
      if (!l) continue;
      try {
        const e = JSON.parse(l), r = e.run || {};
        if (r.game === "push_test" || (o.game && r.game !== o.game) || (o.since && String(r.date) < o.since)) continue;
        out.push({ device: e.device, recv: e.recv, ...r });
      } catch {}
    }
  }
  return out.sort((a, b) => (a.t || 0) - (b.t || 0));
}

/** How the family really played (all machines): per device (runs, last run, lines the device had to drop), per game
 *  (runs, devices, how rounds ended, minutes played) and the newest runs. dev.playstats({since: "2026-11-01", game}). */
export async function playstats(o: { since?: string; game?: string; recent?: number } = {}) {
  const runs = await playRuns(o);
  const devices: Record<string, any> = {};
  for (const f of await readdir(TELEMETRY_STORE).catch(() => [] as string[])) {
    if (!f.endsWith(".meta.json")) continue;
    const m = JSON.parse(await readFile(join(TELEMETRY_STORE, f), "utf8").catch(() => "{}"));
    const iso = (t: number) => t ? new Date(t * 1000).toISOString().slice(0, 16) : "never";
    devices[f.slice(0, -10)] = { runs: 0, last_run: "", last_seen: iso(m.last_seen), last_checkin: iso(m.last_checkin), build: m.build || "?", dropped: m.dropped || 0 };
  }
  const games: Record<string, any> = {};
  for (const r of runs) {
    const dv = (devices[r.device] ??= { runs: 0, last_run: "", last_seen: "?", dropped: 0 });
    dv.runs++; dv.last_run = String(r.date || "").slice(0, 16);
    const g = (games[r.game] ??= { runs: 0, devices: {} as Record<string, number>, ends: {} as Record<string, number>, minutes: 0, last: "" });
    g.runs++; g.devices[r.device] = (g.devices[r.device] || 0) + 1;
    if (r.end) g.ends[r.end] = (g.ends[r.end] || 0) + 1;
    g.minutes += (Number(r.secs ?? r.seconds ?? r.time ?? 0) || 0) / 60;
    g.last = String(r.date || "").slice(0, 16);
  }
  for (const g of Object.values(games)) g.minutes = Math.round(g.minutes);
  const byRuns = Object.fromEntries(Object.entries(games).sort((a: any, b: any) => b[1].runs - a[1].runs));
  return { store: TELEMETRY_STORE, total: runs.length, devices, games: byRuns,
    recent: runs.slice(-(o.recent ?? 10)).map(r => `${String(r.date).slice(0, 16)} ${r.device} ${r.game} ${r.mode ?? ""} ${r.end ?? ""}`) };
}

/** Everything that needs tidying: unmerged finished branches, stale worktrees, uncommitted work, staging drift,
 *  tool copies out of sync, broken services. Returns {clean, issues: [{kind, what, fix}]}. */
/** Worktrees that live for good (merged branch or not): wt-merge is the deploy steward's permanent merge worktree
 *  (branch merge-arcade, fast-forwarded to main after every landing), so it must never be flagged as stale. */
const PERMANENT_WORKTREES = new Set([join(GP, "wt-merge")]);

export async function debt() {
  const issues: { kind: string; what: string; fix: string }[] = [];
  // The shared-globals guard (see installGlobalsGuard) must be live: without it agents' generic globals clash again.
  try { (globalThis as any).__breplLint?.("(async () => (WT = 1\n))"); issues.push({ kind: "brepl-guard", what: "brepl's shared-globals guard is not refusing generic globals (WT = ...)", fix: "reload dev.ts (loadModule('dev')) and check installGlobalsGuard()" }); } catch {}
  if (!(globalThis as any).__evalGuard) issues.push({ kind: "brepl-guard", what: "brepl's shared-globals guard is not installed", fix: "loadModule('dev')" });
  // Known bug patterns ("never just one ant"): flag every instance in the staging copy, not just the one we saw.
  const PATTERNS: { kind: string; files: string; bad: string; unless?: string; fix: string; dirs?: string }[] = [
    { kind: "pad-A", files: "grab_focus", bad: "grab_focus", unless: "JOY_BUTTON_A|ui_input.gd|UiInput", fix: "should now work by design (UiKit.ensure_pad_ui_actions at startup); check the menu reaches it" },
    { kind: "anchors", files: "set_anchors_preset", bad: "add_child\\([a-z_]+\\)\\n\\s*[a-z_]+\\.set_anchors_preset\\(Control\\.PRESET_(CENTER|RIGHT|BOTTOM)", fix: "use UiKit.pin(control, preset) (core/ui_kit.gd): one helper, offsets always reset" },
    { kind: "set_meta-null", files: "_meta(", bad: "set_meta\\([^\\n]*(,\\s*null\\)|else null\\))|get_meta\\([^)\\n]*,\\s*null\\)", fix: "set_meta(k, null) DELETES the key and get_meta(k, null) has NO default (errors when missing): store false and test with get_meta(k, false) is <Type>" },
    { kind: "dir-list-unchecked", files: "get_(directories|files)_at\\(", bad: "get_(directories|files)_at\\(", unless: "dir_exists_absolute|make_dir_recursive_absolute", fix: "check DirAccess.dir_exists_absolute(path) (or make the folder) before get_directories_at / get_files_at: listing a missing folder logs \"Couldn't open directory\" (2026-10-30: user://test_saves/)" },
    { kind: "test-timing-spike", dirs: "tests", files: "get_ticks_(usec|msec)", bad: "(\\w+) = max[fi]\\(\\1, [^\\n]*(get_ticks_usec|get_ticks_msec|\\bus / 1000)(?![^\\n]*timing-spike-ok)", unless: "^extends RefCounted\\n## Timing in generator tests", fix: "time with TestTime.worst(worst_ms, ms, func() -> Variant: return <the call>) (tests/test_time.gd): one slow call on a busy machine re-runs twice and the fastest counts (Mini Golf's 42 ms failed a landing, 2026-11-11)" },
    { kind: "raw-look_at", files: "look(ing)?_at\\(", bad: "(^|\\n)[^#\\n]*(\\blooking_at\\(|[^A-Za-z0-9_]look_at\\()", unless: "static func aim\\(dir", fix: "use UiKit.aim(dir) / aim_from(from, at) / look(node, target) (core/ui_kit.gd): raw looking_at / look_at go NaN or error when the direction is vertical (tests/core_math_test.gd fails on any)" },
  ];
  // Slow landing tests (SLOW_TEST_S) not changed since they were slow, and the nightly full sweep's failures / absence.
  const slow = JSON.parse(await readFile(SLOW_FILE, "utf8").catch(() => "{}"));
  for (const [t, v] of Object.entries(slow) as [string, any][]) {
    const m = await stat(join(LIVE, `tests/${t}.gd`)).then(x => x.mtime.toISOString().slice(0, 16), () => "");
    if (m && m <= v.at) issues.push({ kind: "slow-landing-test", what: `${t} took ${v.secs} s in a landing (${v.branch}, ${v.at})`, fix: `give it a quick mode: Seeded.test_count(n) / Seeded.sampled(i) (core/seeded.gd, GEN_QUICK=1 in landings); the nightly full sweep keeps every seed. Then delete its entry in ~/.cache/duo-arena/slow-tests.json` });
  }
  const nl = JSON.parse(await readFile(NIGHTLY, "utf8").catch(() => "null"));
  if (!nl || Date.now() - Date.parse(nl.date) > 36 * 3600e3)
    issues.push({ kind: "nightly-missing", what: nl ? `the last full test sweep was ${nl.date}` : "no full test sweep has run yet", fix: "systemctl --user status duo-nightly-tests.timer; run one: bg('x', () => dev.nightly())" });
  else for (const [t, r] of Object.entries(nl.tests) as [string, any][])
    if (!r.pass) issues.push({ kind: "nightly-fail", what: `${t} failed the full sweep (${nl.date} @${nl.commit}): ${String(r.tail).split("\n").pop()}`, fix: `GEN_QUICK only samples: fix the seed/date in ~/.cache/duo-arena/nightly/logs/${t}.log, then dev.nightly(["${t}"])` });
  // Voice echo (2026-11-11): every TTS player must log to ~/.claude/said.log, or the room/Deck mics feed Claude's own words back.
  for (const f of (await sh(`grep -lIE "say\\.py|piper |\\bespeak\\b" ~/.local/bin/* 2>/dev/null | grep -v '\\.bak' | xargs -r grep -L said.log`, LIVE)).out.split("\n").filter(Boolean))
    issues.push({ kind: "tts-no-said-log", what: f, fix: "append 'ts<TAB>text' to ~/.claude/said.log at start and end of playback (saidecho.py drops echoes)" });
  for (const pt of PATTERNS) {
    const hits = (await sh(`grep -rlE ${JSON.stringify(pt.files)} --include=*.gd ${pt.dirs ?? "core games arcade"}`, STAGE)).out.split("\n").filter(Boolean);
    for (const f of hits) {
      const txt = await readFile(join(STAGE, f), "utf8").catch(() => "");
      if (!new RegExp(pt.bad).test(txt)) continue;
      if (pt.unless && new RegExp(pt.unless).test(txt)) continue;
      issues.push({ kind: pt.kind, what: f, fix: pt.fix });
    }
  }
  // Shared picks (2026-11-11, two ants): games built their own pick orbs / pods / altars, warning rings / telegraphs
  // and mode colours (BRAVE was orange in two games, blue in two). tests/shared_picks_test.gd scans every game.
  if (await stat(join(STAGE, "tests/shared_picks_test.gd")).then(() => true, () => false)) {
    const sp = (await sh(`DUO_PORT=${20000 + Math.floor(Math.random() * 9999)} timeout 120 godot-test --headless --path . -s res://tests/shared_picks_test.gd 2>&1 | grep "SHARED PICKS: FAIL res://"`, STAGE)).out;
    for (const l of sp.split("\n").filter(Boolean))
      issues.push({ kind: "own-picks-or-warnings", what: l.replace("SHARED PICKS: FAIL ", "").slice(0, 200), fix: "use core/pick_orbs.gd (show_orbs opts keep the look) / core/warn_rings.gd (warn / shape + style) / PickOrbs.mode(); a truly different thing gets '## shared-picks-ok: <func> (why)'" });
  }
  // Viewport grabs: get_image() straight off get_texture() returns null / empty before the first draw or after the
  // viewport is gone (2026-10-30 offscreen runs: "tex is null at texture_get_data", then get_width on null in
  // _save_frame). Grab through FrameGrab.image(vp) (core/frame_grab.gd) or the gdev addon's _grab(vp).
  const grabs = (await sh(`grep -rnE "get_texture\\(\\)\\.get_image\\(\\)" --include=*.gd core games arcade tests addons tools 2>/dev/null | grep -v -e '^[^:]*:[0-9]*:\\s*#'`, LIVE)  /* the repo: staging has no addons/ sync */).out;
  for (const l of grabs.split("\n").filter(Boolean))
    issues.push({ kind: "unguarded-get_image", what: l.slice(0, 160), fix: "use FrameGrab.image(vp) (core/frame_grab.gd): null when nothing is drawn yet or the viewport is gone" });
  // Frame-count waits after an input in bots: networked bots run WITHOUT --fixed-fps (frames fly by far faster than
  // game time), so "press A, await frames(40), check the game started" raced the lobby host's 0.4 s start delay
  // (2026-10-30 arcade_bot). Wait in seconds (create_timer / a ticks_msec loop). Bots that only ever run with
  // --fixed-fps say "## fixed-fps only" in their header.
  for (const f of (await sh(`ls tests/*_bot.gd 2>/dev/null`, LIVE)).out.split("\n").filter(Boolean)) {
    const txt = await readFile(join(LIVE, f), "utf8").catch(() => "");
    if (/## fixed-fps only/.test(txt)) continue;
    for (const m of txt.matchAll(/(?:tap|press)\([^\n]*\)\n\s*await (?:kit\.)?frames\((\d+)\)/g))
      if (Number(m[1]) >= 20) issues.push({ kind: "bot-frame-wait", what: `${f}: ${m[0].replace(/\s+/g, " ").slice(0, 120)}`, fix: "wait in seconds after an input (create_timer / Time.get_ticks_msec loop until the thing happens): networked bots have no --fixed-fps" });
  }
  // Screenshots: spectacle only works in Desktop Mode (it SIGABRTs in Gaming Mode / without a Wayland display), so
  // every tool takes its one shot through tv-shot, which picks gamescopectl or spectacle. Flag any direct call.
  const spec = (await sh(`grep -rnIE "[\\"']spectacle[\\"']|(^|[;&|(]|\\s)spectacle\\s+-" ${BIN} ${HOME}/.local/share/brepl ${HOME}/.local/share/gdev ${LIVE}/tools 2>/dev/null | grep -v -e '/tv-shot:' -e '^[^:]*:[0-9]*:\\s*#'`)).out;
  for (const l of spec.split("\n").filter(Boolean))
    issues.push({ kind: "direct-spectacle", what: l.replace(HOME, "~").slice(0, 160), fix: "take the screenshot with tv-shot OUT.png (one shot, right tool for the mode), never spectacle directly" });
  // Godots (tests or offscreen runs) running from a deleted folder: a removed worktree as cwd or --path logs
  // "getcwd(...) is null" / can't open res:// (2026-10-29). godot.ts / dev.sh / multibot now always pick a folder
  // that exists and the godot.ts reaper quits orphans; anything left here was started some other way.
  const dead = (await sh(`for p in $(pgrep -x godot); do c=$(readlink /proc/$p/cwd); a=$(tr '\\0' ' ' < /proc/$p/cmdline); pp=$(echo "$a" | grep -oP '(?<=--path )\\S+'); if [[ "$c" == *"(deleted)"* ]] || { [ -n "$pp" ] && [ ! -d "$pp" ]; }; then echo "$p $c $pp"; fi; done`)).out;
  for (const l of dead.split("\n").filter(Boolean))
    issues.push({ kind: "dead-cwd-godot", what: `godot ${l.replace(HOME, "~")}`, fix: "quit it (its folder is gone); start test Godots via godot.launch / dev.sh / multibot (they set a cwd that exists)" });
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
      // Work in progress, not debt: an agent's branch checked out in a worktree that moved in the last 12 h (its
      // agent hands it to the steward when done; 2026-10-29: every running deep-* agent was listed as debt).
      const wt = (await sh(`git worktree list --porcelain | grep -B2 "^branch refs/heads/${b}$" | sed -n 's/^worktree //p'`, dir)).out;
      if (wt && Date.now() / 1000 - +(await sh(`git log -1 --format=%ct ${b}`, dir)).out < 12 * 3600) continue;
      issues.push({ kind: "unmerged", what: `${r}: branch ${b} is ${n} commits ahead (${age})`, fix: "merge if finished, else leave parked" });
    }
    for (const w of (await sh("git worktree list --porcelain", dir)).out.split("\n\n").slice(1)) {
      const path = w.match(/^worktree (.*)$/m)?.[1], br = w.match(/^branch refs\/heads\/(.*)$/m)?.[1];
      if (!path || !br) continue;
      if (PERMANENT_WORKTREES.has(path)) continue;  // kept on purpose (the steward's merge worktree), never stale
      const merged = (await sh(`git merge-base --is-ancestor ${br} ${main} && echo y`, dir)).out === "y";
      // A worktree an agent just made from main has no commits yet, so its branch also "is merged": it is only stale
      // when nobody works in it (no uncommitted files) and its branch hasn't moved for 12 h (2026-10-29: fresh
      // wt-deep-* worktrees were flagged for removal minutes after their agents started).
      // (A branch with commits of its own that main merged IS stale at once: land() removes those.)
      const busy = merged && ((await sh("git status --porcelain | head -1", path)).out !== ""
        || ((await sh(`git rev-list --first-parent ${main} | grep -qx "$(git rev-parse ${br})" && echo y`, dir)).out === "y"
          && Date.now() / 1000 - +(await sh(`git log -g -1 --format=%ct ${br}`, dir)).out < 12 * 3600));
      if (merged && !busy) issues.push({ kind: "stale-worktree", what: `${r}: worktree ${path} (branch ${br} already merged)`, fix: `dev.removeWorktree(${JSON.stringify(path)}, ${JSON.stringify(br)}) (quits its Godots first)` });
    }
  }
  // brepl modules on disk must compile: the loader keeps a running copy when a save doesn't, so a broken file
  // only shows at the next brepl start (2026-10-29). Edit them with writeModule(path, text) (build-checked).
  for (const f of [join(HOME, ".local/share/gdev/godot.ts"), ...["dev", "alerts", "peers", "multibot"].map(n => join(HOME, `.local/share/brepl/${n}.ts`))]) {
    const b = await sh(`${process.execPath} build --no-bundle ${f} >/dev/null 2>/tmp/brepl-build-check.err || head -c 300 /tmp/brepl-build-check.err`);
    if (b.out) issues.push({ kind: "module-broken", what: `${f.replace(HOME, "~")}: ${b.out}`, fix: "fix it (write with writeModule(path, text)); brepl runs the last good copy until then" });
  }
  const d = await stage.diff();
  if (d.liveNewer.length || d.onlyLive.length) issues.push({ kind: "stage-behind", what: `live has newer files than staging: ${[...d.liveNewer, ...d.onlyLive].slice(0, 5).join(", ")}`, fix: "dev.stage.pull()" });
  if (d.stageNewer.length || d.onlyStage.length) issues.push({ kind: "undeployed", what: `staging has changes not deployed: ${[...d.stageNewer, ...d.onlyStage].slice(0, 5).join(", ")}`, fix: "test, then dev.stage.deploy(msg)" });
  // tools/ is not in stage.diff (not game code) but dev.land rsyncs it from wt-merge: a direct commit to live leaves staging's copy behind.
  const toolDrift = (await sh(`diff -rq --exclude=__pycache__ ${LIVE}/tools ${STAGE}/tools | wc -l`)).out;
  if (+toolDrift > 0) issues.push({ kind: "stage-tools", what: `${toolDrift} tools/ files differ between live and staging`, fix: "rsync -a --delete --exclude __pycache__ ~/GodotProjects/duo-arena/tools/ ~/GodotProjects/.duo-arena-stage/tools/" });
  // Staging must run like the TV: addons/boot (services) and project.godot (autoloads) match live (2026-10-31: no Boot in staging).
  const bootDrift = (await sh(`diff -rq --exclude=*.uid --exclude=*.import ${LIVE}/addons/boot ${STAGE}/addons/boot 2>&1 | wc -l; diff <(sed 's|^config/name=.*||' ${LIVE}/project.godot) <(sed 's|^config/name=.*||' ${STAGE}/project.godot) | wc -l`)).out.split("\n").map(Number);
  if (bootDrift.some(n => n > 0)) issues.push({ kind: "stage-boot", what: "staging's addons/boot or project.godot differs from live (bots there run without the TV's services)", fix: "rsync -a ~/GodotProjects/duo-arena/addons/boot/ ~/GodotProjects/.duo-arena-stage/addons/boot/; sed 's|^config/name=\"Duo Arena\"$|config/name=\"Duo Arena Stage\"|' ~/GodotProjects/duo-arena/project.godot > ~/GodotProjects/.duo-arena-stage/project.godot" });
  // Plus every tools/ file named like an installed command (~/.local/bin) and every tools/systemd unit, so a new
  // tool never drifts just because nobody added it to TOOL_COPIES.
  const copies: Record<string, string> = { ...TOOL_COPIES };
  for (const f of await readdir(join(LIVE, "tools")).catch(() => [] as string[]))
    if (!Object.values(copies).includes(`tools/${f}`)) copies[join(BIN, f)] = `tools/${f}`;
  for (const f of await readdir(join(LIVE, "tools/systemd")).catch(() => [] as string[]))
    if (!Object.values(copies).includes(`tools/systemd/${f}`)) copies[join(HOME, ".config/systemd/user", f)] = `tools/systemd/${f}`;
  for (const [src, rel] of Object.entries(copies)) {
    const repo = join(LIVE, rel);
    const [a, b] = await Promise.all([readFile(src).catch(() => null), readFile(repo).catch(() => null)]);
    if (a && b && !a.equals(b))
      issues.push({ kind: "tool-copy", what: `${rel} differs from ${src.replace(HOME, "~")}`, fix: `cp ${src} ${repo} and commit` });
  }
  // Real-play telemetry (2026-11-11: no family RUN lines reached the Steam Machine for 2 weeks and nobody noticed):
  // every machine pushes its RUN lines to duo-telemetry-recv; warn when nothing real has arrived for 7 days, or a
  // device had to drop lines it couldn't send.
  {
    const runs = await playRuns();
    const newest = runs.reduce((m, r) => Math.max(m, Number(r.recv) || 0, Number(r.t) || 0), 0);
    const days = Math.floor((Date.now() / 1000 - newest) / 86400);
    // A test run leaking into the family's real lines (2026-11-11: an offscreen Deck-size run on the Steam Machine
    // arrived as a "deck" round from steammachine; godot.ts now sets SAVE_TEST + DUO_TELEMETRY_PUSH=0). The Steam
    // Machine only really plays as the TV (or a flat host / with a Frame), never as a Deck.
    const leaks = runs.filter((r: any) => r.device === "steammachine" && r.machine && !["tv", "frame", "host"].includes(String(r.machine)));
    if (leaks.length) issues.push({ kind: "telemetry-test-leak", what: `${leaks.length} RUN line(s) from steammachine claim machine "${leaks[0].machine}" (${leaks.map((r: any) => r.game).slice(0, 3).join(", ")}): a test run pushed into the family's real telemetry`,
      fix: "find the runner that started Godot without SAVE_TEST/DUO_TELEMETRY_PUSH=0 (godot-test and godot.ts set them), fix it, then delete those lines from ~/.cache/duo-arena/telemetry/steammachine.jsonl" });
    // Check-ins (every arcade start says hello even with nothing to send) tell "nobody played" from "can't reach us".
    const checkins: string[] = [];
    for (const f of await readdir(TELEMETRY_STORE).catch(() => [] as string[])) {
      if (!f.endsWith(".meta.json") || f.startsWith("lan-test-")) continue;
      const m = JSON.parse(await readFile(join(TELEMETRY_STORE, f), "utf8").catch(() => "{}"));
      if (m.last_checkin && Date.now() / 1000 - m.last_checkin < 7 * 86400) checkins.push(`${f.slice(0, -10)} ${new Date(m.last_checkin * 1000).toISOString().slice(0, 10)}`);
    }
    // The Steam Machine's firewall must let the Decks in on 7870 (UDP hello + HTTP); firewalld's zone allowed
    // 1024-65535 on 2026-11-11. A missing firewall-cmd (no firewalld) is fine.
    for (const proto of ["udp", "tcp"]) {
      const q = await sh(`command -v firewall-cmd >/dev/null || { echo yes; exit; }; firewall-cmd --query-port=7870/${proto} 2>&1`);
      if (!/^yes/.test(String(q.out ?? "").trim())) issues.push({ kind: "telemetry-firewall", what: `the Steam Machine's firewall doesn't allow ${proto} 7870 (${String(q.out ?? "").trim().slice(0, 80)}): Decks can't push RUN lines`,
        fix: `ask Simon to run: sudo firewall-cmd --permanent --add-port=7870/${proto} && sudo firewall-cmd --reload` });
    }
    const seen = checkins.length ? `; machines that started the arcade and reached the Steam Machine this week: ${checkins.join(", ")} (so they can send; no rounds finished)` : "; no machine has started the arcade and checked in this week either";
    if (days > 7) issues.push({ kind: "telemetry-gap", what: (newest ? `no real RUN lines from any machine for ${days} days (newest ${new Date(newest * 1000).toISOString().slice(0, 10)})` : "no real RUN lines have ever reached ~/.cache/duo-arena/telemetry") + seen,
      fix: "check duo-telemetry-recv (systemctl --user status duo-telemetry-recv; journalctl --user -u duo-telemetry-recv); prove a Deck's path with tools/telemetry-lan-test DECK (test receiver, refuses while Godot runs there); then ask whether the family played at all" });
    for (const f of await readdir(TELEMETRY_STORE).catch(() => [] as string[])) {
      if (!f.endsWith(".meta.json")) continue;
      const m = JSON.parse(await readFile(join(TELEMETRY_STORE, f), "utf8").catch(() => "{}"));
      const recent = (m.drops || []).filter((x: any) => Date.now() / 1000 - x.t < 7 * 86400).reduce((s: number, x: any) => s + x.n, 0);
      if (recent) issues.push({ kind: "telemetry-drops", what: `${f.slice(0, -10)} dropped ${recent} unsent RUN lines this week (outbox full)`, fix: "the device couldn't reach the Steam Machine for a long time: check its Wi-Fi (family-link status)" });
    }
  }
  // Services and timers that keep things healthy (duo-catch-up delivers deploys to devices that were off).
  for (const s of ["voice-bridge", "claude-watchdog.timer", "duo-catch-up.timer", "test-throttle", "claude-history-index.timer", "duo-telemetry-recv"]) {
    const st = (await sh(`systemctl --user is-active ${s}`)).out;
    if (st !== "active") issues.push({ kind: "service", what: `${s} is ${st}`, fix: `systemctl --user status ${s}` });
  }
  const oom = (await sh("journalctl --since today 2>/dev/null | grep -i earlyoom | grep -i -c -E 'sending SIG(TERM|KILL) to'")).out;
  if (+oom > 0) issues.push({ kind: "oom", what: `earlyoom killed ${oom} processes today`, fix: "journalctl | grep earlyoom" });
  // Devices that missed deploys for days (marker mtime = the FIRST missed deploy; duo-catch-up retries every 2 min,
  // so an old marker means the device has been off or unreachable that long: it needs a person to switch it on).
  const now = Date.now(), DAY = 86400_000;
  // An ONLINE device's old marker isn't "device offline": the job itself keeps failing or waits on purpose (e.g. a
  // Steam shortcut rename that only runs while Steam is closed). family-link knows which tunnels are up.
  const linkUp = JSON.parse(await readFile(join(HOME, ".cache/family-link/link-state.json"), "utf8").catch(() => "{}"));
  const aliasOf = (f: string) => Object.keys(linkUp).filter(a => f === a || f.startsWith(a + "-")).sort((a, b) => b.length - a.length)[0];
  for (const dir of [join(HOME, ".cache/duo-deploy-pending"), join(HOME, ".cache/duo-pending-cmds")])
    for (const f of await readdir(dir).catch(() => [] as string[])) {
      const st = await stat(join(dir, f)).catch(() => null);
      if (!st || now - st.mtimeMs < 3 * DAY) continue;
      const up = linkUp[aliasOf(f) ?? ""]?.up === true;
      issues.push({ kind: "device-behind", what: `${dir.endsWith("cmds") ? "one-off job" : "deploy"} ${f} waiting ${Math.floor((now - st.mtimeMs) / DAY)} days (${up ? "device ONLINE: the job keeps failing or waits for its moment" : "device offline"})`,
        fix: up ? `read the job/marker and run it by hand to see why it fails (one-off jobs may wait on purpose, e.g. for Steam to close); journalctl --user -u duo-catch-up` : "switch the device on with Developer Mode (duo-catch-up delivers it within 2 min); delete the marker if the device is gone" });
    }
  // Test leftovers in /tmp (multibot prunes its own runs after 2 days; this catches anything else that piles up).
  const tmpOld = (await sh("find /tmp -maxdepth 1 \\( -name 'multibot-*' -o -name 'leak-*.log' -o -name 'godot-test-*' \\) -mmin +4320 | wc -l")).out;
  if (+tmpOld > 0) issues.push({ kind: "tmp-pileup", what: `${tmpOld} test leftovers older than 3 days in /tmp`, fix: "find /tmp -maxdepth 1 \\( -name 'multibot-*' -o -name 'leak-*.log' \\) -mmin +4320 -exec rm -rf {} +" });
  // Minecraft test server (~/MinecraftMods/bds-test) left running: it should be stopped after each test (./cmd.sh stop).
  const bds = (await sh("ps -o etimes= -p $(pgrep -x bedrock_server | head -1) 2>/dev/null")).out.trim();
  if (+bds > 3600) issues.push({ kind: "bds-running", what: `Minecraft test server running for ${Math.round(+bds / 60)} min`, fix: "cd ~/MinecraftMods/bds-test && ./cmd.sh stop" });
  // Memory notes: every file needs a line in MEMORY.md (the index is all a new session sees).
  const MEM = join(HOME, ".claude/projects/-home-deck/memory");
  const idx = await readFile(join(MEM, "MEMORY.md"), "utf8").catch(() => "");
  for (const f of await readdir(MEM).catch(() => [] as string[]))
    if (f.endsWith(".md") && f !== "MEMORY.md" && !idx.includes(`(${f})`)) issues.push({ kind: "memory-index", what: `memory/${f} has no line in MEMORY.md`, fix: "add a one-line entry to MEMORY.md" });
  for (const m of idx.matchAll(/\]\(([\w.-]+\.md)\)/g))
    if (!(await stat(join(MEM, m[1])).catch(() => null))) issues.push({ kind: "memory-index", what: `MEMORY.md points to missing ${m[1]}`, fix: "fix or drop the line" });
  const leftovers = (await sh("pgrep -f '^gamescope --[b]ackend headless' | wc -l")).out;
  const ours = ((globalThis as any).godot?.list ? (globalThis as any).godot : await import(`${HOME}/.local/share/gdev/godot.ts`)).list().length;  // the preloaded one (reload() makes a new module)
  if (+leftovers > ours) issues.push({ kind: "orphan", what: `${+leftovers - ours} offscreen game(s) not owned by this brepl`, fix: "pkill -f '[b]ackend headless'" });
  return { clean: issues.length === 0, issues };
}


/** Quit every Godot running from inside `dir` (its cwd or --path): a worktree removed under a running Godot leaves
 *  it logging "Couldn't open directory at path res://" (2026-10-29). TERM, then KILL after 3 s. Returns the pids. */
export async function quitGodotsIn(dir: string) {
  return (await sh(`godot-quit-in ${JSON.stringify(dir)}`)).out.split("\n").filter(Boolean);  // ~/.local/bin/godot-quit-in (tools/)
}

/** Remove a worktree (and its branch, if given) only after quitting the Godots running from it. Use this, never a
 *  bare `git worktree remove`. */
export async function removeWorktree(path: string, branch?: string) {
  const quit = await quitGodotsIn(path);
  const r = await sh(`git worktree remove --force ${JSON.stringify(path)}${branch ? ` && git branch -D ${branch}` : ""}`, LIVE);
  return { quit, out: r.out, code: r.code };
}

/** Install every TOOL_COPIES file (and tools/ file named like a ~/.local/bin command) that changed in live since
 *  `since`: brepl modules through writeModule (build-checked), the rest copied (keeping the mode). */
export async function installTools(since: string) {
  const changed = (await sh(`git diff --name-only ${since} HEAD -- tools addons/gdev`  /* every TOOL_COPIES source, not just tools/ (the gdev addon's gdev_main.gd is one) */, LIVE)).out.split("\n").filter(Boolean);
  const done: string[] = [];
  for (const rel of changed) {
    let dest = Object.entries(TOOL_COPIES).find(([, r]) => r === rel)?.[0];
    if (!dest && rel.split("/").length === 2 && (await stat(join(BIN, rel.slice(6))).catch(() => null))) dest = join(BIN, rel.slice(6));
    if (!dest) continue;
    let src = join(LIVE, rel);
    // The installed copy may carry live edits the repo never got (2026-10-30: a landing reinstalled tools/brepl-dev.ts
    // from a branch and wiped two dev.ts fixes made after that branch started). Never overwrite them: 3-way merge
    // (the old repo copy is the base); on a conflict leave the installed file alone and say so.
    const cur = await readFile(dest, "utf8").catch(() => null);
    const base = (await sh(`git show ${since}:${rel}`, LIVE)).out;
    const neu = await readFile(src, "utf8");
    if (cur !== null && cur !== neu && cur.trimEnd() !== base.trimEnd()) {
      const tmp = `/tmp/install-${process.pid}-${rel.replace(/\//g, "_")}`;
      await writeFile(tmp + ".cur", cur); await writeFile(tmp + ".base", base + "\n"); await writeFile(tmp + ".new", neu);
      const m = await sh(`git merge-file -p ${tmp}.cur ${tmp}.base ${tmp}.new > ${tmp}.out`);
      if (m.code !== 0) { done.push(`${rel}: NOT installed: the installed copy has edits the repo lacks and they conflict (merge by hand, then commit the copy)`); continue; }
      src = tmp + ".out";
      done.push(`${rel}: merged with live edits the repo lacked (commit ${rel} from the installed copy)`);
    }
    if (/\/\.local\/share\/brepl\/[^/]+\.ts$|\/gdev\/godot\.ts$/.test(dest)) {
      try { await (globalThis as any).writeModule(dest, await readFile(src, "utf8")); } catch (e) { done.push(`${rel}: NOT installed (${String(e).slice(0, 200)})`); continue; }
    } else await sh(`cp --preserve=mode ${JSON.stringify(src)} ${JSON.stringify(dest)}`);
    done.push(`${rel} -> ${dest.replace(HOME, "~")}`);
    // A new or changed systemd unit does nothing until systemd reloads it, and a new timer until it is enabled
    // (2026-11-12: duo-nightly-tests.timer had to be enabled by hand after its landing).
    if (dest.includes("/.config/systemd/user/")) {
      const unit = dest.split("/").pop()!;
      const r = await sh(`systemctl --user daemon-reload${unit.endsWith(".timer") ? ` && systemctl --user enable --now ${unit} 2>&1 | tail -1; systemctl --user is-active ${unit}` : ""}`);
      done.push(`systemd reloaded${unit.endsWith(".timer") ? `, ${unit}: ${r.out.split("\n").pop()}` : ""}`);
    }
    // A running user service still executes the OLD copy (2026-11-11: duo-telemetry-recv): restart every active
    // service whose unit runs this file.
    if (dest.startsWith(BIN)) {
      const name = dest.slice(BIN.length + 1);
      const units = (await sh(`grep -l -E "(%h|\\$HOME|${HOME})/\\.local/bin/${name}( |$)" ~/.config/systemd/user/*.service 2>/dev/null`)).out.split("\n").filter(Boolean);
      for (const u of units) {
        const unit = u.split("/").pop()!;
        if ((await sh(`systemctl --user is-active ${unit}`)).out !== "active") continue;
        const r = await sh(`systemctl --user restart ${unit} && systemctl --user is-active ${unit}`);
        done.push(`restarted ${unit}: ${r.out}`);
      }
    }
  }
  return done;
}

// --- Landing a finished game branch (the deploy steward's loop) ----------------------------------------------------

const rport = () => 20000 + Math.floor(Math.random() * 10000);

/** Long guard bots (2026-11-11): the regular bots end before relics + crowded rooms meet, so a THORN ARMOR script
 *  error lived on main for days. dev.land runs these when a branch touches the game (or lands it as botId);
 *  dev.guard(game) runs them by hand. Each must end with BOT RESULT: PASS, no SCRIPT ERROR, no res:// engine ERROR. */
/** Shared-code checks dev.land runs when the branch changes a matching path (run in staging). */
export const PATH_CHECKS: { name: string; paths: RegExp; cmd: string; pass: string }[] = [
  { name: "telemetry-push", paths: /core\/telemetry|tools\/duo-telemetry-recv|tools\/telemetry-push-test|core\/services\.gd/, cmd: "tools/telemetry-push-test .", pass: "PASS telemetry-push-test" },
];

export const LAND_GUARDS: Record<string, { name: string; scene: string; env: Record<string, string>; quitAfter: number; timeout: number }[]> = {
  dungeon_delve: [{ name: "deep-relics", scene: "res://tests/dungeon_delve_bot.tscn", quitAfter: 108000, timeout: 1500,
    env: { DD_MODE: "brave", DD_FLOOR: "8", BOT_GOAL: "guard", DD_RELICS: "all", BOT_PLAYERS: "4", DD_SEED: "111", BOT_END: "1700" } }],
};

export async function guardRun(gb: (typeof LAND_GUARDS)[string][number], project = STAGE) {
  const env = Object.entries(gb.env).map(([k, v]) => `${k}=${v}`).join(" ");
  const t0 = Date.now();
  const o = (await sh(`${env} DUO_PORT=${rport()} timeout ${gb.timeout} godot-test --headless --path . --fixed-fps 60 --quit-after ${gb.quitAfter} ${gb.scene} 2>&1`, project)).out;
  const errs = [...o.split("\n").filter(l => /SCRIPT ERROR/.test(l)), ...engineErrors(o)];
  const result = o.split("\n").filter(l => /BOT RESULT/.test(l)).pop() ?? "no BOT RESULT";
  const pass = /BOT RESULT: PASS/.test(result) && !/stopped at the --quit-after/.test(result) && errs.length === 0;
  return { pass, summary: `${pass ? "ok" : "FAIL"} ${result.trim()} (${Math.round((Date.now() - t0) / 1000)} s)${errs.slice(0, 3).map(e => "\n  " + e).join("")}` };
}

/** Run a game's long guard bots now (in staging, or project). */
export async function guard(game: string, project = STAGE) {
  const out: Record<string, string> = {};
  for (const gb of LAND_GUARDS[game] ?? []) out[gb.name] = (await guardRun(gb, project)).summary;
  return out;
}

/** Land a finished branch: merge it into the permanent merge worktree (~/GodotProjects/wt-merge, branch merge-arcade),
 *  check live == staging, copy into staging, run its gen tests + bot_end_test + core_math, the Deck bot
 *  (DECK_BOT_ONLY=botId), the arcade bot, botId networked (180 s) and otherBots; then duo-deploy + duo-deploy-deck,
 *  merge merge-arcade into live main, fast-forward wt-merge, remove the branch's worktree (~/GodotProjects/wt-<branch>)
 *  and branch. Stops (nothing deployed) with {stop, ...} on a conflict, live/staging drift, or any failing test
 *  (story_pictures_test always runs: pictures belong in games/<game>/story_pictures.gd). */
/** Repo-wide guard tests every landing runs (2026-11-11: gen_budget_test failed on main unnoticed because no landing
 *  ran it; each of these took < 45 s on all of main then). lan_update_test stays out: it compiles a deliberately broken
 *  script, whose expected "Parse Error" would read as a SCRIPT ERROR here. */
export const REPO_GUARDS = ["gen_budget_test", "who_test", "who_net_test", "classic_seats_test", "menu_test", "party_stale_press_test", "bg_gen_test", "engine_sys_test", "engine_ui_test", "pause_banner_test", "contrast_test", "vr_wrist_menu_test"];

/** Lone flat player (2026-11-11, cove-deep2: a lone Deck gunner ran out of cannonballs, a solo VR host stayed in
 *  practice forever): ONE Deck player, no VR, nobody else (DUO_SOLO=1 DUO_MACHINE_KIND=deck BOT_PLAYERS=1), the
 *  game's own bot for 120 s game time. Fails on a failed check, a SCRIPT / res:// engine error, no BOT RESULT, or a
 *  FROZEN game: the bot's last 8 status lines (timestamps stripped) all the same, i.e. ~30 s with nothing changing
 *  (stuck on a results screen, waiting forever for a second player, sandbox with an idle bot). A bot must keep
 *  playing to its end, so a frozen tail is a game softlock or a bot that stopped acting: fix whichever it is.
 *  rounds = RUN lines before the BOT RESULT (rounds that really finished). */
export async function loneRun(id: string, project = STAGE) {
  const o = (await sh(`DUO_SOLO=1 DUO_MACHINE_KIND=deck BOT_PLAYERS=1 DUO_PORT=${rport()} timeout 300 godot-test --headless --path . --fixed-fps 60 --quit-after 7200 res://tests/${id}_bot.tscn 2>&1`, project)).out;
  const lines = o.split("\n");
  const end = lines.findIndex(l => /BOT RESULT/.test(l));
  const before = lines.slice(0, end < 0 ? lines.length : end);
  const status = before.filter(l => /^(\[\s*[\d.]+s\]\s*)?(BOT\b|t=\d)/.test(l) && !/BOT (RESULT|ASSERT|CUES)|SCRIPT/.test(l))
    .map(l => l.replace(/^\[\s*[\d.]+s\]\s*/, "").replace(/\bt=[\d.]+\s*/, "").trim());
  const tail = status.slice(-8);
  const frozen = tail.length >= 8 && tail.every(x => x === tail[0]);
  const rounds = before.filter(l => l.startsWith("RUN: ")).length;
  const errs = [...lines.filter(l => /SCRIPT ERROR/.test(l)), ...engineErrors(o)];
  const result = lines.filter(l => /BOT RESULT/.test(l)).pop() ?? "no BOT RESULT";
  const pass = /BOT RESULT: PASS/.test(result) && errs.length === 0 && !frozen && (rounds > 0 || status.length >= 3);
  return { id, pass, rounds, frozen, summary: `${pass ? "ok" : "FAIL"} ${result.trim()} rounds=${rounds}${frozen ? " FROZEN: " + tail[0].slice(0, 100) : ""}${status.length < 3 && !rounds ? " (no status lines and no finished round: can't tell it plays)" : ""}${errs.slice(0, 3).map(e => "\n  " + e).join("")}` };
}

/** Sweep the lone-flat check over games (default every game with a bot), 2 at a time. */
export async function lone(ids?: string[], project = STAGE) {
  const all: string[] = ids ?? [];
  if (!ids) for (const id of await bots.list()) if (await stat(join(project, "games", id)).then(() => true, () => false)) all.push(id);
  const out: any[] = []; let next = 0;
  await Promise.all([0, 1].map(async () => { while (next < all.length) out.push(await loneRun(all[next++], project)); }));
  out.sort((a, b) => a.id.localeCompare(b.id));
  return { fail: out.filter(r => !r.pass).map(r => `${r.id}: ${r.summary}`), table: out.map(r => `${r.id.padEnd(18)} ${r.summary.split("\n")[0]}`).join("\n") };
}

/** Landing tests must stay quick (2026-11-12: kart_trackgen_test ~220 s and dungeon_delve_floors_test ~130 s made every
 *  landing that ran them long). dev.land records any test over SLOW_TEST_S in ~/.cache/duo-arena/slow-tests.json and
 *  dev.debt reports it until the test file changes: give it a quick mode (Seeded.test_count / Seeded.sampled, GEN_QUICK=1);
 *  the nightly full sweep (dev.nightly, duo-nightly-tests.timer) keeps the full coverage. */
export const SLOW_TEST_S = 60;
const SLOW_FILE = join(HOME, ".cache/duo-arena/slow-tests.json");
const NIGHTLY = join(HOME, ".cache/duo-arena/nightly/latest.json");
async function noteSlowTest(test: string, secs: number, branch: string) {
  const all = JSON.parse(await readFile(SLOW_FILE, "utf8").catch(() => "{}"));
  all[test] = { secs, branch, at: new Date().toISOString().slice(0, 16) };
  await writeFile(SLOW_FILE, JSON.stringify(all, null, 1));
}

/** The full test sweep now (what duo-nightly-tests.timer runs at 03:30): every tests/*_test.gd (or `tests`) on a
 *  snapshot of live main, every seed and date. Long (~15-30 min): run it in bg(). Returns the summary line. */
export async function nightly(tests: string[] = []) {
  return (await sh(`duo-nightly-tests ${tests.join(" ")} 2>&1 | tail -1`)).out;
}

export async function land(branch: string, genTests: string[], botId: string, otherBots: string[], msg: string) {
  // A landing that stopped leaves its merge in wt-merge (and its files in staging) for a retry. Landing a DIFFERENT
  // branch next must not carry it along (2026-10-31: a tools-only landing nearly deployed saga-deep, whose tests had
  // failed): start again from main, staging included.
  // Staging = the repo as the TV runs it: addons/boot (services: QuitAfter, VrViewWatch, SafeApply...) and project.godot
  // (its Boot autoload) too, not just the deployed dirs (2026-10-31: staging had no Boot, so no bot ran with services).
  const stale = (await sh("git log --merges --first-parent --format=%s main..merge-arcade", join(GP, "wt-merge"))).out.split("\n").filter(Boolean);
  if (stale.some(s => !s.includes(`'${branch}'`))) {
    await sh("git merge --abort 2>/dev/null; git reset -q --hard main", join(GP, "wt-merge"));
    await sh(`for d in ${DEPLOYED.join(" ")} tools addons/boot; do rsync -a --delete --exclude '*.import' --exclude '__pycache__' wt-merge/$d/ .duo-arena-stage/$d/; done; cp wt-merge/arcade.tscn .duo-arena-stage/; sed 's|^config/name="Duo Arena"$|config/name="Duo Arena Stage"|' wt-merge/project.godot > .duo-arena-stage/project.godot`, GP);
  }
  // The branch's worktree must be fully committed: land merges the BRANCH, so anything uncommitted (an edit, or an
  // untracked .uid / .gd a re-import made) would silently stay behind (2026-11-11: marble-deep2's
  // marble_maze_deep_test.gd.uid; land used to print tracked changes only and carry on).
  const dirty = (await sh(`git status --porcelain | head -5`, join(GP, `wt-${branch}`))).out.trim();
  if (dirty) return { stop: "uncommitted", out: `wt-${branch} has uncommitted files (commit them on the branch, or ask its agent):\n${dirty}` };
  const m = await sh(`cd ${GP}/wt-merge && git merge --no-edit ${branch} 2>&1 | tail -1; git diff --name-only --diff-filter=U`);
  // (tail -1 of a conflicted merge is "Automatic merge failed...", not CONFLICT: party-deep's whats_new conflict
  // once went on to the tests with its markers in, 2026-10-31. The unmerged-files list after it is the sure sign.)
  if (/CONFLICT|fatal|Automatic merge failed|error:/.test(m.out) || (await sh("git diff --name-only --diff-filter=U", join(GP, "wt-merge"))).out.trim())
    return { stop: "merge", out: m.out + "\n(resolve in ~/GodotProjects/wt-merge and commit, or git merge --abort there)" };
  const drift = await sh(`for d in ${DEPLOYED.join(" ")}; do diff -rq --exclude='*.uid' --exclude='*.import' duo-arena/$d .duo-arena-stage/$d; done`, GP);
  // A retry after a stopped landing (a flaky bot, a fix committed in wt-merge): live is clean and every file where
  // staging differs from live is one merge-arcade changes (so it came from the earlier copy), not someone's edit.
  let retry = false;
  if (drift.out.trim() && !(await sh(`git status --porcelain -- ${DEPLOYED.join(" ")} | grep -v '\\.uid$'`, LIVE)).out) {
    const ours = new Set((await sh("git diff --name-only main merge-arcade", join(GP, "wt-merge"))).out.split("\n").filter(Boolean));
    const differing = [...drift.out.matchAll(/^Files duo-arena\/(\S+) and|^Only in \.duo-arena-stage\/(\S+): (\S+)|^Only in duo-arena\/(\S+): (\S+)/gm)]
      .map(m => m[1] ?? (m[2] ? `${m[2]}/${m[3]}` : `${m[4]}/${m[5]}`));
    retry = differing.length > 0 && differing.every(f => ours.has(f) || [...ours].some(o => o.startsWith(f + "/")));
  }
  if (drift.out.trim() && !retry) return { stop: "live!=stage", out: drift.out };
  await sh(`for d in ${DEPLOYED.join(" ")} tools addons/boot; do rsync -a --delete --exclude '*.import' --exclude '__pycache__' wt-merge/$d/ .duo-arena-stage/$d/; done; cp wt-merge/arcade.tscn .duo-arena-stage/; sed 's|^config/name="Duo Arena"$|config/name="Duo Arena Stage"|' wt-merge/project.godot > .duo-arena-stage/project.godot`, GP);
  const out: Record<string, string> = {};
  let ok = true;
  // story_pictures_test always: it pins core/story_card.gd SHARED_PICTURES (a game's pictures belong in its own
  // games/<game>/story_pictures.gd) and catches one name drawn by two games. progress_test always: a deepened game
  // without games/<game>/progress.gd would be missing from the arcade's Family Trophy Hall. whats_new_test always: a
  // game with a fresh feature commit needs an entry on the lobby's What's New board (arcade/whats_new.gd).
  // shared_picks_test always (once it exists): a game must build picks with core/pick_orbs.gd, attack tells with
  // core/warn_rings.gd and show modes as PickOrbs.mode() (one GENTLE / BRAVE / HARD look everywhere).
  const sharedPicks = await stat(join(STAGE, "tests/shared_picks_test.gd")).then(() => ["shared_picks_test"], () => [] as string[]);
  // Every test of the game being landed runs, not just the ones named (2026-11-12: dodge-deep2 named its deep test only
  // and dodge_ball_gen_test was skipped): tests/<botId>_*test.gd.
  const own = (await readdir(join(STAGE, "tests")).catch(() => [] as string[])).filter(f => f.startsWith(`${botId}_`) && f.endsWith("_test.gd")).map(f => f.slice(0, -3));
  for (const t of [...new Set([...genTests, ...own, "story_pictures_test", "progress_test", "whats_new_test", "layout_check_test", "vr_view_check_test", "bot_end_test", "core_math_test", ...REPO_GUARDS, ...sharedPicks])].filter(Boolean)) {
    // A REPO_GUARDS test whose branch hasn't landed yet (an agent adds its guard to the live dev.ts first, 2026-11-11:
    // contrast_test / vr_wrist_menu_test) can't run here: say so in the results instead of failing every landing.
    // Only REPO_GUARDS may be missing; a missing gen test or core guard still fails below.
    if (REPO_GUARDS.includes(t) && !genTests.includes(t) && !(await stat(join(STAGE, `tests/${t}.gd`)).then(() => true, () => false))) { out[t] = "not in this tree yet (its branch hasn't landed): not run"; continue; }
    // A test with a scene (extends Node, e.g. engine_ui_test) runs as that scene; a SceneTree script runs with -s.
    const scene = await stat(join(STAGE, `tests/${t}.tscn`)).then(() => true, () => false);
    const how = scene ? `--fixed-fps 60 res://tests/${t}.tscn`  /* ends itself (exit code = failures); timeout 600 caps it */ : `-s res://tests/${t}.gd`;
    // GEN_QUICK=1: generator tests check today's sample of seeds/dates (core/seeded.gd Seeded.quick()); the nightly
    // full sweep (tools/duo-nightly-tests) checks them all. A landing test over SLOW_TEST_S is flagged (dev.debt).
    const t0 = Date.now();
    out[t] = (await sh(`GEN_QUICK=1 DUO_PORT=${rport()} timeout 600 godot-test --headless --path . ${how} 2>&1 | grep -v OpenXR | grep -E "PASS|FAIL|SCRIPT ERROR" | tail -3; echo exit=\${PIPESTATUS[0]}`, STAGE)).out;
    const secs = Math.round((Date.now() - t0) / 1000);
    out[t] += ` (${secs} s)`;
    if (secs > SLOW_TEST_S) { out[t] += ` SLOW: over ${SLOW_TEST_S} s in a landing`; await noteSlowTest(t, secs, branch); }
    // Every test prints an explicit verdict, -s scripts too (paper_planes_sky_test exited 0 with only a count line,
    // 2026-11-11; tests/bot_end_test.gd fails a tests/*_test.gd with no PASS line in its code).
    if (!/PASS/.test(out[t])) out[t] += " (no PASS line)";
    ok &&= /exit=0/.test(out[t]) && !/FAIL|SCRIPT ERROR|no PASS line/.test(out[t]);
  }
  // The Deck bot checks games only: for a non-game botId (arcade_lobby: a tools / core landing) DECK_BOT_ONLY matches
  // nothing, and since BotEnd counts checks (0 checks = FAIL, 2026-11-12) that failed every tools-only landing.
  const isGame = await stat(join(STAGE, "games", botId)).then(() => true, () => false);
  if (isGame) {
    const deckOut = (await sh(`DECK_BOT_ONLY=${botId} DUO_PORT=${rport()} timeout 300 godot-test --headless --path . --fixed-fps 60 --quit-after 6000 res://tests/deck_bot.tscn 2>&1`, STAGE)).out;
    out.deck = deckOut.split("\n").filter(l => /BOT RESULT|SCRIPT ERROR/.test(l)).slice(-3).join("\n") + engineErrors(deckOut).slice(0, 3).map(e => `\nSCRIPT ERROR (engine): ${e}`).join("");
    if (/\(0 checks/.test(out.deck)) out.deck += " (no Deck checks ran for this game)";
    ok &&= /BOT RESULT: PASS/.test(out.deck) && !/SCRIPT ERROR|no Deck checks/.test(out.deck);
  } else out.deck = `not run: ${botId} is not a game (the Deck bot checks games)`;
  // Solo VR: the Frame hosting with no TV machine is a real way the family plays, and new bot checks kept assuming TV
  // players there (2026-11-11: 8 games, then treasure-deep2's "map pieces were dug up"). Run the game's bot that way.
  if (isGame && await stat(join(STAGE, `tests/${botId}_bot.tscn`)).then(() => true, () => false)) {
    const so = (await sh(`DUO_HOST=1 BOT_VR=1 BOT_END=62 DUO_PORT=${rport()} timeout 200 godot-test --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/${botId}_bot.tscn 2>&1`, STAGE)).out;
    const soErr = [...so.split("\n").filter(l => /SCRIPT ERROR/.test(l)), ...engineErrors(so)];
    out.solo_vr = (so.split("\n").filter(l => /BOT RESULT/.test(l)).pop() ?? "no BOT RESULT") + soErr.slice(0, 3).map(e => "\n" + e).join("");
    ok &&= /BOT RESULT: PASS/.test(out.solo_vr) && soErr.length === 0;
    // Seated / short VR player (eyes 1.15 m: the little ones): a pick row sinking into a drum kit and a fake head 0.4 m
    // too low only showed seated (2026-11-12: Rhythm Band, Dodge Ball, Paint and Guess).
    const se = (await sh(`DUO_HOST=1 BOT_VR=1 BOT_VR_SEATED=1 BOT_END=62 DUO_PORT=${rport()} timeout 200 godot-test --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/${botId}_bot.tscn 2>&1`, STAGE)).out;
    const seErr = [...se.split("\n").filter(l => /SCRIPT ERROR/.test(l)), ...engineErrors(se)];
    out.seated_vr = (se.split("\n").filter(l => /BOT RESULT/.test(l)).pop() ?? "no BOT RESULT") + seErr.slice(0, 3).map(e => "\n" + e).join("");
    ok &&= /BOT RESULT: PASS/.test(out.seated_vr) && seErr.length === 0;
    // Lone flat player: one Deck player, no VR, nobody else, must reach real play and keep going (loneRun above).
    const lr = await loneRun(botId);
    out.lone_flat = lr.summary;
    ok &&= lr.pass;
  }
  const res: string[] = [];
  for (const [id, o] of [["arcade", {}], [botId, { net: true, joiners: 1, seconds: 180 }], ...otherBots.map(x => [x, {}])] as [string, any][]) {
    process.env.DUO_PORT = String(rport());
    try {
      const r = await bots.run(id, o);
      ok &&= r.pass;
      res.push(`${id}: ` + r.runs.map((x: any) => `${x.mode}:${x.pass ? "ok" : "FAIL"} ${x.result} ${(x.failed || []).join(";")} ${(x.errors || []).join(";")}`).join(" | "));
    } finally { delete process.env.DUO_PORT; }
  }
  // Checks for shared code a landing touches (PATH_CHECKS): e.g. the telemetry push end to end.
  for (const pc of PATH_CHECKS) {
    if (!pc.paths.test((await sh("git diff --name-only main merge-arcade", join(GP, "wt-merge"))).out)) continue;
    const r = await sh(`timeout 300 ${pc.cmd} 2>&1 | tail -3`, STAGE);
    out[`check:${pc.name}`] = r.out;
    ok &&= r.code === 0 && new RegExp(pc.pass).test(r.out);
  }
  // Long guard bots for games whose deep errors only show far into a run (LAND_GUARDS): run when the branch touches
  // the game or lands it as botId.
  const touched = (await sh("git diff --name-only main merge-arcade", join(GP, "wt-merge"))).out;
  for (const [game, guards] of Object.entries(LAND_GUARDS)) {
    if (botId !== game && !touched.includes(`games/${game}/`)) continue;
    for (const gb of guards) {
      const r = await guardRun(gb);
      out[`guard:${gb.name}`] = r.summary;
      ok &&= r.pass;
    }
  }
  if (!ok) return { stop: "tests", out, res };
  // The message goes through a file: JSON.stringify'd "\n" stays a literal backslash-n inside bash quotes
  // (2026-10-29: a merge subject read "...tests)\n\nCo-Authored-By...").
  // msg = one subject line: duo-deploy adds the trailers (a multi-line msg once landed as one subject with literal \n).
  const msgFile = join(GP, "wt-merge/.git-land-msg");
  await writeFile(msgFile, `Merge branch 'merge-arcade' (${branch}: uids, tests)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01UPzLapMn8qMpWGwygUaPCg\n`);
  const d = await sh(`duo-deploy ${JSON.stringify(String(msg).split("\n")[0].trim())} 2>&1 | grep -v offline | tail -4; [ \${PIPESTATUS[0]} -eq 0 ] || { echo "DEPLOY REFUSED by duo-deploy: live main not merged"; exit 1; }; duo-deploy-deck 2>&1 | grep -v offline | tail -4; cd ${LIVE} && git merge -q --no-edit merge-arcade -F ${msgFile} && rm -f ${msgFile} && cd ../wt-merge && git merge -q --ff-only main && echo MERGED; cd ${LIVE} && git log --oneline -2 | cut -c1-60`);
  // The branch's worktree goes only after its Godots quit (an agent's offscreen run may still be up).
  const rm = /MERGED/.test(d.out) ? await removeWorktree(join(GP, `wt-${branch}`), branch) : { quit: [], out: "not removed: the merge into main didn't finish" };
  // Tools the branch changed in the repo (tools/multibot.ts, tools/brepl-dev.ts, ...) get installed where they run,
  // so the repo copy and the installed one never drift (2026-10-30: late-join's multibot.ts --late sat uninstalled).
  const installed = /MERGED/.test(d.out) ? await installTools(`${(await sh("git rev-parse HEAD^1", LIVE)).out}`) : [];
  return { deployed: /MERGED/.test(d.out), ...(/DEPLOY REFUSED/.test(d.out) ? { stop: "deploy" } : {}), out, res, deploy: d.out, removed: rm, installed };
}

export function help() {
  return `dev — Claude's dev loop (brepl). Image paths returned/shown come back as pictures via the brepl MCP tool.
  dev.land(branch, genTests, botId, otherBots, msg)  merge a finished branch via wt-merge, test in staging, deploy TV+Decks, merge live main
  dev.playstats({since?, game?})     how the family really played: RUN lines every machine pushed to the Steam Machine
  dev.playRuns({since?, game?})      those RUN lines as objects ({device, recv, ...run})
  dev.lone(ids?) / dev.loneRun(id, project?)  lone flat player check (one Deck player, no VR, nobody else): rounds advance, never frozen (dev.land runs it)
  dev.guard(game)                    a game's long guard bots (LAND_GUARDS; dev.land runs them when a branch touches the game)
  dev.nightly(tests?)                full sweep of every test (every seed/date; landings run GEN_QUICK samples); nightly at 03:30
  dev.debt()                         tech-debt scan: {clean, issues:[{kind, what, fix}]} (fix them straight away)
  dev.bots.list() / .run(id, {net, joiners}) / .all({only, net, concurrency})   headless bot tests in staging (net: host + joiners, tools/multibot.ts)
  dev.stage.diff() / .pull() / .deploy(msg)                            staging <-> live game
  dev.live.status() / start(proj) / stop() / restart(hard) / log(n, errorsOnly) / shot() / at("-30s", {span})   game on the TV (gdev)
  dev.screen.at("-10s") / .range(a, b)     TV screen recorder     dev.frame.at(t) / .online()   Steam Frame
  dev.voice.tail(n) / .since("14:30") / .say(text, audio) / .health()
  dev.pace()  dev.backlog.open() / .done(match, note) / .add(text)  dev.history(query)  dev.sh(cmd, cwd)
  dev.sweep({only, seconds, vr, concurrency, project})   play games offscreen with monkey input: problems + sheets
  dev.sweep({net: true, clients: 2, only})   host + N TV-machine clients per game over the network: joins, remote seats,
                                     fallbacks to local, errors/frozen per machine -> ~/.cache/sweep/<id>-net.json
  godot.launch(project) -> g: offscreen run (see godot.ts header): g.uiText() g.joy() g.eval() g.at() g.span() g.video()
  godot.launchGroup({project, scene, clients, vr}) -> {host, clients, all, port, status(), quit()}   networked machines
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
 *  posted to the channel as each finishes. Long: run it in bg(). project: another copy of the game (default staging).
 *  net: true plays each game as a NETWORK group instead (godot.launchGroup): one host + `clients` (default 2) TV
 *  machines on one port, the clients press A then mash; per game {id, ok, problems[], machines: [{machine: "host" |
 *  "client1".., port, net: {start, afterJoin, end}, errors, fps, sound, frozen, sheets}], sheets[]} in
 *  ~/.cache/sweep/<id>-net.json. Problems name the machine ("client 2 not connected (fell back to local)",
 *  "client1's P3 is not seated on the host", "host: 1 distinct error(s): ..."). One group at a time by default. */
/** deck: true = test as a Steam Deck would run it: 1280x800 (16:10) and DUO_MACHINE_KIND=deck. Or set width/height/env. */
export async function sweep(o: { only?: string[]; seconds?: number; concurrency?: number; vr?: boolean; net?: boolean; clients?: number; project?: string; deck?: boolean; width?: number; height?: number; env?: Record<string, string> } = {}) {
  if (o.deck) o = { ...o, width: o.width ?? 1280, height: o.height ?? 800, env: { DUO_MACHINE_KIND: "deck", ...(o.env ?? {}) } };
  sweepScreen = { w: o.width ?? 1920, h: o.height ?? 1080, env: o.env ?? {} };
  const proj = o.project ?? STAGE;
  const ids = o.only ?? (await readdir(join(proj, "games"))).filter(d => d !== "engine_template").sort();
  await mkdir(SWEEP, { recursive: true });
  const results: any[] = [];
  let next = 0;
  // net: a group is 1 + clients games, so one group at a time unless asked.
  const n = o.concurrency ?? (o.net ? 1 : await parallelGames());
  const tag = (o.net ? "-net" : "") + (o.vr ? "-vr" : "");
  (globalThis as any).send?.(o.net ? "sweep net" : "sweep", `${ids.length} games, ${n} ${o.net ? `group(s) of host + ${o.clients ?? 2} clients` : "games"} at a time`);
  await Promise.all(Array.from({ length: n }, async () => {
    while (next < ids.length) {
      const id = ids[next++];
      const r = o.net ? await sweepNetOne(id, o.seconds ?? 20, o.clients ?? 2, !!o.vr, proj) : await sweepOne(id, o.seconds ?? 20, !!o.vr, proj);
      results.push(r);
      await Bun.write(join(SWEEP, `${r.id}${tag}.json`), JSON.stringify(r, null, 1));
      const sheets = o.net ? r.machines.map((m: any) => `${m.machine}: ${m.sheets.join(" ")}`).join("\n") : `sheets: ${r.sheets.join(" ")}`;
      (globalThis as any).send?.(`sweep${o.net ? " net" : ""} ${r.id}`, (r.ok ? "ok" : r.problems.join("\n")) + (r.warnings?.length ? `\nwarnings: ${r.warnings.join("; ")}` : "") + `\n${sheets}`);  // text only: show() the sheets when reviewing
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
// The screen the current sweep runs at (checks use it; never assume 1920x1080).
let sweepScreen = { w: 1920, h: 1080, env: {} as Record<string, string> };

async function sweepOne(id: string, seconds: number, vr = false, project = STAGE) {
  const godot = (globalThis as any).godot;
  const r: any = { id, ok: false, problems: [] as string[], errors: [] as string[], fps: 0, sound: false, frozen: false, sheets: [] as string[] };
  let g: any;
  try {
    g = await godot.launch({ project, scene: `res://games/${id}/main.tscn`, vr, width: sweepScreen.w, height: sweepScreen.h, env: sweepScreen.env });
    const head = vr ? (await g.vr().catch(() => null))?.head : null;
    if (vr && !head) r.problems.push("no VR player in fake VR (BOT_VR=1)");
    await Bun.sleep(3000);
    const t0 = Date.now();
    for (let i = 0; Date.now() - t0 < seconds * 1000; i++) {
      const [name, opts] = MONKEY[i % MONKEY.length];
      if (g.child.exitCode !== null) break;
      await g.joy(name, opts ?? {}).catch(() => {});
      if (head && i % 2 === 0) await vrMash(g, head, i / 2);
      await Bun.sleep(400);
    }
    await inspect(g, r, head);
  } catch (e: any) {
    r.problems.push(`launch failed: ${String(e?.message ?? e).slice(0, 400)}`);
  } finally {
    await g?.quit().catch(() => {});
  }
  r.ok = !r.problems.length;
  return r;
}

// net: one host + `clients` TV machines of the game over one shared DUO_PORT (godot.launchGroup). Each client presses
// A (drop-in join) and then mashes like the monkey, all clients at once; the host only moves in fake VR (vr: true).
// Checks, on top of every machine's normal sweep checks (prefixed "host:" / "client2:"): each client really is a
// connected client (not fallen back to local play), it stayed connected, each of its seated players shows up on the
// host as a remote seat in the same slot, no two clients own the same slot, and the host sees one peer per client.
const LOCAL_KINDS = ["pad", "keyboard", "virtual", "local"];
async function sweepNetOne(id: string, seconds: number, clients: number, vr = false, project = STAGE) {
  const godot = (globalThis as any).godot;
  const r: any = { id, net: true, clients, ok: false, problems: [] as string[], warnings: [] as string[], machines: [] as any[], sheets: [] as string[], port: 0 };
  let grp: any;
  try {
    grp = await godot.launchGroup({ project, scene: `res://games/${id}/main.tscn`, clients, vr });
    r.port = grp.port;
    const names = ["host", ...grp.clients.map((_: any, i: number) => `client${i + 1}`)];
    const atStart = await grp.status();
    const head = vr ? (await grp.host.vr().catch(() => null))?.head : null;
    if (vr && !head) r.problems.push("host: no VR player in fake VR (BOT_VR=1)");
    await Bun.sleep(1500);
    for (const c of grp.clients) await c.joy("a").catch(() => {});  // drop in
    await Bun.sleep(2000);
    const afterJoin = await grp.status();
    const t0 = Date.now();
    for (let i = 0; Date.now() - t0 < seconds * 1000; i++) {
      const [name, opts] = MONKEY[i % MONKEY.length];
      await Promise.all([
        ...grp.clients.map((c: any) => c.child.exitCode === null ? c.joy(name, opts ?? {}).catch(() => {}) : null),
        head && i % 2 === 0 ? vrMash(grp.host, head, i / 2) : null,
      ]);
      await Bun.sleep(400);
    }
    const atEnd = await grp.status();
    // Network checks.
    const H = atEnd[0];
    if (!H.has_net) r.problems.push("not networked: no core/net.gd node found");
    else {
      if (H.mode !== "host") r.problems.push(`host is not hosting (mode ${H.mode})`);
      const owner: Record<number, string> = {};
      let connectedClients = 0;
      grp.clients.forEach((_: any, i: number) => {
        const name = `client ${i + 1}`, s0 = atStart[i + 1], s1 = atEnd[i + 1];
        if (s1.error) { r.problems.push(`${name}: no status (${s1.error})`); return; }
        const ok = s1.mode === "client" && s1.connected;
        if (!ok) {
          const was = s0.mode === "client" && s0.connected;
          r.problems.push(s0.mode === "local" || s1.mode === "local" && !was ? `${name} not connected (fell back to local)`
            : was ? `${name} dropped: connected at start, now mode ${s1.mode}${s1.connected ? "" : ", not connected"}`
            : `${name} not connected (mode ${s1.mode}, still trying to join)`);
          return;
        }
        connectedClients++;
        const mine = s1.seats.filter((x: any) => x.active && LOCAL_KINDS.includes(x.kind));
        if (!mine.length) r.problems.push(`${name}: connected but pressing A seated nobody${afterJoin[i + 1].pending?.length ? ` (still pending: slots ${afterJoin[i + 1].pending})` : ""}`);
        for (const seat of mine) {
          const P = `P${seat.slot + 1}`;
          if (owner[seat.slot]) r.problems.push(`${name} and ${owner[seat.slot]} both think they own ${P} (slot ${seat.slot})`);
          owner[seat.slot] = name;
          const onHost = H.seats.find((x: any) => x.slot === seat.slot);
          if (!onHost) r.problems.push(`${name}'s ${P} is not seated on the host`);
          else if (onHost.kind !== "remote" || !onHost.active) r.problems.push(`${name}'s ${P} is on the host as ${onHost.kind}${onHost.active ? "" : " (inactive)"}, not a remote seat`);
        }
      });
      if (H.mode === "host" && H.peers.length !== connectedClients) r.problems.push(`host sees ${H.peers.length} peer(s) but ${connectedClients} client(s) are connected`);
    }
    // Every machine's normal checks (errors, crash, fps, sound, text, frozen) + its sheets.
    for (const [i, g] of grp.all.entries()) {
      const m: any = { machine: names[i], port: g.port, problems: [] as string[], errors: [] as string[], fps: 0, sound: false, frozen: false, sheets: [] as string[],
        net: { start: pick(atStart[i]), afterJoin: pick(afterJoin[i]), end: pick(atEnd[i]) } };
      await inspect(g, m, i === 0 ? head : null).catch((e: any) => m.problems.push(`inspect failed: ${e}`));
      r.machines.push(m);
      r.sheets.push(...m.sheets);
      // Slow fps is a warning here, not a problem: 1 + clients games share this machine's CPU/GPU, so it measures the rig.
      r.warnings.push(...m.problems.filter((p: string) => p.startsWith("slow:")).map((p: string) => `${names[i]}: ${p}`));
      r.problems.push(...m.problems.filter((p: string) => !p.startsWith("slow:")).map((p: string) => `${names[i]}: ${p}`));
    }
  } catch (e: any) {
    r.problems.push(`launch failed: ${String(e?.message ?? e).slice(0, 400)}`);
  } finally {
    await grp?.quit().catch(() => {});
  }
  r.ok = !r.problems.length;
  return r;
}
const pick = (s: any) => s && ({ mode: s.mode, connected: s.connected, peers: s.peers?.length ?? 0, seats: (s.seats ?? []).map((x: any) => `P${x.slot + 1}:${x.kind}${x.active ? "" : "(off)"}`).join(" "), ...(s.error ? { error: s.error } : {}) });

/** One step of the fake-VR monkey: look around, swing a hand, pull the trigger / press A, nudge the stick. */
async function vrMash(g: any, head: number[], k: number) {
  await g.vr({ look: [head[0] + Math.sin(k) * 3, head[1] + Math.cos(k * 1.3) * 0.5, head[2] - 3] }).catch(() => {});
  await g.vrSwing(k % 2 ? "left" : "right", [0, 0.2, -0.6], 0.15).catch(() => {});
  await g.vr({ trigger: k % 3 === 0 ? 1 : 0, a: k % 4 === 1, stick_l: [Math.sin(k), 0] }).catch(() => {});
  await g.vrSwing(k % 2 ? "left" : "right", [0, -0.2, 0.6], 0.15).catch(() => {});
}

/** The checks every sweep runs on one finished offscreen game, into r (problems, errors, fps, sound, frozen, sheets):
 *  crashed, errors in the log, slow, silent, text off screen / overlapping, frozen screen, plus its contact sheets. */
async function inspect(g: any, r: any, head: any = null) {
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
      && (i.rect[0] < -4 || i.rect[1] < -4 || i.rect[0] + i.rect[2] > sweepScreen.w + 4 || i.rect[1] + i.rect[3] > sweepScreen.h + 4))
      .map((i: any) => `"${String(i.text).slice(0, 30)}" @${i.rect.map((v: number) => Math.round(v)).join(",")}`);
    if (cut.length) r.problems.push(`text off screen: ${[...new Set(cut)].slice(0, 4).join("; ")}`);
    // Text drawn over other text (e.g. a timer pill on top of a score card).
    // (Labels stretched over most of the screen just centre their text, so their box says nothing: skip them.)
    const labels = (ui.items ?? []).filter((i: any) => i.text && String(i.text).trim() && i.rect && i.rect[2] > 2 && i.rect[3] > 2
      && i.rect[2] * i.rect[3] < 0.25 * sweepScreen.w * sweepScreen.h && !String(i.path).includes("/GDev/"));
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

// --- Steam Decks (and other devkit-paired SteamOS machines) ------------------------------------------
// Simon, 2026-10-24: "can you do all this through your brepl?" One place to drive paired handhelds over SSH.
// Machines: ssh aliases in ~/.ssh/config (simon-deck = Simon's Deck). Long-lived terminal programs run in a
// tmux session under `systemd-run --user` (SteamOS kills an SSH session's children when it ends).
export const deck = {
  host: "simon-deck",
  /** Run a shell command on the Deck: {code, out}. */
  sh(cmd: string, host = deck.host) { return sh(`ssh -o BatchMode=yes -o ConnectTimeout=5 ${host} ${shq(cmd)}`); },
  /** Is it reachable (on, awake, Developer Mode on)? */
  async up(host = deck.host) { return (await deck.sh("true", host)).code === 0; },
  /** Start a program in a detached tmux session that outlives SSH (e.g. "claude"). */
  async start(name: string, cmd: string, host = deck.host) {
    await deck.sh(`systemctl --user stop ${name} 2>/dev/null; tmux kill-session -t ${name} 2>/dev/null; true`, host);
    return deck.sh(`systemd-run --user --unit=${name} --property=Type=forking --setenv=TERM=xterm-256color --setenv=BROWSER=true --working-directory=$HOME tmux new-session -d -s ${name} -x 220 -y 50 ${shq(cmd + "; echo EXITED; sleep 900")}`, host);
  },
  /** The session's screen (last `lines` non-empty lines). */
  async screen(name: string, lines = 30, host = deck.host) {
    const r = await deck.sh(`tmux capture-pane -p -t ${name} -S -200`, host);
    return r.out.split("\n").filter(l => l.trim()).slice(-lines).join("\n");
  },
  /** Type into the session: text then Enter (enter=false to leave it), or tmux key names via keys([...]). */
  type(name: string, text: string, enter = true, host = deck.host) { return deck.sh(`tmux send-keys -t ${name} -l ${shq(text)}${enter ? `; tmux send-keys -t ${name} Enter` : ""}`, host); },
  keys(name: string, keys: string[], host = deck.host) { return deck.sh(`tmux send-keys -t ${name} ${keys.join(" ")}`, host); },
  stop(name: string, host = deck.host) { return deck.sh(`systemctl --user stop ${name}; tmux kill-session -t ${name}; true`, host); },
  /** Claude Code login without the Deck's browser: starts `claude`, walks the first-run screens, returns the
   *  sign-in URL to open on any device; then deck.claudeCode(code) types the code it shows. */
  async claudeLogin(host = deck.host) {
    await deck.start("claude-login", "$HOME/.local/bin/claude", host);
    for (let i = 0; i < 12; i++) {
      await Bun.sleep(2000);
      const s = await deck.screen("claude-login", 60, host);
      const m = s.replace(/\n/g, "").match(/https:\/\/claude\.com\/cai\/oauth\S+?(?=Paste code|$)/);
      if (m) return { url: m[0].replace(/\s+/g, ""), next: 'deck.claudeCode("<code from the page>")' };
      if (/Choose the text style|Select login method|Press Enter|Security notes|trust/i.test(s)) await deck.keys("claude-login", ["Enter"], host);
    }
    return { error: "no sign-in URL appeared", screen: await deck.screen("claude-login", 20, host) };
  },
  async claudeCode(code: string, host = deck.host) {
    await deck.type("claude-login", code.trim(), true, host);
    await Bun.sleep(4000);
    const ok = (await deck.sh("test -s ~/.claude/.credentials.json && echo yes", host)).out === "yes";
    return { loggedIn: ok, screen: await deck.screen("claude-login", 12, host) };
  },
  /** Push the arcade to the Deck (same as duo-deploy-deck). */
  deploy() { return sh("duo-deploy-deck"); },
};
const shq = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`;

/** Which games can be played by ONE player (Simon, 2026-10-24: a "playable as single player" filter): run each game
 *  locally offscreen with a single pad mashing for `seconds`, then report what's on screen: words that mean it's
 *  stuck waiting for more players, whether the picture keeps changing, and a sheet to look at. One game at a time. */
export async function soloCheck(o: { only?: string[]; seconds?: number } = {}) {
  const godot = (globalThis as any).godot;
  const ids = o.only ?? (await readdir(join(STAGE, "games"))).filter(d => d !== "engine_template").sort();
  const out: any[] = [];
  for (const id of ids) {
    let g: any;
    const r: any = { id, waiting: [] as string[], moving: false, sheet: "" };
    try {
      g = await godot.launch({ project: STAGE, scene: `res://games/${id}/main.tscn`, env: { DUO_MACHINE_KIND: "deck" } });
      await Bun.sleep(3000);
      const t0 = Date.now();
      for (let i = 0; Date.now() - t0 < (o.seconds ?? 18) * 1000; i++) {
        const [name, opts] = MONKEY[i % MONKEY.length];
        await g.joy(name, { ...(opts ?? {}), device: 0 }).catch(() => {});
        await Bun.sleep(350);
      }
      const ui = await g.uiText().catch(() => "");
      r.waiting = [...new Set((ui.match(/(waiting|wait for|needs? (at least )?\d|player 2|2 players|join to start|press a to join|connecting)[^"\n]{0,40}/gi) ?? []).map((s: string) => s.trim()))].slice(0, 4);
      const fr = await g.frames();
      const tail = fr.filter((f: any) => f.t > fr[fr.length - 1].t - 6);
      const sizes = await Promise.all(tail.map(async (f: any) => (await stat(f.path)).size));
      r.moving = new Set(sizes).size > 2;
      const end = fr.length ? fr[fr.length - 1].t : 0;
      r.sheet = (await g.span(end - 8, end, 1).catch(() => []))[0] ?? "";
    } catch (e: any) { r.error = String(e?.message ?? e).slice(0, 200); }
    finally { await g?.quit().catch(() => {}); }
    out.push(r);
    (globalThis as any).send?.(`solo ${id}`, `${r.waiting.length ? "WAITING: " + r.waiting.join(" | ") : "no waiting text"}; picture ${r.moving ? "moving" : "still"}${r.error ? "; " + r.error : ""}`, r.sheet ? [r.sheet] : []);
  }
  await Bun.write(join(HOME, ".cache/sweep/solo.json"), JSON.stringify(out, null, 1));
  return out.map(r => `${r.waiting.length || !r.moving || r.error ? "??" : "ok"} ${r.id}${r.waiting.length ? ": " + r.waiting.join(" | ") : ""}`).join("\n");
}

// fs as a brepl global (agents' snippets and the briefs use fs.promises.*): it used to exist only because an early
// session set it by hand, so a brepl restart lost it (2026-10-31).
import * as nodeFs from "node:fs";
// SHARED-GLOBALS GUARD (2026-11-11): brepl is ONE process for every agent, so globals are shared. One agent's bare
// `WT = ...` overwrote another agent's WT mid-run and that agent's tests ran in the wrong worktree. The core compiles
// each call with an indirect (0, eval)(...), so wrapping globalThis.eval lets brepl refuse a call that sets a GENERIC
// global (1-3 letters like g/W/SP/WT, or WORKTREE/PROJ/ROOT/DIR/BRANCH/STAGE/LIVE/PORT) before any of it runs.
// Use a local const inside the call, or a global prefixed with your branch (fishing_WT, fishing_g).
// "//@shared-ok" anywhere in a call skips the check (for a deliberate, shared name).
const GENERIC_GLOBAL = /^(?:[A-Za-z_$][\w$]{0,2}|WORKTREE|PROJ|PROJECT|ROOT|DIR|BRANCH|STAGE|LIVE|PORT)$/;
export function genericGlobals(code: string): string[] {
  if (code.includes("//@shared-ok")) return [];
  code = stripLiterals(code);
  const declared = new Set([...code.matchAll(/\b(?:const|let|var|function)\s+([A-Za-z_$][\w$]*)/g)].map(m => m[1]));
  for (const m of code.matchAll(/\b(?:const|let|var)\s*[{[]([^}\]]*)[}\]]/g))
    for (const p of m[1].split(/[,:\s=]+/)) if (p) declared.add(p.replace(/^\.\.\./, ""));
  // parameters: (a, b) => / async (r) => / x => / function f(a, b = 2)
  for (const m of code.matchAll(/\(([^()]*)\)\s*=>|\bfunction\b[^(]*\(([^()]*)\)|\b([A-Za-z_$][\w$]*)\s*=>/g))
    for (const p of (m[1] ?? m[2] ?? m[3] ?? "").split(/[,{}\[\]\s=]+/)) if (p) declared.add(p);
  const hit = new Set<string>();
  for (const m of code.matchAll(/globalThis\.([A-Za-z_$][\w$]*)\s*(?:\?\?|\|\||&&)?=(?![=>])/g)) if (GENERIC_GLOBAL.test(m[1])) hit.add(m[1]);
  for (const m of code.matchAll(/(?:^|\n|;|\{|\(|,)[ \t]*([A-Za-z_$][\w$]*)[ \t]*(?:\?\?|\|\||&&)?=(?![=>])/g))
    if (GENERIC_GLOBAL.test(m[1]) && !declared.has(m[1])) hit.add(m[1]);
  return [...hit];
}
// Strings, template literals, regex-free comments -> blanks, so text like "WT = 1" inside a string or a shell command
// (`DUO_PORT=1 godot-test ...`) never counts as an assignment.
function stripLiterals(s: string): string {
  let out = "", i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c === "/" && s[i + 1] === "/") { while (i < s.length && s[i] !== "\n") i++; continue; }
    if (c === "/" && s[i + 1] === "*") { const e = s.indexOf("*/", i + 2); i = e < 0 ? s.length : e + 2; out += " "; continue; }
    if (c === "'" || c === '"' || c === "`") {
      let depth = 0; i++;
      while (i < s.length) {
        if (s[i] === "\\") { i += 2; continue; }
        if (c === "`" && s[i] === "$" && s[i + 1] === "{") { depth++; i += 2; continue; }
        if (c === "`" && depth && s[i] === "}") { depth--; i++; continue; }
        if (s[i] === c && !depth) { i++; break; }
        if (c !== "`" && s[i] === "\n") break;
        i++;
      }
      out += '""'; continue;
    }
    out += c; i++;
  }
  return out;
}
function installGlobalsGuard() {
  const g: any = globalThis;
  g.__breplLint = (src: string) => {
    if (typeof src !== "string" || !src.startsWith("(async () =>")) return;
    const names = genericGlobals(src);
    if (names.length) throw new Error(`refused: this call sets the shared global${names.length > 1 ? "s" : ""} ${names.join(", ")}. brepl is ONE process for every agent, so another agent's call can overwrite a generic global (2026-11-11: a WT was overwritten and tests ran in the wrong worktree). Use a local const inside the call, or prefix the global with your branch (e.g. fishing_${names[0]}). Nothing ran.`);
  };
  if (!g.__evalGuard) {
    const orig = g.eval;
    const guarded = function (src: any) { g.__breplLint?.(src); return orig(src); };
    g.eval = guarded;
    g.__evalGuard = true;
  }
}
export function start() { (globalThis as any).fs ??= nodeFs; installGlobalsGuard(); }
