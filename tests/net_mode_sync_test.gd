extends SceneTree
## Every machine plays at the HOST's difficulty. A networked game whose TV machines (DUO_JOIN) keep their own locally
## chosen mode (a default, their own save, an env var) shows them the wrong pad / charge / fire tells and numbers
## (Duo Arena 2026-11-12: the host's mode pick set game_mode on the host only; the TV stayed "brave").
## Static scan of games/*/: a networked game (it joins with DUO_JOIN / runs as net mode "client") that has a
## difficulty (PickOrbs modes, "gentle" / "brave" / "hard") must either
##   - have its bot call kit.check_host_mode(main.net, <this machine's mode>) (tests/bot_kit.gd; BotKit.host_mode_problem
##     for a bot without a kit), which fails a networked
##     run when the host doesn't share its mode as net state or a TV machine plays at another, or
##   - be listed in HOST_ONLY with why its TV machines never read the difficulty (everything mode-dependent is worked
##     out on the host and replicated).
##   godot-test --headless --path . -s res://tests/net_mode_sync_test.gd   -> NET MODE SYNC: PASS / FAIL

## game id -> why the TV machines never read the difficulty (checked by hand; re-check when the game changes).
const HOST_ONLY := {
	"balloon_pop": "team_mode is read on the host only (round plans, gusts, telemetry); gust numbers reach the TV in the gust event",
	"sheep_round_up": "team_mode is read in host code only; the clock goes out as net state time, the rest as events",
	"tower_stack": "game_mode is read in host code only; it is packed into the replicated job state every machine builds from",
	"elemental_bender": "no difficulty pick: boss_gentle is worked out and used on the host; TV raiders are ghost copies",
}

var fails: Array[String] = []


func _initialize() -> void:
	var mode_re := RegEx.create_from_string("PickOrbs\\.mode\\(|MODE_IDS|\"gentle\"|\"brave\"")
	var net_re := RegEx.create_from_string("DUO_JOIN|mode == \"client\"|mode != \"client\"|is_client\\(")
	var checked := 0
	for g in DirAccess.get_directories_at("res://games"):
		var src := ""
		for f in DirAccess.get_files_at("res://games/" + g):
			if f.ends_with(".gd"):
				src += FileAccess.get_file_as_string("res://games/%s/%s" % [g, f]) + "\n"
		if net_re.search(src) == null or mode_re.search(src) == null:
			continue
		checked += 1
		var bot := FileAccess.get_file_as_string("res://tests/%s_bot.gd" % g)
		var calls := bot.contains("check_host_mode(") or bot.contains("host_mode_problem(")
		if calls and HOST_ONLY.has(g):
			fails.append("%s: its bot checks the host's mode, so drop it from HOST_ONLY" % g)
		elif not calls and not HOST_ONLY.has(g):
			fails.append("%s: networked with a difficulty, but tests/%s_bot.gd never calls kit.check_host_mode(main.net, <mode>) " % [g, g]
				+ "(sync the host's mode as net state and check it on the TV machine), and it isn't in HOST_ONLY with a reason")
	for g in HOST_ONLY:
		if not DirAccess.dir_exists_absolute("res://games/" + String(g)):
			fails.append("HOST_ONLY lists %s, which is gone" % g)
	for f in fails:
		print("  FAIL ", f)
	print("NET MODE SYNC: %s (%d networked games with a difficulty)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(), checked])
	quit(0 if fails.is_empty() else 1)
