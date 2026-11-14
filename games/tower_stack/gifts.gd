extends Node3D
## WREN'S GIFTS (Tower Stack, fourth pass): before some later jobs the team picks one of three gentle gifts on the
## shared pick orbs (core/pick_orbs.gd gift_choices; picks.gd stage "gift"). A gift lasts the NEXT job only and only
## ever helps: nothing about the job's plan changes, so towergen.gd's validator still proves every job (and
## tests/tower_stack_gen_test.gd checks every gift keeps a job valid and never makes it windier or wobblier).
##   flag     WIND-BREAK FLAG   the wind, gusts, the jelly stage's sway and quakes all push half as hard.
##   mortar   STICKY MORTAR     a block resting in its plan spot glues down like honey (specials.gd), and a gentle
##                              place snaps onto its spot from further away.
##   basket   WREN'S BASKET     Wren drops the block the plan needs onto the pad twice as often.
##   capstone GOLDEN CAPSTONE   the tower gets a golden roof and every builder scores BONUS blocks. Opens once the
##                              town has CAPSTONE_AT towers (gift_choices always offers the newest gift).
## Every machine: a little pennant on a pole beside the stage shows the gift that's on (the "gift" state).

const PickOrbs := preload("res://core/pick_orbs.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const GIFTS: Array[Dictionary] = [
	{"id": "flag", "name": "CALM FLAG", "pic": "windflag", "line": "Calm flag! Soft wind!", "color": Color(0.35, 0.7, 1.0), "at": 0},
	{"id": "mortar", "name": "STICKY MORTAR", "pic": "mortar", "line": "Sticky mortar!", "color": Color(0.95, 0.6, 0.25), "at": 0},
	{"id": "basket", "name": "WREN'S BASKET", "pic": "wrenbasket", "line": "Wren brings blocks!", "color": Color(0.55, 0.85, 0.35), "at": 0},
	{"id": "capstone", "name": "GOLD ROOF", "pic": "capstone", "line": "A golden roof!", "color": Color(1.0, 0.82, 0.2), "at": 3},
]
const CAPSTONE_AT := 3  # towers in the town before the golden capstone opens
const CALM := 0.5  # flag: wind, gusts, sway and quakes push this much
const MORTAR_SNAP := 0.4  # mortar: a gentle place this close to its spot snaps on (main.gd SNAP_R otherwise)
const BASKET_HELP := 0.5  # basket: Wren's pad drop comes this much sooner (towergen PAD_HELP x this)
const BONUS := 5  # capstone: blocks of score for every builder
const POLE_AT := Vector3(1.95, 0.0, -1.35)  # beside the stage, clear of the pad, the sock and the pick row

var gift := ""  # every machine: the gift that's on now ("" = none)
var pole: Node3D
var pennant: MeshInstance3D


static func ids() -> Array:
	var out: Array = []
	for g in GIFTS:
		out.append(String(g.id))
	return out


static func of(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## The gifts open now (oldest first, the newest last: gift_choices always offers the newest).
static func unlocked(built: int, all := false) -> Array:
	var out: Array = []
	for g in GIFTS:
		if all or built >= int(g.at):
			out.append(String(g.id))
	return out


static func choices(built: int, last: String, seed_value: int, all := false) -> Array:
	return PickOrbs.gift_choices(unlocked(built, all), last, seed_value)  # (the shared gift pick)


static func entry(id: String) -> Dictionary:
	var g := of(id)
	return {"id": id, "name": String(g.get("name", id)), "pic": String(g.get("pic", "gift")), "color": g.get("color", Color.WHITE)}


## How hard wind / gusts / sway / quakes push with this gift on (1 = as towergen made it).
static func calm(id: String) -> float:
	return CALM if id == "flag" else 1.0


static func snap_r(id: String, plain: float) -> float:
	return maxf(plain, MORTAR_SNAP) if id == "mortar" else plain


static func pad_help(id: String, plain: float) -> float:
	return plain * BASKET_HELP if id == "basket" else plain


static func glues(id: String) -> bool:
	return id == "mortar"


static func bonus(id: String) -> int:
	return BONUS if id == "capstone" else 0


## A job as the host plays it with the gift on (wind and sway scaled; the plan, set and events stay the same): the
## validator must pass it whenever it passes the plain job (tests/tower_stack_gen_test.gd).
static func calmed(s: Dictionary, id: String) -> Dictionary:
	var out := s.duplicate(true)
	out.wind = float(s.get("wind", 0.0)) * calm(id)
	out.sway = float(s.get("sway", 0.0)) * calm(id)
	return out


func _ready() -> void:
	name = "Gifts"
	pole = Node3D.new()
	pole.name = "GiftPole"
	pole.position = POLE_AT
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.045
	cm.height = 1.6
	stick.mesh = cm
	stick.position.y = 0.8
	stick.material_override = MeshKit.material(Color(0.5, 0.36, 0.22))
	pole.add_child(stick)
	pennant = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.36, 0.55, 0.04)
	pennant.mesh = pm
	pennant.rotation.z = -PI * 0.5
	pennant.position = Vector3(0.3, 1.35, 0.0)
	pole.add_child(pennant)
	add_child(pole)
	show_gift("")


## Every machine (the "gift" state): the pennant in the gift's colour, or no pole at all.
func show_gift(id: String) -> void:
	gift = id
	if pole == null:
		return
	pole.visible = id != ""
	if id != "":
		pennant.material_override = MeshKit.material(of(id).get("color", Color.WHITE))


func _process(_delta: float) -> void:
	if pole != null and pole.visible:
		pennant.rotation.y = sin(Time.get_ticks_msec() * 0.004) * (0.12 if gift == "flag" else 0.35)
