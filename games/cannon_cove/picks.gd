extends Node
## CANNON COVE PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after target practice.
##   "gift"  POLLY'S CANNON GIFTS before every wave: three of BOUNCY BALLS, NET SHOT, BIG BARREL, GOLDEN BALL, QUICK LOAD.
## Three big glass orbs bob on the sea off the gunner's cannon (deep.gd row_spots: inside its swing and reach). The
## gunner SHOOTS one (aim and fire: a pick is never a resting hand), or a deckhand muskets one. The first one hit
## decides for the team (a dot in their colour circles it). Nobody hit one by ROW_WAIT: the middle orb (it glows
## brightest) - a lone gunner or a little one is never stuck. The host sends the sticky "orbs" event
## [stage, entries, spots] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/cannon_cove/deep.gd")

const AFTER := 1.2  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []  # the orbs' places (world)
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## Host / local: put up the orbs off the gunner's cannon. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	var c = main.cannons[clampi(int(main.players[0].station), 0, main.cannons.size() - 1)]
	spots = Deep.row_spots(c.global_position, c.outboard, float(main.sea_level), entries.size())
	show_row(new_stage, entries, spots)
	main.net.event("orbs", [new_stage, entries, spots])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, Vector3(0.0, (at[0] as Vector3).y, 0.0), 8.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE,
		"pop": true, "font": 72, "label_y": 1.2, "label_px": 0.006, "two_lines": true, "bob": 0.2})  # (names over the orbs: under them is the sea)


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	return (orbs.orbs[i] as Node3D).global_position


## Every machine: the orb a cannonball at pos hits (-1: none).
func ball_hit(pos: Vector3, extra: float = 0.0) -> int:
	if orbs.orbs.is_empty():
		return -1
	return orbs.nearest_hit(pos, Deep.CATCH + extra)


## Host: the orb a musket shot from `from` along `dir` hits first within max_d: [index, distance] or [-1, INF].
func ray_hit(from: Vector3, dir: Vector3, max_d: float) -> Array:
	var best := -1
	var best_t := max_d
	for o in orbs.orbs:
		if not is_instance_valid(o) or not (o as Node3D).is_inside_tree():
			continue
		var c: Vector3 = (o as Node3D).global_position
		var tt := (c - from).dot(dir)
		if tt < 0.0 or tt > best_t:
			continue
		if (from + dir * tt).distance_to(c) < float(o.hit_radius):
			best_t = tt
			best = int(o.index)
	return [best, best_t]


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
	if t > Deep.ROW_WAIT:
		take(options.size() / 2, -1)  # nobody shot one: the middle one (it glows brightest)


func can_take() -> bool:
	return stage != "" and chosen < 0 and t >= OPEN


## Host / local: orb i taken by slot (0 = the gunner, a deckhand's index, -1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else ("the gunner" if slot == 0 else "P%d" % (slot + 1)), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.PLAYER_COLORS[slot] if slot >= 0 and slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.local_sound("bullseye", -3.0, 1.0 + 0.1 * i)
		main.confetti(at + Vector3.UP * 1.0, false)


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
