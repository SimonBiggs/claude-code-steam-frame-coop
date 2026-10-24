// dev.ts: Claude's dev-loop helpers, preloaded in brepl as `dev` (Simon, 2026-10-24: "pull in a bunch of
// dev loop tooling into your brepl"). Everything returns data (or image paths, which the brepl MCP tool
// shows as pictures). dev.help() lists it all.
import { $ } from "bun";
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
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
  [join(HOME, ".local/share/brepl/mcp.ts")]: "tools/brepl-mcp.ts", [join(BIN, "frame-at")]: "tools/frame-at", [join(BIN, "duo-deploy-frame")]: "tools/duo-deploy-frame",
};

/** Run a shell command: {code, out} (stdout+stderr, trimmed). Never throws. */
export async function sh(cmd: string, cwd = HOME) {
  const r = await $`bash -c ${cmd}`.cwd(cwd).nothrow().quiet();
  return { code: r.exitCode, out: (r.stdout.toString() + r.stderr.toString()).trim() };
}
const lastPath = (out: string) => out.split("\n").map(l => l.trim()).reverse().find(l => /\.(jpe?g|png)$/i.test(l) && existsSync(l));

// --- Bot tests (headless, in the staging copy, at low priority) ------------------------------------

export const bots = {
  /** Game ids that have a bot test. */
  list(): string[] {
    return readdirSync(join(STAGE, "tests")).filter(f => f.endsWith("_bot.tscn")).map(f => f.replace(/_bot\.tscn$/, "")).sort();
  },
  /** Run one bot test. net: also run it as host + client over a local port. Returns pass/fail, failed checks, errors. */
  async run(id: string, o: { net?: boolean; seconds?: number } = {}) {
    const t0 = Date.now();
    const scene = `res://tests/${id}_bot.tscn`;
    const one = async (env: Record<string, string>, extra = "") => {
      const r = await $`nice -n 19 timeout ${o.seconds ?? 150} godot --headless --path ${STAGE} ${{ raw: extra }} ${scene}`.env({ ...process.env, ...env }).nothrow().quiet();
      return r.stdout.toString() + r.stderr.toString();
    };
    const parse = (out: string, mode: string) => ({
      mode,
      pass: /BOT RESULT: PASS/.test(out) && !/SCRIPT ERROR(?!: BOT)/.test(out),
      result: out.match(/BOT RESULT: .*/)?.[0] ?? "no BOT RESULT line (crashed or timed out?)",
      failed: [...out.matchAll(/BOT ASSERT FAILED: (.*)/g)].map(m => m[1]),
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
    const ids = o.only ?? bots.list();
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
      if (m) { (statSync(m[2]).mtimeMs > statSync(m[1]).mtimeMs ? liveNewer : stageNewer).push(m[1].slice(STAGE.length + 1)); continue; }
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
  shot: async () => lastPath((await sh("gdev shot")).out) ?? (await sh("gdev shot")).out,
  /** Frames + change maps around TIME (HH:MM:SS or -30s). */
  at: async (time: string, o: { span?: number; count?: number } = {}) => {
    const r = await sh(`gdev at ${time}${o.span ? ` --span ${o.span}` : ""}${o.count ? ` --count ${o.count}` : ""}`);
    return lastPath(r.out) ?? r.out;
  },
};

// --- Whole TV screen, Steam Frame, room ----------------------------------------------------------------

export const screen = {
  /** Contact sheet of the TV screen ending at TIME (HH:MM:SS or -10s). Needs screen-rec running. */
  at: async (time: string, n = 6) => { const r = await sh(`screen-rec at ${time} ${n}`); return lastPath(r.out) ?? r.out; },
  range: async (from: string, to: string, every = "") => { const r = await sh(`screen-rec range ${from} ${to} ${every}`); return lastPath(r.out) ?? r.out; },
};
export const frame = {
  /** What the Steam Frame headset showed around TIME. */
  at: async (time: string, o: { before?: number; after?: number; count?: number } = {}) => {
    const r = await sh(`frame-at ${time}${o.before ? ` --before ${o.before}` : ""}${o.after ? ` --after ${o.after}` : ""}${o.count ? ` --count ${o.count}` : ""}`);
    return lastPath(r.out) ?? r.out;
  },
  online: async () => (await sh("ssh -o ConnectTimeout=3 -o BatchMode=yes -i ~/.config/steamos-devkit/devkit_rsa steamos@frame true")).code === 0,
};

const VOICE_LOG = join(LIVE, ".dev/voice.log");
export const voice = {
  /** Last n transcript lines. */
  tail: (n = 20) => readFileSync(VOICE_LOG, "utf8").trimEnd().split("\n").slice(-n),
  /** Transcript lines since HH:MM[:SS] today. */
  since: (time: string) => readFileSync(VOICE_LOG, "utf8").split("\n").filter(l => (l.match(/^\[(\d\d:\d\d:\d\d)\]/)?.[1] ?? "") >= time.padEnd(8, ":00").slice(0, 8)),
  /** Speak on the TV (text only unless audio). */
  say: (text: string, audio = false) => sh(`${audio ? "CLAUDE_SAY_AUDIO=1 " : ""}claude-say ${JSON.stringify(text)}`),
  /** Is a mic plugged in and is the bridge transcribing? */
  health: async () => ({
    mic: !!(await sh("arecord -l | grep -q card && echo y")).out,
    bridge: (await sh("systemctl --user is-active voice-bridge")).out,
    lastLine: voice.tail(1)[0],
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
  open: () => readFileSync(BACKLOG, "utf8").split("\n").filter(l => l.startsWith("- [ ]")).map((l, i) => `${i + 1}. ${l.slice(6)}`),
  /** Tick the first open item containing `match`, with a note. */
  done(match: string, note = "") {
    const s = readFileSync(BACKLOG, "utf8");
    const i = s.split("\n").findIndex(l => l.startsWith("- [ ]") && l.includes(match));
    if (i < 0) throw new Error(`no open item contains "${match}"`);
    const lines = s.split("\n");
    lines[i] = lines[i].replace("- [ ]", `- [x]${note ? ` (${new Date().toISOString().slice(0, 10)}: ${note})` : ""}`);
    writeFileSync(BACKLOG, lines.join("\n"));
    return lines[i].slice(0, 160);
  },
  add(text: string) { writeFileSync(BACKLOG, readFileSync(BACKLOG, "utf8").trimEnd() + `\n- [ ] ${text}\n`); return backlog.open().length; },
};

/** Full-text search over every past Claude session on this machine. */
export const history = async (query: string, n = 10) => (await sh(`claude-history search ${JSON.stringify(query)} -n ${n}`)).out;

// --- Tech-debt scan (Simon's rule: fix debt the moment it's found) -----------------------------------

/** Everything that needs tidying: unmerged finished branches, stale worktrees, uncommitted work, staging drift,
 *  tool copies out of sync, broken services. Returns {clean, issues: [{kind, what, fix}]}. */
export async function debt() {
  const issues: { kind: string; what: string; fix: string }[] = [];
  const repos = readdirSync(GP).filter(d => existsSync(join(GP, d, ".git")) && statSync(join(GP, d, ".git")).isDirectory());
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
    if (existsSync(src) && existsSync(repo) && !readFileSync(src).equals(readFileSync(repo)))
      issues.push({ kind: "tool-copy", what: `${rel} differs from ${src.replace(HOME, "~")}`, fix: `cp ${src} ${repo} and commit` });
  }
  for (const s of ["voice-bridge", "claude-watchdog.timer"]) {
    const st = (await sh(`systemctl --user is-active ${s}`)).out;
    if (st !== "active") issues.push({ kind: "service", what: `${s} is ${st}`, fix: `systemctl --user status ${s}` });
  }
  const oom = (await sh("journalctl --since today 2>/dev/null | grep -i earlyoom | grep -i -c -E 'sending SIG(TERM|KILL) to'")).out;
  if (+oom > 0) issues.push({ kind: "oom", what: `earlyoom killed ${oom} processes today`, fix: "journalctl | grep earlyoom" });
  const leftovers = (await sh("pgrep -f '[b]ackend headless' | wc -l")).out;
  const ours = (await import(`${HOME}/.local/share/gdev/godot.ts`)).list().length;
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
