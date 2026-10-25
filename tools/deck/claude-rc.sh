#!/bin/bash
# Claude Code with Remote Control, always on (claude-rc.service runs this inside tmux session "claude-rc").
# Continues the last conversation in ~ (a fresh one the first time). Attach locally: tmux attach -t claude-rc
# Every (re)start (Deck reboot, crash, claude-rc-check) passes an initial prompt telling Claude to re-arm its brepl
# channel watch, like claude-main on the Steam Machine - a resumed session doesn't restart its Monitors by itself.
# Remote Control name: ~/.config/claude-rc/name if present, else from the hostname (simon-steamdeck -> "Simon's Deck").
cd "$HOME" || exit 1
unset LD_PRELOAD
name=$(cat ~/.config/claude-rc/name 2>/dev/null)
if [ -z "$name" ]; then
  h=$(cat /etc/hostname 2>/dev/null); h=${h%%-*}
  name="${h^}'s Deck"; [ -z "$h" ] && name="Steam Deck"
fi
prompt="You were restarted (Deck reboot or crash). Re-arm your brepl channel watch: Monitor \`exec ~/.local/bin/bun ~/.local/share/brepl/channel-watch.ts\`, then read any unread entries in ~/.cache/brepl/channel.jsonl (brepl_poll) and act on requests from the Steam Machine, and carry on."
# Wait for the internet (boot, or Wi-Fi coming back): Remote Control needs it.
for i in $(seq 60); do curl -s -m 3 -o /dev/null https://claude.ai && break; sleep 5; done
~/.local/bin/claude --continue --remote-control "$name" "$prompt" || ~/.local/bin/claude --remote-control "$name" "$prompt"
