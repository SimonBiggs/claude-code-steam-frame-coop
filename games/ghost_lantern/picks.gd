extends "res://core/pick_flow.gd"
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

const WAIT := {"mode": 14.0, "lantern": 12.0}
const GAP := 1.0
const VR_GAP := 0.85  # a VR row a little narrower: the start spot's easel and cuckoo clock (props.gd) stand just outside it
const Y := 1.3
const AHEAD := 1.7  # metres in front of the VR lantern-bearer (a flat one: AHEAD_FLAT, so the row fits the view)
const AHEAD_FLAT := 3.2
const FEET_R := 0.55  # how close (flat) a walking player must come under an orb
const HAND_R := 0.22
const UPGRADES: Array = [
	["wide", "BIG LIGHT", "biglight", Color(1.0, 0.85, 0.35)],
	["far", "LONG LIGHT", "longlight", Color(0.55, 0.85, 1.0)],
	["dizzy", "DIZZY STARS", "dizzystars", Color(1.0, 0.6, 0.95)],
	["vac", "SUPER SUCK", "supersuck", Color(0.55, 1.0, 0.65)],
]
const MAX_LEVEL := 2


func _init() -> void:
	after = 1.0
	waits = WAIT
	wait_default = 10.0
	hand_r = HAND_R
	sync = "state"


## The lantern upgrades this night: three not at MAX_LEVEL yet (the same on every machine for a seed).
static func offer(levels: Dictionary, seed_value: int, night: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "lantern", night])
	var open_ids: Array = []
	for u in UPGRADES:
		if int(levels.get(u[0], 0)) < MAX_LEVEL:
			open_ids.append(String(u[0]))
	for i in range(open_ids.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = open_ids[i]
		open_ids[i] = open_ids[j]
		open_ids[j] = tmp
	return open_ids.slice(0, 3)


static func upgrade_entry(id: String) -> Dictionary:
	for u in UPGRADES:
		if String(u[0]) == id:
			return {"id": id, "name": String(u[1]), "pic": String(u[2]), "color": u[3]}
	return {"id": id, "name": id.to_upper(), "pic": "star", "color": Color.WHITE}


## Host / local: put up the orbs in front of the lantern-bearer.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	var places := _places(entries.size())
	show_row(new_stage, entries, places)
	publish([new_stage, entries, places])


func _places(n: int) -> Array:
	var p0 = main.players[0]
	var head: Transform3D = p0.xr_camera.global_transform if p0.vr and p0.xr_camera != null and p0.xr_camera.is_inside_tree() else p0.global_transform
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var o := head.origin + fwd * (AHEAD if main.players[0].vr else AHEAD_FLAT)
	o.x = clampf(o.x, -19.6, 19.6)
	o.z = clampf(o.z, -6.4, 6.4)
	# Not across a wall between the rooms (x = -7 / 7): slide into the room the lantern-bearer is in.
	var gap := VR_GAP if main.players[0].vr else GAP
	var half := (n - 1) * 0.5 * gap + 0.6
	for wx in [-7.0, 7.0]:
		var side := signf(head.origin.x - wx)
		if absf(o.x - wx) < half * absf(right.x) + 0.4:
			o.x = wx + side * (half * absf(right.x) + 0.4)
	var out: Array = []
	for i in n:
		var p := o + right * (float(i) - (n - 1) * 0.5) * gap
		out.append(Vector3(p.x, 0.0, p.z))  # (VR cards keep clear of the orbs themselves: UiKit.vr_dodge)
	return out


func show_row(new_stage: String, entries: Array, places: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, Vector3.ZERO, GAP, Y, {"at": places, "scale": 0.7, "pop": true, "touch": FEET_R})


## VR players' hands reaching into an orb, the others walking under one.
func takers() -> Dictionary:
	var points := {}
	for p in main.players:
		if not p.active or p.ghost:
			continue
		if p.vr:
			for k in 2:
				var hand: Node3D = p.hand_r if k == 0 else p.hand_l
				if hand != null and hand.is_inside_tree():
					points["h%d_%d" % [p.index, k]] = [hand.global_position, int(p.index), "hand"]
		elif p.is_inside_tree() and (not p.remote or main.net.connected):
			points["p%d" % p.index] = [p.global_position, int(p.index), "walk"]
	return points


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot % main.PLAYER_COLORS.size()]


func fx(i: int, _slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.local_sound("note", -4.0, 1.0 + 0.12 * i)
		main.burst(at, col, 14, 0.06)
