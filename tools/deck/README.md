# Steam Deck setup (Simon's Deck, devkit-paired: `ssh simon-deck`)

- `~/DuoArena/` = Godot + the arcade + `run.sh` (tools/deck-run.sh): joins the family game, or `--solo`; fullscreen 1280x800.
  `duo-deploy-deck` keeps it current (run by every `duo-deploy`).
- Steam library (Game Mode): Living Room Arcade, Arcade (Deck only), Claude Code (`claude-terminal.sh`, big-font
  `ClaudeDeck.profile`). Added with `steamos-add-to-steam`; art from `steam-grid-art.py` into `userdata/<id>/config/grid`.
- Claude Code always on with Remote Control: `claude-rc.service` (tmux session `claude-rc`, waits for the internet,
  `--continue --remote-control "Simon's Deck"`), `claude-rc-check.timer` re-checks every 2 min. Auto mode + default
  onboarding are in `~/.claude/settings.json` / `~/.claude.json` (not in the repo).
- brepl runs there too (brepl.service) with the brepl MCP tool; `brepl-tunnel@simon-deck` (on the Steam Machine)
  links both REPL inboxes over SSH: `peer("simon-deck").send/eval`, and on the Deck `peer("SteamMachine").send`.
