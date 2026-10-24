#!/usr/bin/env bun
// channel-watch: one short line per new brepl channel entry, for a Claude Code Monitor (which can only carry
// text). Pull the full output and pictures with the brepl_poll tool. Run: bun ~/.local/share/brepl/channel-watch.ts
const tail = Bun.spawn(["tail", "-n0", "-F", `${process.env.HOME}/.cache/brepl/channel.jsonl`], { stdout: "pipe", stderr: "ignore" });
let buf = "";
for await (const chunk of tail.stdout) {
  buf += new TextDecoder().decode(chunk);
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i);
    buf = buf.slice(i + 1);
    try {
      const e = JSON.parse(line);
      const first = e.text.split("\n").find((l: string) => l.trim()) ?? "";
      const more = e.text.split("\n").length > 1 ? ` (+${e.text.split("\n").length - 1} lines)` : "";
      console.log(`${e.t} ${e.source}: ${first.slice(0, 90)}${more}${e.images.length ? ` [${e.images.length} image${e.images.length > 1 ? "s" : ""}]` : ""}`);
    } catch {}
  }
}
