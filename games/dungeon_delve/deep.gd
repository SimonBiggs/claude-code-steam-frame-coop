extends Node3D
## DUNGEON DELVE: BRAVE and HEROIC, the deep dungeon (the GENTLE run is main.gd + dungeon.gd).
## Picked in the practice room by standing on the orange BRAVE or red HEROIC pad (it fills up; faster
## the more of you stand on it). Then: 4 biomes (Slime Caves, Bone Crypt, Crystal Caves, Lava Forge) x 4
## seeded floors (floorgen.gd), the 4th ending in the biome's boss; a shop camp between floors, and a
## RELIC ALTAR at the camp after the 2nd floor and after each boss (relics.gd: pick ONE of 2-3).
##  - HEROES (classes.gd): bonk a statue in the practice room to be a KNIGHT, ARCHER or WIZARD.
##  - CINDER'S HOARD: every coin you pick up goes into Cinder's hoard for good (bosses add a pile); a big
##    enough hoard unlocks new heroes and new relics (the gold pile in the practice room shows it).
##  - Hearts: heroes have 4 (HEROIC 3), the knight one more (heart containers: up to 8). At zero you're knocked out; a friend
##    standing next to you fills your ring and you pop back up (2 hearts). Everyone out = back to the
##    first floor of the zone (the checkpoint) with what you had then; HEROIC has no checkpoints: the
##    run ends. BRAVE also helps knocked-out heroes up when a room is cleared.
##  - Rooms: walk in and the doors shut until every monster is gone (friends left outside are popped
##    in). Keys open locked doors (the exit / the boss door); puzzle doors need their two switches on
##    together; a cracked wall hides a treasure room (3 hits or a bomb); traps: spikes, boulders,
##    crumbly floor. The stairs fill like the pads: stand on them together.
##  - Loot (loot.gd): gold, potions (Y), bombs (B), abilities on X (dash, shield bash, bow), heart
##    containers; the shop sells more, plus SWORD +1 and a LUCKY CHARM. Each boss leaves three
##    treasures: everyone picks ONE (that's your build for the next zone).
##  - Alone on BRAVE (a Deck on its own): one more heart, a lucky charm on every floor, a few less
##    monsters per room. Attacks soft-aim at the nearest monster in reach. HEROIC opens after the
##    Slime King has been beaten on BRAVE.
##  - The VR knight: a real sword that hits for 2, swats goo balls and boss ORBS back (big damage),
##    BLOCKS sweeps and shoves when the blade is between him and the hit; bosses aim at him a lot.
##    His hearts sit on the blade. Touch pickups, chests, levers and shop items with either hand.
##  - Scaling: more monster health and extra monsters with more players; deeper = tougher; HEROIC =
##    tougher, faster, more elites, no checkpoints, no free potion.
##  - Persistence (main.save "deep"): best depth, bosses beaten, unlocked hats (the hat stand in the
##    practice room: bonk it to swap hats) and starting perks (a potion, +1 heart, bombs).
## The host runs everything; other machines build the same floor from the seed and mirror the state
## store ("d_*" keys), the snapshot (deep_pack) and events ("d_*").

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const FloorView := preload("res://games/dungeon_delve/floor_view.gd")
const Foes := preload("res://games/dungeon_delve/foes.gd")
const Tele := preload("res://games/dungeon_delve/tele.gd")
const Loot := preload("res://games/dungeon_delve/loot.gd")
const Hero := preload("res://games/dungeon_delve/hero.gd")
const DeepHud := preload("res://games/dungeon_delve/deep_hud.gd")
const VrRig := preload("res://core/vr_rig.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const Telemetry := preload("res://core/telemetry.gd")
const Relics := preload("res://games/dungeon_delve/relics.gd")
const Classes := preload("res://games/dungeon_delve/classes.gd")

const DIFF := {
	"brave": {"hp": 1.25, "spd": 1.08, "dmg": 0, "checkpoints": true, "potions": 1, "auto_revive": true, "hearts": 4},
	"heroic": {"hp": 1.7, "spd": 1.22, "dmg": 0, "checkpoints": false, "potions": 0, "auto_revive": false, "hearts": 3},
}
const REVIVE_TIME := 3.5  ## seconds a friend must stand by you (a hit on the helper starts it again)
const REVIVE_R := 1.5
const IFRAMES := 1.2
const STAIRS_R := 1.5
const ATTACK_REACH := 1.05
const PADS := {"brave": Vector3(-2.2, 0.0, -2.5), "heroic": Vector3(2.2, 0.0, -2.5), "daily": Vector3(-3.5, 0.0, 2.7)}
const PAD_COLORS := {"brave": Color(1.0, 0.6, 0.2), "heroic": Color(1.0, 0.3, 0.35), "daily": Color(0.35, 0.8, 1.0)}
const HAT_RACK := Vector3(3.7, 0.0, 2.6)
const HAT_UNLOCKS: Array = [["none", ""], ["party", "run"], ["viking", "floor3"], ["wizard", "boss0"], ["crown", "boss1"], ["halo", "boss3"]]
## The hero statues (bonk one to be that hero) along the right wall, and Cinder's hoard by the left wall.
const CLASS_SPOTS := {"knight": Vector3(3.75, 0.0, -1.3), "archer": Vector3(3.75, 0.0, -0.1), "wizard": Vector3(3.75, 0.0, 1.1)}
const HOARD_SPOT := Vector3(-3.2, 0.0, 1.05)
const ALTAR_SPOTS: Array[Vector2] = [Vector2(2.3, 4.2), Vector2(3.6, 3.3), Vector2(4.3, 1.9)]  ## relic stones at the camp
const BOSS_HOARD := 40  ## a boss adds this (x biome) to Cinder's hoard
const SHOP_SPOTS: Array[Vector2] = [Vector2(-3.0, 0.2), Vector2(-1.0, 0.2), Vector2(1.0, 0.2), Vector2(3.0, 0.2)]

var main: Node
var net: Node
var party: Node
var active := false
var f: Dictionary = {}
var view: FloorView
var foes: Foes
var tele: Tele
var hud: DeepHud
var lobby: Node3D
var pad_rings := {}
var pad_labels := {}
var built_key := ""

# Host.
var mode := ""
var daily := false
var seed_v := 0
var zone := 0
var floor_i := 0
var kind := "floor"
var after := [0, 0]  ## the floor after the shop: [zone, floor]
var stats := {}  ## slot -> {"hp", "max", "pot", "bomb", "abil", "dmg", "charm", "down"}
var stats_dirty := false
var iframes := {}
var revive := {}
var pickups := {}  ## id -> {"kind", "p", "v", "t"}
var next_pick := 1
var hazards: Array = []
var trap_clock := 0.0
var traps_out := PackedFloat32Array()
var sw_out := PackedFloat32Array()
var sw_linger := {}  ## switch id -> seconds it stays on
var collapse := {}  ## trap id -> {"shake": {tile: t}, "fall": {tile: t}}
var secret_hits := {}
var open_bits := 0
var seen_bits := 0
var cleared_bits := 0
var spawned_bits := 0
var lock_room := -1
var entry := Vector3.INF
var straggle_t := -1.0
var stairs_fill := 0.0
var portal := Vector3.INF
var checkpoint := {}
var phase_t := 0.0
var shop: Array = []
var pad_fill := {"brave": 0.0, "heroic": 0.0, "daily": 0.0}
var hat_cd := {}
var sword_cd := {}
var _poke_cd := {}
var _touch_prev := {}
var _gold := 0
var _keys := 0
var tally := {"kills": 0, "floors": [], "bosses": 0, "wipes": 0, "revives": 0, "keys": 0, "doors": 0, "secrets": 0,
	"puzzles": 0, "bought": 0, "potions": 0, "hurts": 0, "blocks": 0, "reflects": 0, "rooms": 0, "downs": 0,
	"pickups": 0, "checkpoints": 0, "zones": {}, "bombs": 0, "abilities": 0, "traps": 0, "chests": 0, "by": {}}
var src := ""  ## what is hurting someone right now (tests: tally["by"])
var runrec := {}  ## this run, for core/telemetry.gd (written at the end or on quit)
var relic_group := 0
var relic_taken := {}  ## group -> {slot: true}: boss treasures, one each
var altar_group := 0  ## the relic altar's group at this camp (0: none)
var pet_cd := {}  ## slot -> seconds to the baby dragon's next fireball (DRAGON EGG)
var fang := {}  ## slot -> monsters bopped (VAMPIRE FANG: every 4th heals)
var cls_cd := {}

# Every machine.
var pick_nodes := {}
var pick_kinds := {}
var revive_vals := {}
var shop_nodes: Array[Node3D] = []
var knight_hearts: Node3D
var _hearts_shown := ""
var _t := 0.0
var _last_phase := ""
var class_nodes := {}  ## class id -> {"statue", "label", "sub"}
var hoard_node: Node3D
var hoard_label: Label3D
var hoard_sub: Label3D
var _hoard_shown := -1
var pets := {}  ## slot -> baby dragon node (DRAGON EGG)
var bubbles := {}  ## slot -> bubble node (BUBBLE SHIELD)


func setup(m: Node) -> void:
	main = m
	net = m.net
	party = m.party
	view = FloorView.new()
	view.name = "Floor"
	add_child(view)
	foes = Foes.new()
	foes.name = "Foes"
	add_child(foes)
	tele = Tele.new()
	add_child(tele)
	if net.mode != "client":
		foes.deep = self
	_build_lobby()
	if main.hud != null:
		hud = DeepHud.new()
		hud.setup(main.hud, party)
		hud.visible = false


func is_host() -> bool:
	return net.mode != "client"


func heroic() -> bool:
	return String(net.state_get("mode", "gentle")) == "heroic"


func diff() -> Dictionary:
	return DIFF.get(mode if mode != "" else String(net.state_get("mode", "brave")), DIFF["brave"])


# --- The lobby pads (practice room of the gentle dungeon) -----------------------------------------

func _build_lobby() -> void:
	lobby = Node3D.new()
	lobby.name = "Lobby"
	main.add_child(lobby)
	for mname in PADS:
		var col: Color = PAD_COLORS[mname]
		var b := MeshKit.Builder.new()
		b.cylinder(0.85, 0.9, 0.08, MeshKit.at(Vector3(0, 0.04, 0)), Color(0.3, 0.28, 0.34), 18)
		b.cylinder(0.7, 0.7, 0.04, MeshKit.at(Vector3(0, 0.1, 0)), col, 18, true)
		if mname == "brave":
			b.box(Vector3(0.08, 0.6, 0.02), MeshKit.at(Vector3(0, 1.35, 0)), Color(0.85, 0.92, 1.0), true)
			b.box(Vector3(0.3, 0.05, 0.05), MeshKit.at(Vector3(0, 1.05, 0)), Color(1.0, 0.8, 0.3), true)
			b.cylinder(0.035, 0.035, 0.16, MeshKit.at(Vector3(0, 0.95, 0)), Color(0.5, 0.3, 0.2), 6)
		elif mname == "daily":
			b.star(8, 0.3, 0.16, 0.06, MeshKit.at(Vector3(0, 1.2, 0)), Color(1.0, 0.9, 0.4), true)
			b.sphere(0.13, MeshKit.at(Vector3(0, 1.2, 0.02)), Color(1.0, 0.75, 0.3), 10, true)
		else:
			b.cylinder(0.22, 0.24, 0.16, MeshKit.at(Vector3(0, 1.1, 0)), Color(1.0, 0.8, 0.3), 12, true)
			for k in 5:
				var a := TAU * k / 5.0
				b.cone(0.06, 0.2, MeshKit.at(Vector3(cos(a) * 0.19, 1.27, sin(a) * 0.19)), Color(1.0, 0.8, 0.3), 6, true)
				b.sphere(0.035, MeshKit.at(Vector3(cos(a) * 0.23, 1.12, sin(a) * 0.23)), Color(1.0, 0.3, 0.4), 6, true)
		var pad := MeshKit.instance(b.build(), false)
		pad.position = PADS[mname]
		lobby.add_child(pad)
		var rb := MeshKit.Builder.new()
		rb.torus(0.95, 0.07, Transform3D.IDENTITY, Color(1.0, 1.0, 1.0), 24, 4, true)
		var ring := MeshKit.instance(rb.build(), false)
		ring.position = PADS[mname] + Vector3(0.0, 0.12, 0.0)
		ring.scale = Vector3.ONE * 0.05
		lobby.add_child(ring)
		pad_rings[mname] = ring
		var l := Label3D.new()
		l.text = String(mname).to_upper()
		l.font_size = 64
		l.pixel_size = 0.006
		l.outline_size = 22
		l.modulate = col.lightened(0.3)
		l.outline_modulate = Color(0, 0, 0, 0.95)
		l.position = PADS[mname] + Vector3(0.0, 1.9, 0.0)
		lobby.add_child(l)
		pad_labels[mname] = l
		var best := Label3D.new()
		best.font_size = 40
		best.pixel_size = 0.005
		best.outline_size = 16
		best.outline_modulate = Color(0, 0, 0, 0.95)
		best.position = PADS[mname] + Vector3(0.0, 1.62, 0.0)
		best.name = "Best"
		l.add_child(best)
		best.position = Vector3(0.0, -0.28, 0.0)
	# The hat stand: bonk it (or touch it) to swap your hat for one you've unlocked.
	var hb := MeshKit.Builder.new()
	hb.cylinder(0.05, 0.06, 1.5, MeshKit.at(Vector3(0, 0.75, 0)), Color(0.5, 0.33, 0.2), 8)
	hb.cylinder(0.32, 0.36, 0.06, MeshKit.at(Vector3(0, 0.03, 0)), Color(0.5, 0.33, 0.2), 12)
	for k in 3:
		var a2 := TAU * k / 3.0
		hb.cylinder(0.025, 0.025, 0.35, MeshKit.at(Vector3(cos(a2) * 0.12, 1.4, sin(a2) * 0.12), Vector3.ONE, Vector3(sin(a2) * 0.8, 0, -cos(a2) * 0.8)), Color(0.5, 0.33, 0.2), 6)
	hb.add_mesh(Creatures.hat_mesh("wizard", Color(0.4, 0.4, 0.9), Color(1.0, 0.85, 0.3)), MeshKit.at(Vector3(0, 1.55, 0)))
	var rack := MeshKit.instance(hb.build(), false)
	rack.position = HAT_RACK
	lobby.add_child(rack)
	_build_class_statues()
	_build_hoard()


## The three hero statues on little plinths (bonk one to be that hero; locked ones show what's needed).
func _build_class_statues() -> void:
	class_nodes.clear()
	for id in Classes.ORDER:
		var ci: Dictionary = Classes.info(id)
		var root := Node3D.new()
		root.position = CLASS_SPOTS[id]
		root.rotation.y = -PI * 0.5  # facing into the room
		lobby.add_child(root)
		var pb := MeshKit.Builder.new()
		pb.cylinder(0.36, 0.42, 0.22, MeshKit.at(Vector3(0, 0.11, 0)), Color(0.45, 0.42, 0.5), 12)
		pb.torus(0.4, 0.035, MeshKit.at(Vector3(0, 0.23, 0)), ci["color"], 16, 4, true)
		root.add_child(MeshKit.instance(pb.build(), false))
		var look := {"class": "knight" if id == "knight" else ("archer" if id == "archer" else "mage"), "seed": 5, "outfit": (ci["color"] as Color).darkened(0.2)}
		for k in ci["look"]:
			look[k] = ci["look"][k]
		var statue := Creatures.humanoid(look)
		statue.position.y = 0.22
		statue.scale = Vector3.ONE * 1.0
		root.add_child(statue)
		var l := Label3D.new()
		l.text = String(ci["name"])
		l.font_size = 48
		l.pixel_size = 0.005
		l.outline_size = 16
		l.modulate = (ci["color"] as Color).lightened(0.2)
		l.outline_modulate = Color(0, 0, 0, 0.95)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.position = CLASS_SPOTS[id] + Vector3(0.0, 1.75, 0.0)
		lobby.add_child(l)
		var sub := Label3D.new()
		sub.font_size = 36
		sub.pixel_size = 0.005
		sub.outline_size = 14
		sub.outline_modulate = Color(0, 0, 0, 0.95)
		sub.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sub.position = CLASS_SPOTS[id] + Vector3(0.0, 1.5, 0.0)
		lobby.add_child(sub)
		class_nodes[id] = {"statue": statue, "label": l, "sub": sub}


## Cinder's hoard: a pile of gold that grows with the family's hoard, with the next unlock above it.
func _build_hoard() -> void:
	hoard_node = Node3D.new()
	hoard_node.position = HOARD_SPOT
	lobby.add_child(hoard_node)
	hoard_label = Label3D.new()
	hoard_label.font_size = 48
	hoard_label.pixel_size = 0.005
	hoard_label.outline_size = 16
	hoard_label.modulate = UiKit.GOLD
	hoard_label.outline_modulate = Color(0, 0, 0, 0.95)
	hoard_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	hoard_label.position = HOARD_SPOT + Vector3(0.0, 1.45, 0.0)
	lobby.add_child(hoard_label)
	hoard_sub = Label3D.new()
	hoard_sub.font_size = 34
	hoard_sub.pixel_size = 0.005
	hoard_sub.outline_size = 14
	hoard_sub.outline_modulate = Color(0, 0, 0, 0.95)
	hoard_sub.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	hoard_sub.position = HOARD_SPOT + Vector3(0.0, 1.2, 0.0)
	lobby.add_child(hoard_sub)
	_hoard_shown = -1


func _hoard_pile(h: int) -> void:
	for c in hoard_node.get_children():
		c.queue_free()
	var b := MeshKit.Builder.new()
	var gold := Color(1.0, 0.8, 0.28)
	var n := clampi(4 + int(sqrt(float(h)) * 0.9), 4, 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := 0.25 + minf(0.45, float(h) / 2500.0)
	b.cone(r + 0.1, 0.18 + r * 0.6, MeshKit.at(Vector3(0, 0.0, 0)), gold.darkened(0.15), 14)
	for k in n:
		var a := rng.randf() * TAU
		var d := rng.randf() * r
		var y := (0.18 + r * 0.6) * (1.0 - d / (r + 0.1)) * 0.9
		b.cylinder(0.07, 0.07, 0.025, MeshKit.at(Vector3(cos(a) * d, y, sin(a) * d), Vector3.ONE, Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))), gold, 10, true)
	if h >= 300:
		b.box(Vector3(0.12, 0.12, 0.12), MeshKit.at(Vector3(0.1, 0.25 + r * 0.5, 0.05), Vector3.ONE, Vector3(0.6, 0.6, 0)), Color(0.4, 0.95, 1.0), true)
	if h >= 900:
		b.add_mesh(Creatures.hat_mesh("crown", Color(1.0, 0.8, 0.3), Color(1.0, 0.3, 0.4)), MeshKit.at(Vector3(-0.08, 0.2 + r * 0.6, 0.0)))
	hoard_node.add_child(MeshKit.instance(b.build(), false))


