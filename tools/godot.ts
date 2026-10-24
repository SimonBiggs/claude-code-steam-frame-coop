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

export type LaunchOpts = { project: string; scene?: string; width?: number; height?: number; env?: Record<string, string>; timeout?: number };

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
    try { await g.cmd("ping"); return g; } catch { await Bun.sleep(300); }
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
