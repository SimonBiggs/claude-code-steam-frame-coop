extends SceneTree
## Bots check "did phase X happen" with tests/bot_kit.gd watch_state() + seen(key, value) / seen_values(key), never by
## polling the phase from kit.every() / _process into a flag they assert on later: a quick phase (a VR bot touching a
## level-up stone at once, a pick the bots take in a blink) comes and goes between two polls on a busy machine, so
## the check flakes (Crystal Saga's "the party levelled up", 2026-11-12). Static scan of every tests/*_bot.gd:
##   A. a flag set under a phase test (results_showing(), state_get("...phase"), _phase(), a local copy of the
##      phase) that an assert reads;
##   B. a dict filled from a polled state_get("key") (holes / courses seen) that an assert reads;
##   C. a bot's own "phase:" / "step:" record built from polling;
##   D. kit.seen / kit.seen_values without kit.watch_state(main.net) (nothing would ever be counted).
## A flag kept only to run UI checks once while the results show is fine: just don't assert on it.
##   godot-test --headless --path . -s res://tests/bot_phase_watch_test.gd   -> BOT PHASE WATCH: PASS / FAIL

## Bots another lane is moving onto watch_state right now (remove when it lands; the test says when it's stale).
const PENDING := {"mech_titans_bot.gd": "deep2-mech lane, 2026-11-12"}

var ph_var_re := RegEx.create_from_string("var (\\w+) := (?:String\\()?(?:main\\.net\\.state_get\\(\"\\w*phase\"|_phase\\(\\))")
var dict_re := RegEx.create_from_string("(?m)^\\t+(\\w+)\\[[^\\n]*state_get\\(\"(\\w+)\"[^\\n]*\\] = true")
var own_rec_re := RegEx.create_from_string("(?m)^\\t+\\w+\\[\"(?:phase|step|\\w*_phase):\" \\+")
var fails: Array[String] = []


func _flag_re(ph_vars: Array) -> RegEx:
	var alts := ["results_showing\\(\\)", "state_get\\(\"\\w*phase\"", "_phase\\(\\)"]
	for v in ph_vars:
		alts.append("\\b%s\\b" % v)
	return RegEx.create_from_string("(?m)^\\t+(?:el)?if [^\\n]*(?:%s)[^\\n]*:\\n(?:\\t+if not \\w+:\\n)?\\t+(\\w+) (?:= true|\\+= 1)" % "|".join(alts))


func _asserted(src: String, name: String) -> bool:
	return RegEx.create_from_string("assert_\\w+\\([^\\n]*\\b%s\\b" % name).search(src) != null


func problems(src: String) -> Array[String]:
	var out: Array[String] = []
	var ph_vars := []
	for m in ph_var_re.search_all(src):
		ph_vars.append(m.get_string(1))
	for m in _flag_re(ph_vars).search_all(src):
		if _asserted(src, m.get_string(1)):
			out.append("asserts on %s, a flag polled from the phase: use kit.seen(\"phase\", ...) > 0" % m.get_string(1))
	for m in dict_re.search_all(src):
		if _asserted(src, m.get_string(1)):
			out.append("asserts on %s, filled from a polled state_get(\"%s\"): use kit.seen_values(\"%s\") / kit.seen" % [m.get_string(1), m.get_string(2), m.get_string(2)])
	if own_rec_re.search(src) != null:
		out.append("records phases / steps itself from a poll: use kit.watch_state + kit.seen")
	if ("kit.seen(" in src or "kit.seen_values(" in src) and not "kit.watch_state(" in src:
		out.append("uses kit.seen without kit.watch_state(main.net) right after add_child(main)")
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("BOT PHASE WATCH: FAIL ", what)


func _initialize() -> void:
	# the scanner itself: the old ways must be caught, the new ones not
	_check(not problems("\tif main.results_showing() and not saw_results:\n\t\tsaw_results = true\n\tkit.assert_true(saw_results, \"x\")").is_empty(), "self-test: results_showing() flag")
	_check(not problems("\tvar ph := String(main.net.state_get(\"phase\", \"\"))\n\tif ph == \"pick\":\n\t\tsaw_pick = true\n\tkit.assert_true(saw_pick or late, \"x\")").is_empty(), "self-test: local phase copy")
	_check(not problems("\tif _phase() == \"choose\":\n\t\tsaw_choose += 1\n\tkit.assert_true(saw_choose > 0, \"x\")").is_empty(), "self-test: _phase() counter")
	_check(not problems("\tholes_seen[int(main.net.state_get(\"hole\", 0))] = true\n\tkit.assert_true(holes_seen.size() >= 3, \"x\")").is_empty(), "self-test: polled dict")
	_check(not problems("\tseen[\"phase:\" + phase] = true").is_empty(), "self-test: own phase record")
	_check(not problems("\tkit.assert_true(kit.seen(\"phase\", \"results\") > 0, \"x\")").is_empty(), "self-test: seen without watch_state")
	_check(problems("\tkit.watch_state(main.net)\n\tif main.results_showing() and not saw_results:\n\t\tsaw_results = true\n\t\tkit.assert_true(main.results_ui != null, \"ui\")\n\tkit.assert_true(kit.seen(\"phase\", \"results\") > 0, \"x\")").is_empty(), "self-test: the new way passes")
	var n := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not f.ends_with("_bot.gd"):
			continue
		n += 1
		var bad := problems(FileAccess.get_file_as_string("res://tests/" + f))
		if PENDING.has(f):
			if bad.is_empty():
				_check(false, "%s no longer polls phases: remove it from PENDING" % f)
			else:
				print("BOT PHASE WATCH: pending %s (%s): %s" % [f, PENDING[f], bad[0]])
			continue
		for b in bad:
			_check(false, "res://tests/%s %s" % [f, b])
	print("BOT PHASE WATCH: %s (%d bots)%s" % ["PASS" if fails.is_empty() else "FAIL", n, "" if fails.is_empty() else " %d" % fails.size()])
	quit(0 if fails.is_empty() else 1)