func _animate_lobby(delta: float) -> void:
	if pad_rings.size() != PADS.size() or pad_labels.size() != PADS.size() or class_nodes.size() != Classes.ORDER.size() or hoard_node == null:
		# Pads added by a hot reload (the TV runs the game while it's updated): build them again now.
		lobby.queue_free()
		pad_rings.clear()
		pad_labels.clear()
		_build_lobby()
	var show_pads: bool = not active and String(net.state_get("phase", "")) in ["practice", "cleared"] and int(net.state_get("room", 0)) == 0
	lobby.visible = show_pads or (not active and int(net.state_get("room", 0)) == 0)
	var h := int(net.state_get("d_hoard", 0))
	if h != _hoard_shown and hoard_node != null:
		_hoard_shown = h
		_hoard_pile(h)
		hoard_label.text = "HOARD %d" % h
		var nx: Dictionary = Relics.next_unlock(h)
		var nh := 1 << 30
		var what := ""
		if not nx.is_empty():
			nh = int(nx["hoard"])
			what = String(nx["name"])
		for id in Classes.ORDER:
			var ch := int(Classes.info(id)["hoard"])
			if ch > h and ch < nh:
				nh = ch
				what = String(Classes.info(id)["name"])
		hoard_sub.text = "%s AT %d" % [what, nh] if what != "" else "ALL UNLOCKED!"
		hoard_sub.modulate = UiKit.TEXT_DIM if what != "" else UiKit.GOLD
		for id2 in class_nodes:
			var cn: Dictionary = class_nodes[id2]
			var need := int(Classes.info(id2)["hoard"])
			(cn["sub"] as Label3D).text = "" if h >= need else "LOCKED %d" % need
			(cn["sub"] as Label3D).modulate = UiKit.TEXT_DIM
			(cn["statue"] as Node3D).visible = h >= need
	for id3 in class_nodes:
		var cn2: Dictionary = class_nodes[id3]
		(cn2["label"] as Label3D).visible = show_pads
		(cn2["sub"] as Label3D).visible = show_pads
		var st3: Node3D = cn2["statue"]
		st3.rotation.y = lerp_angle(st3.rotation.y, 0.0, 1.0 - exp(-6.0 * delta))
	if hoard_label != null:
		hoard_label.visible = show_pads
		hoard_sub.visible = show_pads
	if not active:
		_sync_lobby_looks()
	var fills: Array = net.state_get("d_pads", [0.0, 0.0])
	var i := 0
	for mname in PADS:
		var k: float = float(fills[i]) if i < fills.size() else 0.0
		i += 1
		if not pad_rings.has(mname) or not pad_labels.has(mname):
			continue  # a pad added by a hot reload: built at the next game start
		var ring: Node3D = pad_rings[mname]
		ring.scale = ring.scale.lerp(Vector3.ONE * maxf(0.05, k), 1.0 - exp(-12.0 * delta))
		ring.visible = show_pads
		(pad_labels[mname] as Label3D).visible = show_pads
		var bests: Dictionary = net.state_get("d_best", {})
		var bl: Label3D = (pad_labels[mname] as Label3D).get_node_or_null("Best")
		var g := int(bests.get(daily_key() if mname == "daily" else mname, -1))
		if mname == "heroic" and not bool(net.state_get("d_heroic_ok", true)):
			(pad_labels[mname] as Label3D).text = "LOCKED"
			(pad_labels[mname] as Label3D).modulate = Color(0.6, 0.6, 0.65)
			if bl != null:
				bl.text = "beat the Slime King"
			continue
		(pad_labels[mname] as Label3D).text = String(mname).to_upper()
		(pad_labels[mname] as Label3D).modulate = (PAD_COLORS[mname] as Color).lightened(0.3)
		if bl != null:
			bl.text = "BEST %d-%d" % [g / FloorGen.FLOORS_PER_ZONE + 1, g % FloorGen.FLOORS_PER_ZONE + 1] if g > 0 else ""


## Host: the lobby pads fill while players stand on them; full = the run starts.
func lobby_step(delta: float) -> void:
	if not net.state_has("d_best") and main.save != null:
		var pb: Dictionary = progress()["best"]
		net.state_set("d_best", pb.duplicate())
		net.state_set("d_heroic_ok", heroic_unlocked())
	if main.save != null and int(net.state_get("d_hoard", -1)) != hoard():
		net.state_set("d_hoard", hoard())
	if main.save != null and not net.state_has("d_cls"):
		var cl := {}
		var saved: Dictionary = progress()["cls"]
		for k in saved:
			if Classes.unlocked(hoard()).has(String(saved[k])):
				cl[int(k)] = String(saved[k])
		net.state_set("d_cls", cl)
	for k2 in cls_cd.keys():
		cls_cd[k2] = float(cls_cd[k2]) - delta
	var players := _players(true)
	var total := maxi(1, players.size())
	var fills: Array = []
	for mname in PADS:
		var on := 0
		var c: Vector3 = PADS[mname]
		if mname == "heroic" and not heroic_unlocked():
			fills.append(0.0)
			continue  # beat the Slime King on BRAVE first
		for pl in players:
			var p: Vector3 = (pl as Dictionary)["p"]
			if Vector2(p.x - c.x, p.z - c.z).length() < 0.95:
				on += 1
		var fv: float = pad_fill.get(mname, 0.0)
		if on > 0:
			fv += delta * (0.3 + 0.7 * float(on) / total) / 2.2
		else:
			fv = maxf(0.0, fv - delta * 0.8)
		pad_fill[mname] = fv
		fills.append(snappedf(clampf(fv, 0.0, 1.0), 0.05))
		if fv >= 1.0:
			pad_fill[mname] = 0.0
			start_run(String(mname))
			return
	if fills != net.state_get("d_pads", []):
		net.state_set("d_pads", fills)


## Host: a hero bonked near the hat stand / the knight touched it.
func try_hat(slot: int, at: Vector3) -> bool:
	if active or Vector2(at.x - HAT_RACK.x, at.z - HAT_RACK.z).length() > 1.1:
		return false
	if float(hat_cd.get(slot, 0.0)) > 0.0:
		return true
	hat_cd[slot] = 0.5
	var owned := unlocked_hats()
	var hats: Dictionary = net.state_get("d_hats", {}).duplicate()
	var cur := String(hats.get(slot, "none"))
	var idx := owned.find(cur)
	var nxt: String = owned[(idx + 1) % owned.size()]
	hats[slot] = nxt
	net.state_set("d_hats", hats)
	var pd := progress()
	(pd["hat"] as Dictionary)[str(slot)] = nxt
	main.save.mark_dirty()
	main.sound_at("equip", HAT_RACK + Vector3(0, 1.4, 0), -2.0)
	main.confetti(HAT_RACK + Vector3(0, 1.5, 0), Color(0.7, 0.6, 1.0), 16)
	net.event("confetti", [HAT_RACK + Vector3(0, 1.5, 0), Color(0.7, 0.6, 1.0), 16])
	return true


## Host: a hero bonked near a hero statue: become that hero (if Cinder's hoard has unlocked it).
func try_class(slot: int, at: Vector3) -> bool:
	if active or _is_knight(slot):
		return false
	for id in CLASS_SPOTS:
		var c: Vector3 = CLASS_SPOTS[id]
		if Vector2(at.x - c.x, at.z - c.z).length() > 1.3:
			continue
		if float(cls_cd.get(slot, 0.0)) > 0.0:
			return true
		cls_cd[slot] = 0.5
		var top := c + Vector3(0, 1.2, 0)
		if not Classes.unlocked(hoard()).has(id):
			main.sound_at("ui_error", top, -2.0)
			net_popup(top + Vector3(0, 0.4, 0), "LOCKED", "bad")
			return true
		var cl: Dictionary = (net.state_get("d_cls", {}) as Dictionary).duplicate()
		cl[slot] = id
		net.state_set("d_cls", cl)
		(progress()["cls"] as Dictionary)[str(slot)] = id
		main.save.mark_dirty()
		main.sound_at("level_up", top, -2.0)
		main.confetti(top, Classes.info(id)["color"], 24)
		net.event("confetti", [top, Classes.info(id)["color"], 24])
		net_popup(top + Vector3(0, 0.5, 0), String(Classes.info(id)["name"]), "heal")
		if class_nodes.has(id):
			((class_nodes[id] as Dictionary)["statue"] as Node3D).rotation.y = 0.6  # a little wiggle
		return true
	return false


## A hero's class (the VR knight is always the knight).
func class_of(slot: int) -> String:
	if _is_knight(slot):
		return "knight"
	var id := String((net.state_get("d_cls", {}) as Dictionary).get(slot, "knight"))
	if OS.has_environment("DD_CLASS"):
		var l: PackedStringArray = OS.get_environment("DD_CLASS").split(",")
		id = l[slot % l.size()]
	return id if Classes.valid(id) else "knight"


## Cinder's hoard: every coin the family ever picked up in the deep dungeon (plus boss piles).
func hoard() -> int:
	if OS.has_environment("DD_HOARD"):
		return int(OS.get_environment("DD_HOARD"))
	return int(progress().get("hoard", 0))


## Host: n more gold in the hoard; anything newly unlocked gets a cheer.
func _add_hoard(n: int) -> void:
	if n <= 0 or main.save == null:
		return
	var before := hoard()
	var pd := progress()
	pd["hoard"] = int(pd.get("hoard", 0)) + n
	main.save.mark_dirty()
	var after_h := hoard()
	net.state_set("d_hoard", after_h)
	for id in Classes.ORDER:
		var need := int(Classes.info(id)["hoard"])
		if before < need and after_h >= need:
			_unlocked("NEW HERO: %s!" % String(Classes.info(id)["name"]))
	for r in Relics.LIST:
		if before < int(r["hoard"]) and after_h >= int(r["hoard"]):
			_unlocked("NEW RELIC: %s!" % String(r["name"]))


func _unlocked(text: String) -> void:
	net.event("d_banner", [text, "level"])
	main.show_headline(text, 3.0)
	main.story({"who": "CINDER", "line": "My hoard grew! " + text.capitalize(), "pic": "cinder", "color": main.CINDER_COLOR, "duration": 3.0})
	if runrec.has("unlocks"):
		(runrec["unlocks"] as Array).append(text)


# --- Persistence ---------------------------------------------------------------------------------

## The saved deep progress (inside main.save.data).
func progress() -> Dictionary:
	var d: Dictionary = main.save.data
	if not d.has("deep") or typeof(d["deep"]) != TYPE_DICTIONARY:
		d["deep"] = {}
	var pd: Dictionary = d["deep"]
	for k in ["best", "bosses", "wins"]:
		if not pd.has(k) or typeof(pd[k]) != TYPE_DICTIONARY:
			pd[k] = {"brave": 0, "heroic": 0}
	if not pd.has("hat") or typeof(pd["hat"]) != TYPE_DICTIONARY:
		pd["hat"] = {}
	if not pd.has("cls") or typeof(pd["cls"]) != TYPE_DICTIONARY:
		pd["cls"] = {}
	if not pd.has("hoard") or typeof(pd["hoard"]) not in [TYPE_INT, TYPE_FLOAT]:
		pd["hoard"] = 0
	if not pd.has("runs"):
		pd["runs"] = 0
	return pd


## HEROIC opens once the Slime King is beaten on BRAVE (kids kept stumbling onto it and losing in a minute).
func heroic_unlocked() -> bool:
	if OS.has_environment("DD_MODE"):
		return true
	return _bosses_beaten() & 1 != 0


func _bosses_beaten() -> int:
	var pd := progress()
	return int((pd["bosses"] as Dictionary).get("brave", 0)) | int((pd["bosses"] as Dictionary).get("heroic", 0))


func unlocked_hats() -> Array:
	var pd := progress()
	var out: Array = []
	var best := maxi(int((pd["best"] as Dictionary).get("brave", 0)), int((pd["best"] as Dictionary).get("heroic", 0)))
	var bosses := _bosses_beaten()
	for h in HAT_UNLOCKS:
		var need: String = (h as Array)[1]
		var ok := need == "" or (need == "run" and int(pd["runs"]) > 0) or (need == "floor3" and best >= 2)
		if need.begins_with("boss"):
			ok = bosses & (1 << int(need.substr(4))) != 0
		if ok:
			out.append((h as Array)[0])
	return out


## Starting perks from bosses beaten (any deep difficulty).
func perks() -> Dictionary:
	var b := _bosses_beaten()
	return {"potion": 1 if b & 1 else 0, "heart": 1 if b & 2 else 0, "bombs": 3 if b & 4 else 0}


func _record_depth() -> void:
	var pd := progress()
	var g := FloorGen.global_floor(zone, floor_i)
	var best: Dictionary = pd["best"]
	var key := daily_key() if daily else mode
	if g > int(best.get(key, 0)):
		best[key] = g
		main.save.mark_dirty()
		net.state_set("d_best", best.duplicate())


# --- Players ---------------------------------------------------------------------------------------

func _is_knight(slot: int) -> bool:
	return slot == 0 and main.vr_rig != null


func knight_head() -> Vector3:
	if main.vr_rig != null:
		return main.vr_rig.head_position()
	return Vector3.ZERO


func _feet_of(slot: int) -> Vector3:
	if _is_knight(slot):
		var hp: Vector3 = main.vr_rig.head_position()
		return Vector3(hp.x, 0.0, hp.z)
	if main.heroes.has(slot):
		return (main.heroes[slot] as Node3D).position
	return Vector3.INF


## Host: every player: [{"slot", "p", "knight", "down"}]; alive_only drops knocked-out ones.
func _players(alive_only: bool = false) -> Array:
	var out: Array = []
	for s in main.heroes:
		var down := bool((stats.get(int(s), {}) as Dictionary).get("down", false)) if active else false
		if alive_only and down:
			continue
		out.append({"slot": int(s), "key": int(s), "p": (main.heroes[s] as Node3D).position, "knight": false, "down": down})
	if main.vr_rig != null:
		var kd := bool((stats.get(0, {}) as Dictionary).get("down", false)) if active else false
		if not (alive_only and kd):
			out.append({"slot": 0, "key": 0, "p": _feet_of(0), "knight": true, "down": kd})
	return out


func _new_stats(slot: int) -> Dictionary:
	var d := diff()
	var pk := perks()
	var cid := class_of(slot)
	var ci: Dictionary = Classes.info(cid)
	var knight := _is_knight(slot)
	var hearts := maxi(2, int(d["hearts"]) + int(pk["heart"]) + (1 if knight else int(ci["hearts"])))
	return {"hp": hearts, "max": hearts, "pot": int(d["potions"]) + int(pk["potion"]) + (0 if knight else int(ci["pots"])),
		"bomb": int(pk["bombs"]) + (0 if knight else int(ci["bombs"])), "abil": "" if knight else String(ci["abil"]),
		"dmg": 2 if knight else 1, "charm": 0, "down": false, "cls": cid, "relics": [], "bubble": false, "rise": 0.0, "ph_used": false}


func has_relic(slot: int, id: String) -> bool:
	return ((stats.get(slot, {}) as Dictionary).get("relics", []) as Array).has(id)


## Alone on BRAVE (a Deck kid on their own): a lucky charm on every floor (that's all: Simon found it too easy).
func _solo_brave() -> bool:
	return mode == "brave" and _players().size() == 1


func _ensure_stats() -> void:
	for pl in _players():
		var s: int = (pl as Dictionary)["slot"]
		if not stats.has(s):
			stats[s] = _new_stats(s)
			stats_dirty = true
	for s in stats.keys():
		if not main.heroes.has(int(s)) and not _is_knight(int(s)):
			stats.erase(s)
			stats_dirty = true


func _st(slot: int) -> Dictionary:
	return stats.get(slot, {})


func _alive(slot: int) -> bool:
	return stats.has(slot) and not bool((stats[slot] as Dictionary)["down"])


# --- Runs and floors -------------------------------------------------------------------------------

static func daily_key() -> String:
	return "daily:" + Time.get_date_string_from_system()


