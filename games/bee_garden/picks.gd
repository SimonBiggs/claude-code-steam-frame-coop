extends Node
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

const PickOrbs := preload("res://core/pick_orbs.gd")
const GardenGen := preload("res://games/bee_garden/gardengen.gd")

const WAIT := {"mode": 14.0, "gift": 12.0}
const AFTER := 1.0     # seconds the taken orb shows its dot before the orbs go
const GAP := 2.3
const Y := 2.6         # well above the flower heads (hands and bees working the flowers never touch one by chance) and,
                       # in VR, above Queen Bea's story cards (never in front of them)
const ROW := Vector3(0.0, 0.0, 0.9)   # the row's middle: over the front half of the bed, in the gardener's reach
const SCALE := 0.6
const BEE_R := 0.3     # a bee this close to an orb's picture takes it
const HAND_R := 0.25   # a VR hand
const GLOVE_R := 0.75  # the flat glove (over the orb, grab held with nothing in it ...)
const GLOVE_HOLD := 0.5  # ... for this long: carrying a seed or picking fruit underneath never takes one
const HIT_R := 0.5     # an orb's touch size (x SCALE)

var main: Node
var orbs: PickOrbs
var stage := ""        # host: "" | "mode" | "gift"
var options: Array = []
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option)
var history: Array = []
var glove_on := -1
var glove_t := 0.0


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0  # nothing shoots them: bees, hands and the glove only
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


## Host: the gifts still to give (seeded order for the round), at most three.
static func offer(taken: Array, seed_value: int, round_n: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "gift", round_n])
	var open: Array = []
	for gf in GardenGen.GIFTS:
		if not taken.has(String(gf[0])):
			open.append(String(gf[0]))
	for i in range(open.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = open[i]
		open[i] = open[j]
		open[j] = tmp
	return open.slice(0, 3)


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


## Host / local: put the orbs up.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = float(WAIT.get(new_stage, 10.0))
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	glove_on = -1
	show_row(new_stage, entries)
	if main.net.mode == "host":
		main.net.state_set("orbs", [new_stage, entries])
	print("PICK %s up: %s" % [new_stage, str(opts)])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, GAP, Y, {"scale": SCALE, "pop": true, "font": 72, "hit_r": HIT_R})


## Where orb i's picture is (bots fly there); Vector3.INF if none.
func orb_pos(i: int) -> Vector3:
	for o in orbs.orbs:
		if is_instance_valid(o) and o.index == i and o.is_inside_tree():
			return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else o.global_position
	return Vector3.INF


## Host / local, every frame while the orbs are up.
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


## Host / local: bees flying into an orb, the gardener's hands touching one (physics frames).
func _physics_process(delta: float) -> void:
	if stage == "" or chosen >= 0 or main.net == null or main.net.mode == "client":
		return
	for b in main.bees():
		if not b.active or not b.is_inside_tree():
			continue
		var i: int = orbs.nearest_hit(b.global_position, BEE_R)
		if i >= 0:
			take(i, b.index)
			return
	var gd = main.gardener
	if gd == null or gd.ghost:
		return
	for h in gd.hands:
		if gd.vr:
			var i2: int = orbs.nearest_hit(h.pos, HAND_R)
			if i2 >= 0:
				take(i2, 0)
				return
		elif gd.flat:
			var i3: int = orbs.at_point(h.pos, GLOVE_R) if h.gripping and h.held == "" else -1
			if i3 != glove_on:
				glove_on = i3
				glove_t = 0.0
			elif i3 >= 0:
				glove_t += delta
				if glove_t >= GLOVE_HOLD:
					take(i3, 0)
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
		main.local_sound("pollen", -2.0, 1.0 + 0.12 * i)
		main.burst(at, col, 14, 0.06, false)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by >= 0])
	stage = ""
	options = []
	orbs.clear()
	if main.net.mode == "host":
		main.net.state_set("orbs", ["", []])
	if on_done.is_valid():
		on_done.call(st, opt)
