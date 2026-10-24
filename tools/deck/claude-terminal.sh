#!/bin/bash
# Claude Code in a terminal (a Steam "non-Steam game" entry, usable from Game Mode). First run: type /login.
# Big font for the Deck screen (ClaudeDeck Konsole profile); no Steam overlay preload (it only spams errors).
unset LD_PRELOAD
exec konsole --profile ClaudeDeck --hide-menubar --hide-tabbar --workdir "$HOME" -e bash -lc "claude; echo; echo Claude exited - press Enter to close; read"
