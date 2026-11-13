extends "res://core/pick_flow.gd"
## BEE GARDEN PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices between rounds:
##   "mode"  GENTLE / BRAVE / HARD after the practice round (round 1 is the same calm round in every mode; the
##           family's last mode floats in the middle).
##   "gift"  QUEEN BEA'S GIFT after each later round: three of BUMBLE BEES (bees carry 4 pollen), ZOOM WINGS (bees
##           fly faster), SWEET FLOWERS (pollen regrows faster) and WILDFLOWERS (three empty spots bloom), each once a
##           visit (gardengen.gd GIFTS: the validator proves every gift only helps).
## The orbs float in a row over the middle of the bed. A BEE flies into one; the GARDENER touches one with a hand (VR)
## or holds the glove's grab on it (flat). The first touch decides for the team (a dot in their colour circles it).
## Nobody chooses in time? The middle orb (it glows brightest) is taken: little ones never get stuck.
## Host / local decide; the host keeps the "orbs" state [stage, entries] (sticky: a machine joining mid-pick sees the
## orbs too) and sends "take" [i, slot] events; every machine draws.

const GardenGen := preload("res://games/bee_garden/gardengen.gd")

const WAIT := {"mode": 14.0, "gift": 12.0}
const GAP := 2.3
const Y := 2.6         # well above the flower heads (hands and bees working the flowers never touch one by chance)
const VR_LIFT := 0.15  # VR: the row at the gardener's eye height (+ this); Queen Bea's cards and the HOORAY banner
                       # keep clear of the orbs by themselves (UiKit.vr_dodge)
const ROW := Vector3(0.0, 0.0, 0.9)   # the row's middle: over the front half of the bed, in the gardener's reach
const SCALE := 0.6
const BEE_R := 0.3     # a bee this close to an orb's picture takes it
const HAND_R := 0.25   # a VR hand
const GLOVE_R := 0.75  # the flat glove (over the orb, grab held with nothing in it ...)
const GLOVE_HOLD := 0.5  # ... for this long: carrying a seed or picking fruit underneath never takes one
const HIT_R := 0.5     # an orb's touch size (x SCALE)

var row_y := Y


func _init() -> void:
	after = 1.0
	waits = WAIT
	wait_default = 10.0
	hand_r = HAND_R
	sync = "state"


## Queen Bea's gifts this round: three not taken yet (the same on every machine for a seed).
static func offer(taken: Array, seed_value: int, round_n: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "gift", round_n])
	var open_ids: Array = []
	for gf in GardenGen.GIFTS:
		if not taken.has(String(gf[0])):
			open_ids.append(String(gf[0]))
	for i in range(open_ids.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = open_ids[i]
		open_ids[i] = open_ids[j]
		open_ids[j] = tmp
	return open_ids.slice(0, 3)


static func gift_entry(id: String) -> Dictionary:
	for gf in GardenGen.GIFTS:
		if String(gf[0]) == id:
			return {"id": id, "name": String(gf[1]), "pic": String(gf[2]), "color": gf[3]}
	return {"id": id, "name": id.to_upper(), "pic": "star", "color": Color.WHITE}


static func mode_entries(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var d := PickOrbs.mode(String(id))
		out.append({"id": id, "name": String(d.name), "pic": String(d.pic), "color": d.color})
	return out


## Host / local: put up the orbs (at the VR gardener's eye height when there is one).
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	row_y = Y
	var gd = main.gardener
	if gd != null and gd.vr and gd.xr_camera != null and gd.xr_camera.is_inside_tree():
		row_y = clampf(gd.xr_camera.global_position.y + VR_LIFT, Y, 4.5)
	show_row(new_stage, entries, row_y)
	publish([new_stage, entries, row_y])


func orbs_off() -> Array:
	return ["", [], Y]


func show_row(new_stage: String, entries: Array, y: float = Y) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, GAP, y, {"scale": SCALE, "pop": true, "font": 72, "hit_r": HIT_R})


## The bees flying into an orb, the VR gardener's hands, the flat gardener's glove holding grab
## over one with nothing in it.
func takers() -> Dictionary:
	var points := {}
	for b in main.bees():
		if b.active and b.is_inside_tree():
			points["b%d" % int(b.index)] = [b.global_position, int(b.index), "bee"]
	var gd = main.gardener
	if gd != null and not gd.ghost:
		for k in gd.hands.size():
			var h = gd.hands[k]
			if gd.vr:
				points["h%d" % k] = [h.pos, 0, "hand"]
			elif gd.flat:  # (always a taker: gripping over an orb is the move in)
				points["g%d" % k] = [h, 0, "glove"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	match kind:
		"bee":
			return orbs.nearest_hit(point, BEE_R)
		"glove":
			return orbs.at_point(point.pos, GLOVE_R) if point.gripping and point.held == "" else -1
	return orbs.nearest_hit(point, hand_r)


func dwell_for(kind: String) -> float:
	match kind:
		"glove":
			return GLOVE_HOLD
		"bee":
			return foot_dwell
	return hand_dwell


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot % main.PLAYER_COLORS.size()]


func fx(i: int, _slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.local_sound("pollen", -2.0, 1.0 + 0.12 * i)
		main.burst(at, col, 14, 0.06, false)
