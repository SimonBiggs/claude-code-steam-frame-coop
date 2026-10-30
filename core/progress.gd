extends RefCounted
## The family's progress in every story game, for the arcade's Family Trophy Hall (arcade/hall.gd), read from the
## games' saves through core/save.gd WITHOUT loading any game scene. Each deepened game opts in with
##   games/<game>/progress.gd:
##     const SAVE_ID := "tower_stack"   # its core/save.gd game_id
##     const WHO := "wren"              # its story friend (a story picture: StoryCard.has_picture)
##     const GROWS := "tower"           # what the family grows (a story picture or a UiKit icon kind)
##     const COLOR := Color(...)
##     static func progress_summary(data: Dictionary, today: String) -> Dictionary  # {"grown": int, "daily": bool, "played"?: bool}
##     static func sample(today: String) -> Dictionary   # a save as the game writes it (grown > 0, daily done)
## "daily" means today's daily round was DONE (finished / completed), never just started: a game that stamps today's
## date when the daily STARTS (so the next round isn't the daily) keeps that and saves a separate "daily_done" when
## it finishes (check() catches a start stamp read as done: start_marks / started_problems).
## found by itself (one scan of res://games, cached), like core/story_pictures.gd. tests/progress_test.gd fails when a
## game with a daily seed (a deepened game) has no progress.gd, or its summary misreads its own sample save.
##   var rows := Progress.summaries()            # {game id: {"grown", "daily", "played"}}
##   Progress.pack(rows) / Progress.unpack(arr)   # compact form for the lobby network
##   Progress.merge(host_rows, my_rows)           # one family: the further-grown of each game, either's daily

const Save := preload("res://core/save.gd")
const Seeded := preload("res://core/seeded.gd")

static var _paths: Dictionary = {}  # game id -> its progress.gd path (found at once: a file check per game)
static var _scripts: Dictionary = {}  # game id -> its loaded script (loaded when first needed, or a few per frame)
static var _scanned := false
## How long finding every progress.gd took, and loading (compiling) them so far, in ms. Loading is ~0.5 ms a game on
## the Steam Machine, so the lobby never loads them all in one frame: load_some() a few per frame (tests/progress_test.gd).
static var scan_ms := 0.0
static var load_ms := 0.0


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	if not DirAccess.dir_exists_absolute("res://games"):
		return
	var t0 := Time.get_ticks_usec()
	for g in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/progress.gd" % g
		if FileAccess.file_exists(path):
			_paths[g] = path
	scan_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Does this game have a progress.gd? (never loads it)
static func has(id: String) -> bool:
	_scan()
	return _paths.has(id)


## The progress.gd script of a game (null if it has none); loads it now if it isn't yet.
static func script_of(id: String):
	_scan()
	if not _scripts.has(id) and _paths.has(id):
		var t0 := Time.get_ticks_usec()
		_scripts[id] = load(String(_paths[id]))
		load_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return _scripts.get(id)


## Is this game's script loaded already?
static func is_loaded(id: String) -> bool:
	return _scripts.has(id)


## Load scripts until `budget_ms` is used up (at least one). True once every game's script is loaded.
static func load_some(budget_ms: float = 4.0) -> bool:
	_scan()
	var t0 := Time.get_ticks_usec()
	for id in _paths:
		if _scripts.has(id):
			continue
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			return false
		script_of(String(id))
	return true


## Every game id with a progress.gd.
static func ids() -> Array[String]:
	_scan()
	var out: Array[String] = []
	for g in _paths:
		out.append(String(g))
	return out


## One game's summary from a save Dictionary: {"grown": int >= 0, "daily": bool, "played": bool}.
static func summary_of(id: String, data: Dictionary, today: String = "") -> Dictionary:
	var s = script_of(id)
	if s == null:
		return {}
	var r: Variant = s.progress_summary(data, today if today != "" else Seeded.today())
	var d: Dictionary = r if r is Dictionary else {}
	var daily := bool(d.get("daily", false))
	return {"grown": maxi(0, int(d.get("grown", 0))), "daily": daily, "played": bool(d.get("played", false)) or daily}


## Every opted-in game's summary from this machine's saves (only the games in `only`, when given).
static func summaries(only: Array = []) -> Dictionary:
	var today := Seeded.today()
	var out := {}
	for id in ids():
		if not only.is_empty() and not only.has(id):
			continue
		out[id] = summary_of(id, Save.load_data(String(script_of(id).SAVE_ID)), today)
	return out


## Compact for the network: [date, id, grown, flags, id, grown, flags...] (flags: 1 = daily done, 2 = played today).
static func pack(rows: Dictionary) -> Array:
	var out: Array = [Seeded.today()]
	for id in rows:
		var r: Dictionary = rows[id]
		out.append_array([String(id), int(r.get("grown", 0)), (1 if r.get("daily", false) else 0) | (2 if r.get("played", false) else 0)])
	return out


## pack() back to rows. Another day's dailies (the sender's clock is on yesterday) don't count as done today.
static func unpack(arr: Array) -> Dictionary:
	var out := {}
	if arr.is_empty():
		return out
	var same_day := String(arr[0]) == Seeded.today()
	var k := 1
	while k + 2 < arr.size():
		var id := String(arr[k])
		var flags := int(arr[k + 2])
		out[id] = {"grown": maxi(0, int(arr[k + 1])), "daily": same_day and (flags & 1) != 0, "played": same_day and (flags & 2) != 0}
		k += 3
	return out


