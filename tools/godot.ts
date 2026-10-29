// godot.ts: run a Godot project OFFSCREEN and drive it from Bun (brepl: `godot` is preloaded).
// The game renders on the GPU inside a headless gamescope (nothing on the TV), with no sound, no VR,
// no access to the real controllers (bwrap hides /dev/input), its own user:// data and its own ports,
// so it can run next to someone playing. Control goes through addons/gdev/control.gd (HTTP JSON).
//
//   g = await godot.launch("duo-arena")                 // or {project, scene, width, height, env}
//   await g.ui()                                         // visible buttons/labels + focus
//   await g.joy("right"); await g.joy("a")              // dpad/buttons/sticks: a b x y lb rb start back up down left right lx ly ...
//   await g.action("ui_accept"); await g.key("Enter"); await g.click("/root/Arcade/.../Button")
//   await g.eval("scene.name")                           // GDScript; tree, root, scene, find("*Kart*") in scope
//   await g.shot()                                       // PNG path (Read it), default ~/.cache/gdev-offscreen/<port>/shot.png
//   await g.log(30); await g.quit()                      // godot.list(), godot.stopAll()
//   g = await godot.launch({project, scene, vr: true})   // fake VR player (BOT_VR=1): g.vr({head, look, left, right,
//     trigger, grip, a, b, stick_l, stick_r}), g.vrSwing("right", [0,.3,-.6]), g.vrTrigger(), g.vrShot() = headset view,
//     g.span(a, b, fps, {vr: true}) / g.at(t, {vr: true}) = the recorded headset view
//   Several MACHINES (one host + TV-machine clients, networked over one shared DUO_PORT on 127.0.0.1):
//   grp = await godot.launchGroup({project, scene, clients: 2, vr, record})   // host DUO_HOST=1 (+BOT_VR=1 if vr), clients
//     DUO_JOIN=127.0.0.1 joining one at a time; -> {host, clients: Game[], all, port, status(), quit()}
//   await grp.status()   // per machine: {machine: "host"|"client1"|.., mode: host/client/local, connected, peers,
//     seats: [{slot, kind: remote/pad/keyboard/virtual (core/party.gd) or vr/remote/ghost/local (main.players), active}]}
//   await godot.netStatus(g)  // the same for one Game;  godot.launch({..., duoPort}) picks the network port (default control+1000)
import { spawn, type ChildProcess } from "node:child_process";
import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";

const HOME = process.env.HOME!;
const GDEV = join(HOME, ".local/share/gdev");
const RUNS = join(HOME, ".cache/gdev-offscreen");
const AUTOLOAD = 'GDev="*res://addons/gdev/bridge.gd"';

export type RecordOpts = { fps?: number; width?: number };
/** record: on by default at 30 fps, 960 px (Simon: "while headless is running you should always be recording at 30 frames per second"; it feeds at/span/video) so g.at(...) can show any past moment; false turns it off. */
/** vr: true runs the game's VR player in fake VR (BOT_VR=1): drive it with g.vr(...), see through it with g.vrShot(). */
/** duoPort: the game's network port (DUO_PORT); default control port + 1000 (unique per launch). Give several launches the
 *  same one to network them (launchGroup does). */
