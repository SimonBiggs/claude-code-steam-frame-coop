extends Node
## STARSHIP CREW PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first seeded
##           trip's first mission.
##   "gift"  CAPTAIN WHISKERS' SHIP MODULES before every mission from the second of a seeded trip: three of BUBBLE
##           SHIELD, TRACTOR BEAM, TURBO, MEGA LASER, STAR BOOST.
## Three big glass orbs float in space just ahead of the ship, above its usual line (deep.gd row_spots: space x, y,
## so they slide past like the rings when the ship steers). The PILOT steers until one sits straight ahead and holds it
## there (deep.gd DWELL; a ship already lined up with one when they open must move off and come back: a resting ship
## never picks); a GUNNER zaps one with their crosshair (a press: deliberate). The CPU gunner never picks. The first
## one decides for the team (a dot in their colour circles it). Nobody in time? The middle orb (it glows brightest):
## a lone player or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a
## machine joining mid-pick sees the orbs too) and "take".

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/starship_crew/deep.gd")
const Space := preload("res://games/starship_crew/space.gd")
const Party := preload("res://core/party.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const RESTING := 99

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []  # every machine: the orbs' places in space (Vector2)
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var line := -2  # host: the orb the ship is lined up with (-2: not looked yet; RESTING: lined up when they opened)
var dwell := 0.0


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	line = -2
	dwell = 0.0
	show_row(new_stage, entries, Deep.row_spots(entries.size()))
	main.net.event("orbs", [new_stage, entries, spots])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		spots = []
		return
	spots = at.duplicate()
	orbs.position = Vector3.ZERO
	var places: Array = []
	for s in spots:
		var p: Vector2 = s
		places.append(Vector3(p.x, p.y + Space.SHIP_Y, Deep.ROW_Z))
	orbs.show_orbs(new_stage, entries, places[0], 4.0, 0.0, {"at": places, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
		"label_y": -1.05, "label_px": 0.008, "two_lines": true, "bob": 0.1})
	follow()


## Every machine, every frame: the orbs slide with space (the ship's sideways place).
func follow() -> void:
	if main.space != null:
		orbs.position = Vector3(-main.space.off.x, -main.space.off.y, 0.0)


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


## Seconds left to pick.
func left() -> float:
	return maxf(0.0, Deep.wait_for(stage, main.pick_nobody()) - t) if stage != "" and chosen < 0 else 0.0


## Host / local, every frame while the orbs are up.
func tick(delta: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= AFTER:
			_finish()
		return
	t += minf(delta, 0.1)  # (a loading hitch never eats the wait)
	if main.vr_rig != null:
		_pilot(delta)
		if chosen >= 0:
			return
	if t > Deep.wait_for(stage, main.pick_nobody()):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## The pilot: the ship lined up with an orb, held there (a ship lined up when they opened must move off first).
func _pilot(delta: float) -> void:
	var i := Deep.lined_up(spots, main.space.off)
	if line == -2:
		line = RESTING if i >= 0 else -1
	if line == RESTING:
		if i < 0:
			line = -1
		dwell = 0.0
		return
	if i != line:
		dwell = 0.0
	line = i
	if i >= 0 and t >= Deep.OPEN:
		dwell += delta
		if dwell >= Deep.DWELL:
			take(i, 0)


## Host: the lined-up orb gently holds the ship (kids stop on it more easily).
func hold_pull() -> Vector2:
	if stage == "" or chosen >= 0 or line < 0 or line == RESTING or line >= spots.size():
		return Vector2.ZERO
	return spots[line] - main.space.off


## Host: a gunner zapped at uv (TV screen). True when it hit an orb (picked) - the zap is used up either way while
## the orbs are up.
func zap_at(slot: int, uv: Vector2) -> bool:
	if stage == "" or chosen >= 0 or slot < 0 or t < Deep.OPEN:
		return false
	var best := -1
	var bd := INF
	for i in orbs.orbs.size():
		var w := orb_position(i)
		if w == Vector3.INF:
			continue
		var s: Vector2 = main.project(w)
		var d := Vector2((s.x - uv.x) * main.ASPECT, s.y - uv.y).length()
		if d < 0.2 and d < bd:
			bd = d
			best = i
	if best >= 0:
		take(best, slot)
		return true
	return false


## Host / local: orb i taken by slot (0 = the pilot or P1, -1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst.
func take_fx(i: int, slot: int) -> void:
	var col: Color = Party.COLORS[slot % Party.COLORS.size()] if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.confetti(at, col, 30)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	spots = []
	orbs.clear()
	main.net.event("orbs", ["", [], []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)