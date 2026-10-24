#!/bin/bash
# Claude Code with Remote Control, always on (claude-rc.service runs this inside tmux session "claude-rc").
# Continues the last conversation in ~ (a fresh one the first time). Attach locally: tmux attach -t claude-rc
cd "$HOME" || exit 1
unset LD_PRELOAD
# Wait for the internet (boot, or Wi-Fi coming back): Remote Control needs it.
for i in $(seq 60); do curl -s -m 3 -o /dev/null https://claude.ai && break; sleep 5; done
~/.local/bin/claude --continue --remote-control "Simon's Deck" || ~/.local/bin/claude --remote-control "Simon's Deck"
