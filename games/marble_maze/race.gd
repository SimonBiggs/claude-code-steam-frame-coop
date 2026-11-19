extends Node
## MARBLE MAZE third pass: TODAY'S RACE. Story.RACE_LEGS mazes of the day (story.gd daily(date, mode, wd, leg)) against
## ONE clock that only runs while the marbles roll (not during the intros or the HOORAY in between). The team's time is
## when the last marble gets home in the last maze. Then:
##   a CUP for Bobo's trophy shelf (story.gd medal(): gold / silver / bronze from the three mazes' shortest ways),
##   the family's BEST TIMES (save race = {date: [[secs, marbles], ...]} best first, race_best = the best ever),
##   and the GHOST: the first marble's way through today's best run is saved, and the next race today rolls a
##   see-through ghost marble along it (race your own best!).
## The host (or local game) owns the clock, the save and the ghost; the TV machine draws the clock and the ghost from
## the "race" event [secs, running, leg (-1: no new leg), ghost points or null].
## Every machine: a big world clock over the far edge of the board (TV chase cams and the VR giant both see it) and the
## clock in each TV view's HUD (main.gd _simple_hud).

const Story := preload("res://games/marble_maze/story.gd")
const Seeded := preload("res://core/seeded.gd")
const GhostHand := preload("res://core/ghost_hand.gd")
const VrViewCheck := preload("res://core/vr_view_check.gd")

const REC_HZ := 10.0
const KEEP_DAYS := 14
const KEEP_TIMES := 5
const CUPS_MAX := 60
const GHOST_COLOR := Color(0.75, 0.95, 1.0, 0.55)

var main
var on := false  # a race is being run (leg 0's start .. the last leg's finish)
var t := 0.0  # race seconds so far (play time only)
var steps := 0  # host: the legs' shortest ways added up
var leg := 0
var marbles := 1
var running := false  # the clock ticks (a leg is being played)
var leg_t := 0.0  # play seconds in this leg (moves the ghost)
var rec: Array = []  # host: this race's legs, each [x mm, z mm, x, z, ...] at REC_HZ
var rec_t := 0.0
var sync_t := 0.0
var ghost_pts: Array = []
var ghost_node: MeshInstance3D
var clock3d: Label3D
var last: Dictionary = {}  # host: the last finished race {secs, medal, best_today, best_ever, marbles}


func _ready() -> void:
	name = "MarbleRace"


## Host / local: a race leg starts (main.gd _start_level for a "daily" desc). def: the maze (its "steps").
func begin_leg(leg_i: int, def: Dictionary) -> void:
	if leg_i == 0 or not on:
		on = true
		t = 0.0
		steps = 0
		rec = []
	leg = leg_i
	leg_t = 0.0
	rec_t = 0.0
	running = false
	steps += int(def.get("steps", 0))
	while rec.size() <= leg:
		rec.append([])
	rec[leg] = []
	var g: Dictionary = main.save.data.ghost if main.save != null and main.save.data.get("ghost") is Dictionary else {}
	var pts: Array = []
	if str(g.get("d", "")) == Seeded.today() and g.get("legs") is Array and (g.legs as Array).size() > leg:
		pts = g.legs[leg]
	set_ghost(pts)
	main.net.event("race", [t, false, leg, pts])


## Host / local: the race stops (a pick board, a game restart: nothing saved).
func stop() -> void:
	if not on:
		return
	on = false
	running = false
	set_ghost([])
	main.net.event("race", [t, false, -2, null])


## Every machine: the race event.
func apply(args: Array) -> void:
	t = float(args[0])
	running = bool(args[1])
	var lg := int(args[2])
	if lg == -2:
		on = false
		set_ghost([])
		return
	on = true
	if lg >= 0:
		leg = lg
		leg_t = 0.0
		set_ghost(args[3] if args.size() > 3 and args[3] is Array else [])


func set_ghost(pts: Array) -> void:
	ghost_pts = pts.duplicate()
	if ghost_node == null and not pts.is_empty():
		ghost_node = MeshInstance3D.new()
		ghost_node.name = "RaceGhost"
		ghost_node.mesh = main.sphere_mesh(0.028)
		ghost_node.material_override = GhostHand.make_mat(GHOST_COLOR)
		ghost_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.board.add_child(ghost_node)
	if ghost_node != null:
		ghost_node.visible = false


## Every machine, every frame.
func tick(delta: float) -> void:
	var host: bool = main.net.mode != "client"
	if host:
		var now: bool = on and main.state == "play"
		if now != running:
			running = now
			main.net.event("race", [t, running, -1, null])
	if on and running:
		t += delta
		leg_t += delta
		if host:
			_record(delta)
			sync_t += delta
			if sync_t >= 1.0:
				sync_t = 0.0
				main.net.event("race", [t, true, -1, null])
	_draw_ghost()
	_draw_clock()