export type LaunchOpts = { project: string; scene?: string; width?: number; height?: number; env?: Record<string, string>; timeout?: number; record?: boolean | RecordOpts; vr?: boolean; duoPort?: number };
// Async on purpose: a spawnSync here would freeze the whole brepl (no 3 s backgrounding, no polls) while it runs.
const sh = async (cmd: string[]) => {
  const p = Bun.spawn(cmd, { cwd: safeCwd(), stdout: "pipe", stderr: "pipe" });
  const [out, err, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
  if (code) throw new Error(`${cmd[0]} failed: ${err.slice(-600)}`);
  return out;
};

/** A child started from a deleted folder (a removed worktree as brepl's cwd) logs "getcwd(...) is null" and can't open
 *  res:// (2026-10-29). Every spawn here runs from a folder that exists: brepl itself goes HOME when its cwd is gone. */
export function safeCwd(dir?: string): string {
  try { if (!existsSync(process.cwd())) process.chdir(process.env.HOME!); } catch { process.chdir(process.env.HOME!); }
  return dir && existsSync(dir) ? dir : process.env.HOME!;
}

const running = new Map<number, Game>();

/** Copy the bridge + control server into the project and make sure the GDev autoload is there (like `gdev start`). */
async function install(proj: string) {
  const dst = join(proj, "addons/gdev");
  await mkdir(dst, { recursive: true });
  for (const f of ["bridge.gd", "caption.gd", "control.gd"]) {
    const src = join(GDEV, f);
    const [a, b] = await Promise.all([readFile(src).catch(() => null), readFile(join(dst, f)).catch(() => null)]);
    if (a && (!b || !a.equals(b))) await copyFile(src, join(dst, f));
  }
  const cfg = join(proj, "project.godot");
  let text = await readFile(cfg, "utf8");
  if (!text.includes(AUTOLOAD)) {
    text = text.includes("[autoload]\n") ? text.replace("[autoload]\n", `[autoload]\n\n${AUTOLOAD}\n`) : `${text.trimEnd()}\n\n[autoload]\n\n${AUTOLOAD}\n`;
    await writeFile(cfg, text);
  }
}

/** Wait (up to 3 min) while the machine is short of memory, so test games never push the family's game into the
 *  kernel's OOM killer (Simon's Steam Machine has 15 GB and often runs a big game; we saw 0.9 GB free). */
async function waitForMemory(minGB = 2.5) {
  for (let i = 0; i < 90; i++) {
    const mem = await readFile("/proc/meminfo", "utf8");
    const gb = parseInt(mem.match(/MemAvailable:\s+(\d+)/)?.[1] ?? "0") / 1048576;
    if (gb >= minGB) return;
    if (i === 0) (globalThis as any).send?.("⚠ godot.launch", `waiting: only ${gb.toFixed(1)} GB free (need ${minGB})`);
    await Bun.sleep(2000);
  }
  throw new Error(`not enough free memory to start a test game (need ${minGB} GB)`);
}

export async function launch(o: LaunchOpts | string): Promise<Game> {
  const opts: LaunchOpts = typeof o === "string" ? { project: o } : o;
  await waitForMemory();
  const proj = opts.project.includes("/") ? resolve(opts.project) : join(HOME, "GodotProjects", opts.project);
  if (!(await Bun.file(join(proj, "project.godot")).exists())) throw new Error(`no Godot project at ${proj}`);
  await install(proj);
  const w = opts.width ?? 1920, h = opts.height ?? 1080;
  // Ports handed out by this REPL stay reserved until the game quits: probing a port and releasing it before the
  // game binds it raced between concurrent launches ("gdev control: cannot listen"). Kept on globalThis so a hot
  // reload of this module keeps the reservations.
  const reserved: Set<number> = ((globalThis as any).__gdevPorts ??= new Set<number>());
  let port = 0;
  for (let i = 0; i < 200 && !port; i++) {
    const p = 21000 + Math.floor(Math.random() * 8000);
    if (reserved.has(p) || reserved.has(p + 1000)) continue;
    try { Bun.listen({ hostname: "127.0.0.1", port: p, socket: { data() {} } }).stop(true); port = p; } catch {}
  }
  reserved.add(port);
  reserved.add(port + 1000);
  const dir = join(RUNS, String(port));
  await mkdir(join(dir, "data"), { recursive: true });
  const logPath = join(dir, "game.log");
  // No real controllers: hide /dev/input AND every /dev/hidraw* (Godot's SDL reads pads through hidraw too; a
  // family member's PS4 pad was steering offscreen tests), and turn SDL's HIDAPI driver off for good measure.
  const hidraw = (await readdir("/dev").catch(() => [] as string[])).filter(f => f.startsWith("hidraw")).flatMap(f => ["--ro-bind", "/dev/null", `/dev/${f}`]);
  // Never take the TV's displays: Gaming Mode's games were opening into an offscreen gamescope that held X display :1
  // (Steam sends games to :1, and X abstract sockets are shared between namespaces). So each run gets a private /tmp
  // whose lock files reserve :0-:19 (test displays land on :20-:32; Xwayland only searches up to :32), and its own XDG_RUNTIME_DIR for gamescope-N sockets.
  // Only gamescope gets the private /tmp: Godot runs in a nested bwrap with the real /tmp bound back (tests save files
  // there), and still reaches its Xwayland through the abstract X socket.
  const hostTmp = join(dir, "hosttmp");
  await mkdir(hostTmp, { recursive: true });
  const args = ["--dev-bind", "/", "/", "--tmpfs", "/dev/input", ...hidraw, "--bind", "/tmp", hostTmp, "--tmpfs", "/tmp", "--die-with-parent",
    "sh", "-c", 'for i in $(seq 0 19); do printf "%10d\\n" $$ > /tmp/.X$i-lock; done; exec "$@"', "sh",
    "gamescope", "--backend", "headless", "-W", String(w), "-H", String(h), "-w", String(w), "-h", String(h), "--",
    "bwrap", "--dev-bind", "/", "/", "--bind", hostTmp, "/tmp", "--die-with-parent", "godot", "--path", proj, "--audio-driver", "Dummy", "--xr-mode", "off", "--resolution", `${w}x${h}`, ...(opts.scene ? [opts.scene] : [])];
  await mkdir(join(dir, "run"), { recursive: true, mode: 0o700 });
  const env = { ...process.env, ...(opts.vr ? { BOT_VR: "1" } : {}), SDL_JOYSTICK_HIDAPI: "0", XDG_RUNTIME_DIR: join(dir, "run"), GDEV_CONTROL_PORT: String(port), XDG_DATA_HOME: join(dir, "data"), DUO_PORT: String(opts.duoPort ?? port + 1000), ...opts.env };
  for (const k of ["DUO_HOST", "DUO_JOIN"]) if (!opts.env?.[k]) delete env[k];  // local unless asked
  for (const k of ["DISPLAY", "WAYLAND_DISPLAY", "GAMESCOPE_WAYLAND_DISPLAY"]) delete env[k];  // never the TV's display
  const log = Bun.file(logPath).writer();
  // Low CPU priority so offscreen tests never make the family's game on the TV stutter.
  const child = spawn("nice", ["-n", "10", "bwrap", ...args], { env, cwd: safeCwd(proj), detached: true, stdio: ["ignore", "pipe", "pipe"] });
  const write = (b: Buffer) => { log.write(b); log.flush(); };
  child.stdout!.on("data", write);
  child.stderr!.on("data", write);
  const g = new Game(port, proj, child, logPath, dir);
  running.set(port, g);
  startReaper();
  child.on("exit", () => running.delete(port));
  const deadline = Date.now() + (opts.timeout ?? 60_000);
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`game exited (${child.exitCode}) before it was ready:\n${await g.logTail(25)}`);
    try {
      await g.cmd("ping");
      if (opts.record !== false) await g.record(typeof opts.record === "object" ? opts.record : {});
      return g;
    } catch { await Bun.sleep(300); }
  }
  await g.quit();
  throw new Error(`no control server after ${(opts.timeout ?? 60_000) / 1000}s:\n${await g.logTail(25)}`);
}

