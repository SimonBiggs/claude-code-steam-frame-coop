extends SceneTree
## SHARED PICKS: every game builds its picture picks with core/pick_orbs.gd and its attack / hazard tells with
## core/warn_rings.gd, and shows the GENTLE / BRAVE / HARD modes with PickOrbs.mode() (one set of names and colours
## everywhere, so kids learn them once). Scans games/**/*.gd and fails on a game's own:
##   - WARNING code: a func named like warn / tell / telegraph / marker / danger that builds meshes -> WarnRings
##   - PICK code: a func named like pick / pod / orb / altar / choice that builds a Label3D and meshes -> PickOrbs
##     (look through its opts: body / icon / at / scale ...)
##   - MODE look: "gentle"/"brave"/"hard"/"heroic"/"mega": Color(...) or "name": "GENTLE"/... -> PickOrbs.mode()
##   - SEASON props: a game's own copy of the seasonal props (a "winter" snowman / "autumn" pumpkin built in a match)
##     -> core/season_kit.gd prop() / drift() (three games had copied them by 2026-11-11)
##   - GIFT pick: a game's own "gift order" shuffle -> PickOrbs.gift_choices(unlocked, last, seed) (six games had
##     copied it by 2026-11-13)
##   - PICK FLOW: a game's own dwell / take / finish (RESTING dwell, the nobody-chose middle take, the AFTER wait before
##     the orbs go) -> extends "res://core/pick_flow.gd" and override takers() / orb_at() / fx() ... (28 games had
##     their own copy of it by 2026-11-13)
##   - VOTES: a game counting its own votes (a vote / ballot tally += 1 in a func) -> pick_flow's vote mode (`vote = true`
##     in its picks.gd _init: everyone's dwell or shot is their vote, majority wins, tie_rule / tie_pick(), voters();
##     four games had their own by 2026-11-14)
## A diegetic thing that only looks similar (a hazard vent, a shop sign) is allowed by a line in its file:
##   ## shared-picks-ok: <func name> (why)
## Every game script must also compile (load() + can_instantiate()).
## Also smoke-tests both helpers (every option, every shape and style) so the games can lean on them.
##   godot-test --headless --path . -s res://tests/shared_picks_test.gd     Prints SHARED PICKS: PASS / FAIL.

