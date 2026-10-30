extends Node3D
## DUNGEON DELVE: BRAVE and HEROIC, the deep dungeon (the GENTLE run is main.gd + dungeon.gd).
## Picked in the practice room by standing on the orange BRAVE or red HEROIC pad (it fills up; faster
## the more of you stand on it). Then: 3 zones (Slime Caves, Bone Crypt, Lava Forge) x 4 seeded floors
## (floorgen.gd), the 4th ending in the zone's boss; a shop camp between floors.
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

const DIFF := {
	"brave": {"hp": 1.1, "spd": 1.05, "dmg": 0, "checkpoints": true, "potions": 1, "auto_revive": true, "hearts": 4},
	"heroic": {"hp": 1.55, "spd": 1.2, "dmg": 0, "checkpoints": false, "potions": 0, "auto_revive": false, "hearts": 3},
}
const REVIVE_TIME := 3.5  ## seconds a friend must stand by you (a hit on the helper starts it again)
const REVIVE_R := 1.5
const IFRAMES := 1.2
const STAIRS_R := 1.5
const ATTACK_REACH := 1.05
const PADS := {"brave": Vector3(-2.2, 0.0, -2.5), "heroic": Vector3(2.2, 0.0, -2.5), "daily": Vector3(-3.5, 0.0, 2.7)}
const PAD_COLORS := {"brave": Color(1.0, 0.6, 0.2), "heroic": Color(1.0, 0.3, 0.35), "daily": Color(0.35, 0.8, 1.0)}
const HAT_RACK := Vector3(3.7, 0.0, 2.6)
const HAT_UNLOCKS: Array = [["none", ""], ["party", "run"], ["viking", "floor3"], ["wizard", "boss0"], ["crown", "boss1"], ["halo", "boss2"]]
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

# Every machine.
var pick_nodes := {}
var pick_kinds := {}
var revive_vals := {}
var shop_nodes: Array[Node3D] = []
var knight_hearts: Node3D
var _hearts_shown := ""
var _t := 0.0
var _last_phase := ""


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