## m: "brave", "heroic" or "daily" (BRAVE rules, the same dungeon for everyone all day: beat your best).
func start_run(m: String) -> void:
	daily = m == "daily"
	mode = "brave" if daily else m
	seed_v = int(OS.get_environment("DD_SEED")) if OS.has_environment("DD_SEED") else randi() % 1000000
	if daily:
		seed_v = absi(hash(Time.get_date_string_from_system())) % 1000000
	zone = 0
	floor_i = 0
	if OS.has_environment("DD_FLOOR") and not main.has_meta("deep_started"):
		var g := clampi(int(OS.get_environment("DD_FLOOR")), 0, 99)
		zone = g / FloorGen.FLOORS_PER_ZONE
		floor_i = g % FloorGen.FLOORS_PER_ZONE
	main.set_meta("deep_started", true)
	net.state_set("mode", mode)
	stats.clear()
	_gold = 0
	_keys = 0
	_ensure_stats()
	if FloorGen.global_floor(zone, floor_i) > 0:
		# Starting deeper (DD_FLOOR, tests): the gear a run would have found by then.
		var g0 := FloorGen.global_floor(zone, floor_i)
		for s in stats:
			var st0: Dictionary = stats[s]
			st0["dmg"] = int(st0["dmg"]) + g0 / 3
			st0["max"] = mini(8, int(st0["max"]) + g0 / 3)
			st0["hp"] = st0["max"]
			st0["pot"] = int(st0["pot"]) + 1 + g0 / 4
			# ... and the relics a run would have picked by then (one per altar).
			var party_l: Array = [{"knight": _is_knight(int(s)), "relics": st0["relics"]}]
			for k0 in (g0 + 2) / 2:
				var o: Array = Relics.offer(seed_v, k0 / 2, 1 + 2 * (k0 % 2), Relics.unlocked(hoard()), party_l)
				if not o.is_empty():
					(st0["relics"] as Array).append(String(o[0]))
					if String(o[0]) == "glass":
						st0["max"] = maxi(2, int(st0["max"]) - 2)
						st0["hp"] = st0["max"]
		_gold = 20 * g0
	checkpoint = {}
	var pd := progress()
	pd["runs"] = int(pd["runs"]) + 1
	main.save.mark_dirty()
	main.awards.reset()
	for pl in _players():
		var s: int = (pl as Dictionary)["slot"]
		main.awards.set_player(s, "KNIGHT" if _is_knight(s) else party.name_of(s))
	active = true
	var kinds: Array = []
	for pl in _players():
		var s0: int = (pl as Dictionary)["slot"]
		kinds.append("vr" if _is_knight(s0) else party.machine_kind(s0))
	runrec = {"mode": mode, "daily": daily, "seed": seed_v, "players": kinds, "solo": kinds.size() == 1,
		"floor_times": [], "kos": [], "gold_in": 0, "gold_out": 0, "items": [], "relics": [], "bosses": [],
		"clock": 0.0, "floor_t0": 0.0, "boss_t0": 0.0, "boss_phase": 1, "done": false,
		"start_floor": FloorGen.global_floor(zone, floor_i), "classes": [], "hoard0": hoard(), "unlocks": [], "offers": []}
	for pl2 in _players():
		(runrec["classes"] as Array).append(class_of(int((pl2 as Dictionary)["slot"])))
	fang.clear()
	pet_cd.clear()
	net.state_set("phase", "deep")
	main.monsters.clear()
	load_floor(zone, floor_i, "floor")
	print("Dungeon Delve: %s run, seed %d" % [m, seed_v])


func load_floor(z: int, fl: int, k: String) -> void:
	zone = z
	floor_i = fl
	kind = k
	f = FloorGen.generate(seed_v, z, fl, mode == "heroic", k)
	foes.clear()
	tele.clear()
	_build_floor(f)
	open_bits = FloorGen.start_open_bits(f)
	seen_bits = 1
	cleared_bits = 1
	spawned_bits = 1
	lock_room = -1
	entry = Vector3.INF
	straggle_t = -1.0
	stairs_fill = 0.0
	portal = Vector3.INF
	hazards.clear()
	pickups.clear()
	sw_linger.clear()
	collapse.clear()
	secret_hits.clear()
	trap_clock = 0.0
	phase_t = 0.0
	foes.cfg = _cfg()
	# Keys, mimics (asleep in their rooms).
	var rooms: Array = f["rooms"]
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		if r.has("key_at"):
			_spawn_pick(Loot.KEY, FloorGen.to_world(f, i, r["key_at"]), false)
	for mm in FloorGen.mimic_list(f):
		foes.spawn(FloorGen.F_MIMIC, FloorGen.to_world(f, int((mm as Array)[0]), (mm as Array)[1]), int((mm as Array)[0]))
	if k == "shop":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_v, z, fl, "shop"])
		shop = Loot.shop_stock(rng, z, mode == "heroic")
		for it in shop:
			(it as Array).append(0)
		net.state_set("d_shop", shop.duplicate(true))
		# The camp: everyone back up, and a breather.
		for s in stats:
			var st: Dictionary = stats[s]
			if bool(st["down"]):
				st["down"] = false
				st["hp"] = 1
			st["hp"] = mini(int(st["max"]), int(st["hp"]) + 1)
		stats_dirty = true
		altar_group = 0
		if Relics.altar_after(fl):
			_build_altar(z, fl)
	else:
		if fl == 0 and bool(diff()["checkpoints"]) and z < FloorGen.ZONE_COUNT:  # no checkpoints in the endless depths
			checkpoint = {"zone": z, "stats": stats.duplicate(true), "gold": _gold}
			tally["checkpoints"] = int(tally["checkpoints"]) + 1
		elif checkpoint.is_empty():
			checkpoint = {"zone": z, "stats": stats.duplicate(true), "gold": _gold, "floor": fl}
		if not runrec.is_empty() and not (tally["floors"] as Array).is_empty():
			(runrec["floor_times"] as Array).append([int((tally["floors"] as Array).back()), snappedf(float(runrec.get("clock", 0.0)) - float(runrec["floor_t0"]), 0.1)])
			runrec["floor_t0"] = float(runrec.get("clock", 0.0))
		(tally["floors"] as Array).append(FloorGen.global_floor(z, fl))
		if _solo_brave():
			for s in stats:
				(stats[s] as Dictionary)["charm"] = 1
		for s2 in stats:
			(stats[s2] as Dictionary)["ph_used"] = false  # the phoenix feather works again on every floor
		(tally["zones"] as Dictionary)[z] = true
		_record_depth()
	net.state_set("d_floor", [seed_v, z, fl, k, mode == "heroic"])
	_sync_doors()
	net.state_set("d_chests", 0)
	net.state_set("d_pots", 0)
	net.state_set("d_seen", seen_bits)
	net.state_set("d_cleared", cleared_bits)
	net.state_set("d_portal", null)
	net.state_set("d_boss", [])
	net.state_set("d_phase", "play")
	_sync_money()
	stats_dirty = true
	# Everyone to the start.
	var at := FloorGen.room_center(f, 0) + Vector3(0.0, 0.0, 2.6 if k != "shop" else 3.2)
	for s in main.heroes:
		main._warp_hero(int(s), at)
	if main.vr_rig != null:
		main.blink(func() -> void: main.vr_rig.place(at + Vector3(0.0, 0.0, 0.8), 0.0))
	net.event("d_floor", [z, fl, k])
	_floor_banner(z, fl, k)


func _cfg() -> Dictionary:
	var d := diff()
	return FloorGen.scaling(float(d["hp"]), float(d["spd"]), mode == "heroic", zone, floor_i, maxi(1, _players().size()), String(f.get("mod", "")))


func _sync_doors() -> void:
	net.state_set("d_lock", lock_room)
	net.state_set("d_open", open_bits)


func _sync_money() -> void:
	net.state_set("d_gold", _gold)
	net.state_set("d_keys", _keys)


## Host: everyone was knocked out.
func _wipe() -> void:
	tally["wipes"] = int(tally["wipes"]) + 1
	net.state_set("d_phase", "wipe")
	phase_t = 0.0
	main.sound_at("sad_trombone", _feet_of(_players()[0]["slot"]) if not _players().is_empty() else Vector3.ZERO, -4.0)
	music_mood("defeat")


func _after_wipe() -> void:
	if bool(diff()["checkpoints"]) and not checkpoint.is_empty() and zone < FloorGen.ZONE_COUNT:
		stats = (checkpoint["stats"] as Dictionary).duplicate(true)
		for s in stats:
			var st: Dictionary = stats[s]
			st["hp"] = st["max"]
			st["down"] = false
		_ensure_stats()
		_gold = int(checkpoint["gold"])
		_keys = 0
		stats_dirty = true
		net.event("d_banner", ["BACK TO THE CHECKPOINT", "info"])
		load_floor(int(checkpoint["zone"]), int(checkpoint.get("floor", 0)), "floor")
	else:
		finish(false)


## Host: one telemetry line for this run (end: "win", "wipe" or "quit"). Once per run.
func _telemetry(end: String) -> void:
	if runrec.is_empty() or bool(runrec["done"]) or not is_host():
		return
	runrec["done"] = true
	var r := runrec.duplicate(true)
	for k in ["clock", "floor_t0", "boss_t0", "done"]:
		r.erase(k)
	var kinds: Array = []
	for pl in _players():
		var s0: int = (pl as Dictionary)["slot"]
		kinds.append("vr" if _is_knight(s0) else party.machine_kind(s0))
	r["players"] = kinds
	r["solo"] = kinds.size() == 1
	r["end"] = end
	r["depth"] = FloorGen.global_floor(zone, floor_i)
	r["zone"] = zone + 1
	r["floor"] = floor_i + 1
	r["secs"] = snappedf(float(runrec.get("clock", 0.0)), 0.1)
	if lock_room >= 0 and String(((f["rooms"] as Array)[lock_room] as Dictionary)["role"]) == "boss":
		r["boss_phase_reached"] = int(runrec["boss_phase"])
	for k2 in ["kills", "wipes", "revives", "downs", "potions", "bombs", "secrets", "puzzles", "keys", "chests", "bought", "hurts", "blocks", "reflects", "traps"]:
		r[k2] = tally.get(k2, 0)
	r["dmg_by"] = (tally["by"] as Dictionary).duplicate()
	r["gold_left"] = _gold
	r["hoard"] = hoard()
	var held: Array = []
	for s2 in stats:
		held.append([String((stats[s2] as Dictionary).get("cls", "")), ((stats[s2] as Dictionary).get("relics", []) as Array).duplicate()])
	r["held"] = held
	Telemetry.run("dungeon_delve", r)


## The game is closing / back to the arcade mid-run: that counts as a quit.
func _exit_tree() -> void:
	if active:
		_telemetry("quit")


## Host: the run is over (won: beat the last boss).
func finish(won: bool) -> void:
	_telemetry("win" if won else "wipe")
	var key := daily_key() if daily else mode
	var new_best := FloorGen.global_floor(zone, floor_i) > int((progress()["best"] as Dictionary).get(key, 0))
	_record_depth()
	if daily:
		main.save.data["daily"] = Time.get_date_string_from_system()  # TODAY'S DUNGEON played (Seeded.today(); the Trophy Hall reads it)
		main.save.mark_dirty()
	if won:
		var pd := progress()
		var wins: Dictionary = pd["wins"]
		wins[mode] = int(wins.get(mode, 0)) + 1
		main.save.mark_dirty()
	net.state_set("d_phase", "won" if won else "over")
	main.story({"who": "CINDER", "line": "You did it! WOW!" if won else "Let's try again!", "pic": "cinder",
		"color": "ffd25a" if won else main.CINDER_COLOR, "duration": 3.5})
	var g := FloorGen.global_floor(zone, floor_i)
	var beat := won or bool(runrec.get("won", false))
	main.end_results("VICTORY!" if beat else "THE END", "victory" if beat else "defeat",
		"DEPTH %d" % (FloorGen.global_floor(zone, floor_i) + 1) + ("  -  ALL BOSSES BEATEN!" if beat else ""),
		[["DEEPEST", "%d-%d%s" % [zone + 1, floor_i + 1, "  NEW BEST!" if new_best else ""]], ["MONSTERS", str(int(tally["kills"]))],
		["BOSSES", str(int(tally["bosses"]))], ["HOARD", "%d  +%d" % [hoard(), maxi(0, hoard() - int(runrec.get("hoard0", hoard())))]], ["HELPED UP", str(int(tally["revives"]))],
		["TIME", HudKit.clock_text(float(runrec.get("clock", 0.0)))]])
	print("Dungeon Delve: run over, %s, depth %d" % ["won" if won else "lost", g])


## Back to the gentle dungeon (the results screen's "again").
func stop() -> void:
	active = false
	mode = ""
	f = {}
	built_key = ""
	foes.clear()
	tele.clear()
	view.clear()
	for id in pick_nodes:
		(pick_nodes[id] as Node3D).queue_free()
	pick_nodes.clear()
	pick_kinds.clear()
	_clear_shop_nodes()
	pickups.clear()
	stats.clear()
	if is_host():
		net.state_set("mode", "gentle")
		net.state_set("d_floor", [])
		net.state_set("d_stats", {})
		net.state_set("d_boss", [])
		net.state_set("d_phase", "")
	if hud != null:
		hud.visible = false
	main.dungeon.visible = true
	for s2 in main.heroes:
		(main.heroes[s2] as Hero).speed_mul = 1.0
		(main.heroes[s2] as Hero).set_bubble(false)


func _floor_banner(z: int, fl: int, k: String) -> void:
	var zd: Dictionary = FloorGen.zone_data(z)
	if k == "shop":
		main.show_headline("SHOP", 3.0)
		if hud != null:
			HudKit.banner([main.hud], "SHOP", "", {"duration": 1.6})
		music_mood("shop")
	else:
		var sub := "BOSS FLOOR" if FloorGen.is_boss_floor(fl) else ""
		var mod := FloorGen.modifier(seed_v, z, fl)
		if z >= FloorGen.ZONE_COUNT:
			sub = "DEPTH %d" % (FloorGen.global_floor(z, fl) + 1) + ("  " + mod if mod != "" else "") + ("  BOSS" if FloorGen.is_boss_floor(fl) else "")
			main.show_headline("DEPTH %d %s" % [FloorGen.global_floor(z, fl) + 1, mod], 3.0)
			if hud != null:
				HudKit.banner([main.hud], String(zd["name"]), sub, {"duration": 2.4})
			music_mood("tension")
			return
		main.show_headline("%s %d" % [String(zd["short"]), fl + 1], 3.0)
		if hud != null:
			HudKit.banner([main.hud], String(zd["name"]), "%s%d-%d" % [sub + "  " if sub != "" else "", z + 1, fl + 1], {"duration": 2.0})
		music_mood("dungeon" if String(zd["id"]) != "forge" else "tension")


func music_mood(m: String) -> void:
	main.music.play_mood(m)


# --- Building the floor (every machine) -------------------------------------------------------------

func _build_floor(fl: Dictionary) -> void:
	var key := "%d/%d/%d/%s" % [int(fl["seed"]), int(fl["zone"]), int(fl["floor"]), String(fl["kind"])]
	if key == built_key:
		return
	built_key = key
	f = fl
	view.build(fl)
	foes.set_floor(fl)
	if not is_host():
		pass
	main.dungeon.visible = false
	for id in pick_nodes:
		(pick_nodes[id] as Node3D).queue_free()
	pick_nodes.clear()
	pick_kinds.clear()
	_clear_shop_nodes()
	if String(fl["kind"]) == "shop":
		_build_shop_props()
	if hud != null:
		hud.visible = true
		hud.set_floor(fl)


func _clear_shop_nodes() -> void:
	for n in shop_nodes:
		n.queue_free()
	shop_nodes.clear()


func _build_shop_props() -> void:
	var c := FloorGen.room_center(f, 0)
	var keeper := Creatures.humanoid({"class": "bard", "seed": 77, "hat": "top_hat", "weapon": "none"})
	keeper.position = c + Vector3(0.0, 0.0, -2.6)
	add_child(keeper)
	shop_nodes.append(keeper)
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(5.0, 0.9, 0.7), 0.06, MeshKit.at(Vector3(0, 0.45, 0)), Color(0.55, 0.36, 0.22))
	b.box(Vector3(5.2, 0.08, 0.8), MeshKit.at(Vector3(0, 0.92, 0)), Color(0.7, 0.48, 0.3))
	var counter := MeshKit.instance(b.build(), false)
	counter.position = c + Vector3(0.0, 0.0, -1.7)
	add_child(counter)
	shop_nodes.append(counter)
	var fire := MeshKit.Builder.new()
	for k in 5:
		var a := TAU * k / 5.0
		fire.cylinder(0.06, 0.06, 0.6, MeshKit.at(Vector3(cos(a) * 0.25, 0.08, sin(a) * 0.25), Vector3.ONE, Vector3(0, a, PI * 0.5)), Color(0.5, 0.33, 0.2), 6)
	fire.cone(0.3, 0.6, MeshKit.at(Vector3(0, 0.4, 0)), Color(1.0, 0.6, 0.2), 8, true)
	fire.cone(0.18, 0.45, MeshKit.at(Vector3(0, 0.5, 0)), Color(1.0, 0.9, 0.4), 8, true)
	var fn := MeshKit.instance(fire.build(), false)
	fn.position = c + Vector3(-3.2, 0.0, 2.8)
	add_child(fn)
	shop_nodes.append(fn)
	if Relics.altar_after(int(f.get("floor", 0))):
		# The relic altar: three glowing stones in the corner (relics sit on them; deep._build_altar).
		var ab := MeshKit.Builder.new()
		for sp in ALTAR_SPOTS:
			var q := FloorGen.to_world(f, 0, sp) - c
			ab.cylinder(0.42, 0.5, 0.18, MeshKit.at(q + Vector3(0, 0.09, 0)), Color(0.42, 0.4, 0.5), 12)
			ab.torus(0.46, 0.03, MeshKit.at(q + Vector3(0, 0.19, 0)), Color(0.75, 0.6, 1.0), 16, 4, true)
		var altar := MeshKit.instance(ab.build(), false)
		altar.position = c
		add_child(altar)
		shop_nodes.append(altar)


