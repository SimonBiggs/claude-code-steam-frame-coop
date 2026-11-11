extends SceneTree
## SHARED PICKS: every game builds its picture picks with core/pick_orbs.gd and its attack / hazard tells with
## core/warn_rings.gd, and shows the GENTLE / BRAVE / HARD modes with PickOrbs.mode() (one set of names and colours
## everywhere, so kids learn them once). Scans games/**/*.gd and fails on a game's own:
##   - WARNING code: a func named like warn / tell / telegraph / marker / danger that builds meshes -> WarnRings
##   - PICK code: a func named like pick / pod / orb / altar / choice that builds a Label3D and meshes -> PickOrbs
##     (look through its opts: body / icon / at / scale ...)
##   - MODE look: "gentle"/"brave"/"hard"/"heroic"/"mega": Color(...) or "name": "GENTLE"/... -> PickOrbs.mode()
## A diegetic thing that only looks similar (a hazard vent, a shop sign) is allowed by a line in its file:
##   ## shared-picks-ok: <func name> (why)
## Also smoke-tests both helpers (every option, every shape and style) so the games can lean on them.
##   godot-test --headless --path . -s res://tests/shared_picks_test.gd     Prints SHARED PICKS: PASS / FAIL.

const PickOrbs := preload("res://core/pick_orbs.gd")
const WarnRings := preload("res://core/warn_rings.gd")

const WARN_NAME := "(?i)(warn|tell|telegraph|danger)"
const WARN_FILE := "(?i)/(tele|warn|telegraph)[a-z_]*\\.gd$"
const PICK_NAME := "(?i)(pick(?!up)|pod|orb|altar|choice|choose)"
## Ground shapes (a glow on a body, a sphere round a boss, is not a ring on the ground).
const WARN_GEOMETRY := "(\\.torus\\(|\\.disc\\(|CylinderMesh\\.new|TorusMesh\\.new|PlaneMesh\\.new|SurfaceTool\\.new|ring_mesh\\()"
const PICK_GEOMETRY := "(MeshInstance3D\\.new\\(|MeshKit\\.instance\\(|Sprite3D\\.new)"
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
	if not ok.has("modes"):
		var rx_mode := RegEx.create_from_string(MODE_LOOK)
		var mm := rx_mode.search(text)
		if mm != null:
			out.append("%s: its own mode look (%s): use PickOrbs.mode(id) / mode_color / mode_name (same names and colours everywhere)" % [path, mm.get_string().left(40)])
	return out


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
	var good := "func boss_warn(p):\n\trings.warn(p, 2.0, Color.RED, 1.0)\nfunc show_pick(d):\n\torbs.show_orbs(\"x\", d, Vector3.ZERO)\n"
	_expect(scan("bad", bad_warn).size() == 1, "the scan finds a home-made warning ring")
	_expect(scan("bad", bad_pick).size() == 1, "the scan finds home-made picks")
	_expect(scan("bad", bad_mode).size() == 1, "the scan finds a game's own mode colours")
	_expect(scan("good", good).is_empty(), "the scan passes code that uses the helpers")
	_expect(scan("ok", "## shared-picks-ok: _make_pod (a test)\n" + bad_pick).is_empty(), "shared-picks-ok lets a func through")
	# 2. Every game.
	var n := 0
	for path in game_files():
		n += 1
		for e in scan(path, FileAccess.get_file_as_string(path)):
			_expect(false, e)
	_expect(n > 50, "found the games (%d files)" % n)
	# 3. Modes: one list, the old ids map onto it.
	_expect(PickOrbs.mode_name("mega") == "HARD" and PickOrbs.mode_name("heroic") == "HARD", "mega / heroic show as HARD")
	_expect(PickOrbs.mode_color("zoom") == PickOrbs.mode_color("brave"), "zoom shows as BRAVE")
	_expect(PickOrbs.mode_ids("hard") == ["gentle", "hard", "brave"], "mode_ids puts the last mode in the middle")

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