func _animate_lobby(delta: float) -> void:
	if pad_rings.size() != PADS.size() or pad_labels.size() != PADS.size():
		# Pads added by a hot reload (the TV runs the game while it's updated): build them again now.
		lobby.queue_free()
		pad_rings.clear()
		pad_labels.clear()
		_build_lobby()
	var show_pads: bool = not active and String(net.state_get("phase", "")) in ["practice", "cleared"] and int(net.state_get("room", 0)) == 0
	lobby.visible = show_pads or (not active and int(net.state_get("room", 0)) == 0)
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
	var hearts := int(d["hearts"]) + int(pk["heart"]) + (1 if _is_knight(slot) else 0)
	return {"hp": hearts, "max": hearts, "pot": int(d["potions"]) + int(pk["potion"]), "bomb": int(pk["bombs"]),
		"abil": "", "dmg": 2 if _is_knight(slot) else 1, "charm": 0, "down": false}


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
		"start_floor": FloorGen.global_floor(zone, floor_i)}
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
	var n := maxi(1, _players().size())
	var g := FloorGen.global_floor(zone, floor_i)
	# Difficulty climbs every floor: health, speed, and from the Lava Forge (HEROIC: the Crypt) harder hits.
	# Endless depths (after the third boss): every lap round the zones is tougher, plus the floor's twist.
	var tier := maxi(0, zone - FloorGen.ZONE_COUNT + 1)
	var mod := String(f.get("mod", ""))
	if tier > 0:
		g = mini(g, 13)  # the per-floor climb levels off; tiers take over
		return {"hp": float(d["hp"]) * (1.0 + 0.11 * g) * (1.0 + 0.25 * tier) * (1.3 if mod == "STONE" else 1.0) * (1.0 + 0.25 * (n - 1)),
			"boss_hp": float(d["hp"]) * (1.0 + 0.45 * (n - 1)) * (1.0 + 0.15 * zone),
			"dmg": (1 if mode == "heroic" else 0) + tier / 2,
			"spd": float(d["spd"]) * (1.0 + 0.04 * g) * (1.0 + 0.04 * tier) * (1.2 if mod == "SWIFT" else 1.0)}
	return {"hp": float(d["hp"]) * (1.0 + 0.11 * g) * (1.0 + 0.25 * (n - 1)),
		"boss_hp": float(d["hp"]) * (1.0 + 0.45 * (n - 1)) * (1.0 + 0.15 * zone),
		"dmg": (1 if mode == "heroic" and zone >= 1 else 0),
		"spd": float(d["spd"]) * (1.0 + 0.04 * g)}


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
	var g := FloorGen.global_floor(zone, floor_i)
	var beat := won or bool(runrec.get("won", false))
	main.end_results("VICTORY!" if beat else "THE END", "victory" if beat else "defeat",
		"DEPTH %d" % (FloorGen.global_floor(zone, floor_i) + 1) + ("  -  ALL BOSSES BEATEN!" if beat else ""),
		[["DEEPEST", "%d-%d%s" % [zone + 1, floor_i + 1, "  NEW BEST!" if new_best else ""]], ["MONSTERS", str(int(tally["kills"]))],
		["BOSSES", str(int(tally["bosses"]))], ["SECRETS", str(int(tally["secrets"]))], ["HELPED UP", str(int(tally["revives"]))],
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
		music_mood("dungeon" if z != 2 else "tension")


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
	if String(((f["rooms"] as Array)[r] as Dictionary)["role"]) != "boss":
		music_mood("dungeon" if zone != 2 else "tension")


# --- Hits ----------------------------------------------------------------------------------------

## Host: hit monster id. slot: who (-2 = a reflected shot / bomb). Returns the result.
func hit_foe(id: int, dmg: float, from: Vector3, slot: int, pierce: bool = false) -> String:
	if not foes.mons.has(id):
		return ""
	var m: Dictionary = foes.mons[id]
	var c := foes.center_of(id)
	var res := foes.hit(id, dmg, from, pierce)
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
	var kind: int = m["kind"]
	var p: Vector3 = m["p"]
	var c := foes.center_of(id)
	var boss := Foes.is_boss(kind)
	foes.remove(id)
	tally["kills"] = int(tally["kills"]) + 1
	main.awards.add(maxi(slot, 0), "bops")
	var cols: Array[Color] = [Color(0.6, 1.0, 0.6), Color(0.8, 0.7, 1.0), Color(1.0, 0.7, 0.4)]
	poof(c, cols[zone % cols.size()], 90 if boss else 32)
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


func shot_hits_foe(mid: int, dmg: float, from: Vector3, k: String) -> void:
	var res := hit_foe(mid, dmg, from, -2, k == "orb")
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
	var words := ["", "", "HE'S ANGRY!", "WATCH OUT!"]
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
			if (k == Loot.COIN or k == Loot.COIN5) and d < 2.2 and d > 0.5:
				var to := Vector3(fp.x - p.x, 0.0, fp.z - p.z).normalized()
				pk["p"] = p + to * 5.0 * delta
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
						(runrec["relics"] as Array).append(String(Loot.NAMES[k]))
					tally["relics"] = int(tally.get("relics", 0)) + 1
					if (relic_taken[rg] as Dictionary).size() < _players().size():
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
			try_hat(slot, args[0])
		return
	if String(net.state_get("d_phase", "play")) != "play" or not _alive(slot):
		return
	var st: Dictionary = stats[slot]
	match action:
		"atk":
			if args.size() >= 2:
				_attack(slot, args[0], float(args[1]), float(st["dmg"]), ATTACK_REACH, false)
		"bash":
			if args.size() >= 2 and String(st["abil"]) == "bash":
				_attack(slot, args[0], float(args[1]), float(st["dmg"]) + 1.0, 1.7, true)
				iframes[slot] = maxf(float(iframes.get(slot, 0.0)), 0.3)
		"dash":
			if String(st["abil"]) == "dash":
				iframes[slot] = maxf(float(iframes.get(slot, 0.0)), 0.4)
		"bow":
			if args.size() >= 2 and String(st["abil"]) == "bow":
				var pos: Vector3 = args[0]
				var yaw := float(args[1])
				var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
				var sid := foes.shoot("arrow", pos + Vector3(0, 0.6, 0) + fwd * 0.4, fwd * 13.0, -2)
				foes.shots[sid]["dmg"] = float(st["dmg"])
				main.sound_at("bow", pos, -4.0)
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
				_add_hazard({"shape": "circle", "pos": land, "dir": Vector3.ZERO, "size": Vector2(1.8, 0.0), "warn": 1.3,
					"stay": 0.3, "pdmg": 0, "fdmg": 4.0 + float(st["dmg"]) - 1.0, "tick": 0.0, "breaks": true, "by": slot})
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
func _attack(slot: int, pos: Vector3, yaw: float, dmg: float, reach: float, bash: bool) -> void:
	net.event("bonk", [slot])
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
		if not foes.mons.has(id):
			continue
		var c := foes.center_of(id)
		var to := Vector3(c.x - pos.x, 0.0, c.z - pos.z)
		var d := to.length()
		if c.y > 1.8 or d > reach + foes.radius_of(id):
			continue
		if d > 0.4 and fwd.dot(to / d) < 0.25:
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
	if not hit:
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
				var res := hit_foe(int(id), float(_st(0).get("dmg", 2)), head, 0)
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
		var n: Node3D = pick_nodes[id]
		var p: Vector3 = pk["p"]
		n.position = n.position.lerp(p + Vector3(0, 0.08 * sin(_t * 3.0 + int(id)), 0), 1.0 - exp(-20.0 * delta))
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
		var abil := String(sd.get("abil", ""))
		if abil == "bow":
			want["weapon"] = "bow"
		elif abil == "bash":
			want["offhand"] = "round_shield"
		elif abil == "dash":
			want["weapon"] = "dagger"
		h.set_look(want)
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
		cd["a"] = 0.4
		# Soft aim: turn to the nearest monster in reach (kids rarely line up exactly).
		var best := 2.0
		for id in foes.mons:
			var m: Dictionary = foes.mons[id]
			var mp: Vector3 = (m["node"] as Node3D).position
			var d := Vector2(mp.x - h.position.x, mp.z - h.position.z).length()
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