## The shop's pedestals follow the stock in the store (prices, sold out).
func _refresh_shop(stock: Array) -> void:
	for n in shop_nodes.duplicate():
		if n.has_meta("pedestal"):
			n.queue_free()
			shop_nodes.erase(n)
	if f.is_empty() or String(f.get("kind", "")) != "shop":
		return
	for i in mini(stock.size(), SHOP_SPOTS.size()):
		var it: Array = stock[i]
		var n := Node3D.new()
		n.set_meta("pedestal", true)
		n.position = FloorGen.to_world(f, 0, SHOP_SPOTS[i])
		add_child(n)
		shop_nodes.append(n)
		var b := MeshKit.Builder.new()
		b.cylinder(0.3, 0.36, 0.8, MeshKit.at(Vector3(0, 0.4, 0)), Color(0.45, 0.42, 0.5), 10)
		b.cylinder(0.38, 0.38, 0.06, MeshKit.at(Vector3(0, 0.83, 0)), Color(1.0, 0.8, 0.3))
		n.add_child(MeshKit.instance(b.build(), false))
		var sold := int(it[2]) != 0
		if not sold:
			var item := MeshKit.instance(Loot.mesh(int(it[0])), false)
			item.position = Vector3(0.0, 1.25, 0.0)
			item.scale = Vector3.ONE * 1.6
			item.name = "Item"
			n.add_child(item)
		var l := Label3D.new()
		l.text = "SOLD" if sold else "%d" % int(it[1])
		l.font_size = 56
		l.pixel_size = 0.005
		l.outline_size = 18
		l.modulate = UiKit.GOLD if not sold else UiKit.TEXT_DIM
		l.outline_modulate = Color(0, 0, 0, 0.95)
		l.position = Vector3(0.0, 1.85, 0.0)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y if main.vr_rig == null else BaseMaterial3D.BILLBOARD_DISABLED
		n.add_child(l)
		var nm := Label3D.new()
		nm.text = String(Loot.NAMES[int(it[0])])
		nm.font_size = 40
		nm.pixel_size = 0.004
		nm.outline_size = 14
		nm.outline_modulate = Color(0, 0, 0, 0.95)
		nm.position = Vector3(0.0, 0.5, 0.42)
		n.add_child(nm)


# --- Host: every frame -----------------------------------------------------------------------------

func host_step(delta: float) -> void:
	_t += delta
	phase_t += delta
	for k in hat_cd.keys():
		hat_cd[k] = float(hat_cd[k]) - delta
	for k in iframes.keys():
		iframes[k] = float(iframes[k]) - delta
		if float(iframes[k]) <= 0.0:
			iframes.erase(k)
	for k in _poke_cd.keys():
		_poke_cd[k] = float(_poke_cd[k]) - delta
		if float(_poke_cd[k]) <= 0.0:
			_poke_cd.erase(k)
	if f.is_empty():
		return
	_ensure_stats()
	if not runrec.is_empty():
		runrec["clock"] = float(runrec.get("clock", 0.0)) + delta  # game time (tests run faster than real time)
	var ph := String(net.state_get("d_phase", "play"))
	if ph == "wipe":
		if phase_t > 3.5:
			_after_wipe()
		_flush()
		return
	if ph != "play":
		_flush()
		return
	var alive := _players(true)
	var targets: Array = alive
	_rooms_step(delta, alive)
	var active_rooms := {}
	for pl in alive:
		var r := FloorGen.room_at(f, (pl as Dictionary)["p"])
		if r >= 0:
			active_rooms[r] = true
	foes.cfg = _cfg()
	foes.step(delta, targets, lock_room if lock_room >= 0 else -99)
	_wake_rooms(active_rooms)
	_hazards_step(delta)
	_traps_step(delta, alive)
	_features_step(delta, alive)
	_pets_step(delta, alive)
	_switches_step(delta, alive)
	_doors_step(alive)
	_pickups_step(delta, alive)
	_revive_step(delta, alive)
	_stairs_step(delta, alive)
	_knight_step(delta)
	if not _players().is_empty() and alive.is_empty():
		_wipe()
	_flush()


func _flush() -> void:
	if stats_dirty:
		stats_dirty = false
		net.state_set("d_stats", stats.duplicate(true))


## Mimics woken in a quiet room shut its doors too; monsters in rooms nobody is in rest.
func _wake_rooms(active_rooms: Dictionary) -> void:
	if lock_room >= 0:
		return
	for r in active_rooms:
		if foes.count_in(int(r)) > 0:
			_lock(int(r), Vector3.INF)
			return


func _lock(r: int, at: Vector3) -> void:
	for s in stats:
		if has_relic(int(s), "bubble") and not bool((stats[s] as Dictionary)["bubble"]):
			(stats[s] as Dictionary)["bubble"] = true  # a fresh bubble for every fight
			stats_dirty = true
	lock_room = r
	straggle_t = 2.2
	entry = at if at != Vector3.INF else FloorGen.room_center(f, r)
	_sync_doors()
	main.sound_at("door", FloorGen.room_center(f, r), -2.0, 0.8)


func _rooms_step(delta: float, alive: Array) -> void:
	var rooms: Array = f["rooms"]
	for pl in alive:
		var p: Vector3 = (pl as Dictionary)["p"]
		var r := FloorGen.room_at(f, p)
		if r < 0:
			continue
		if seen_bits & (1 << r) == 0:
			seen_bits |= 1 << r
			net.state_set("d_seen", seen_bits)
			tally["rooms"] = int(tally["rooms"]) + 1
		if lock_room >= 0 or spawned_bits & (1 << r) != 0:
			continue
		var c := FloorGen.room_center(f, r)
		if absf(p.x - c.x) > FloorGen.HALF - 1.0 or absf(p.z - c.z) > FloorGen.HALF - 1.0:
			continue
		spawned_bits |= 1 << r
		var rd: Dictionary = rooms[r]
		if (rd["foes"] as Array).is_empty():
			if foes.count_in(r) == 0:
				_room_clear(r, false)
			continue
		_spawn_room(r, p)
		_lock(r, p)
	if lock_room >= 0:
		if foes.count_in(lock_room) == 0:
			_room_clear(lock_room, true)
		elif straggle_t > 0.0:
			straggle_t -= delta
			if straggle_t <= 0.0:
				_pull_stragglers()


func _pull_stragglers() -> void:
	var at := entry
	var c := FloorGen.room_center(f, lock_room)
	if at == Vector3.INF or not FloorGen.walkable(view.rects, view.obst, at, 0.4):
		at = c
	for s in main.heroes:
		var hp: Vector3 = (main.heroes[s] as Node3D).position
		if FloorGen.room_at(f, hp) != lock_room:
			main._warp_hero(int(s), at)
	if main.vr_rig != null and FloorGen.room_at(f, _feet_of(0)) != lock_room:
		var to := at
		main.blink(func() -> void: main.vr_rig.place(to, NAN))


## from: where the players came in. Mixed groups: shooters and healers stand at the far side, behind
## the shield bearers and slimes, so you have to get through (or round) them.
func _spawn_room(r: int, from: Vector3 = Vector3.INF) -> void:
	var rd: Dictionary = (f["rooms"] as Array)[r]
	foes.cfg = _cfg()
	var boss := false
	var placed := 0
	for fo in rd["foes"]:
		var a: Array = fo
		var k: int = a[0]
		placed += 1
		var p := FloorGen.to_world(f, r, a[1])
		if from != Vector3.INF and k in [FloorGen.F_SPITTER, FloorGen.F_HEALER, FloorGen.F_BOMBER]:
			var c := FloorGen.room_center(f, r)
			var in_dir := Vector3(from.x - c.x, 0.0, from.z - c.z).normalized()
			var off := p - c
			if off.dot(in_dir) > -1.0:
				var back := c + (off - in_dir * (off.dot(in_dir) + 2.8))
				back = FloorGen.room_clamp(f, r, back, 0.8)
				if FloorGen.walkable(view.rects, view.obst, back, 0.4):
					p = back
		foes.spawn(k, p, r, bool(a[2]))
		poof(p + Vector3(0.0, 0.5, 0.0), Color(0.8, 0.7, 1.0), 14)
		if Foes.is_boss(k):
			boss = true
			runrec["boss_t0"] = float(runrec.get("clock", 0.0))
			runrec["boss_phase"] = 1
			net.state_set("d_boss", [String(Foes.BOSS_NAMES[k]), 1.0])
			net.event("d_banner", [String(Foes.BOSS_NAMES[k]), "boss"])
			main.show_headline(String(Foes.BOSS_NAMES[k]), 3.0)
			music_mood("boss")
	# Bigger parties: extra monsters.
	if not boss:
		var n := _players().size()
		var extra := maxi(0, (n - 2) / 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_v, zone, floor_i, r, "extra"])
		var table: Dictionary = FloorGen.zone_data(zone)["foes"]
		for k2 in extra:
			var taken: Array = []
			var sp := FloorGen.to_world(f, r, FloorGen.free_spot(f, r, rng, taken, 0.7, 4.0))
			var kind2: int = FloorGen._weighted(table, rng)
			if kind2 == FloorGen.F_SWARM:
				kind2 = FloorGen.F_SLIME
			foes.spawn(kind2, sp, r, false)
		music_mood("battle")
	main.sound_at("alarm" if boss else "drumroll", FloorGen.room_center(f, r), -6.0)


func _room_clear(r: int, fought: bool) -> void:
	cleared_bits |= 1 << r
	net.state_set("d_cleared", cleared_bits)
	if lock_room == r:
		lock_room = -1
		_sync_doors()
	if not fought:
		return
	var c := FloorGen.room_center(f, r)
	main.sound_at("fanfare", c, -6.0)
	main.sound_at("door", c, -4.0)
	if bool(diff()["auto_revive"]):
		for s in stats:
			var st: Dictionary = stats[s]
			if bool(st["down"]):
				_revive(int(s))
	if randf() < 0.15:
		_spawn_pick(Loot.HEART, c + Vector3(0.0, 0.5, 0.0), true)
	for s2 in stats:
		if has_relic(int(s2), "boom") and int((stats[s2] as Dictionary)["bomb"]) < 9:
			(stats[s2] as Dictionary)["bomb"] = int((stats[s2] as Dictionary)["bomb"]) + 1
			stats_dirty = true
	if String(((f["rooms"] as Array)[r] as Dictionary)["role"]) != "boss":
		music_mood("dungeon" if String(FloorGen.zone_data(zone)["id"]) != "forge" else "tension")


# --- Hits ----------------------------------------------------------------------------------------

## Host: hit monster id. slot: who (-2 = a reflected shot / bomb). Returns the result.
func hit_foe(id: int, dmg: float, from: Vector3, slot: int, pierce: bool = false) -> String:
	if not foes.mons.has(id):
		return ""
	var m: Dictionary = foes.mons[id]
	var c := foes.center_of(id)
	var res := foes.hit(id, dmg, from, pierce)
	if slot >= 0 and res == "hit" and has_relic(slot, "fire") and foes.mons.has(id):
		foes.mons[id]["burn"] = 3.2
		foes.mons[id]["burn_by"] = slot
	match res:
		"kill":
			_foe_died(id, m, slot)
		"hit":
			net_popup(c + Vector3(0, 0.4, 0), str(int(round(dmg))), "damage")
			main.sound_at("sword_hit", c, -6.0, randf_range(1.0, 1.25))
			main.confetti(c, Color(1.0, 1.0, 1.0), 8)
			net.event("confetti", [c, Color(1.0, 1.0, 1.0), 8])
			if Foes.is_boss(int(m["kind"])):
				net.state_set("d_boss", [String(Foes.BOSS_NAMES[int(m["kind"])]), snappedf(float(m["hp"]) / float(m["max"]), 0.01)])
		"block":
			net_popup(c + Vector3(0, 0.4, 0), "TINK", "miss")
			main.sound_at("block", c, -2.0, 1.3)
	return res


func _foe_died(id: int, m: Dictionary, slot: int) -> void:
	if slot >= 0 and has_relic(slot, "fang") and stats.has(slot):
		fang[slot] = int(fang.get(slot, 0)) + 1
		var stf: Dictionary = stats[slot]
		if int(fang[slot]) % 4 == 0 and int(stf["hp"]) < int(stf["max"]) and not bool(stf["down"]):
			stf["hp"] = int(stf["hp"]) + 1
			stats_dirty = true
			heal_fx(_feet_of(slot) + Vector3(0, 0.8, 0))
			net_popup(_feet_of(slot) + Vector3(0, 1.5, 0), "+1", "heal")
	var kind: int = m["kind"]
	var p: Vector3 = m["p"]
	var c := foes.center_of(id)
	var boss := Foes.is_boss(kind)
	foes.remove(id)
	tally["kills"] = int(tally["kills"]) + 1
	main.awards.add(maxi(slot, 0), "bops")
	poof(c, (FloorGen.zone_data(zone)["glow"] as Color).lightened(0.2), 90 if boss else 32)
	shake(0.9 if boss else 0.12)  # (TV / Deck camera only: the VR view never shakes)
	main.sound_at("pop", c, 0.0, randf_range(0.85, 1.1))
	main.sound_at("sparkle", c, -6.0)
	var gold := int(Foes.GOLD[kind]) * (3 if bool(m["elite"]) else 1)
	while gold > 0:
		var k := Loot.COIN5 if gold >= 5 else Loot.COIN
		gold -= 5 if k == Loot.COIN5 else 1
		_spawn_pick(k, Vector3(p.x, 0.5, p.z), true)
	if bool(m["elite"]) and randf() < 0.4 or randf() < 0.03:
		_spawn_pick(Loot.POTION, Vector3(p.x, 0.5, p.z), true)
	elif randf() < 0.04:
		_spawn_pick(Loot.HEART, Vector3(p.x, 0.5, p.z), true)
	if boss:
		_boss_down(kind, Vector3(p.x, 0.0, p.z))


func _boss_down(kind: int, at: Vector3) -> void:
	if runrec.has("bosses"):
		(runrec["bosses"] as Array).append({"name": String(Foes.BOSS_NAMES[kind]), "secs": snappedf(float(runrec.get("clock", 0.0)) - float(runrec["boss_t0"]), 0.1)})
	tally["bosses"] = int(tally["bosses"]) + 1
	net.state_set("d_boss", [])
	_add_hoard(BOSS_HOARD * (1 + mini(zone, FloorGen.ZONE_COUNT)))
	for k in 4:
		var q := at + Vector3(randf_range(-2, 2), 1.0 + k * 0.5, randf_range(-2, 2))
		main.confetti(q, Color(1.0, 0.85, 0.2), 60)
		net.event("confetti", [q, Color(1.0, 0.85, 0.2), 60])
	main.sound_at("fanfare", at, 0.0)
	main.sound_at("cheer", at, -2.0)
	main.sound_at("applause", at, -6.0)
	net.event("d_banner", ["%s DOWN!" % String(Foes.BOSS_NAMES[kind]), "victory"])
	main.show_headline("YOU WON!", 4.0)
	music_mood("victory")
	foes.clear()  # the boss's helpers poof too
	var pd := progress()
	var bosses: Dictionary = pd["bosses"]
	bosses[mode] = int(bosses.get(mode, 0)) | (1 << zone)
	main.save.mark_dirty()
	net.state_set("d_heroic_ok", heroic_unlocked())
	for s in stats:
		if bool((stats[s] as Dictionary)["down"]):
			_revive(int(s))
	# The boss's treasure: three things, everyone picks ONE (your build: harder hits, more hearts, ...).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_v, zone, "relic"])
	var pool: Array = [Loot.SWORD, Loot.MAXHEART, Loot.CHARM, Loot.BOMBS, Loot.ABILITIES[rng.randi_range(0, 2)], Loot.POTION]
	# Only treasures somebody can still use (no SWORD when every sword is at +2...).
	var can := func(k: int) -> bool:
		for s in stats:
			var sd: Dictionary = stats[s]
			match k:
				Loot.SWORD:
					if int(sd["dmg"]) < (4 if _is_knight(int(s)) else 3):
						return true
				Loot.MAXHEART:
					if int(sd["max"]) < 8:
						return true
				Loot.CHARM:
					if int(sd["charm"]) == 0:
						return true
				_:
					return true
		return false
	pool = pool.filter(func(k: int) -> bool: return can.call(k))
	FloorGen._shuffle(pool, rng)
	relic_group += 1
	relic_taken[relic_group] = {}
	for k in mini(3, pool.size()):
		_spawn_pick(int(pool[k]), at + Vector3(-1.6 + k * 1.6, 0.35, 1.6), false)
		(pickups[next_pick - 1] as Dictionary)["relic"] = relic_group
	net.event("d_banner", ["PICK ONE!", "level"])
	if zone == FloorGen.ZONE_COUNT - 1:
		# Beat the whole dungeon! It counts as a win; the stairs keep going down (endless depths).
		runrec["won"] = true
		var pdw := progress()
		var wins: Dictionary = pdw["wins"]
		wins[daily_key() if daily else mode] = int(wins.get(daily_key() if daily else mode, 0)) + 1
		main.save.mark_dirty()
		net.event("d_banner", ["YOU BEAT THE DUNGEON!", "victory"])
		main.show_headline("YOU WON! KEEP GOING?", 5.0)
	portal = FloorGen.room_center(f, int(f["boss"])) + Vector3(0.0, 0.0, -2.5)
	net.state_set("d_portal", portal)


func shot_hits_foe(mid: int, dmg: float, from: Vector3, k: String, by: int = -2) -> void:
	var res := hit_foe(mid, dmg, from, by, k in ["orb", "bolt"])
	if k == "orb" and res in ["hit", "kill"] and foes.mons.has(mid):
		var m: Dictionary = foes.mons[mid]
		m["st"] = Foes.STUN
		m["t"] = 1.4
		net_popup(foes.center_of(mid) + Vector3(0, 0.8, 0), "BIG HIT!", "crit")
		shake(0.6)


func shot_gone(_sid: int, p: Vector3, k: String) -> void:
	if k == "bomb":
		return
	main.confetti(p, Color(1.0, 1.0, 1.0) if k != "orb" else Color(0.6, 0.8, 1.0), 10)
	net.event("confetti", [p, Color(1.0, 1.0, 1.0), 10])


