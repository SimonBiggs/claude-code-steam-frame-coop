// peers.ts (hot-reloadable brepl module): REPL-to-REPL channels between machines (Simon, 2026-10-24: let the Steam
// Machine's and the Deck's REPLs "send things to channels within each other's repls", "over the ssh connection").
// Like Rust channels rebuilt across machines: each brepl has a local INBOX socket (~/.cache/brepl/peer-in.sock)
// that only accepts {from, source, text, images} and puts it in the channel (which wakes the Claude watching it);
// no code runs. The Steam Machine's brepl-tunnel@<peer> service keeps one SSH connection per peer that forwards
// both inboxes (peer-<name>.sock on each side), so nothing new listens on the network.
//   peer(name).send(source, text, images)   a remote mpsc send into that machine's channel (pictures copied)
//   peer(name).pipe(source, stream)         stream lines across
//   peer(name).eval(code)                   run code in that REPL, oneshot reply (needs SSH access there)
import { mkdirSync, unlinkSync, readFileSync } from "node:fs";
import { inspect } from "node:util";

const CACHE = `${process.env.HOME}/.cache/brepl`;
const IMG_DIR = `${CACHE}/peer-img`;
const INBOX = `${CACHE}/peer-in.sock`;
let server: any = null;

export function start(ctx: { send: Function; show: Function }) {
  const { send, show } = ctx;
  mkdirSync(IMG_DIR, { recursive: true });
  const me = (() => { try { return readFileSync("/etc/hostname", "utf8").trim(); } catch { return "brepl"; } })();
  try { unlinkSync(INBOX); } catch {}
  server = Bun.listen({
    unix: INBOX,
    socket: {
      open(sk: any) { sk.data = ""; },
      data(sk: any, d: any) { sk.data += d.toString(); },
      async close(sk: any) {
        try {
          const m = JSON.parse(sk.data);
          const from = String(m.from || "peer").replace(/[^\w.-]/g, "_");
          const paths = await Promise.all((m.images || []).map(async (im: any, i: number) => {
            const out = `${IMG_DIR}/${Date.now()}-${from}-${i}-${String(im.name).replace(/[^\w.-]/g, "_")}`;
            await Bun.write(out, Buffer.from(String(im.b64), "base64"));
            return out;
          }));
          send(`${from}: ${String(m.source || "msg").slice(0, 60)}`, String(m.text ?? ""), paths);
        } catch (e) { send("⚠ peer inbox", `bad message: ${e}`); }
      },
    },
  });
  const packImages = async (paths: any) => Promise.all([paths].flat().filter(Boolean).map(async (p: string) => ({ name: String(p).split("/").pop(), b64: Buffer.from(await Bun.file(p).arrayBuffer()).toString("base64") })));
  const toPeer = (name: string, msg: any) => new Promise((ok, bad) => {
    Bun.connect({ unix: `${CACHE}/peer-${name}.sock`, socket: {
      open(sk: any) { sk.write(JSON.stringify(msg)); sk.end(); },
      close() { ok({ sent: name }); }, data() {}, error(_: any, e: any) { bad(e); },
      connectError(_: any, e: any) { bad(new Error(`no link to ${name} (is brepl-tunnel@${name} up?): ${e?.message ?? e}`)); },
    } }).catch(bad);
  });
  (globalThis as any).peer = (name: string) => ({
    send: async (source: string, text: any = "", images: any = []) => toPeer(name, { from: me, source, text: typeof text === "string" ? text : inspect(text, { depth: 4 }), images: await packImages(images) }),
    pipe: (source: string, readable: any) => { (async () => { const dec = new TextDecoder(); for await (const c of readable) await toPeer(name, { from: me, source, text: typeof c === "string" ? c : dec.decode(c) }).catch(() => {}); })(); return `piping to ${name} as "${source}"`; },
    eval: async (code: string) => {
      const r = Bun.spawn(["ssh", "-o", "BatchMode=yes", name, "BREPL_RAW=1 $HOME/.local/bin/bun $HOME/.local/bin/brepl"], { stdin: new Blob([code]), stdout: "pipe", stderr: "pipe" });
      let out = await new Response(r.stdout).text();
      out += await new Response(r.stderr).text();
      await r.exited;
      const m = out.match(/\u0001SHOW (.*)\n?/);
      if (m) {
        const local: string[] = [];
        for (const p of JSON.parse(m[1])) {
          const dst = `${IMG_DIR}/${Date.now()}-${name}-${String(p).split("/").pop()}`;
          await Bun.spawn(["scp", "-q", "-o", "BatchMode=yes", `${name}:${p}`, dst]).exited;
          local.push(dst);
        }
        show(local);
      }
      return out.replace(/\u0001SHOW .*\n?/, "").trimEnd();
    },
  });
  (globalThis as any).peers = { me, inbox: INBOX };
}

export function stop() {
  try { server?.stop(true); } catch {}
  server = null;
}