const PickOrbs := preload("res://core/pick_orbs.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const PickFlow := preload("res://core/pick_flow.gd")

const WARN_NAME := "(?i)(warn|tell|telegraph|danger)"
const WARN_FILE := "(?i)/(tele|warn|telegraph)[a-z_]*\\.gd$"
const PICK_NAME := "(?i)(pick(?!up)|pod|orb|altar|choice|choose)"
## Ground shapes (a glow on a body, a sphere round a boss, is not a ring on the ground).
const WARN_GEOMETRY := "(\\.torus\\(|\\.disc\\(|CylinderMesh\\.new|TorusMesh\\.new|PlaneMesh\\.new|SurfaceTool\\.new|ring_mesh\\()"
const PICK_GEOMETRY := "(MeshInstance3D\\.new\\(|MeshKit\\.instance\\(|Sprite3D\\.new)"
const SEASON_COPY := "(?s)\"winter\"\\s*:[^\n]*snowman.{0,1200}\"autumn\"\\s*:[^\n]*pumpkin"
const GIFT_COPY := "Seeded\\.rng\\([^\\n]*\"gift order\""
## A game's own copy of the pick flow (core/pick_flow.gd): its RESTING dwell, its nobody-chose take, its AFTER wait.
const FLOW_COPY := "(?m)(^\\s*[a-z_]+\\[[^\\]\\n]+\\]\\s*=\\s*RESTING\\b|take\\(options\\.size\\(\\) / 2, -1\\)|done_t >= AFTER\\b)"
## A game's own vote count: a line adding one to a tally near a vote / ballot name (within 3 lines).
const VOTE_NAME := "(?i)\\b[a-z_]*(vote|ballot)[a-z_]*\\b"
const VOTE_COUNT := "(\\+=\\s*1\\b|=\\s*int\\(.*\\)\\s*\\+\\s*1\\b)"
const MODE_LOOK := "\"(gentle|brave|hard|heroic|mega)\"\\s*:\\s*Color\\(|\"name\"\\s*:\\s*\"(GENTLE|BRAVE|HARD|HEROIC)\"|\"kind\"\\s*:\\s*\"mode\"[^}\\n]*\"name\"\\s*:\\s*\""

var fails := 0
var frames := 0
var orbs: PickOrbs
var rings: WarnRings
var hits := []


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SHARED PICKS: FAIL ", what)


## The problems in one file's text ([] = fine). path is only for the messages.
static func scan(path: String, text: String) -> Array:
	var out: Array = []
	var ok := {}
	var rx_ok := RegEx.create_from_string("shared-picks-ok:\\s*([A-Za-z0-9_]+)")
	for m in rx_ok.search_all(text):
		ok[m.get_string(1)] = true
	var rx_func := RegEx.create_from_string("(?m)^(static )?func ([A-Za-z0-9_]+)\\(")
	var rx_warn := RegEx.create_from_string(WARN_NAME)
	var rx_pick := RegEx.create_from_string(PICK_NAME)
	var rx_wgeo := RegEx.create_from_string(WARN_GEOMETRY)
	var rx_pgeo := RegEx.create_from_string(PICK_GEOMETRY)
	if RegEx.create_from_string(WARN_FILE).search(path) and not ok.has("file"):
		out.append("%s: a game's own warning file: use core/warn_rings.gd (shape(): circle / ring / line / sector)" % path)
	var found := rx_func.search_all(text)
	for i in found.size():
		var fname := found[i].get_string(2)
		if ok.has(fname):
			continue
		var body := text.substr(found[i].get_end(), (found[i + 1].get_start() if i + 1 < found.size() else text.length()) - found[i].get_end())
		if rx_warn.search(fname) and rx_wgeo.search(body) and not body.contains("WarnRings") and not body.contains("rings."):
			out.append("%s: %s() draws its own warning: use core/warn_rings.gd (warn / shape, style \"rings\" / \"disc\" / \"flash\")" % [path, fname])
		elif rx_pick.search(fname) and rx_pgeo.search(body) and body.contains("Label3D.new") and not body.contains("PickOrbs"):
			out.append("%s: %s() builds its own picks: use core/pick_orbs.gd show_orbs(..., opts) (body / icon / at keep your look)" % [path, fname])
		if _counts_votes(body):
			out.append("%s: %s() counts its own votes: use core/pick_flow.gd's vote mode (vote = true in a picks.gd _init; voters() / tie_rule / tie_pick() keep a game's differences)" % [path, fname])
	if not ok.has("seasons") and RegEx.create_from_string(SEASON_COPY).search(text):
		out.append("%s: its own seasonal props (snowman, pumpkin...): use core/season_kit.gd prop(builder, season, at, i, size)" % path)
	if not ok.has("gifts") and RegEx.create_from_string(GIFT_COPY).search(text):
		out.append("%s: its own gift pick shuffle: use PickOrbs.gift_choices(unlocked, last, seed)" % path)
	if not ok.has("flow"):
		var mf := RegEx.create_from_string(FLOW_COPY).search(text)
		if mf != null:
			out.append("%s: its own pick flow (%s): extends \"res://core/pick_flow.gd\" (takers / orb_at / dwell_for / fx keep a game's own differences)" % [path, mf.get_string().strip_edges().left(40)])
	if not ok.has("modes"):
		var rx_mode := RegEx.create_from_string(MODE_LOOK)
		var mm := rx_mode.search(text)
		if mm != null:
			out.append("%s: its own mode look (%s): use PickOrbs.mode(id) / mode_color / mode_name (same names and colours everywhere)" % [path, mm.get_string().left(40)])
	return out


## True if a func body adds one to a tally within 3 lines of a vote / ballot name (a game's own vote count).
static func _counts_votes(body: String) -> bool:
	var rx_name := RegEx.create_from_string(VOTE_NAME)
	var rx_count := RegEx.create_from_string(VOTE_COUNT)
	var lines := body.split("\n")
	for j in lines.size():
		if lines[j].strip_edges().begins_with("#") or rx_count.search(lines[j]) == null:
			continue
		for k in range(maxi(0, j - 3), j + 1):
			if rx_name.search(lines[k]) != null:
				return true
	return false


static func game_files(dir: String = "res://games") -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(game_files(dir.path_join(d)))
	return out


func _initialize() -> void:
	# 1. The scanner can fail (and passes the right way).
	var bad_warn := "func boss_warn(p):\n\tvar mi := MeshInstance3D.new()\n\tmi.mesh = TorusMesh.new()\n"
	var bad_pick := "func _make_pod(k):\n\tvar l := Label3D.new()\n\tvar m := MeshKit.instance(x)\n"
	var bad_mode := "const C := {\"brave\": Color(1, 0.6, 0.2)}\n"
	var bad_season := "\tmatch s:\n\t\t\"winter\":  # a snowman\n\t\t\tb.sphere(1)\n\t\t\"autumn\":  # a pumpkin\n\t\t\tb.sphere(2)\n"
	var good := "func boss_warn(p):\n\trings.warn(p, 2.0, Color.RED, 1.0)\nfunc show_pick(d):\n\torbs.show_orbs(\"x\", d, Vector3.ZERO)\n"
	_expect(scan("bad", bad_warn).size() == 1, "the scan finds a home-made warning ring")
	_expect(scan("bad", bad_pick).size() == 1, "the scan finds home-made picks")
	_expect(scan("bad", bad_mode).size() == 1, "the scan finds a game's own mode colours")
	_expect(scan("bad", bad_season).size() == 1, "the scan finds a game's own seasonal props")
	_expect(scan("bad", "\treturn Seeded.shuffled(Seeded.rng(seed_value, \"gift order\"), out)\n").size() == 1, "the scan finds a game's own gift pick")
	_expect(scan("bad", "\t\tinside[id] = RESTING if i >= 0 else -1\n").size() == 1, "the scan finds a game's own RESTING dwell")
	_expect(scan("bad", "\tif t <= 0.0:\n\t\ttake(options.size() / 2, -1)\n").size() == 1, "the scan finds a game's own nobody-chose take")
	_expect(scan("bad", "\t\tif done_t >= AFTER:\n\t\t\t_finish()\n").size() == 1, "the scan finds a game's own finish wait")
	_expect(scan("bad", "func _resolve():\n\tfor k in takes:\n\t\tvotes[int(takes[k])] += 1\n").size() == 1, "the scan finds a game's own vote count")
	_expect(scan("bad", "static func team_mode(p):\n\tfor s in p:\n\t\tvotes[m] = int(votes.get(m, 0)) + 1\n").size() == 1, "the scan finds a game's own vote tally")
	_expect(scan("good", "func _finish():\n\tvar votes := picks.votes\n\tvar a := 1\n\tvar b := 2\n\tvar c := 3\n\tscore += 1\n").is_empty(), "a vote name far from a count is fine")
	_expect(scan("ok", "## shared-picks-ok: _resolve (a test)\nfunc _resolve():\n\tvotes[k] += 1\n").is_empty(), "shared-picks-ok lets a vote count through")
	_expect(scan("good", good).is_empty(), "the scan passes code that uses the helpers")
	_expect(scan("ok", "## shared-picks-ok: _make_pod (a test)\n" + bad_pick).is_empty(), "shared-picks-ok lets a func through")
	# 2. Every game.
	var n := 0
	for path in game_files():
		n += 1
		for e in scan(path, FileAccess.get_file_as_string(path)):
			_expect(false, e)
		# Every game script compiles (a gen test that never loads a broken altar.gd still said PASS, 2026-11-11).
		var scr := load(path) as Script
		_expect(scr != null and scr.can_instantiate(), "%s does not compile" % path)
	_expect(n > 50, "found the games (%d files)" % n)
	# 3. Modes: one list, the old ids map onto it.
	_expect(PickOrbs.mode_name("mega") == "HARD" and PickOrbs.mode_name("heroic") == "HARD", "mega / heroic show as HARD")
	_expect(PickOrbs.mode_color("zoom") == PickOrbs.mode_color("brave"), "zoom shows as BRAVE")
	_expect(PickOrbs.mode_ids("hard") == ["gentle", "hard", "brave"], "mode_ids puts the last mode in the middle")
	# The shared flow's helpers (the flow itself runs in every game's bot).
	_expect(PickFlow.order_along([Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 0)], Vector3.RIGHT) == [1, 2, 0], "order_along: left to right")
	_expect(not PickFlow.head_moved(Transform3D(), Transform3D(Basis(), Vector3(0.1, 0, 0))), "head_moved: a small step keeps the row")
	_expect(PickFlow.head_moved(Transform3D(), Transform3D(Basis(Vector3.UP, 0.8), Vector3.ZERO)), "head_moved: a turn moves the row")
	# The vote mode's count (the flow itself runs in Hide & Seek's, Elemental Bender's, Snowball Blitz's, Duo Arena's bots).
	var pf = PickFlow.new()
	var abc := ["a", "b", "c"]
	_expect(pf.winner_of("gift", abc, {}, 1) == 1, "vote: nobody voted -> the default")
	_expect(pf.winner_of("gift", abc, {0: 2}, 1) == 2, "vote: one player alone decides")
	_expect(pf.winner_of("gift", abc, {0: 2, 1: 2, 2: 0}, 1) == 2, "vote: the most votes win")
	_expect(pf.winner_of("gift", abc, {0: 0, 1: 1}, 1) == 1, "vote: a tie with the middle -> the middle")
	_expect(pf.winner_of("gift", abc, {0: 0, 1: 2}, 1) == 0, "vote: a tie without the middle -> the nearest (lower)")
	_expect(pf.winner_of("mode", ["gentle", "hard", "brave"], {0: 1, 1: 2}, 1) == 1, "vote: middle rule on a mode tie keeps the middle")
	pf.tie_rule = "gentler"
	_expect(pf.winner_of("mode", ["gentle", "hard", "brave"], {0: 1, 1: 2}, 1) == 2, "vote: gentler rule: hard vs brave -> brave")
	_expect(pf.winner_of("mode", ["gentle", "brave", "hard"], {0: 0, 1: 2, 2: 1, 3: 1, 4: 0}, 1) == 0, "vote: gentler rule: gentle vs brave -> gentle")
	_expect(pf.winner_of("gift", abc, {0: 0, 1: 2}, 1) == 0, "vote: gentler rule on a gift stage -> nearest the middle")
	pf.free()
	# 4. The shared gift pick: three different, the newest always there, not the last one again, the same for a seed.
	var un := ["a", "b", "c", "d", "e"]
	for s in 50:
		var g := PickOrbs.gift_choices(un, "b", s)
		_expect(g.size() == 3 and g.has("e") and not g.has("b") and g == PickOrbs.gift_choices(un, "b", s), "gift_choices seed %d: %s" % [s, str(g)])
		var d := {}
		for id in g:
			d[id] = true
		_expect(d.size() == 3, "gift_choices gives three different gifts")
	_expect(PickOrbs.gift_choices(["a", "b", "c"], "c", 3).size() == 3, "gift_choices with only three unlocked offers all three")