func boss_phase(id: int, ph: int) -> void:
	runrec["boss_phase"] = ph
	var c := foes.center_of(id)
	main.sound_at("alarm", c, -2.0)
	shake(0.5)
	var words := ["", "", "ANGRY!" if foes.mons.has(id) and int(foes.mons[id]["kind"]) == FloorGen.B_CRYSTAL else "HE'S ANGRY!", "WATCH OUT!"]
	net.event("d_banner", [words[clampi(ph, 0, 3)], "boss"])
	main.show_headline(words[clampi(ph, 0, 3)], 2.5)
	if foes.mons.has(id) and int(foes.mons[id]["kind"]) == FloorGen.B_BONE and ph == 2:
		main.show_headline("HIT HIS BACK!", 3.0)
		net.event("d_banner", ["HIT HIS BACK!", "info"])


func boss_stunned(id: int) -> void:
	main.show_headline("HIT HIM NOW!", 2.5)
	net.event("d_banner", ["HIT HIM NOW!", "info"])
	poof(foes.center_of(id) + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.3), 30)


func heal_fx(p: Vector3) -> void:
	main.confetti(p, Color(0.4, 1.0, 0.5), 14)
	net.event("confetti", [p, Color(0.4, 1.0, 0.5), 14])


func poof(p: Vector3, col: Color, n: int) -> void:
	main.poof_fx(p, col, n)
	net.event("poof", [p, col, n])


func shake(a: float) -> void:
	main.shake = maxf(main.shake, a)
	net.event("d_shake", [a])


func sound_at(n: String, p: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	main.sound_at(n, p, db, pitch)


func net_popup(p: Vector3, text: String, style: String) -> void:
	HudKit.popup(self, p, text, {"style": style})
	net.event("d_popup", [p, text, style])


func telegraph(shape: String, pos: Vector3, dir: Vector3, size: Vector2, warn: float) -> void:
	tele.add(shape, pos, dir, size, warn, 0.0)
	net.event("d_tele", [shape, pos, dir, size, warn, 0.0])


## Host: an area that goes off after `warn` seconds: hurts players inside (dmg), and monsters too when
## hits_foes (bombs). stay > 0 keeps it glowing; tick > 0 hurts again every tick seconds (lava).
func hazard(shape: String, pos: Vector3, dir: Vector3, size: Vector2, warn: float, stay: float, dmg: int, hits_foes: bool, tick: float = 0.0) -> void:
	_add_hazard({"shape": shape, "pos": pos, "dir": dir, "size": size, "warn": warn, "stay": stay, "pdmg": dmg,
		"fdmg": 2.0 if hits_foes else 0.0, "tick": tick, "breaks": hits_foes})


func _add_hazard(h: Dictionary) -> void:
	h["t"] = 0.0
	h["done"] = false
	h["next_tick"] = float(h["warn"]) + float(h["tick"])
	hazards.append(h)
	tele.add(String(h["shape"]), h["pos"], h["dir"], h["size"], float(h["warn"]), maxf(0.2, float(h["stay"])))
	net.event("d_tele", [String(h["shape"]), h["pos"], h["dir"], h["size"], float(h["warn"]), maxf(0.2, float(h["stay"]))])


func _hazards_step(delta: float) -> void:
	var i := 0
	while i < hazards.size():
		var h: Dictionary = hazards[i]
		h["t"] = float(h["t"]) + delta
		var t: float = h["t"]
		if not bool(h["done"]) and t >= float(h["warn"]):
			h["done"] = true
			_hazard_go(h)
		elif bool(h["done"]) and float(h["tick"]) > 0.0 and t >= float(h["next_tick"]):
			h["next_tick"] = t + float(h["tick"])
			_hazard_hurt_players(h)
		if t > float(h["warn"]) + float(h["stay"]):
			hazards.remove_at(i)
			continue
		i += 1


func _hazard_hurt_players(h: Dictionary) -> void:
	if int(h["pdmg"]) <= 0:
		return
	src = "area_" + String(h["shape"])
	for pl in _players(true):
		var p: Vector3 = (pl as Dictionary)["p"]
		if Tele.inside(String(h["shape"]), h["pos"], h["dir"], h["size"], p, 0.25):
			hurt(int((pl as Dictionary)["slot"]), int(h["pdmg"]), h["pos"], String(h["shape"]) in ["sector", "line"])


func _hazard_go(h: Dictionary) -> void:
	var pos: Vector3 = h["pos"]
	_hazard_hurt_players(h)
	if float(h["fdmg"]) > 0.0:
		for mid in foes.mons.keys():
			if foes.mons.has(mid) and Tele.inside(String(h["shape"]), pos, h["dir"], h["size"], foes.mons[mid]["p"], 0.3):
				hit_foe(int(mid), float(h["fdmg"]), pos, int(h.get("by", -2)), true)
	if bool(h["breaks"]):
		main.sound_at("explosion", pos, 0.0)
		poof(pos + Vector3(0, 0.4, 0), Color(1.0, 0.6, 0.2), 40)
		shake(0.4)
		# Bombs crack secret walls and pots.
		var dl: Array = f["doors"]
		for di in dl.size():
			if int((dl[di] as Dictionary)["type"]) == FloorGen.SECRET and open_bits & (1 << di) == 0:
				if FloorGen.door_world(f, di).distance_to(pos) < 2.4:
					_open_secret(di)
		for pid in view.pots.size():
			if not view.pot_broken(pid) and (view.pots[pid]["p"] as Vector3).distance_to(pos) < 1.8:
				_break_pot(pid)
	elif String(h["shape"]) in ["circle", "ring"] and float(h["size"].x) >= 2.0:
		shake(0.3)


# --- Players getting hurt ---------------------------------------------------------------------------

## Host: something hurts player `key` (a slot). Returns "hit", "block" or "" (nothing happened).
func hurt(key: int, dmg: int, from: Vector3, blockable: bool) -> String:
	if not active or not stats.has(key) or String(net.state_get("d_phase", "play")) != "play":
		return ""
	var st: Dictionary = stats[key]
	if bool(st["down"]) or iframes.has(key) or dmg <= 0:
		return ""
	if OS.has_environment("DD_GOD"):
		return ""
	var knight := _is_knight(key)
	var at := _feet_of(key)
	if knight and blockable and _knight_guard(from):
		iframes[key] = 0.45
		tally["blocks"] = int(tally["blocks"]) + 1
		main.sound_at("block", knight_head(), 0.0, 1.0)
		net_popup(knight_head() + (from - knight_head()).normalized() * 0.6, "BLOCK!", "heal")
		main.vr_rig.pulse(VrRig.RIGHT, 0.9, 0.12)
		return "block"
	if bool(st.get("bubble", false)):
		st["bubble"] = false
		stats_dirty = true
		iframes[key] = 0.8
		net_popup(at + Vector3(0, 1.4, 0), "POP!", "heal")
		main.sound_at("pop", at, 0.0, 1.4)
		poof(at + Vector3(0, 0.8, 0), Color(0.6, 0.85, 1.0), 20)
		return "block"
	# Getting hit while helping a friend up starts their ring again.
	for ds in revive.keys():
		if Vector2(_feet_of(int(ds)).x - at.x, _feet_of(int(ds)).z - at.z).length() < REVIVE_R and float(revive[ds]) > 0.0:
			revive[ds] = 0.0
	st["hp"] = int(st["hp"]) - dmg
	(tally["by"] as Dictionary)[src] = int((tally["by"] as Dictionary).get(src, 0)) + dmg
	iframes[key] = IFRAMES
	tally["hurts"] = int(tally["hurts"]) + 1
	stats_dirty = true
	net.event("d_hurt", [key, dmg])
	_on_hurt(key, dmg)
	if has_relic(key, "thorns"):
		var spiked := false
		for mid in foes.mons.keys():
			if foes.mons.has(mid) and Vector2(foes.mons[mid]["p"].x - at.x, foes.mons[mid]["p"].z - at.z).length() < 2.3:
				hit_foe(int(mid), 3.0, at, -2, true)
				spiked = true
		if spiked:
			poof(at + Vector3(0, 0.5, 0), Color(0.45, 0.9, 0.4), 24)
	var push := Vector3(at.x - from.x, 0.0, at.z - from.z)
	if push.length() > 0.01 and not knight:
		_knock(key, push.normalized() * 5.0, 0.15)
	if int(st["hp"]) <= 0:
		if int(st["charm"]) > 0:
			st["charm"] = 0
			st["hp"] = 2
			iframes[key] = 2.0
			net_popup(at + Vector3(0, 1.6, 0), "LUCKY!", "crit")
			main.sound_at("power_up", at, 0.0)
		else:
			st["hp"] = 0
			st["down"] = true
			if not runrec.is_empty():
				(runrec["kos"] as Array).append({"slot": key, "by": src, "floor": FloorGen.global_floor(zone, floor_i)})
			revive[key] = 0.0
			if has_relic(key, "phoenix") and not bool(st.get("ph_used", false)):
				st["ph_used"] = true
				st["rise"] = 2.0  # up again by yourself in a moment
			tally["downs"] = int(tally["downs"]) + 1
			main.sound_at("faint", at, -2.0)
			if knight:
				main.show_headline("HELP!", 3.0)
	return "hit"


## Every machine: the look of a hit (the host calls it directly, others from the event).
func _on_hurt(key: int, dmg: int) -> void:
	var at := Vector3.INF
	if main.heroes.has(key):
		var h: Hero = main.heroes[key]
		h.hurt()
		at = h.position
		if party.is_local(key):
			party.rumble(key, 0.5, 0.5, 0.2)
	elif key == 0 and main.vr_rig != null:
		at = knight_head() + main.vr_rig.head_forward() * 0.8 + Vector3(0, -0.3, 0)
		main.vr_rig.pulse(VrRig.LEFT, 0.8, 0.15)
		main.vr_rig.pulse(VrRig.RIGHT, 0.8, 0.15)
		main.hurt_flash()
	if at != Vector3.INF:
		HudKit.damage(self, at + Vector3(0, 1.3, 0), dmg)
		sfx_at("debuff", at, -4.0)


func sfx_at(n: String, p: Vector3, db: float) -> void:
	main.sfx.play_at(n, p, db, 1.0)


func _knock(slot: int, v: Vector3, secs: float) -> void:
	if main.heroes.has(slot) and party.is_local(slot):
		(main.heroes[slot] as Hero).push(v, secs)
	else:
		net.event("d_knock", [slot, v, secs])


## The knight blocks when the blade is between his head and the hit.
func _knight_guard(from: Vector3) -> bool:
	if main.hands == null:
		return false
	var head := knight_head()
	var to := from - head
	to.y = clampf(to.y, -0.6, 0.3)
	var guard := head + to.normalized() * 0.45 + Vector3(0, -0.15, 0)
	var bl: Array = main.hands.blade()
	return main.hands.seg_dist(guard, bl[0], bl[1]) < 0.36


func _revive(slot: int) -> void:
	var st: Dictionary = stats[slot]
	st["down"] = false
	st["rise"] = 0.0
	st["hp"] = maxi(2, int(ceil(float(st["max"]) * 0.4)))
	iframes[slot] = 2.0
	revive.erase(slot)
	stats_dirty = true
	tally["revives"] = int(tally["revives"]) + 1
	var at := _feet_of(slot)
	poof(at + Vector3(0, 0.6, 0), Color(0.5, 1.0, 0.6), 30)
	main.sound_at("level_up", at, -2.0)
	main.awards.add(slot, "revived")
	if _is_knight(slot):
		main.show_headline("BACK UP!", 2.0)


func _revive_step(delta: float, alive: Array) -> void:
	for s in stats:
		var st: Dictionary = stats[s]
		if not bool(st["down"]):
			continue
		var at := _feet_of(int(s))
		if float(st.get("rise", 0.0)) > 0.0:
			st["rise"] = float(st["rise"]) - delta
			if float(st["rise"]) <= 0.0:
				_revive(int(s))
				net_popup(at + Vector3(0, 1.6, 0), "PHOENIX!", "crit")
				poof(at + Vector3(0, 0.8, 0), Color(1.0, 0.6, 0.2), 40)
				continue
		var helpers := 0
		for pl in alive:
			var p: Vector3 = (pl as Dictionary)["p"]
			if Vector2(p.x - at.x, p.z - at.z).length() < REVIVE_R:
				helpers += 1
				main.awards.add(int((pl as Dictionary)["slot"]), "helps", delta)
		var k: float = revive.get(int(s), 0.0)
		k = k + delta * helpers / REVIVE_TIME if helpers > 0 else maxf(0.0, k - delta * 0.25)
		revive[int(s)] = k
		if k >= 1.0:
			_revive(int(s))


# --- Traps, switches, doors --------------------------------------------------------------------------

func _traps_step(delta: float, alive: Array) -> void:
	trap_clock += delta
	src = "trap"
	var tl: Array = f["traps"]
	traps_out.resize(tl.size() * 2)
	for ti in tl.size():
		var td: Dictionary = tl[ti]
		var r: int = td["room"]
		var here: Array = []
		for pl in alive:
			if FloorGen.room_at(f, (pl as Dictionary)["p"]) == r:
				here.append(pl)
		match String(td["kind"]):
			"spikes":
				var period: float = td["period"]
				var tm := fmod(trap_clock + float(td["phase"]), period)
				var s := 0.0 if tm < period - 1.8 else (1.0 if tm < period - 0.9 else 2.0)
				traps_out[ti * 2] = s
				traps_out[ti * 2 + 1] = 0.0
				if s >= 2.0:
					for pl in here:
						var p: Vector3 = (pl as Dictionary)["p"]
						for tp in td["tiles"]:
							var w := FloorGen.to_world(f, r, tp)
							if absf(p.x - w.x) < FloorGen.TILE * 0.5 and absf(p.z - w.z) < FloorGen.TILE * 0.5:
								if hurt(int((pl as Dictionary)["slot"]), 1, w, false) != "":
									tally["traps"] = int(tally["traps"]) + 1
									# Bounced off the spikes towards the nearer side of the band (no standing in them).
									var tl0: Array = td["tiles"]
									var a0 := FloorGen.to_world(f, r, tl0[0])
									var a1 := FloorGen.to_world(f, r, tl0[tl0.size() - 1])
									var along := (a1 - a0).normalized()
									var mid := (a0 + a1) * 0.5
									var off := Vector3(p.x - mid.x, 0.0, p.z - mid.z)
									var side := off - along * off.dot(along)
									if side.length() < 0.05:
										side = Vector3(-along.z, 0.0, along.x)
									_knock(int((pl as Dictionary)["slot"]), side.normalized() * 9.0, 0.22)
								break
			"boulder":
				var period2: float = td["period"]
				var tm2 := fmod(trap_clock + float(td["phase"]), period2)
				var s2 := 0.0
				var v := 0.0
				if tm2 >= period2 - 3.2 and tm2 < period2 - 2.0:
					s2 = 1.0
					if tm2 - delta < period2 - 3.2:
						main.sound_at("rain" if false else "engine", FloorGen.room_center(f, r), -8.0, 0.5)
				elif tm2 >= period2 - 2.0:
					s2 = 2.0
					v = lerpf(-1.25, 1.25, (tm2 - (period2 - 2.0)) / 2.0)
					var bp := view.boulder_lane_point(td, v)
					for pl in here:
						var p2: Vector3 = (pl as Dictionary)["p"]
						if Vector2(p2.x - bp.x, p2.z - bp.z).length() < 0.95:
							var axis := Vector3(1, 0, 0) if int(td["axis"]) == 0 else Vector3(0, 0, 1)
							if hurt(int((pl as Dictionary)["slot"]), 1, bp - axis, false) != "":
								tally["traps"] = int(tally["traps"]) + 1
								var side := Vector3(p2.x - bp.x, 0.0, p2.z - bp.z)
								var away := side - axis * side.dot(axis)
								if away.length() < 0.05:
									away = Vector3(axis.z, 0.0, axis.x)
								_knock(int((pl as Dictionary)["slot"]), away.normalized() * 7.0, 0.2)
				traps_out[ti * 2] = s2
				traps_out[ti * 2 + 1] = v
			"collapse":
				if not collapse.has(ti):
					collapse[ti] = {"shake": {}, "fall": {}}
				var cs: Dictionary = collapse[ti]
				var shake_d: Dictionary = cs["shake"]
				var fall_d: Dictionary = cs["fall"]
				var tiles: Array = td["tiles"]
				var sbits := 0
				var fbits := 0
				for k in tiles.size():
					var w2 := FloorGen.to_world(f, r, tiles[k])
					if fall_d.has(k):
						fall_d[k] = float(fall_d[k]) - delta
						if float(fall_d[k]) <= 0.0:
							fall_d.erase(k)
					elif shake_d.has(k):
						shake_d[k] = float(shake_d[k]) - delta
						if float(shake_d[k]) <= 0.0:
							shake_d.erase(k)
							fall_d[k] = 5.0
							main.sound_at("crash", w2, -6.0, 0.7)
					for pl in here:
						var p3: Vector3 = (pl as Dictionary)["p"]
						if absf(p3.x - w2.x) < FloorGen.TILE * 0.45 and absf(p3.z - w2.z) < FloorGen.TILE * 0.45:
							if fall_d.has(k):
								_fall(int((pl as Dictionary)["slot"]), r, w2)
							elif not shake_d.has(k):
								shake_d[k] = 0.8
								main.sound_at("dice", w2, -8.0, 0.6)
					if shake_d.has(k):
						sbits |= 1 << k
					if fall_d.has(k):
						fbits |= 1 << k
				traps_out[ti * 2] = float(sbits)
				traps_out[ti * 2 + 1] = float(fbits)


## Fell down a crumbly hole: ouch, and back to the room's doorway.
func _fall(slot: int, r: int, at: Vector3) -> void:
	if iframes.has(slot):
		return
	hurt(slot, 1, at, false)
	iframes[slot] = 1.5
	tally["traps"] = int(tally["traps"]) + 1
	var back := FloorGen.room_center(f, r)
	var best := INF
	var ds: Dictionary = ((f["rooms"] as Array)[r] as Dictionary)["doors"]
	for d in ds:
		var di: int = ds[d]
		if view.pass_bits & (1 << di) == 0:
			continue
		var q := FloorGen.door_inside(f, di, r, 1.0)
		if q.distance_to(at) < best:
			best = q.distance_to(at)
			back = q
	if _is_knight(slot):
		main.blink(func() -> void: main.vr_rig.place(back, NAN))
	else:
		main._warp_hero(slot, back)


func _switches_step(delta: float, alive: Array) -> void:
	var sl: Array = f["switches"]
	sw_out.resize(sl.size())
	var n := maxi(1, _players().size())
	var linger := 7.0 if n == 1 else 1.4
	for sid in sl.size():
		var s: Dictionary = sl[sid]
		var w := FloorGen.to_world(f, int(s["room"]), s["p"])
		var held := false
		if String(s["kind"]) == "plate":
			for pl in alive:
				var p: Vector3 = (pl as Dictionary)["p"]
				if Vector2(p.x - w.x, p.z - w.z).length() < 0.7:
					held = true
			if held:
				if not sw_linger.has(sid) or float(sw_linger[sid]) < linger - 0.01:
					if not sw_linger.has(sid):
						main.sound_at("tock", w, -4.0, 1.2)
				sw_linger[sid] = linger
		var lt: float = sw_linger.get(sid, 0.0)
		if not held and lt > 0.0:
			lt -= delta
			sw_linger[sid] = lt
			if lt <= 0.0:
				sw_linger.erase(sid)
				main.sound_at("tick", w, -8.0, 0.8)
		sw_out[sid] = 1.0 if held else clampf(lt / linger, 0.0, 0.99)
	# Puzzle doors: all their switches on at once.
	var dl: Array = f["doors"]
	for di in dl.size():
		var d: Dictionary = dl[di]
		if int(d["type"]) != FloorGen.PUZZLE or open_bits & (1 << di) != 0:
			continue
		var all := true
		for sid in d["switches"]:
			if float(sw_out[int(sid)]) <= 0.0:
				all = false
		if all:
			open_bits |= 1 << di
			_sync_doors()
			tally["puzzles"] = int(tally["puzzles"]) + 1
			var m := FloorGen.door_world(f, di)
			main.sound_at("correct", m, 0.0)
			main.sound_at("door", m, -2.0)
			main.confetti(m + Vector3(0, 1.2, 0), Color(0.4, 0.8, 1.0), 40)
			net.event("confetti", [m + Vector3(0, 1.2, 0), Color(0.4, 0.8, 1.0), 40])
			net.event("d_banner", ["OPEN!", "level"])


## A lever got hit (sword, bonk, hand): it stays on for a bit.
func _pull_lever(sid: int) -> void:
	var sl: Array = f["switches"]
	var n := maxi(1, _players().size())
	var linger := 7.0 if n == 1 else 1.4
	if float(sw_linger.get(sid, 0.0)) <= 0.0:
		main.sound_at("tock", FloorGen.to_world(f, int((sl[sid] as Dictionary)["room"]), (sl[sid] as Dictionary)["p"]), -2.0, 0.9)
	sw_linger[sid] = linger + 0.6


func _doors_step(alive: Array) -> void:
	if _keys <= 0:
		return
	var dl: Array = f["doors"]
	for di in dl.size():
		var d: Dictionary = dl[di]
		var t := int(d["type"])
		if (t != FloorGen.LOCKED and t != FloorGen.BOSS) or open_bits & (1 << di) != 0:
			continue
		var m := FloorGen.door_world(f, di)
		for pl in alive:
			var p: Vector3 = (pl as Dictionary)["p"]
			if Vector2(p.x - m.x, p.z - m.z).length() < 1.9:
				_keys -= 1
				open_bits |= 1 << di
				_sync_doors()
				_sync_money()
				tally["doors"] = int(tally["doors"]) + 1
				main.sound_at("door", m, 0.0)
				main.sound_at("kaching", m, -4.0)
				main.key_fx(p + Vector3(0, 1.4, 0), m + Vector3(0, 1.0, 0))
				net.event("key", [p + Vector3(0, 1.4, 0), m + Vector3(0, 1.0, 0)])
				if t == FloorGen.BOSS:
					net.event("d_banner", ["BOSS!", "boss"])
				return


func _open_secret(di: int) -> void:
	open_bits |= 1 << di
	_sync_doors()
	tally["secrets"] = int(tally["secrets"]) + 1
	var m := FloorGen.door_world(f, di)
	main.sound_at("crash", m, 0.0, 0.8)
	main.sound_at("reveal", m, -2.0)
	poof(m + Vector3(0, 0.8, 0), Color(0.75, 0.7, 0.65), 50)
	net.event("d_banner", ["SECRET!", "level"])


## Host: something hit the wall near `at`: a cracked wall there takes a hit.
func _hit_secret(at: Vector3) -> bool:
	var dl: Array = f["doors"]
	for di in dl.size():
		if int((dl[di] as Dictionary)["type"]) != FloorGen.SECRET or open_bits & (1 << di) != 0:
			continue
		var m := FloorGen.door_world(f, di)
		if Vector2(at.x - m.x, at.z - m.z).length() < 1.5:
			if _poke_cd.has("w%d" % di):
				return true
			_poke_cd["w%d" % di] = 0.3
			secret_hits[di] = int(secret_hits.get(di, 0)) + 1
			main.sound_at("crash", m, -6.0, 1.3)
			main.confetti(at + Vector3(0, 0.6, 0), Color(0.7, 0.65, 0.6), 12)
			net.event("confetti", [at + Vector3(0, 0.6, 0), Color(0.7, 0.65, 0.6), 12])
			if int(secret_hits[di]) >= 3:
				_open_secret(di)
			return true
	return false


func _break_pot(pid: int) -> void:
	var bits := int(net.state_get("d_pots", 0))
	if bits & (1 << pid) != 0:
		return
	net.state_set("d_pots", bits | (1 << pid))
	var p: Vector3 = view.pots[pid]["p"]
	main.confetti(p + Vector3(0, 0.3, 0), Color(0.95, 0.55, 0.35), 24)
	net.event("confetti", [p + Vector3(0, 0.3, 0), Color(0.95, 0.55, 0.35), 24])
	main.sound_at("crash", p, -10.0, 1.6)
	var x := randf()
	_spawn_pick(Loot.COIN if x < 0.6 else (Loot.COIN5 if x < 0.92 else Loot.HEART), p + Vector3(0, 0.4, 0), true)


func _open_chest(cid: int, slot: int) -> void:
	var bits := int(net.state_get("d_chests", 0))
	if bits & (1 << cid) != 0:
		return
	net.state_set("d_chests", bits | (1 << cid))
	tally["chests"] = int(tally["chests"]) + 1
	var p: Vector3 = view.chests[cid]["p"]
	var room: int = view.chests[cid]["room"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_v, zone, floor_i, cid, "chest"])
	var big := String(((f["rooms"] as Array)[room] as Dictionary)["role"]) in ["secret", "treasure"]
	for k in Loot.chest_loot(rng, FloorGen.global_floor(zone, floor_i), big):
		_spawn_pick(int(k), p + Vector3(0, 0.6, 0), true)
	if bool(((f["rooms"] as Array)[room] as Dictionary).get("heart", false)) and big:
		_spawn_pick(Loot.MAXHEART, p + Vector3(0, 0.7, 0), true)
		((f["rooms"] as Array)[room] as Dictionary)["heart"] = false
	main.confetti(p + Vector3(0, 0.5, 0), Color(1.0, 0.85, 0.2), 40)
	net.event("confetti", [p + Vector3(0, 0.5, 0), Color(1.0, 0.85, 0.2), 40])
	main.sound_at("chest", p, -2.0)
	main.sound_at("coin", p, -4.0)
	main.awards.add(maxi(slot, 0), "chests")