func _record(delta: float) -> void:
	rec_t -= delta
	if rec_t > 0.0 or leg >= rec.size():
		return
	rec_t = 1.0 / REC_HZ
	var m = _lead()
	if m == null:
		return
	var p: Vector3 = m.lp if not m.home else Vector3(main.board.goal.x, 0.0, main.board.goal.y)
	(rec[leg] as Array).append(int(round(p.x * 1000.0)))
	(rec[leg] as Array).append(int(round(p.z * 1000.0)))


## The marble whose way the ghost keeps: the first active one.
func _lead():
	for p in main.players:
		if p.index > 0 and p.active:
			return p
	return null


func _draw_ghost() -> void:
	if ghost_node == null:
		return
	var n := ghost_pts.size() / 2
	ghost_node.visible = on and n > 1 and (main.state == "play" or main.state == "intro")
	if not ghost_node.visible:
		return
	var f := clampf(leg_t * REC_HZ, 0.0, float(n - 1))
	var i := int(f)
	var j := mini(i + 1, n - 1)
	var a := Vector2(float(ghost_pts[i * 2]), float(ghost_pts[i * 2 + 1])) / 1000.0
	var b := Vector2(float(ghost_pts[j * 2]), float(ghost_pts[j * 2 + 1])) / 1000.0
	var p := a.lerp(b, f - i)
	ghost_node.position = Vector3(p.x, 0.03, p.y)


func _draw_clock() -> void:
	if clock3d == null:
		if not on:
			return
		clock3d = Label3D.new()
		clock3d.name = "RaceClock"
		clock3d.font_size = 72
		clock3d.outline_size = 22
		clock3d.pixel_size = 0.0022
		clock3d.modulate = Color(1.0, 0.95, 0.6)
		clock3d.outline_modulate = Color(0.15, 0.1, 0.05)
		clock3d.set_meta(VrViewCheck.COVER_OK_META, true)  # a VR card may pass in front of it for a moment
		main.add_child(clock3d)
	clock3d.visible = on and (main.state == "play" or main.state == "intro" or main.state == "clear")
	if clock3d.visible:
		clock3d.text = Story.clock(t)
		clock3d.position = Vector3(0.0, float(main.board_y) + 0.26, -0.66)


## Host / local: a leg was cleared. Returns the finished race (last leg) or {}.
func leg_cleared() -> Dictionary:
	if not on:
		return {}
	running = false
	main.net.event("race", [t, false, -1, null])
	if leg < Story.RACE_LEGS - 1:
		return {}
	return _finish()


func _finish() -> Dictionary:
	on = false
	marbles = maxi(1, main.active_marbles().size())
	var secs := snappedf(t, 0.1)
	var medal := Story.medal(secs, steps, marbles)
	var out := {"secs": secs, "medal": medal, "marbles": marbles, "steps": steps, "best_today": false, "best_ever": false}
	if main.save != null:
		var d: Dictionary = main.save.data
		var today := Seeded.today()
		var race: Dictionary = d.race
		var list: Array = race.get(today, [])
		list.append([secs, marbles, medal])
		list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		out.best_today = float(list[0][0]) == secs
		race[today] = list.slice(0, KEEP_TIMES)
		while race.size() > KEEP_DAYS:
			race.erase(race.keys()[0])
		var be: Array = d.race_best
		if be.is_empty() or secs < float(be[0]):
			out.best_ever = not be.is_empty()  # the very first race is a best too, but not a "NEW BEST!" moment
			d.race_best = [secs, today, marbles]
		var cups: Array = d.cups
		var rank := {"bronze": 0, "silver": 1, "gold": 2}
		if not cups.is_empty() and str(cups[cups.size() - 1][0]) == today:
			if int(rank[medal]) > int(rank.get(str(cups[cups.size() - 1][1]), 0)):
				cups[cups.size() - 1] = [today, medal]
		else:
			cups.append([today, medal])
			out["new_cup"] = true
		while cups.size() > CUPS_MAX:
			cups.remove_at(0)
		if out.best_today:
			d.ghost = {"d": today, "legs": rec.duplicate(true)}
		d.races = int(d.get("races", 0)) + 1
		main.save.mark_dirty()
	last = out
	main.net.event("race", [t, false, -1, null])
	return out


## What the BEST TIMES board shows (town.gd set_times): today's best few, the best ever, the cups (newest last).
static func board_data(d: Dictionary) -> Dictionary:
	var today := Seeded.today()
	var race: Dictionary = d.get("race", {}) if d.get("race") is Dictionary else {}
	var rows: Array = []
	for r in race.get(today, []):
		rows.append([float(r[0]), int(r[1]), str(r[2]) if (r as Array).size() > 2 else ""])
	var cups: Array = []
	for c in (d.get("cups", []) if d.get("cups") is Array else []):
		cups.append(str(c[1]))
	var be: Array = d.get("race_best", []) if d.get("race_best") is Array else []
	return {"today": rows, "best": float(be[0]) if not be.is_empty() else -1.0, "cups": cups}