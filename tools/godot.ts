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
import { spawn, type ChildProcess } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const HOME = process.env.HOME!;
const GDEV = join(HOME, ".local/share/gdev");
const RUNS = join(HOME, ".cache/gdev-offscreen");
const AUTOLOAD = 'GDev="*res://addons/gdev/bridge.gd"';

export type RecordOpts = { fps?: number; width?: number };
/** record: on by default (5 fps, 960 px) so g.at(...) can show any past moment; false turns it off. */
export type LaunchOpts = { project: string; scene?: string; width?: number; height?: number; env?: Record<string, string>; timeout?: number; record?: boolean | RecordOpts };
const sh = (cmd: string[]) => { const r = Bun.spawnSync(cmd, { stderr: "pipe" }); if (r.exitCode) throw new Error(`${cmd[0]} failed: ${r.stderr.toString().slice(-400)}`); };

const running = new Map<number, Game>();

/** Copy the bridge + control server into the project and make sure the GDev autoload is there (like `gdev start`). */
function install(proj: string) {
  const dst = join(proj, "addons/gdev");
  mkdirSync(dst, { recursive: true });
  for (const f of ["bridge.gd", "caption.gd", "control.gd"]) {
    const src = join(GDEV, f);
    if (existsSync(src) && (!existsSync(join(dst, f)) || !readFileSync(src).equals(readFileSync(join(dst, f))))) copyFileSync(src, join(dst, f));
  }
  const cfg = join(proj, "project.godot");
  let text = readFileSync(cfg, "utf8");
  if (!text.includes(AUTOLOAD)) {
    text = text.includes("[autoload]\n") ? text.replace("[autoload]\n", `[autoload]\n\n${AUTOLOAD}\n`) : `${text.trimEnd()}\n\n[autoload]\n\n${AUTOLOAD}\n`;
    writeFileSync(cfg, text);
  }
}

export async function launch(o: LaunchOpts | string): Promise<Game> {
  const opts: LaunchOpts = typeof o === "string" ? { project: o } : o;
  const proj = opts.project.includes("/") ? resolve(opts.project) : join(HOME, "GodotProjects", opts.project);
  if (!existsSync(join(proj, "project.godot"))) throw new Error(`no Godot project at ${proj}`);
  install(proj);
  const w = opts.width ?? 1920, h = opts.height ?? 1080;
  let port = 0;
  for (let i = 0; i < 50 && !port; i++) {
    const p = 21000 + Math.floor(Math.random() * 8000);
    try { Bun.listen({ hostname: "127.0.0.1", port: p, socket: { data() {} } }).stop(true); port = p; } catch {}
  }
  const dir = join(RUNS, String(port));
  mkdirSync(join(dir, "data"), { recursive: true });
  const logPath = join(dir, "game.log");
  const args = ["--dev-bind", "/", "/", "--tmpfs", "/dev/input", "--tmpfs", "/tmp/.X11-unix", "--die-with-parent",
    "gamescope", "--backend", "headless", "-W", String(w), "-H", String(h), "-w", String(w), "-h", String(h), "--",
    "godot", "--path", proj, "--audio-driver", "Dummy", "--xr-mode", "off", "--resolution", `${w}x${h}`, ...(opts.scene ? [opts.scene] : [])];
  const env = { ...process.env, GDEV_CONTROL_PORT: String(port), XDG_DATA_HOME: join(dir, "data"), DUO_PORT: String(port + 1000), ...opts.env };
  for (const k of ["DUO_HOST", "DUO_JOIN"]) if (!opts.env?.[k]) delete env[k];  // local unless asked
  const log = Bun.file(logPath).writer();
  const child = spawn("bwrap", args, { env, detached: true, stdio: ["ignore", "pipe", "pipe"] });
  const write = (b: Buffer) => { log.write(b); log.flush(); };
  child.stdout!.on("data", write);
  child.stderr!.on("data", write);
  const g = new Game(port, proj, child, logPath, dir);
  running.set(port, g);
  child.on("exit", () => running.delete(port));
  const deadline = Date.now() + (opts.timeout ?? 60_000);
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`game exited (${child.exitCode}) before it was ready:\n${g.logTail(25)}`);
    try {
      await g.cmd("ping");
      if (opts.record !== false) await g.record(typeof opts.record === "object" ? opts.record : {});
      return g;
    } catch { await Bun.sleep(300); }
  }
  await g.quit();
  throw new Error(`no control server after ${(opts.timeout ?? 60_000) / 1000}s:\n${g.logTail(25)}`);
}

export class Game {
  constructor(public port: number, public project: string, public child: ChildProcess, public logPath: string, public dir: string) {}