# --- Pickups ---------------------------------------------------------------------------------------

func _spawn_pick(k: int, p: Vector3, pop: bool) -> void:
	var id := next_pick
	next_pick += 1
	var v := Vector3.ZERO
	if pop:
		var a := randf() * TAU
		v = Vector3(cos(a) * randf_range(0.8, 2.2), randf_range(2.5, 4.0), sin(a) * randf_range(0.8, 2.2))
	var r := FloorGen.room_at(f, p)
	pickups[id] = {"kind": k, "p": p, "v": v, "t": 0.0, "room": r}


func _pickups_step(delta: float, alive: Array) -> void:
	for id in pickups.keys():
		if not pickups.has(id):
			continue  # (a boss treasure group vanished together)
		var pk: Dictionary = pickups[id]
		pk["t"] = float(pk["t"]) + delta
		var p: Vector3 = pk["p"]
		var v: Vector3 = pk["v"]
		var k: int = pk["kind"]
		if v.length() > 0.01 or p.y > 0.31:
			v.y -= 12.0 * delta
			var np := p + v * delta
			var r: int = pk["room"]
			if r >= 0:
				np = FloorGen.room_clamp(f, r, np, 0.4)
				var flat := FloorGen.clamp_move(foes.room_rects[r], foes.obst, Vector3(p.x, 0, p.z), Vector3(np.x, 0, np.z), 0.2)
				np.x = flat.x
				np.z = flat.z
			if np.y <= 0.3:
				np.y = 0.3
				v = Vector3(v.x * 0.4, -v.y * 0.3 if absf(v.y) > 1.5 else 0.0, v.z * 0.4)
				if v.length() < 0.3:
					v = Vector3.ZERO
			pk["p"] = np
			pk["v"] = v
			p = np
		if float(pk["t"]) < 0.5:
			continue
		for pl in alive:
			var s: int = (pl as Dictionary)["slot"]
			var fp: Vector3 = (pl as Dictionary)["p"]
			var d := Vector2(fp.x - p.x, fp.z - p.z).length()
			var knight := bool((pl as Dictionary)["knight"])
			if knight and main.vr_rig != null:
				for hnd in 2:
					if main.vr_rig.hand_point(hnd).distance_to(p) < 0.4:
						d = 0.0
			var pull := 2.2
			if has_relic(s, "magnet"):
				pull = 9.0 if k in [Loot.COIN, Loot.COIN5, Loot.HEART] and FloorGen.room_at(f, fp) == FloorGen.room_at(f, p) else 2.2
			if (k == Loot.COIN or k == Loot.COIN5 or (k == Loot.HEART and pull > 2.5)) and d < pull and d > 0.5:
				var to := Vector3(fp.x - p.x, 0.0, fp.z - p.z).normalized()
				pk["p"] = p + to * (5.0 if pull < 2.5 else 9.0) * delta
			var nope: Dictionary = pk.get("nope", {})
			if nope.has(s):
				if d > 1.5:
					nope.erase(s)
				continue
			var rg := int(pk.get("relic", 0))
			if rg > 0 and (relic_taken.get(rg, {}) as Dictionary).has(s):
				continue  # already took one of these
			if d < 0.7 and _collect(s, k, p):
				if rg > 0:
					(relic_taken[rg] as Dictionary)[s] = true
					if runrec.has("relics"):
						(runrec["relics"] as Array).append(Relics.id_of_kind(k) if Relics.is_relic_kind(k) else String(Loot.NAMES[k]))
					tally["relics"] = int(tally.get("relics", 0)) + 1
					if (relic_taken[rg] as Dictionary).size() < _players().size() and not _all_chose(rg):
						break  # the others still get to choose
					for id2 in pickups.keys():
						if int((pickups[id2] as Dictionary).get("relic", 0)) == rg:
							pickups.erase(id2)
					break
				pickups.erase(id)
				break


## Host: player slot takes pickup k (false = can't use it, it stays).
func _collect(slot: int, k: int, p: Vector3) -> bool:
	if not stats.has(slot):
		return false
	var st: Dictionary = stats[slot]
	var knight := _is_knight(slot)
	var text := ""
	match k:
		Loot.COIN, Loot.COIN5:
			var n := 1 if k == Loot.COIN else 5
			_gold += n
			runrec["gold_in"] = int(runrec.get("gold_in", 0)) + n
			_add_hoard(n)
			_sync_money()
			main.awards.add(slot, "gold", n)
			main.sound_at("coin", p, -6.0, randf_range(1.0, 1.2))
			text = "+%d" % n
		Loot.KEY:
			_keys += 1
			_sync_money()
			tally["keys"] = int(tally["keys"]) + 1
			main.sound_at("kaching", p, -2.0)
			main.sound_at("sparkle", p, -4.0)
			net.event("d_banner", ["KEY!", "level"])
			text = "KEY"
		Loot.POTION:
			if knight:
				if int(st["hp"]) >= int(st["max"]):
					return false
				st["hp"] = mini(int(st["max"]), int(st["hp"]) + 3)
				tally["potions"] = int(tally["potions"]) + 1
			else:
				if int(st["pot"]) >= 5:
					return false
				st["pot"] = int(st["pot"]) + 1
			main.sound_at("potion", p, -4.0)
			text = "POTION"
		Loot.HEART:
			if int(st["hp"]) >= int(st["max"]):
				return false
			st["hp"] = int(st["hp"]) + 1
			main.sound_at("heal", p, -4.0)
			text = "+1"
		Loot.BOMBS:
			if knight or int(st["bomb"]) >= 9:
				return false
			st["bomb"] = mini(9, int(st["bomb"]) + 3)
			main.sound_at("equip", p, -4.0)
			text = "BOMBS"
		Loot.DASH, Loot.BASH, Loot.BOW:
			if knight:
				return false
			var old := String(st["abil"])
			var want := Loot.ability_id(k)
			if old == want:
				return false
			st["abil"] = want
			tally["abilities"] = int(tally["abilities"]) + 1
			if old != "":
				var ok: int = Loot.ABILITY_NAMES[old]
				_spawn_pick(ok, p + Vector3(0, 0.5, 0), true)
				(pickups[next_pick - 1] as Dictionary)["nope"] = {slot: true}  # not back to them until they step away
			main.sound_at("power_up", p, -2.0)
			text = String(Loot.NAMES[k])
		Loot.MAXHEART:
			if int(st["max"]) >= 8:
				return false
			st["max"] = int(st["max"]) + 1
			st["hp"] = int(st["hp"]) + 1
			main.sound_at("level_up", p, -2.0)
			text = "+1 HEART"
		Loot.SWORD:
			if int(st["dmg"]) >= (4 if knight else 3):
				return false  # swords stop getting better at +2
			st["dmg"] = int(st["dmg"]) + 1
			text = "SWORD +1"
		Loot.CHARM:
			st["charm"] = 1
			text = "LUCKY!"
		_:
			if not Relics.is_relic_kind(k):
				return false
			var rid := Relics.id_of_kind(k)
			if not Relics.usable(rid, {"knight": knight, "relics": st.get("relics", [])}):
				return false
			if not st.has("relics"):
				st["relics"] = []
			(st["relics"] as Array).append(rid)
			match rid:
				"glass":
					st["max"] = maxi(2, int(st["max"]) - 2)
					st["hp"] = mini(int(st["hp"]), int(st["max"]))
				"boom":
					st["bomb"] = maxi(int(st["bomb"]), 3)
				"bubble":
					st["bubble"] = true
			main.sound_at("level_up", p, 0.0)
			poof(p + Vector3(0, 0.5, 0), Relics.info(rid)["color"], 30)
			text = String(Relics.info(rid)["name"])
			stats_dirty = true
			tally["pickups"] = int(tally["pickups"]) + 1
			net_popup(p + Vector3(0, 0.9, 0), text, "crit")
			return true
	tally["pickups"] = int(tally["pickups"]) + 1
	stats_dirty = true
	if k not in [Loot.COIN, Loot.COIN5] and runrec.has("items"):
		(runrec["items"] as Array).append(String(Loot.NAMES[k]))
	if text != "" and k != Loot.COIN:
		net_popup(p + Vector3(0, 0.8, 0), text, "score" if k in [Loot.COIN5] else "heal")
	return true


