extends RefCounted
## Telemetry: one line per finished run (or quit), so balance can be judged from how the family really
## played. Shared by every game (no per-game copies).
##   const Telemetry := preload("res://core/telemetry.gd")
##   Telemetry.run("dungeon_delve", {"mode": "brave", "depth": 5, "end": "wipe", ...})
## Writes "RUN: {json}" to the game log (stdout, so it lands in .dev/game.log on the TV and Decks) and
## appends the same JSON to user://telemetry.jsonl. Added automatically: game, t (unix time), date,
## machine (core/machine.gd kind), host (OS host name). Tests and bots write user://telemetry_test.jsonl
## instead (core/save.gd test mode), so they never mix with the family's runs.
## Telemetry.read(game_id = "") -> Array of Dictionaries from this machine's file (newest last).
## Summaries across machines: tools/dd-balance (collects RUN lines from the TV log and every Deck).

const Save := preload("res://core/save.gd")
const Machine := preload("res://core/machine.gd")
const PATH := "user://telemetry.jsonl"
const TEST_PATH := "user://telemetry_test.jsonl"
const MAX_BYTES := 2000000  ## keep the file small: start again (keeping the newest half) past this


static func path() -> String:
	return TEST_PATH if Save.test_mode() else PATH


## Record one run. data: plain values only (numbers, strings, arrays, dictionaries).
static func run(game_id: String, data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	d["game"] = game_id
	d["t"] = int(Time.get_unix_time_from_system())
	d["date"] = Time.get_datetime_string_from_system()
	d["machine"] = Machine.kind()
	d["host"] = OS.get_environment("HOSTNAME") if OS.has_environment("HOSTNAME") else ""
	var line := JSON.stringify(d)
	print("RUN: " + line)
	_append(path(), line)
	return d


static func _append(p: String, line: String) -> void:
	var f := FileAccess.open(p, FileAccess.READ_WRITE) if FileAccess.file_exists(p) else FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > MAX_BYTES:
		var text := f.get_as_text()
		f.close()
		var keep := text.substr(text.length() / 2)
		keep = keep.substr(keep.find("\n") + 1)
		f = FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			return
		f.store_string(keep)
	f.seek_end()
	f.store_string(line + "\n")
	f.close()


static func read(game_id: String = "", p: String = "") -> Array:
	var out: Array = []
	var fp := p if p != "" else path()
	if not FileAccess.file_exists(fp):
		return out
	for l in FileAccess.get_file_as_string(fp).split("\n", false):
		var v: Variant = JSON.parse_string(l)
		if v is Dictionary and (game_id == "" or String((v as Dictionary).get("game", "")) == game_id):
			out.append(v)
	return out