  async cmd(cmd: string, args: Record<string, unknown> = {}): Promise<any> {
    const r = await fetch(`http://127.0.0.1:${this.port}/`, { method: "POST", body: JSON.stringify({ cmd, ...args }) });
    const out = await r.json();
    if (out && typeof out === "object" && "error" in out) throw new Error(`${cmd}: ${out.error}${out.source ? `\n${out.source}\n${this.logTail(8)}` : ""}`);
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
  // --- Recorder: frames in <dir>/rec/<ms>.jpg, inputs + marks in rec/events.txt and the overlay ---
  recDir = "";
  recStart = 0;  // Date.now() when recording started (frame names are ms after this)
  async record(o: RecordOpts = {}) {
    this.recDir = join(this.dir, "rec");
    Bun.spawnSync(["rm", "-rf", this.recDir]);
    await this.cmd("record", { dir: this.recDir, fps: o.fps ?? 5, width: o.width ?? 960 });
    this.recStart = Date.now();
    return this.recDir;
  }
  stopRecording() { return this.cmd("record", { stop: true }); }
  /** Note shown in the recording overlay and the events list ("trying the pause menu"). */
  mark(text: string, seconds = 3) { return this.cmd("mark", { text, seconds }); }
  /** [{t, text}] of inputs and marks, t = seconds since recording started. */
  events(): { t: number; text: string }[] {
    try {
      return readFileSync(join(this.recDir, "events.txt"), "utf8").trim().split("\n").filter(Boolean)
        .map(l => ({ t: parseFloat(l), text: l.slice(l.indexOf(" ") + 1) }));
    } catch { return []; }
  }
  /** Recorded frames, oldest first: [{t (s), path}]. */
  frames() {
    const names = [...new Bun.Glob("*.jpg").scanSync(this.recDir)].sort();
    return names.map(n => ({ t: parseInt(n) / 1000, path: join(this.recDir, n) }));
  }
  /** Seconds since recording started for: a number (as is), "-3s" (3 s ago), or text matching an event
   *  ("▶ a" = the last A press; "2nd ▶ a" or "#2 ▶ a" = the 2nd one), which picks the moment just after it. */
  time(when: number | string): number {
    if (typeof when === "number") return when;
    const rel = when.match(/^-(\d+(?:\.\d+)?)s?$/);
    if (rel) return (Date.now() - this.recStart) / 1000 - parseFloat(rel[1]);
    const nth = when.match(/^(?:#(\d+)|(\d+)(?:st|nd|rd|th))\s+(.*)$/);
    const text = (nth ? nth[3] : when).toLowerCase();
    const hits = this.events().filter(e => e.text.toLowerCase().includes(text));
    if (!hits.length) throw new Error(`no event matching "${text}" (see g.events())`);
    const e = nth ? hits[parseInt(nth[1] ?? nth[2]) - 1] : hits[hits.length - 1];
    if (!e) throw new Error(`only ${hits.length} events match "${text}"`);
    return e.t + 0.4;
  }
  /** The recorded frame at `when` (see time()): an image path to Read. */
  at(when: number | string) {
    const fr = this.frames();
    if (!fr.length) throw new Error("nothing recorded (g.record() first)");
    const t = this.time(when);
    const out = join(this.dir, "at.jpg");
    copyFileSync(fr.reduce((a, b) => (Math.abs(b.t - t) < Math.abs(a.t - t) ? b : a)).path, out);
    return out;
  }
  /** Many moments at once, from..to (anything time() takes; default the whole recording) at `fps` frames
   *  per second (default: whatever gives ~12). Returns image paths to Read: frames sheets, "moves" sheets
   *  (magenta = changed since the previous tile) and one motion summary (trails, blue early -> red late).
   *  Every tile also shows a spectrogram of the sound and the inputs pressed since the previous tile. */
  span(from: number | string = 0, to?: number | string, fps?: number) {
    const fr = this.frames();
    if (!fr.length) throw new Error("nothing recorded (g.record() first)");
    const a = this.time(from), b = to === undefined ? fr[fr.length - 1].t : this.time(to);
    const step = fps ? 1 / fps : Math.max((b - a) / 11, 0.05);
    const picks: { t: number; path: string }[] = [];
    for (let t = a; t <= b + 1e-6; t += step) {
      const f = fr.reduce((x, y) => (Math.abs(y.t - t) < Math.abs(x.t - t) ? y : x));
      if (picks[picks.length - 1]?.path !== f.path) picks.push(f);
    }
    if (picks.length > 48) throw new Error(`${picks.length} frames is too many to look at: use a lower fps or a shorter span`);
    const rate = (() => { try { return readFileSync(join(this.recDir, "audio.rate"), "utf8").trim(); } catch { return "44100"; } })();
    const r = Bun.spawnSync([join(GDEV, "recsheet.py"), join(this.dir, "span"), "--audio", join(this.recDir, "audio.f32"), "--rate", rate,
      "--events", join(this.recDir, "events.txt"), ...picks.map(p => `${p.t.toFixed(2)}:${p.path}`)], { stderr: "pipe" });
    if (r.exitCode) throw new Error(`recsheet failed: ${r.stderr.toString().slice(-600)}`);
    return r.stdout.toString().trim().split("\n");
  }
  /** MP4 of the recording (or from..to), real speed. Returns its path (SendUserFile it to Simon). */
  video(from: number | string = 0, to?: number | string, out = join(this.dir, "run.mp4")) {
    const fr = this.frames();
    const a = this.time(from), b = to === undefined ? Infinity : this.time(to);
    const pick = fr.filter(f => f.t >= a && f.t <= b);
    const list = pick.map((f, i) => `file '${f.path}'\nduration ${((pick[i + 1]?.t ?? f.t + 0.2) - f.t).toFixed(3)}`).join("\n");
    writeFileSync(join(this.dir, "frames.txt"), list + `\nfile '${pick[pick.length - 1].path}'\n`);
    sh(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", join(this.dir, "frames.txt"),
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "26", "-r", "30", out]);
    return out;
  }

  logTail(n = 30) { try { return readFileSync(this.logPath, "utf8").split("\n").filter(l => l && !l.includes("vulkan:") && !l.includes("sockets.c")).slice(-n).join("\n"); } catch { return ""; } }
  log(n = 30) { return this.logTail(n); }
  async quit() {
    try { await this.cmd("quit"); await Bun.sleep(500); } catch {}
    try { process.kill(-this.child.pid!, "SIGTERM"); } catch {}
    running.delete(this.port);
  }
}

export function list() { return [...running.values()].map(g => ({ port: g.port, project: g.project, pid: g.child.pid })); }
export async function stopAll() { for (const g of [...running.values()]) await g.quit(); }