export class Game {
  lastUsed = Date.now();  // the last g.* call (the reaper quits games nobody drives)
  constructor(public port: number, public project: string, public child: ChildProcess, public logPath: string, public dir: string) {}

  async cmd(cmd: string, args: Record<string, unknown> = {}): Promise<any> {
    this.lastUsed = Date.now();
    const r = await fetch(`http://127.0.0.1:${this.port}/`, { method: "POST", body: JSON.stringify({ cmd, ...args }) });
    const out = await r.json();
    if (out && typeof out === "object" && "error" in out) throw new Error(`${cmd}: ${out.error}${out.source ? `\n${out.source}\n${await this.logTail(8)}` : ""}`);
    return out;
  }
  ping() { return this.cmd("ping"); }
  async eval(code: string) { return (await this.cmd("eval", { code })).value; }
  async tree(path = "/root", depth = 3) { return (await this.cmd("tree", { path, depth })).tree; }
  ui() { return this.cmd("ui"); }
  /** Compact text view of ui(): one line per visible button/label, focused one marked with ▶. */
  async uiText() {
    const u = await this.ui();
    return u.items.map((i: any) => `${i.focus ? "▶" : " "} ${i.class.padEnd(14)} ${JSON.stringify(i.text ?? "")} @${i.rect?.join(",")}  ${i.path}`).join("\n");
  }
  joy(button: string, o: { frames?: number; device?: number; value?: number } = {}) { return this.cmd("press", { joy: button, ...o }); }
  key(key: string, o: { frames?: number } = {}) { return this.cmd("press", { key, ...o }); }
  action(action: string, o: { frames?: number } = {}) { return this.cmd("press", { action, ...o }); }
  click(target: string | [number, number]) { return this.cmd("click", typeof target === "string" ? { node: target } : { x: target[0], y: target[1] }); }
  wait(frames = 1) { return this.cmd("wait", { frames }); }
  sleep(seconds: number) { return this.cmd("wait", { seconds }); }
  speed(value: number) { return this.cmd("speed", { value }); }
  scene(path: string) { return this.cmd("scene", { path }); }
  async shot(path = join(this.dir, "shot.png"), width = 1280) { return (await this.cmd("shot", { path, width })).path as string; }
  // --- Fake VR (launch with vr: true) ---
  /** Drive the VR player: {head, look, left, right: [x,y,z] world (relative: true = move by), trigger, grip: 0..1,
   *  a, b: bool, stick_l, stick_r: [x,y]}. Returns head/hand positions; g.vr() just reports them. */
  vr(o: Record<string, any> = {}) { return this.cmd("vr", o); }
  /** Squeeze the trigger for `seconds` then let go (a swing, a grab, a shot). */
  async vrTrigger(seconds = 0.3, value = 1) { await this.vr({ trigger: value }); await Bun.sleep(seconds * 1000); return this.vr({ trigger: 0 }); }
  /** Move a hand from where it is by [dx,dy,dz] over `seconds` (a punch, a swing, a throw), in steps. */
  async vrSwing(hand: "left" | "right", by: [number, number, number], seconds = 0.3) {
    const steps = Math.max(2, Math.round(seconds * 30));
    for (let i = 0; i < steps; i++) { await this.vr({ [hand]: by.map(v => v / steps), relative: true }); await Bun.sleep((seconds * 1000) / steps); }
    return this.vr();
  }
  /** What the headset would show: PNG from the VR head camera (or any Camera3D node path). */
  async vrShot(path = join(this.dir, "vr.png"), o: { camera?: string; width?: number; height?: number } = {}) { return (await this.cmd("camshot", { path, ...o })).path as string; }
  // --- Recorder: frames in <dir>/rec/<ms>.jpg, inputs + marks in rec/events.txt and the overlay ---
  recDir = "";
  recStart = 0;  // Date.now() when recording started (frame names are ms after this)
  async record(o: RecordOpts = {}) {
    this.recDir = join(this.dir, "rec");
    await sh(["rm", "-rf", this.recDir]);
    await this.cmd("record", { dir: this.recDir, fps: o.fps ?? 30, width: o.width ?? 960 });
    this.recStart = Date.now();
    return this.recDir;
  }
  stopRecording() { return this.cmd("record", { stop: true }); }
  /** Note shown in the recording overlay and the events list ("trying the pause menu"). */
  mark(text: string, seconds = 3) { return this.cmd("mark", { text, seconds }); }
  /** [{t, text}] of inputs and marks, t = seconds since recording started. */
  async events(): Promise<{ t: number; text: string }[]> {
    try {
      return (await readFile(join(this.recDir, "events.txt"), "utf8")).trim().split("\n").filter(Boolean)
        .map(l => ({ t: parseFloat(l), text: l.slice(l.indexOf(" ") + 1) }));
    } catch { return []; }
  }
  /** Recorded frames, oldest first: [{t (s), path}]. */
  /** Recorded frames, oldest first: [{t (s), path}]. vr: the VR head's view (fake VR runs record both). */
  async frames(o: { vr?: boolean } = {}) {
    const dir = o.vr ? join(this.recDir, "vr") : this.recDir;
    const names = (await Array.fromAsync(new Bun.Glob("*.jpg").scan(dir)).catch(() => [] as string[])).sort();
    return names.map(n => ({ t: parseInt(n) / 1000, path: join(dir, n) }));
  }
  /** Seconds since recording started for: a number (as is), "-3s" (3 s ago), or text matching an event
   *  ("▶ a" = the last A press; "2nd ▶ a" or "#2 ▶ a" = the 2nd one), which picks the moment just after it. */
  async time(when: number | string): Promise<number> {
    if (typeof when === "number") return when;
    const rel = when.match(/^-(\d+(?:\.\d+)?)s?$/);
    if (rel) return (Date.now() - this.recStart) / 1000 - parseFloat(rel[1]);
    const nth = when.match(/^(?:#(\d+)|(\d+)(?:st|nd|rd|th))\s+(.*)$/);
    const text = (nth ? nth[3] : when).toLowerCase();
    const hits = (await this.events()).filter(e => e.text.toLowerCase().includes(text));
    if (!hits.length) throw new Error(`no event matching "${text}" (see g.events())`);
    const e = nth ? hits[parseInt(nth[1] ?? nth[2]) - 1] : hits[hits.length - 1];
    if (!e) throw new Error(`only ${hits.length} events match "${text}"`);
    return e.t + 0.4;
  }
  /** The recorded frame at `when` (see time()): an image path to Read. */
  async at(when: number | string, o: { vr?: boolean } = {}) {
    const fr = await this.frames(o);
    if (!fr.length) throw new Error("nothing recorded (g.record() first)");
    const t = await this.time(when);
    const out = join(this.dir, o.vr ? "at-vr.jpg" : "at.jpg");
    await copyFile(fr.reduce((a, b) => (Math.abs(b.t - t) < Math.abs(a.t - t) ? b : a)).path, out);
    return out;
  }
  /** Many moments at once, from..to (anything time() takes; default the whole recording) at `fps` frames
   *  per second (default: whatever gives ~12). Returns image paths to Read: frames sheets, "moves" sheets
   *  (magenta = changed since the previous tile) and one motion summary (trails, blue early -> red late).
   *  Every tile also shows a spectrogram of the sound and the inputs pressed since the previous tile. */
  async span(from: number | string = 0, to?: number | string, fps?: number, o: { vr?: boolean } = {}) {
    const fr = await this.frames(o);
    if (!fr.length) throw new Error("nothing recorded (g.record() first)");
    const a = await this.time(from), b = to === undefined ? fr[fr.length - 1].t : await this.time(to);
    const step = fps ? 1 / fps : Math.max((b - a) / 11, 0.05);
    const picks: { t: number; path: string }[] = [];
    for (let t = a; t <= b + 1e-6; t += step) {
      const f = fr.reduce((x, y) => (Math.abs(y.t - t) < Math.abs(x.t - t) ? y : x));
      if (picks[picks.length - 1]?.path !== f.path) picks.push(f);
    }
    if (picks.length > 48) throw new Error(`${picks.length} frames is too many to look at: use a lower fps or a shorter span`);
    const rate = await readFile(join(this.recDir, "audio.rate"), "utf8").then(s => s.trim(), () => "44100");
    const out = await sh([join(GDEV, "recsheet.py"), join(this.dir, o.vr ? "span-vr" : "span"), "--audio", join(this.recDir, "audio.f32"), "--rate", rate,
      "--events", join(this.recDir, "events.txt"), ...picks.map(p => `${p.t.toFixed(2)}:${p.path}`)]);
    return out.trim().split("\n");
  }
  /** MP4 of the recording (or from..to), real speed. Returns its path (SendUserFile it to Simon). */
  async video(from: number | string = 0, to?: number | string, out = join(this.dir, "run.mp4"), o: { vr?: boolean } = {}) {
    const fr = await this.frames(o);
    const a = await this.time(from), b = to === undefined ? Infinity : await this.time(to);
    const pick = fr.filter(f => f.t >= a && f.t <= b);
    const list = pick.map((f, i) => `file '${f.path}'\nduration ${((pick[i + 1]?.t ?? f.t + 0.2) - f.t).toFixed(3)}`).join("\n");
    await writeFile(join(this.dir, "frames.txt"), list + `\nfile '${pick[pick.length - 1].path}'\n`);
    await sh(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", join(this.dir, "frames.txt"),
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "26", "-r", "30", out]);
    return out;
  }

  async logTail(n = 30) { try { return (await readFile(this.logPath, "utf8")).split("\n").filter(l => l && !l.includes("vulkan:") && !l.includes("sockets.c")).slice(-n).join("\n"); } catch { return ""; } }
  log(n = 30) { return this.logTail(n); }
  async quit() {
    try { await this.cmd("quit"); await Bun.sleep(500); } catch {}
    try { process.kill(-this.child.pid!, "SIGTERM"); } catch {}
    running.delete(this.port);
    const reserved: Set<number> | undefined = (globalThis as any).__gdevPorts;
    reserved?.delete(this.port);
    reserved?.delete(this.port + 1000);
  }
}

/** Orphans: a bg() job that threw between launch() and quit() left its offscreen game running for an hour, and a
 *  game whose worktree was removed spammed "getcwd ... is null" game-errors (2026-10-29). Every minute, quit games
 *  whose project folder is gone or that nobody has driven (no g.* call) for REAP_IDLE_MIN minutes. */
const REAP_IDLE_MIN = 15;
function startReaper() {
  if ((globalThis as any).__gdevReaper) return;
  (globalThis as any).__gdevReaper = setInterval(async () => {
    for (const g of [...running.values()]) {
      const gone = !(await Bun.file(join(g.project, "project.godot")).exists());
      const idle = Date.now() - g.lastUsed > REAP_IDLE_MIN * 60_000;
      if (gone || idle) {
        (globalThis as any).send?.("godot reaper", `quit the offscreen game on port ${g.port} (${gone ? "its project folder is gone" : `idle ${REAP_IDLE_MIN} min`}): ${g.project}`);
        await g.quit();
      }
    }
  }, 60_000);
}

export function list() { return [...running.values()].map(g => ({ port: g.port, project: g.project, pid: g.child.pid })); }
export async function stopAll() { for (const g of [...running.values()]) await g.quit(); }

// --- Multi-machine: one host + N "TV machines" (clients) on one shared DUO_PORT ---------------------------

/** GDScript run in a game (g.eval) that reports its network state: core/net.gd's mode/connected, the ENet peers,
 *  and who is seated: core/party.gd seats (device kinds) when the game has a party, else main.players (duo_arena style). */
const NET_STATUS_GD = `var nets := []
var parties := []
for n in root.find_children("*", "", true, false):
	var s = n.get_script()
	if s == null or n.is_queued_for_deletion():
		continue
	if s.resource_path == "res://core/net.gd":
		nets.append(n)
	elif s.resource_path == "res://core/party.gd":
		parties.append(n)
var net = nets[0] if nets.size() > 0 else null
if scene != null and scene.get("net") is Node:
	net = scene.get("net")
var mp := tree.get_multiplayer()
var has_peer: bool = mp.multiplayer_peer != null and not (mp.multiplayer_peer is OfflineMultiplayerPeer)
var out := {"scene": scene.scene_file_path if scene != null else "", "has_net": net != null}
out["mode"] = net.mode if net != null else "local"
out["connected"] = net.connected if net != null else false
out["peers"] = Array(mp.get_peers()) if has_peer else []
out["id"] = mp.get_unique_id() if has_peer else 0
var party = scene.get("party") if scene != null else null
if not (party is Node and party.has_method("active_slots")):
	party = parties[0] if parties.size() > 0 else null
var seats := []
if party != null:
	out["seats_from"] = "party"
	for s in party.active_slots():
		var d: int = party.device_of(s)
		var kind := "remote" if d == -3 else ("keyboard" if d == -2 else ("virtual" if d >= 40 else ("pad" if d >= 0 else "none")))
		seats.append({"slot": s, "device": d, "kind": kind, "active": true})
	var pend := []
	for s in 7:
		if party.is_pending(s):
			pend.append(s)
	out["pending"] = pend
else:
	var ps = scene.get("players") if scene != null else null
	out["seats_from"] = "players" if ps is Array else "none"
	if ps is Array:
		for p in ps:
			if p is Node and p.get("index") != null:
				var a = p.get("active")
				var kind := "vr" if p.get("vr") else ("remote" if p.get("remote") else ("ghost" if p.get("ghost") else "local"))
				seats.append({"slot": p.index, "kind": kind, "active": not (a is bool) or a})
out["seats"] = seats
out`;

export type NetStatus = { mode: string; connected: boolean; peers: number[]; id: number; has_net: boolean; scene: string;
  seats_from: "party" | "players" | "none"; seats: { slot: number; kind: string; device?: number; active: boolean }[]; pending?: number[]; error?: string };

/** Network state of one game (see NET_STATUS_GD). Never throws: {error} if the game can't answer. */
export async function netStatus(g: Game): Promise<NetStatus> {
  try { return await g.eval(NET_STATUS_GD); }
  catch (e: any) { return { mode: "?", connected: false, peers: [], id: 0, has_net: false, scene: "", seats_from: "none", seats: [], error: String(e?.message ?? e).split("\n")[0] }; }
}

/** A free UDP port (ENet is UDP) away from the control ports (21000-29000) and their +1000 defaults. */
async function freeUdpPort() {
  for (let i = 0; i < 50; i++) {
    const p = 31000 + Math.floor(Math.random() * 8000);
    try { const s = await Bun.udpSocket({ hostname: "0.0.0.0", port: p }); s.close(); return p; } catch {}
  }
  throw new Error("no free UDP port");
}

export type Group = { host: Game; clients: Game[]; port: number; all: Game[]; status(): Promise<({ machine: string; port: number } & NetStatus)[]>; quit(): Promise<void> };

/** One host + `clients` TV machines of the same game, networked over one shared DUO_PORT on 127.0.0.1 (bwrap shares
 *  the network). The host gets DUO_HOST=1 (+ BOT_VR=1 if vr), each client DUO_JOIN=127.0.0.1. The host starts first
 *  and must be hosting; then the clients join ONE AT A TIME (client 1 is always the first to join), each waited on
 *  until it either connected or gave up and fell back to local play (`settle` s, default 12). Each Game records as usual.
 *  group.status() -> per machine {machine: "host" | "client1".., mode, connected, peers, seats: [{slot, kind, active}]}. */
export async function launchGroup(o: { project: string; scene?: string; clients?: number; vr?: boolean; record?: boolean | RecordOpts;
  env?: Record<string, string>; settle?: number; width?: number; height?: number }): Promise<Group> {
  const port = await freeUdpPort();
  const base = { project: o.project, scene: o.scene, record: o.record ?? true, duoPort: port, width: o.width, height: o.height };
  const games: Game[] = [];
  const quit = async () => { await Promise.all(games.map(g => g.quit().catch(() => {}))); };
  const settle = async (g: Game, done: (s: NetStatus) => boolean) => {
    const until = Date.now() + (o.settle ?? 12) * 1000;
    let s = await netStatus(g);
    while (!done(s) && Date.now() < until && g.child.exitCode === null) { await Bun.sleep(300); s = await netStatus(g); }
    return s;
  };
  try {
    const host = await launch({ ...base, vr: o.vr, env: { ...o.env, DUO_HOST: "1" } });
    games.push(host);
    await settle(host, s => s.mode === "host" || !s.has_net);
    const clients: Game[] = [];
    for (let i = 0; i < (o.clients ?? 2); i++) {
      const c = await launch({ ...base, env: { ...o.env, DUO_JOIN: "127.0.0.1" } });
      games.push(c); clients.push(c);
      await settle(c, s => (s.mode === "client" && s.connected) || s.mode === "local" || !s.has_net);
    }
    const names = ["host", ...clients.map((_, i) => `client${i + 1}`)];
    return {
      host, clients, port, all: games, quit,
      status: () => Promise.all(games.map(async (g, i) => ({ machine: names[i], port: g.port, ...(await netStatus(g)) }))),
    };
  } catch (e) { await quit(); throw e; }
}
