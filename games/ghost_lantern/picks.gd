extends Node
## GHOST LANTERN PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices:
##   "mode"     GENTLE / BRAVE / HARD before the first night of a visit (the family's last mode in the middle).
##   "lantern"  GRANNY BOO'S LANTERN GIFT between nights: three of BIG LIGHT (a wider beam), LONG LIGHT (it shines
##              further), DIZZY STARS (ghosts get dizzy quicker) and SUPER SUCK (vacuums and the lantern slurp faster);
##              each can be taken twice in a visit.
## The orbs float in a row at chest height in front of the lantern-bearer. The VR lantern-bearer TOUCHES one with a
## hand; a TV player (or a flat lantern-bearer) WALKS under one. The first touch decides for the team (a dot in their
## colour circles it). Nobody chooses in time? The middle orb (it glows brightest) is taken: little ones never get stuck.
## Host / local decide; the host keeps the "orbs" state [stage, entries, places] (sticky: a machine joining mid-pick
## sees the orbs too) and sends "take" [i, slot] events; every machine draws.

const PickOrbs := preload("res://core/pick_orbs.gd")

const WAIT := {"mode": 14.0, "lantern": 12.0}
const AFTER := 1.0  # seconds the taken orb shows its dot before the orbs go
const GAP := 1.0
const Y := 1.3
const AHEAD := 1.7  # metres in front of the VR lantern-bearer (a flat one: AHEAD_FLAT, so the row fits the view)
const AHEAD_FLAT := 3.2
const VR_LIFT := 0.3  # VR: the row at eye height, above Granny Boo's story cards
const FEET_R := 0.55  # how close (flat) a walking player must come under an orb
const HAND_R := 0.22
## Lantern gifts: [id, name, picture, colour]. main.gd reads the levels (upgrades[id], 0..MAX_LEVEL).
const UPGRADES: Array = [
	["wide", "BIG LIGHT", "biglight", Color(1.0, 0.85, 0.35)],
	["far", "LONG LIGHT", "longlight", Color(0.55, 0.85, 1.0)],
	["dizzy", "DIZZY STARS", "dizzystars", Color(1.0, 0.6, 0.95)],
	["vac", "SUPER SUCK", "supersuck", Color(0.55, 1.0, 0.65)],
]
const MAX_LEVEL := 2

var main: Node
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "lantern"
var options: Array = []  # host: what each orb means (mode ids / upgrade ids)
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option)
var history: Array = []  # host: what was chosen this visit (telemetry)


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0  # nothing shoots them: hands and feet only
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


## Host: the upgrade ids the lantern-bearer may still take (seeded order for the night), at most three.
static func offer(levels: Dictionary, seed_value: int, night: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "lantern", night])
	var open: Array = []
	for u in UPGRADES:
		if int(levels.get(u[0], 0)) < MAX_LEVEL:
			open.append(String(u[0]))
	for i in range(open.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = open[i]
		open[i] = open[j]
		open[j] = tmp
	return open.slice(0, 3)


static func upgrade_entry(id: String) -> Dictionary:
	for u in UPGRADES:
		if String(u[0]) == id:
			return {"id": id, "name": String(u[1]), "pic": String(u[2]), "color": u[3]}
	return {"id": id, "name": id.to_upper(), "pic": "star", "color": Color.WHITE}


## Host / local: put up the orbs in front of the lantern-bearer.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = float(WAIT.get(new_stage, 10.0))
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	var places := _places(entries.size())
	show_row(new_stage, entries, places)
	if main.net.mode == "host":
		main.net.state_set("orbs", [new_stage, entries, places])
	print("PICK %s up: %s" % [new_stage, str(opts)])


## A row across the lantern-bearer's view, AHEAD metres in front at chest height, kept inside the house.
func _places(n: int) -> Array:
	var head: Transform3D = main.players[0].net_head if main.players[0].vr else main.players[0].global_transform
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var o := head.origin + fwd * (AHEAD if main.players[0].vr else AHEAD_FLAT)
	o.x = clampf(o.x, -19.6, 19.6)
	o.z = clampf(o.z, -6.4, 6.4)
	# Not across a wall between the rooms (x = -7 / 7): slide into the room the lantern-bearer is in.
	var half := (n - 1) * 0.5 * GAP + 0.6
	for wx in [-7.0, 7.0]:
		var side := signf(head.origin.x - wx)
		if absf(o.x - wx) < half * absf(right.x) + 0.4:
			o.x = wx + side * (half * absf(right.x) + 0.4)
	var out: Array = []
	for i in n:
		var p := o + right * (float(i) - (n - 1) * 0.5) * GAP
		out.append(Vector3(p.x, VR_LIFT if main.players[0].vr else 0.0, p.z))
	return out


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, places: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, Vector3.ZERO, GAP, Y, {"at": places, "scale": 0.7, "pop": true, "touch": FEET_R})


## Host / local, every frame while the orbs are up (the clock; touches are physics frames: _physics_process).
func tick(delta: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= AFTER:
			_finish()
		return
	t -= delta
	if t <= 0.0:
		take(options.size() / 2, -1)  # the middle one (it glows brightest)


## Host / local: a VR hand touching an orb, or someone walking under one (where the hands and feet are this frame).
func _physics_process(_delta: float) -> void:
	if stage == "" or chosen >= 0 or main.net.mode == "client":
		return
	for p in main.players:
		if not p.active or p.ghost:
			continue
		if p.vr:
			for hand in [p.hand_r, p.hand_l]:
				if hand == null or not hand.is_inside_tree():
					continue
				var i2 := orbs.nearest_hit(hand.global_position, HAND_R)
				if i2 >= 0:
					take(i2, p.index)
					return
		elif p.is_inside_tree() and (not p.remote or main.net.connected):
			var i := orbs.at_point(p.global_position)
			if i >= 0:
				take(i, p.index)
				return


## Host / local: orb i taken by slot (-1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	if main.net.mode == "host":
		main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.PLAYER_COLORS[slot % main.PLAYER_COLORS.size()] if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.local_sound("note", -4.0, 1.0 + 0.12 * i)
		main.burst(at, col, 14, 0.06)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by >= 0])
	stage = ""
	options = []
	orbs.clear()
	if main.net.mode == "host":
		main.net.state_set("orbs", ["", [], []])
	if on_done.is_valid():
		on_done.call(st, opt)