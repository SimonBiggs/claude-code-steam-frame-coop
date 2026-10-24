#!/usr/bin/env bun
// brepl MCP server (Simon, 2026-10-24: "can your brepl programmatically show you multiple screenshots
// without you needing to explicitly call view image?"). One tool, `brepl`: runs code in the persistent
// Bun REPL (~/.local/bin/brepl) and returns its text AND every image it showed: show(...paths) or a
// returned image path / array of paths, e.g. `g.span(0, 10, 2)` comes back as the sheets themselves.
// Registered with: claude mcp add brepl -s user -- ~/.local/bin/bun ~/.local/share/brepl/mcp.ts
import { readFileSync, statSync } from "node:fs";

const BREPL = `${process.env.HOME}/.local/bin/brepl`;
const MAX_IMAGES = 12, MAX_BYTES = 4_500_000;
const MIME: Record<string, string> = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp", gif: "image/gif" };

const TOOL = {
  name: "brepl",
  description: [
    "Run JavaScript/TypeScript in Claude's persistent async Bun REPL (state survives between calls: bare `x = 1` and globalThis persist; top-level await; the last expression is returned).",
    "Images come back as pictures: call show(path, ...) or return an image path (or array of paths).",
    "Preloaded: godot (offscreen Godot runs: g = await godot.launch('duo-arena'); g.uiText(), g.joy('a'), g.action('ui_accept'), g.eval(gdscript), g.shot(), g.at(t), g.span(from, to, fps) -> frame/movement/motion sheets with sound + inputs, g.video(), g.quit())",
    "and dev (dev.help() lists the dev-loop helpers: bots, debt scan, stage/deploy, live game, screen, voice, pace, backlog, history).",
  ].join(" "),
  inputSchema: {
    type: "object",
    properties: { code: { type: "string", description: "Code to evaluate. Put statements on separate lines." } },
    required: ["code"],
  },
};

async function call(code: string) {
  const p = Bun.spawn([BREPL], { stdin: new Blob([code]), stdout: "pipe", stderr: "pipe", env: { ...process.env, BREPL_RAW: "1" } });
  let text = await new Response(p.stdout).text();
  text += await new Response(p.stderr).text();
  const code_ = await p.exited;
  const content: any[] = [];
  let paths: string[] = [];
  text = text.replace(/\u0001SHOW (.*)\n?/, (_, j) => { paths = JSON.parse(j); return ""; });
  const notes: string[] = [];
  for (const path of paths.slice(0, MAX_IMAGES)) {
    try {
      const size = statSync(path).size;
      if (size > MAX_BYTES) { notes.push(`[image too big to show (${(size / 1e6).toFixed(1)} MB): ${path}]`); continue; }
      const ext = path.split(".").pop()!.toLowerCase();
      content.push({ type: "text", text: `[image: ${path}]` });
      content.push({ type: "image", data: readFileSync(path).toString("base64"), mimeType: MIME[ext] ?? "image/png" });
    } catch (e) { notes.push(`[cannot read image ${path}: ${e}]`); }
  }
  if (paths.length > MAX_IMAGES) notes.push(`[${paths.length - MAX_IMAGES} more images not shown]`);
  content.unshift({ type: "text", text: (text.trimEnd() || "(no output)") + (notes.length ? "\n" + notes.join("\n") : "") });
  return { content, isError: code_ !== 0 };
}

function reply(id: unknown, result: unknown) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n"); }
function fail(id: unknown, message: string) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code: -32601, message } }) + "\n"); }

let buf = "";
for await (const chunk of Bun.stdin.stream()) {
  buf += new TextDecoder().decode(chunk);
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg: any;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg.id === undefined) continue;  // notifications
    switch (msg.method) {
      case "initialize":
        reply(msg.id, { protocolVersion: msg.params?.protocolVersion ?? "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "brepl", version: "1.0.0" } });
        break;
      case "ping": reply(msg.id, {}); break;
      case "tools/list": reply(msg.id, { tools: [TOOL] }); break;
      case "tools/call":
        if (msg.params?.name !== "brepl") { fail(msg.id, `unknown tool ${msg.params?.name}`); break; }
        call(String(msg.params?.arguments?.code ?? "")).then(r => reply(msg.id, r), e => reply(msg.id, { content: [{ type: "text", text: String(e) }], isError: true }));
        break;
      default: fail(msg.id, `method not found: ${msg.method}`);
    }
  }
}