func _pack_pickups() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in pickups:
		var pk: Dictionary = pickups[id]
		var p: Vector3 = pk["p"]
		out.append_array([float(id), float(pk["kind"]), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	return out


# --- Stairs, shop -------------------------------------------------------------------------------------

func _stairs_step(delta: float, alive: Array) -> void:
	var at := Vector3.INF
	if kind == "shop" or (view.stairs_at != Vector3.INF and cleared_bits & (1 << int(f["exit"])) != 0 and lock_room != int(f["exit"])):
		at = view.stairs_at
	if portal != Vector3.INF:
		at = portal
	if at == Vector3.INF:
		stairs_fill = 0.0
		return
	var on := 0
	for pl in alive:
		var p: Vector3 = (pl as Dictionary)["p"]
		if Vector2(p.x - at.x, p.z - at.z).length() < STAIRS_R:
			on += 1
	var total := maxi(1, alive.size())
	if on > 0:
		stairs_fill += delta * (0.3 + 0.7 * float(on) / total) / 1.8
	else:
		stairs_fill = maxf(0.0, stairs_fill - delta)
	if stairs_fill >= 1.0:
		stairs_fill = 0.0
		main.sound_at("warp", at, 0.0)
		_next_floor()


func _next_floor() -> void:
	if kind == "shop":
		load_floor(int(after[0]), int(after[1]), "floor")
		return
	if FloorGen.is_boss_floor(floor_i):
		after = [zone + 1, 0]  # (past the third zone: the endless depths)
	else:
		after = [zone, floor_i + 1]
	load_floor(zone, floor_i, "shop")


## Host: buy shop item i for slot. Returns true if it did something.
func _buy(slot: int, i: int) -> bool:
	if i < 0 or i >= shop.size():
		return false
	var it: Array = shop[i]
	var at := FloorGen.to_world(f, 0, SHOP_SPOTS[i]) + Vector3(0, 1.2, 0)
	if int(it[2]) != 0:
		return false
	if _gold < int(it[1]):
		main.sound_at("ui_error", at, -2.0)
		net_popup(at + Vector3(0, 0.5, 0), "%d" % int(it[1]), "bad")
		return true
	var k: int = it[0]
	var ok := false
	if k == Loot.KEY:
		_keys += 1
		ok = true
	else:
		ok = _collect(slot, k, at)
	if not ok:
		main.sound_at("ui_error", at, -2.0)
		return true
	_gold -= int(it[1])
	runrec["gold_out"] = int(runrec.get("gold_out", 0)) + int(it[1])
	it[2] = 1
	_sync_money()
	net.state_set("d_shop", shop.duplicate(true))
	tally["bought"] = int(tally["bought"]) + 1
	main.sound_at("kaching", at, 0.0)
	return true


# --- Host: hero actions ----------------------------------------------------------------------------

func on_request(slot: int, action: String, args: Array) -> void:
	if not active:
		if action == "atk" and args.size() >= 2:
			if not try_class(slot, args[0]):
				try_hat(slot, args[0])
		return
	if String(net.state_get("d_phase", "play")) != "play" or not _alive(slot):
		return
	var st: Dictionary = stats[slot]
	match action:
		"atk":
			if args.size() >= 2:
				var shot := String(Classes.info(String(st.get("cls", "knight")))["shot"]) if not _is_knight(slot) else ""
				if shot != "":
					_class_shot(slot, args[0], float(args[1]), shot)
					_attack(slot, args[0], float(args[1]), 0.0, ATTACK_REACH, false, true)
				else:
					_attack(slot, args[0], float(args[1]), _hit_dmg(slot, float(st["dmg"])), ATTACK_REACH, false)
		"bash":
			if args.size() >= 2 and String(st["abil"]) == "bash":
				_attack(slot, args[0], float(args[1]), _hit_dmg(slot, float(st["dmg"]) + 1.0), 1.7, true)
				iframes[slot] = maxf(float(iframes.get(slot, 0.0)), 0.3)
		"dash":
			if String(st["abil"]) == "dash":
				iframes[slot] = maxf(float(iframes.get(slot, 0.0)), 0.4)
		"bow":
			if args.size() >= 2 and String(st["abil"]) == "bow":
				_class_shot(slot, args[0], float(args[1]), "arrow")
		"bomb":
			if args.size() >= 2 and int(st["bomb"]) > 0:
				st["bomb"] = int(st["bomb"]) - 1
				stats_dirty = true
				tally["bombs"] = int(tally["bombs"]) + 1
				var pos2: Vector3 = args[0]
				var yaw2 := float(args[1])
				var land := pos2 + Vector3(sin(yaw2), 0.0, cos(yaw2)) * 2.8
				var r := FloorGen.room_at(f, pos2)
				if r >= 0:
					land = FloorGen.room_clamp(f, r, land, 0.3)
				foes.lob("bomb", pos2 + Vector3(0, 0.9, 0), land, 0.5, -2)
				var boom := has_relic(slot, "boom")
				_add_hazard({"shape": "circle", "pos": land, "dir": Vector3.ZERO, "size": Vector2(2.6 if boom else 1.8, 0.0), "warn": 1.3,
					"stay": 0.3, "pdmg": 0, "fdmg": 4.0 + float(st["dmg"]) - 1.0 + (2.0 if boom else 0.0), "tick": 0.0, "breaks": true, "by": slot})
				main.sound_at("whoosh", pos2, -4.0, 1.2)
		"potion":
			if int(st["pot"]) > 0 and int(st["hp"]) < int(st["max"]):
				st["pot"] = int(st["pot"]) - 1
				st["hp"] = mini(int(st["max"]), int(st["hp"]) + 3)
				stats_dirty = true
				tally["potions"] = int(tally["potions"]) + 1
				var at := _feet_of(slot)
				main.sound_at("potion", at, -2.0)
				main.sound_at("heal", at, -4.0)
				poof(at + Vector3(0, 0.8, 0), Color(1.0, 0.4, 0.55), 18)
				net_popup(at + Vector3(0, 1.5, 0), "+3", "heal")


## Host: a swing / bonk in front of a hero (yaw = facing). bash = shield bash (shoves, ignores shields).
## A hero's hit with relics: GLASS SWORD doubles it.
func _hit_dmg(slot: int, dmg: float) -> float:
	return dmg * (2.0 if has_relic(slot, "glass") else 1.0)


## Host: an archer's arrow / a wizard's magic spark / the bow ability (TRIPLE SHOT: three in a fan).
func _class_shot(slot: int, pos: Vector3, yaw: float, k: String) -> void:
	var st: Dictionary = stats[slot]
	var n := 3 if has_relic(slot, "triple") else 1
	var spd := float(Classes.SHOT_SPEED.get(k, 13.0))
	for i in n:
		var a := yaw + (i - (n - 1) * 0.5) * 0.24
		var fwd := Vector3(sin(a), 0.0, cos(a))
		var sid := foes.shoot(k, pos + Vector3(0, 0.6, 0) + fwd * 0.4, fwd * spd, -2)
		foes.shots[sid]["dmg"] = _hit_dmg(slot, float(st["dmg"]))
		foes.shots[sid]["by"] = slot
	main.sound_at("bow" if k == "arrow" else "magic", pos, -4.0, 1.0 if k == "arrow" else 1.4)


func _attack(slot: int, pos: Vector3, yaw: float, dmg: float, reach: float, bash: bool, props_only: bool = false) -> void:
	net.event("bonk", [slot])
	var spin := has_relic(slot, "spin") and not bash and not props_only
	if spin:
		reach += 0.3
		poof(pos + Vector3(0, 0.5, 0), Color(0.95, 0.95, 1.0), 10)
	if main.heroes.has(slot) and not party.is_local(slot):
		(main.heroes[slot] as Hero).bonk_anim()
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var hit := false
	# The shop first.
	if kind == "shop":
		for i in SHOP_SPOTS.size():
			var sp := FloorGen.to_world(f, 0, SHOP_SPOTS[i])
			if Vector2(sp.x - pos.x, sp.z - pos.z).length() < 1.3:
				if _buy(slot, i):
					return
	for id in foes.mons.keys():
		if props_only:
			break
		if not foes.mons.has(id):
			continue
		var c := foes.center_of(id)
		var to := Vector3(c.x - pos.x, 0.0, c.z - pos.z)
		var d := to.length()
		if c.y > 1.8 or d > reach + foes.radius_of(id):
			continue
		if d > 0.4 and fwd.dot(to / d) < 0.25 and not spin:
			continue
		var res := hit_foe(int(id), dmg, pos, slot, bash)
		if res != "":
			hit = true
			if bash and foes.mons.has(id) and not Foes.is_boss(int(foes.mons[id]["kind"])):
				foes.mons[id]["kb"] = fwd * 6.0
				foes.mons[id]["st"] = Foes.STUN
				foes.mons[id]["t"] = 1.0
	# Swat goo balls and orbs back.
	for sid in foes.shots.keys():
		if props_only:
			break
		if not foes.shots.has(sid):
			continue
		var sp2: Vector3 = foes.shots[sid]["p"]
		var to2 := Vector3(sp2.x - pos.x, 0.0, sp2.z - pos.z)
		if to2.length() < reach + 0.5 and sp2.y < 2.0 and (to2.length() < 0.5 or fwd.dot(to2.normalized()) > 0.2):
			if foes.reflect(int(sid), pos + fwd * 6.0):
				hit = true
				tally["reflects"] = int(tally["reflects"]) + 1
				main.sound_at("ding", sp2, -2.0, 1.4)
	var at := pos + fwd * 0.75
	# Pots, chests, levers, cracked walls.
	for pid in view.pots.size():
		if not view.pot_broken(pid) and Vector2((view.pots[pid]["p"] as Vector3).x - at.x, (view.pots[pid]["p"] as Vector3).z - at.z).length() < 0.75:
			_break_pot(pid)
			hit = true
	for cid in view.chests.size():
		if not view.chest_open(cid) and Vector2((view.chests[cid]["p"] as Vector3).x - at.x, (view.chests[cid]["p"] as Vector3).z - at.z).length() < 0.95:
			_open_chest(cid, slot)
			hit = true
	var sl: Array = f["switches"]
	for sid2 in sl.size():
		var s: Dictionary = sl[sid2]
		if String(s["kind"]) == "lever":
			var w := FloorGen.to_world(f, int(s["room"]), s["p"])
			if Vector2(w.x - at.x, w.z - at.z).length() < 1.0:
				_pull_lever(sid2)
				hit = true
	if _hit_secret(at + fwd * 0.3):
		hit = true
	if not hit and not props_only:
		main.sound_at("swish", at, -10.0, randf_range(1.1, 1.3))


# --- Host: the VR knight -----------------------------------------------------------------------------

var _tip_prev := Vector3.INF


func _knight_step(delta: float) -> void:
	if main.vr_rig == null or main.hands == null:
		return
	var rig: VrRig = main.vr_rig
	var down := not _alive(0)
	rig.locomotion = not down
	for k in sword_cd.keys():
		sword_cd[k] = float(sword_cd[k]) - delta
		if float(sword_cd[k]) <= 0.0:
			sword_cd.erase(k)
	if down:
		_tip_prev = Vector3.INF
		return
	var bl: Array = main.hands.blade()
	var base: Vector3 = bl[0]
	var tip: Vector3 = bl[1]
	var speed := 0.0
	if _tip_prev != Vector3.INF:
		speed = (tip - _tip_prev).length() / maxf(delta, 0.0001)
		if speed > 25.0:
			speed = 0.0
	_tip_prev = tip
	var swinging := speed > 1.2
	var head := rig.head_position()
	if swinging:
		for id in foes.mons.keys():
			if not foes.mons.has(id) or sword_cd.has(id):
				continue
			var c := foes.center_of(id)
			if main.hands.seg_dist(c, base, tip) < foes.radius_of(id) + 0.1:
				sword_cd[id] = 0.35
				var res := hit_foe(int(id), _hit_dmg(0, float(_st(0).get("dmg", 2))), head, 0)
				if res != "":
					main.hands.swings += 1
					rig.pulse(VrRig.RIGHT, 0.8 if res != "block" else 0.3, 0.08)
	for sid in foes.shots.keys():
		if not foes.shots.has(sid):
			continue
		var sp: Vector3 = foes.shots[sid]["p"]
		if main.hands.seg_dist(sp, base, tip) < float(foes.shots[sid]["r"]) + 0.15 and speed > 0.6:
			if foes.reflect(int(sid), head + rig.head_forward() * 6.0):
				tally["reflects"] = int(tally["reflects"]) + 1
				rig.pulse(VrRig.RIGHT, 1.0, 0.1)
				main.sound_at("ding", sp, 0.0, 1.2)
				net_popup(sp + Vector3(0, 0.3, 0), "SWAT!", "heal")
	# Touching things: either hand or the blade.
	var touch_now := {}
	var points: Array = [rig.hand_point(VrRig.LEFT), rig.hand_point(VrRig.RIGHT), (base + tip) * 0.5, tip]
	for pid in view.pots.size():
		if view.pot_broken(pid):
			continue
		var pp: Vector3 = view.pots[pid]["p"] + Vector3(0, 0.2, 0)
		for q in points:
			if (q as Vector3).distance_to(pp) < 0.35:
				_break_pot(pid)
				break
	for cid in view.chests.size():
		if view.chest_open(cid):
			continue
		var cp: Vector3 = view.chests[cid]["p"] + Vector3(0, 0.4, 0)
		for q in points:
			if (q as Vector3).distance_to(cp) < 0.5:
				_open_chest(cid, 0)
				break
	var sl: Array = f["switches"]
	for sid2 in sl.size():
		var s: Dictionary = sl[sid2]
		if String(s["kind"]) != "lever":
			continue
		var lp := FloorGen.to_world(f, int(s["room"]), s["p"]) + Vector3(0, 1.1, 0)
		for q in points:
			if (q as Vector3).distance_to(lp) < 0.45:
				touch_now["l%d" % sid2] = true
				if not _touch_prev.has("l%d" % sid2):
					_pull_lever(sid2)
					rig.pulse(VrRig.LEFT, 0.5, 0.06)
				break
	if swinging:
		for q in [tip, (base + tip) * 0.5]:
			if _hit_secret(q):
				rig.pulse(VrRig.RIGHT, 0.6, 0.08)
				break
	if kind == "shop":
		for i in SHOP_SPOTS.size():
			var ip := FloorGen.to_world(f, 0, SHOP_SPOTS[i]) + Vector3(0, 1.25, 0)
			for hnd in 2:
				if rig.hand_point(hnd).distance_to(ip) < 0.3:
					touch_now["s%d" % i] = true
					if not _touch_prev.has("s%d" % i):
						_buy(0, i)
	_touch_prev = touch_now


# --- Every machine --------------------------------------------------------------------------------

## Every machine, every frame (main._process).
func process(delta: float) -> void:
	_animate_lobby(delta)
	if not active:
		return
	if not is_host():
		_t += delta
	view.animate(delta, _focus_room())
	foes.animate(delta)
	tele.animate(delta)
	_animate_pickups(delta)
	_sync_hero_looks()
	for s in main.heroes:
		var h: Hero = main.heroes[s]
		if h.down:
			h.set_revive(float(revive_vals.get(int(s), 0.0)))
	_knight_hearts()
	_animate_pets(delta)
	for n in shop_nodes:
		var item: Node = n.get_node_or_null("Item")
		if item != null:
			(item as Node3D).rotation.y += delta * 1.5
			(item as Node3D).position.y = 1.25 + 0.06 * sin(_t * 3.0 + n.position.x)
	if hud != null:
		hud.update(delta, self)
	var ph := String(net.state_get("d_phase", ""))
	if ph != _last_phase:
		_last_phase = ph
		if ph == "wipe":
			main.show_headline("OH NO!", 3.0)
			if hud != null:
				HudKit.banner([main.hud], "OH NO!", "everyone is out", {"style": "defeat", "duration": 3.0})


func _focus_room() -> int:
	if f.is_empty():
		return -1
	if lock_room >= 0 and is_host():
		return lock_room
	var lr := int(net.state_get("d_lock", -1))
	if lr >= 0 and lr < (f["rooms"] as Array).size():
		return lr
	var cnt := {}
	for s in main.heroes:
		var r := FloorGen.room_at(f, (main.heroes[s] as Node3D).position)
		if r >= 0:
			cnt[r] = int(cnt.get(r, 0)) + 1
	if main.vr_rig != null:
		var kr := FloorGen.room_at(f, _feet_of(0))
		if kr >= 0:
			cnt[kr] = int(cnt.get(kr, 0)) + 2
	elif main.avatar != null and main.avatar.visible:
		var ar := FloorGen.room_at(f, main.avatar.head.global_position)
		if ar >= 0:
			cnt[ar] = int(cnt.get(ar, 0)) + 2
	var best := 0
	var bn := -1
	for r in cnt:
		if int(cnt[r]) > bn:
			bn = int(cnt[r])
			best = int(r)
	return best


func _animate_pickups(delta: float) -> void:
	var src: Dictionary = pickups if is_host() else _mirror_picks
	for id in src:
		var pk: Dictionary = src[id]
		var k: int = pk["kind"]
		if not pick_nodes.has(id):
			var mi := MeshKit.instance(Loot.mesh(k), false)
			add_child(mi)
			mi.position = pk["p"]
			mi.scale = Vector3.ONE * 0.2  # pop in
			var tw := mi.create_tween()
			tw.tween_property(mi, "scale", Vector3.ONE * 1.25, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(mi, "scale", Vector3.ONE, 0.12)
			pick_nodes[id] = mi
			pick_kinds[id] = k
			if Relics.is_relic_kind(k):
				var rl := Label3D.new()
				rl.text = String(Relics.info(Relics.id_of_kind(k))["name"])
				rl.font_size = 40
				rl.pixel_size = 0.004
				rl.outline_size = 14
				rl.modulate = (Relics.info(Relics.id_of_kind(k))["color"] as Color).lightened(0.3)
				rl.outline_modulate = Color(0, 0, 0, 0.95)
				rl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				rl.position = Vector3(0.0, 0.62, 0.0)
				mi.add_child(rl)
		var n: Node3D = pick_nodes[id]
		var p: Vector3 = pk["p"]
		var lift := 0.3 if Relics.is_relic_kind(k) else 0.0  # relics float over their altar stones
		n.position = n.position.lerp(p + Vector3(0, lift + 0.08 * sin(_t * 3.0 + int(id)), 0), 1.0 - exp(-20.0 * delta))
		n.rotation.y += delta * 2.0
	for id in pick_nodes.keys():
		if not src.has(id):
			(pick_nodes[id] as Node3D).queue_free()
			pick_nodes.erase(id)
			pick_kinds.erase(id)


var _mirror_picks := {}


## Heroes' hats and gear follow the store (abilities show as a bow / shield in hand).
func _sync_hero_looks() -> void:
	var st: Dictionary = net.state_get("d_stats", {})
	var hats: Dictionary = net.state_get("d_hats", {})
	for s in main.heroes:
		var h: Hero = main.heroes[s]
		var sd: Dictionary = st.get(int(s), {})
		var want := {"hat": String(hats.get(int(s), "")) if String(hats.get(int(s), "none")) != "none" else ""}
		var cid := String(sd.get("cls", ""))
		if Classes.valid(cid):
			want["class"] = "knight" if cid == "knight" else ("archer" if cid == "archer" else "mage")
			for k in Classes.info(cid)["look"]:
				want[k] = Classes.info(cid)["look"][k]
		var abil := String(sd.get("abil", ""))
		if abil == "bow":
			want["weapon"] = "bow"
		elif abil == "bash":
			want["offhand"] = "round_shield"
		elif abil == "dash" and cid != "archer":
			want["weapon"] = "dagger"
		h.set_look(want)
		h.speed_mul = float(Classes.info(cid)["speed"]) * (1.25 if (sd.get("relics", []) as Array).has("boots") else 1.0) if Classes.valid(cid) else 1.0
		h.set_bubble(bool(sd.get("bubble", false)))
		h.set_down(bool(sd.get("down", false)))


## The knight's hearts: little glowing hearts along the flat of the blade.
func _knight_hearts() -> void:
	if main.hands == null or main.hands.sword == null:
		return
	var sd: Dictionary = (net.state_get("d_stats", {}) as Dictionary).get(0, {})
	var key := "%d/%d" % [int(sd.get("hp", 0)), int(sd.get("max", 0))] if active else ""
	if key == _hearts_shown:
		return
	_hearts_shown = key
	if knight_hearts != null:
		knight_hearts.queue_free()
		knight_hearts = null
	if key == "":
		return
	var b := MeshKit.Builder.new()
	var hp := int(sd.get("hp", 0))
	var mx := int(sd.get("max", 0))
	for i in mx:
		var col := Color(1.0, 0.25, 0.35) if i < hp else Color(0.25, 0.25, 0.3)
		var z := -0.22 - i * 0.085
		for sx in [-1.0, 1.0]:
			b.sphere(0.018, MeshKit.at(Vector3(sx * 0.014, 0.022, z - 0.008)), col, 6, i < hp)
		b.cone(0.026, 0.035, MeshKit.at(Vector3(0, 0.022, z + 0.016), Vector3(1, 1, 0.6), Vector3(PI * 0.5, 0, 0)), col, 6, i < hp)
	knight_hearts = MeshKit.instance(b.build(), false)
	main.hands.sword.add_child(knight_hearts)


func camera_target() -> Array:
	var sum := Vector3.ZERO
	var n := 0
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for s in main.heroes:
		var p: Vector3 = (main.heroes[s] as Node3D).position
		sum += p
		n += 1
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.z))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.z))
	if main.avatar != null and main.avatar.visible:
		var ap: Vector3 = main.avatar.head.global_position
		sum += Vector3(ap.x, 0, ap.z)
		n += 1
	elif main.vr_rig != null:
		sum += _feet_of(0)
		n += 1
	var fr := _focus_room()
	var c := FloorGen.room_center(f, fr) if fr >= 0 else Vector3.ZERO
	var want := c if n == 0 else (sum / n).lerp(c, 0.45)
	var spread := 0.0 if n < 2 else (mx - mn).length()
	return [want, clampf(14.0 + spread * 0.3, 14.0, 18.0)]