## 4. The helpers with every option (on the first frame: root is in the tree then).
func _helpers() -> void:
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	orbs.on_hit = func(i: int, by) -> void: hits.append([i, by])
	root.add_child(orbs)
	var list: Array = [PickOrbs.mode("gentle"), PickOrbs.mode("brave"), PickOrbs.mode("hard")]
	orbs.show_orbs("mode", list, Vector3(0, 0, -4))
	_expect(orbs.orbs.size() == 3 and orbs.showing(), "three default orbs")
	_expect(orbs.take(1, Color.RED) != Vector3.INF and orbs.take(7, Color.RED) == Vector3.INF, "take")
	(orbs.orbs[2] as PickOrbs.Orb).hit(1.0, Vector3.ZERO, 1.0, "p1")
	_expect(hits == [[2, "p1"]], "an orb hit reaches on_hit")
	var stand := func(_e: Dictionary, is_def: bool) -> Node3D:
		var n3 := Node3D.new()
		var g := MeshInstance3D.new()
		g.name = "Glow"
		g.mesh = BoxMesh.new()
		n3.add_child(g)
		n3.set_meta("def", is_def)
		return n3
	var pic := func(_e: Dictionary) -> Node3D: return MeshInstance3D.new()
	var at: Array = [Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(30, 0, 0)]
	orbs.show_orbs("pods", list, Vector3.ZERO, 0.0, 0.0, {"at": at, "body": stand, "icon": pic, "spin": 1.4, "icon_y": 2.0,
		"scale": 3.0, "two_lines": true, "def": 0, "touch": 2.0, "group": "test_orbs", "max_y": 3.0})
	_expect(orbs.orbs.size() == 3, "custom picks")
	_expect(bool((orbs.orbs[0] as PickOrbs.Orb).ball.get_meta("def")), "opts.def is the default")
	_expect(orbs.at_point(Vector3(20.5, 0, 0)) == 1, "at_point finds the pick at its place (got %d)" % orbs.at_point(Vector3(20.5, 0, 0)))
	_expect(orbs.at_point(Vector3(20.5, 9, 0)) == -1, "at_point skips players above max_y")
	_expect(orbs.nearest_hit(Vector3(30, 6, 0), 0.5) == 2, "nearest_hit aims at the picture")
	_expect(get_nodes_in_group("test_orbs").size() == 3, "opts.group")
	orbs.show_takers({0: 1, 1: 1, 2: 0}, {0: Color.RED, 1: Color.BLUE, 2: Color.GREEN})
	_expect((orbs.orbs[1] as PickOrbs.Orb).dots.get_child_count() == 2, "show_takers puts two dots on pick 1")
	rings = WarnRings.new()
	root.add_child(rings)
	rings.warn(Vector3(1, 0, 1), 3.0, Color.RED, 0.5)
	rings.warn(Vector3(1, 0, 1), 3.0, Color.RED, 0.5, 0.25, {"style": "disc"})
	for k in WarnRings.KINDS:
		for st in WarnRings.STYLES:
			rings.shape(k, Vector3.ZERO, Vector3(1, 0, 0), Vector2(4.0, 1.0), Color.ORANGE, 0.4, {"style": st, "stay": 0.2})
	_expect(rings.count() == 2 + WarnRings.KINDS.size() * WarnRings.STYLES.size(), "every shape and style shows")
	_expect(WarnRings.inside("line", Vector3.ZERO, Vector3(1, 0, 0), Vector2(4, 1), Vector3(3, 0, 0.2)), "inside a line")
	_expect(not WarnRings.inside("line", Vector3.ZERO, Vector3(1, 0, 0), Vector2(4, 1), Vector3(3, 0, 2)), "outside a line")
	_expect(WarnRings.inside("sector", Vector3.ZERO, Vector3(0, 0, 1), Vector2(5, 0.5), Vector3(0.5, 0, 3)), "inside a sector")
	var ts: Array[Dictionary] = rings.tells()
	_expect(ts.size() == rings.count() and String(ts[0].kind) == "circle" and (ts[0].pos as Vector3).is_equal_approx(Vector3(1, 0, 1))
		and float(ts[0].secs) == 0.5 and float(ts[0].t) == 0.0, "tells() lists each tell (kind, pos, dir, size, t, secs, stay)")


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		_helpers()
	if frames == 90:  # 1.5 s at 60 fps: every tell has gone off and gone
		_expect(rings.count() == 0, "tells go away after secs + stay (%d left)" % rings.count())
		orbs.clear()
		print("SHARED PICKS: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
		quit(1 if fails > 0 else 0)
	return false