## One family across machines: each game as far as either has grown it, its daily done if either did it.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for id in b:
		var rb: Dictionary = b[id]
		if not out.has(id):
			out[id] = rb.duplicate()
			continue
		var ra: Dictionary = out[id]
		ra.grown = maxi(int(ra.get("grown", 0)), int(rb.get("grown", 0)))
		ra.daily = bool(ra.get("daily", false)) or bool(rb.get("daily", false))
		ra.played = bool(ra.get("played", false)) or bool(rb.get("played", false))
	return out


## Problems (empty = fine): a deepened game (one using Seeded's daily seed) without a progress.gd, a picture that
## doesn't exist, a summary that crashes on an empty save or misreads the game's own sample save.
## pretend_missing: game ids to treat as having no progress.gd (tests prove the check can fail).
static func check(game_ids: Array, pretend_missing: Array = []) -> Array[String]:
	const StoryCard := preload("res://core/story_card.gd")
	var out: Array[String] = []
	var today := Seeded.today()
	for id in game_ids:
		var deep := false
		var dir := "res://games/%s/" % id
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".gd"):
					var src := FileAccess.get_file_as_string(dir + f)
					if src.contains("daily_seed(") or src.contains("daily_key("):
						deep = true
						break
		var s = null if pretend_missing.has(id) else script_of(String(id))
		var marks := {}  # save key -> where starting a round writes today's date into it
		if s != null and DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".gd") and f != "progress.gd":
					var found := start_marks(FileAccess.get_file_as_string(dir + f))
					for k in found:
						marks[k] = "%s %s()" % [f, found[k]]
		if s == null:
			if deep:
				out.append("%s has a daily challenge but no games/%s/progress.gd (the arcade's Family Trophy Hall can't show it)" % [id, id])
			continue
		for c in ["SAVE_ID", "WHO", "GROWS", "COLOR"]:
			if not c in s.get_script_constant_map():
				out.append("games/%s/progress.gd has no %s" % [id, c])
		if not out.is_empty() and String(out[-1]).begins_with("games/%s/" % id):
			continue
		if not StoryCard.has_picture(String(s.WHO)):
			out.append("games/%s/progress.gd WHO %s is not a story picture" % [id, s.WHO])
		if not StoryCard.has_picture(String(s.GROWS)) and not FileAccess.get_file_as_string("res://core/ui_kit.gd").contains("\t\t\t\"%s\":" % s.GROWS):
			out.append("games/%s/progress.gd GROWS %s is neither a story picture nor a UiKit icon" % [id, s.GROWS])
		var empty := summary_of(String(id), {}, today)
		if int(empty.get("grown", -1)) != 0 or bool(empty.get("daily", true)):
			out.append("games/%s/progress.gd: an empty save must read as grown 0, daily not done (got %s)" % [id, str(empty)])
		var sam: Dictionary = summary_of(String(id), s.sample(today), today)
		if int(sam.get("grown", 0)) <= 0 or not bool(sam.get("daily", false)):
			out.append("games/%s/progress.gd: its sample save must read as grown > 0, daily done (got %s)" % [id, str(sam)])
		var old: Dictionary = summary_of(String(id), s.sample("2000-01-01"), today)
		if bool(old.get("daily", true)):
			out.append("games/%s/progress.gd: a daily done on another day must not count as done today" % id)
		out.append_array(started_problems(String(id), s, marks))
	return out


## Daily stars mean DONE: a save where only starting today's round happened (each `marks` key, from start_marks(),
## stamped today on an empty save and on an old sample) must not read as today's daily done. `s`: a progress.gd script.
static func started_problems(id: String, s, marks: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var today := Seeded.today()
	for k in marks:
		for base in [{}, s.sample("2000-01-01")]:
			var started: Dictionary = (base as Dictionary).duplicate(true)
			started[k] = today
			var r: Variant = s.progress_summary(started, today)
			if r is Dictionary and bool((r as Dictionary).get("daily", false)):
				out.append(("games/%s/progress.gd reads \"%s\" as today's daily done, but %s writes it when a round STARTS:"
					+ " keep it (it stops the next round being the daily) and report a separate daily_done set when the"
					+ " daily round finishes") % [id, k, marks[k]])
				break
	return out


## Save keys that a round-STARTING function (_start_*, _new_*, _open_*, load_*, _begin_*, _setup*, _ready) stamps with
## today's date after looking at them itself ("first round today? then it's the daily" — or it hands the whole save to
## a helper that decides), {key: function name}. Those keys say "started today", never "done today" (check()).
static func start_marks(src: String) -> Dictionary:
	var out := {}
	var head := RegEx.create_from_string("^(?:static\\s+)?func\\s+(\\w+)")
	var start_name := RegEx.create_from_string("^_?(start|new|open|load|begin|setup|ready)")
	var stamp := RegEx.create_from_string("(?m)save\\.data(?:\\.(\\w+)|\\[\\s*\"(\\w+)\"\\s*\\])\\s*=\\s*(?:today|Seeded\\.today\\(\\)|Time\\.get_date_string_from_system\\(\\))\\s*(?:#|$)")
	var fname := ""
	var body: PackedStringArray = []
	for line in (src + "\nfunc _end_of_source():").split("\n"):
		var h := head.search(line)
		if h != null:
			if fname != "" and start_name.search(fname) != null:
				var text := "\n".join(body)
				for st in stamp.search_all(text):
					var k := st.get_string(1) if st.get_string(1) != "" else st.get_string(2)
					var reads := RegEx.create_from_string("data(?:\\.%s\\b|\\[\\s*\"%s\"\\s*\\]|\\.get\\(\"%s\")(?!\\s*=[^=])" % [k, k, k])
					if reads.search(text) != null or text.contains("(save.data)"):
						out[k] = fname
			fname = h.get_string(1)
			body = []
		elif fname != "":
			body.append(line)
	return out