# --- Owner input (every machine: its own heroes) -----------------------------------------------------

var _cds := {}


func owned_input(delta: float, h: Hero, slot: int) -> void:
	var sd: Dictionary = (net.state_get("d_stats", {}) as Dictionary).get(slot, {})
	var down := bool(sd.get("down", false))
	var ph := String(net.state_get("d_phase", "play"))
	var can := not down and ph == "play" and String(net.state_get("phase", "")) == "deep"
	var mv: Vector2 = party.stick(slot, "move") if can else Vector2.ZERO
	var dir := Vector3(mv.x, 0.0, mv.y)
	if dir.length() < 0.15:
		dir = Vector3.ZERO
	var cl := func(from: Vector3, to: Vector3) -> Vector3: return view.clamp(from, to, Hero.RADIUS)
	h.step(delta, dir.limit_length(1.0), cl)
	var cd: Dictionary = _cds.get(slot, {})
	_cds[slot] = cd
	for k in cd.keys():
		cd[k] = float(cd[k]) - delta
	if not can:
		return
	var yaw := h.rotation.y
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	if (party.just_pressed(slot, "accept") or party.just_pressed(slot, "rt")) and float(cd.get("a", 0.0)) <= 0.0:
		var cid := String(sd.get("cls", "knight"))
		cd["a"] = float(Classes.SHOT_CD.get(String(Classes.info(cid)["shot"]), 0.4))
		# Soft aim: turn to the nearest monster in reach (kids rarely line up exactly).
		var best := 2.0
		for id in foes.mons:
			var m: Dictionary = foes.mons[id]
			var mp: Vector3 = (m["node"] as Node3D).position
			var d := Vector2(mp.x - h.position.x, mp.z - h.position.z).length()
			if Classes.valid(String(sd.get("cls", ""))) and String(Classes.info(String(sd["cls"]))["shot"]) != "":
				d *= 0.33  # shooters aim at monsters further off (same room)
				if FloorGen.room_at(f, mp) != FloorGen.room_at(f, h.position):
					continue
			if d < best and int(m["st"]) != Foes.SLEEP:
				best = d
				yaw = atan2(mp.x - h.position.x, mp.z - h.position.z)
		h.rotation.y = yaw
		h.bonk_anim()
		main.bonked[slot] = true
		party.rumble(slot, 0.2, 0.0, 0.06)
		net.request(slot, "atk", [h.position, yaw])
	if party.just_pressed(slot, "x") and float(cd.get("x", 0.0)) <= 0.0:
		var abil := String(sd.get("abil", ""))
		match abil:
			"dash":
				cd["x"] = 0.8
				var d2 := dir if dir.length() > 0.2 else fwd
				h.push(d2.normalized() * 13.0, 0.18)
				net.request(slot, "dash", [])
				main.sfx.play_at("whoosh", h.position, -4.0, 1.4)
			"bash":
				cd["x"] = 1.4
				h.push(fwd * 9.0, 0.16)
				h.bonk_anim()
				net.request(slot, "bash", [h.position + fwd * 0.6, yaw])
				main.sfx.play_at("kick", h.position, -2.0, 0.8)
			"bow":
				cd["x"] = 0.45
				h.anim.play("attack", 0.3)
				net.request(slot, "bow", [h.position, yaw])
	if party.just_pressed(slot, "back") and float(cd.get("b", 0.0)) <= 0.0 and int(sd.get("bomb", 0)) > 0:
		cd["b"] = 0.6
		h.anim.play("attack", 0.3)
		net.request(slot, "bomb", [h.position, yaw])
	if party.just_pressed(slot, "y") and float(cd.get("y", 0.0)) <= 0.0 and int(sd.get("pot", 0)) > 0:
		cd["y"] = 0.8
		net.request(slot, "potion", [])


# --- Network ----------------------------------------------------------------------------------------

func deep_pack() -> Array:
	if not active:
		return []
	var rv := PackedFloat32Array()
	for s in revive:
		rv.append_array([float(s), snappedf(float(revive[s]), 0.02)])
	return [foes.pack(), foes.pack_shots(), traps_out, sw_out, _pack_pickups(), rv, snappedf(stairs_fill, 0.02)]


func deep_unpack(a: Array) -> void:
	if a.size() < 7 or f.is_empty():
		return
	foes.unpack(a[0])
	foes.unpack_shots(a[1])
	view.apply_traps(a[2])
	view.apply_switches(a[3])
	var pk: PackedFloat32Array = a[4]
	var seen := {}
	var i := 0
	while i + 4 < pk.size():
		var id := int(pk[i])
		seen[id] = true
		_mirror_picks[id] = {"kind": int(pk[i + 1]), "p": Vector3(pk[i + 2], pk[i + 3], pk[i + 4])}
		i += 5
	for id in _mirror_picks.keys():
		if not seen.has(id):
			_mirror_picks.erase(id)
	revive_vals.clear()
	var rv: PackedFloat32Array = a[5]
	var j := 0
	while j + 1 < rv.size():
		revive_vals[int(rv[j])] = rv[j + 1]
		j += 2
	stairs_fill = float(a[6])


func host_visuals() -> void:
	if not active:
		return
	view.apply_traps(traps_out)
	view.apply_switches(sw_out)
	revive_vals = revive.duplicate()


func on_state(key: String, value: Variant) -> void:
	match key:
		"mode":
			if String(value) == "gentle" and active and not is_host():
				stop()
		"d_floor":
			var a: Array = value if value is Array else []
			if a.size() >= 5:
				if not is_host():
					active = true
					seed_v = int(a[0])
					zone = int(a[1])
					floor_i = int(a[2])
					kind = String(a[3])
					_build_floor(FloorGen.generate(int(a[0]), int(a[1]), int(a[2]), bool(a[4]), String(a[3])))
					_apply_all()
			elif not is_host() and active:
				stop()
		"d_open", "d_lock":
			_apply_doors()
		"d_chests":
			view.set_chests(int(value))
		"d_pots":
			view.set_pots(int(value))
		"d_shop":
			_refresh_shop(value if value is Array else [])
		"d_portal":
			if value is Vector3:
				view.stairs_at = value
				if view.stairs_ring == null:
					view.stairs_ring = view._ring(1.2, Color(0.5, 1.0, 0.7))
				view.stairs_ring.position = (value as Vector3) + Vector3(0, 0.04, 0)
	if hud != null and active:
		hud.on_state(key, value, self)


func _apply_doors() -> void:
	if f.is_empty():
		return
	var ob := int(net.state_get("d_open", 0))
	var lr := int(net.state_get("d_lock", -1))
	view.set_pass(ob & ~FloorGen.room_door_bits(f, lr), ob)


func _apply_all() -> void:
	_apply_doors()
	view.set_chests(int(net.state_get("d_chests", 0)))
	view.set_pots(int(net.state_get("d_pots", 0)))
	_refresh_shop(net.state_get("d_shop", []))
	var pv: Variant = net.state_get("d_portal", null)
	if pv is Vector3:
		on_state("d_portal", pv)


func apply_event(k: String, args: Array) -> void:
	match k:
		"d_tele":
			tele.add(String(args[0]), args[1], args[2], args[3], float(args[4]), float(args[5]))
		"d_popup":
			HudKit.popup(self, args[0], String(args[1]), {"style": String(args[2])})
		"d_hurt":
			_on_hurt(int(args[0]), int(args[1]))
		"d_knock":
			var s := int(args[0])
			if main.heroes.has(s) and party.is_local(s):
				(main.heroes[s] as Hero).push(args[1], float(args[2]))
		"d_shake":
			main.shake = maxf(main.shake, float(args[0]))
		"d_banner":
			if hud != null:
				HudKit.banner([main.hud], String(args[0]), "", {"style": String(args[1]), "duration": 1.6})
			main.show_headline(String(args[0]), 2.5)
		"d_floor":
			_floor_banner(int(args[0]), int(args[1]), String(args[2]))


# --- Relics, biome hazards, pets ----------------------------------------------------------------------

## Host: the relic altar at this camp: 2-3 relics on stones (Relics.offer), everyone takes ONE.
func _build_altar(z: int, fl: int) -> void:
	var party_l: Array = []
	for s in stats:
		party_l.append({"knight": _is_knight(int(s)), "relics": (stats[s] as Dictionary).get("relics", [])})
	var o := Relics.offer(seed_v, z, fl, Relics.unlocked(hoard()), party_l)
	if runrec.has("offers"):
		(runrec["offers"] as Array).append(o)
	if o.is_empty():
		return
	relic_group += 1
	relic_taken[relic_group] = {}
	altar_group = relic_group
	for i in mini(o.size(), ALTAR_SPOTS.size()):
		_spawn_pick(Relics.kind_of(String(o[i])), FloorGen.to_world(f, 0, ALTAR_SPOTS[i]) + Vector3(0.0, 0.3, 0.0), false)
		(pickups[next_pick - 1] as Dictionary)["relic"] = relic_group
	net.event("d_banner", ["PICK A RELIC!", "level"])


## Everyone who could still take something from treasure group rg has taken one.
func _all_chose(rg: int) -> bool:
	var taken: Dictionary = relic_taken.get(rg, {})
	for pl in _players():
		var s: int = (pl as Dictionary)["slot"]
		if taken.has(s) or not stats.has(s):
			continue
		for id in pickups:
			var pk: Dictionary = pickups[id]
			if int(pk.get("relic", 0)) != rg:
				continue
			var k := int(pk["kind"])
			if not Relics.is_relic_kind(k) or Relics.usable(Relics.id_of_kind(k), {"knight": _is_knight(s), "relics": (stats[s] as Dictionary).get("relics", [])}):
				return false
	return true


## Host: the biome's own hazards (crystal shard lanes, lava vents) go off in rooms with players in them.
## Each glows first (FloorGen.FEATURE warn) on every screen and in VR.
func _features_step(delta: float, alive: Array) -> void:
	var rooms: Array = f["rooms"]
	var here := {}
	for pl in alive:
		var r := FloorGen.room_at(f, (pl as Dictionary)["p"])
		if r >= 0:
			here[r] = true
	for r2 in here:
		for fe in ((rooms[int(r2)] as Dictionary).get("features", []) as Array):
			var fd: Dictionary = fe
			var fk := String(fd["kind"])
			var fc: Dictionary = FloorGen.FEATURE[fk]
			var period := float(fc["period"])
			var warn := float(fc["warn"])
			var t1 := fmod(trap_clock + float(fd["phase"]), period)
			var fire_at := period - warn
			if t1 - delta < fire_at and t1 >= fire_at:
				var w := FloorGen.to_world(f, int(r2), fd["p"])
				var dmg := 1 + int(foes.cfg.get("dmg", 0))
				if fk == "vents":
					hazard("circle", w, Vector3.ZERO, Vector2(float(fc["radius"]), 0.0), warn, 0.7, dmg, false)
					main.sound_at("fire", w, -8.0, 0.7)
				else:
					var dv := Vector2(FloorGen.DIRS[int(fd["dir"])])
					hazard("line", w, Vector3(dv.x, 0.0, dv.y), Vector2(float(fc["len"]), float(fc["width"])), warn, 0.45, dmg, false)
					main.sound_at("sparkle", w, -6.0, 0.6)


## Host: DRAGON EGG: the baby dragon spits a fireball at the nearest awake monster in your room.
func _pets_step(delta: float, alive: Array) -> void:
	for pl in alive:
		var s: int = (pl as Dictionary)["slot"]
		if not has_relic(s, "egg"):
			continue
		pet_cd[s] = float(pet_cd.get(s, 1.0)) - delta
		if float(pet_cd[s]) > 0.0:
			continue
		var p: Vector3 = (pl as Dictionary)["p"]
		var r := FloorGen.room_at(f, p)
		var best := -1
		var bd := 8.0
		for id in foes.mons:
			var m: Dictionary = foes.mons[id]
			if int(m["room"]) != r or int(m["st"]) == Foes.SLEEP:
				continue
			var d := Vector2(Vector3(m["p"]).x - p.x, Vector3(m["p"]).z - p.z).length()
			if d < bd:
				bd = d
				best = int(id)
		if best < 0:
			pet_cd[s] = 0.3
			continue
		pet_cd[s] = 1.6
		var from := p + Vector3(0.0, 1.4, 0.0)
		var sid := foes.shoot("fire", from, (foes.center_of(best) - from).normalized() * 9.0, -2)
		foes.shots[sid]["dmg"] = 1.0 + float(FloorGen.global_floor(zone, floor_i)) / 8.0
		foes.shots[sid]["by"] = s
		main.sound_at("fire", from, -10.0, 1.6)


## Host: one second of FIRE SWORD burning.
func burn_tick(id: int) -> void:
	if not foes.mons.has(id):
		return
	var c := foes.center_of(id)
	poof(c, Color(1.0, 0.55, 0.2), 6)
	hit_foe(id, 1.0, c, -2, true)


## Every machine: the baby dragons fly round their heroes (and by the VR knight's shoulder).
func _animate_pets(delta: float) -> void:
	var st: Dictionary = net.state_get("d_stats", {})
	var want := {}
	for s in st:
		if ((st[s] as Dictionary).get("relics", []) as Array).has("egg"):
			want[int(s)] = true
	for s2 in pets.keys():
		if not want.has(s2):
			(pets[s2] as Node3D).queue_free()
			pets.erase(s2)
	for s3 in want:
		var at := Vector3.INF
		if main.heroes.has(s3):
			at = (main.heroes[s3] as Node3D).position + Vector3(0.0, 1.3, 0.0)
		elif s3 == 0 and main.vr_rig != null:
			at = knight_head() + main.vr_rig.head_forward().cross(Vector3.UP) * -0.6 + Vector3(0.0, -0.25, 0.0)
		if at == Vector3.INF:
			continue
		if not pets.has(s3):
			var d := Creatures.monster("dragon", {"color": Color(1.0, 0.6, 0.3), "scale": 0.28, "seed": 3})
			add_child(d)
			d.position = at
			pets[s3] = d
		var n: Node3D = pets[s3]
		var a := _t * 1.6 + float(s3)
		var goal := at + (Vector3(cos(a) * 0.55, 0.12 * sin(_t * 4.0), sin(a) * 0.55) if main.heroes.has(s3) else Vector3.ZERO)
		var mv := goal - n.position
		n.position = n.position.lerp(goal, 1.0 - exp(-6.0 * delta)) if mv.length() < 4.0 else goal
		if mv.length() > 0.01:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(mv.x, mv.z), 1.0 - exp(-8.0 * delta))


## Not in a run: heroes who picked a hero statue look like that hero (and wear their hat).
func _sync_lobby_looks() -> void:
	var cl: Dictionary = net.state_get("d_cls", {})
	if cl.is_empty():
		return
	var hats: Dictionary = net.state_get("d_hats", {})
	for s in main.heroes:
		if not cl.has(int(s)):
			continue
		var cid := String(cl[int(s)])
		if not Classes.valid(cid):
			continue
		var h: Hero = main.heroes[s]
		var want := {"hat": String(hats.get(int(s), "")) if String(hats.get(int(s), "none")) != "none" else "",
			"class": "knight" if cid == "knight" else ("archer" if cid == "archer" else "mage")}
		for k in Classes.info(cid)["look"]:
			want[k] = Classes.info(cid)["look"][k]
		h.set_look(want)
		h.speed_mul = 1.0
		h.set_bubble(false)
