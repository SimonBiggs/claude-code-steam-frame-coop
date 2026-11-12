extends Node3D
## DUO ARENA second pass in the game (deep.gd has the data and the fair-play checks; main.gd decides and calls in):
## Nova's gifts working (zap, bubble, hearts, magnet, fire, sleepy, zoom), the zone's TOLD surprises (a warn ring
## first, then the drop / the roll), Nova's lost friends (a bubble over the far wall, saved by beating the zone's
## boss), the seasons (props on the stands + drift) and NOVA'S CITY growing (new towers, friends' houses).
## Every machine draws; the host decides (events: "season", "gifts", "surp", "zap", "friend"; friends in "keep").

const Deep := preload("res://games/duo_arena/deep.gd")
const Gen := preload("res://games/duo_arena/arenagen.gd")
const Seeded := preload("res://core/seeded.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const DecorScript := preload("res://games/duo_arena/decor.gd")
const Picks := preload("res://games/duo_arena/picks.gd")

const CAGE_AT := Vector3(0.0, 7.0, -15.0)  # a lost friend's bubble: over the far wall, in front of everyone
const SPRING_HEAL := 6.0  # hp a second in Nova's spring
const SEASON_PROP_R := 21.0  # on the first row of the stands (decor.gd tiers: 20 .. 22.5 m, 0.6 m up)
const SEASON_PROP_Y := 0.62
const SEASON_LINES := {"spring": ["Spring flowers!", "daisy"], "summer": ["Sunny arena!", "sunflower"],
	"autumn": ["Autumn leaves!", "acorn"], "winter": ["Snowy arena!", "snowflake"]}
const DRIFT_COLORS := {"spring": Color(1.0, 0.75, 0.85), "summer": Color(1.0, 0.95, 0.6), "autumn": Color(0.95, 0.5, 0.15),
	"winter": Color(0.95, 0.97, 1.0)}
const CITY_R := 30.5  # new towers: between the light pylons (27 m) and the old skyline (32 m+)

var main
var season := ""
var gifts: Array = []  # gift ids the team has this game
var friends := {}  # friend id -> 1: saved for good (the family's)
var told_kinds := {}  # host: surprise kinds already explained this game
var surprises_run := 0
var tells_seen := 0  # surprise tells drawn on this machine (bots check a TV machine gets them)
var friends_run: Array = []
var _plan: Array = []  # host: this wave's surprises still to come
var _wave_t := 0.0
var _rollers: Array = []  # host: [{pos, dir, len, t, hit}] rolling now
var _zap_t := 0.0
var _heart_t := 0.0
var _season_root: Node3D
var _city_root: Node3D
var _city_key := ""
var _cage: Node3D
var _cage_friend := ""
var _followers: Array[Node3D] = []
var _t := 0.0


func _ready() -> void:
	name = "DeepPlay"


# --- Seasons -------------------------------------------------------------------------------------------------

## Host: the run's season (the shared override wins: ARCADE_SEASON / ARCADE_SEASON_DUO_ARENA).
static func pick_season() -> String:
	return SeasonKit.override(Deep.GAME_ID, Seeded.season(), Deep.SEASONS)


## Every machine: dress the stands for the season.
func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	if _season_root != null:
		_season_root.queue_free()
	_season_root = Node3D.new()
	_season_root.name = "Season"
	add_child(_season_root)
	var b := MeshKit.Builder.new()
	var n := 16
	for i in n:
		var a := TAU * (i + 0.5) / float(n)
		var at := Vector3(cos(a) * SEASON_PROP_R, SEASON_PROP_Y, sin(a) * SEASON_PROP_R)
		SeasonKit.prop(b, s, at, i, 1.3, -at.normalized())
	_season_root.add_child(MeshKit.instance(b.build(), false))
	_season_root.add_child(SeasonKit.drift(DRIFT_COLORS[s], s, {"box": Vector3(17.0, 0.5, 17.0), "at": Vector3(0, 11.0, 0),
		"amount": 120, "lifetime": 9.0, "size": 0.16}))
	print("DEEP season %s" % s)


# --- Gifts ---------------------------------------------------------------------------------------------------

func has_gift(id: String) -> bool:
	return gifts.has(id)


## Host: the team took a gift (it lasts the rest of the game).
func add_gift(id: String) -> void:
	if gifts.has(id) or Deep.gift(id).is_empty():
		return
	gifts.append(id)
	main.net.state_set("da_gifts", gifts.duplicate())
	if main.net.mode == "host":
		main.net.event("gifts", [gifts.duplicate()])
	apply_team_gifts()
	if id == "bubble":
		for p in main.players:
			if p.active and not p.is_down:
				p.bubble_t = maxf(p.bubble_t, Deep.BUBBLE_SECS)
	print("DEEP gift %s (now %s)" % [id, gifts])


## Client: the host's gift list.
func set_gifts(ids: Array) -> void:
	gifts = ids.duplicate()


## Host: FIRE and ZOOM make everyone stronger once (players who join later get it at the next wave).
func apply_team_gifts() -> void:
	for p in main.players:
		if not p.active:
			continue
		for g in [["fire", "damage", Deep.FIRE_K], ["zoom", "speed", Deep.ZOOM_K]]:
			if gifts.has(g[0]) and not p.has_meta("gift_" + String(g[0])):
				p.set_meta("gift_" + String(g[0]), true)
				p.add_personal(String(g[1]), "mul", float(g[2]))
				Picks.clamp_personal(p.personal)


## Host: a monster was made (SLEEPY slows everything but bosses).
func on_spawned(e) -> void:
	if gifts.has("sleepy") and e.kind != "target" and not e.is_boss():
		e.speed *= Deep.SLEEPY_K


# --- Waves ---------------------------------------------------------------------------------------------------

## Host: a wave starts: its told surprises, a BUBBLE, team gifts for anyone new.
func on_wave_started(wave: int) -> void:
	_plan = Deep.plan(main.run_seed, wave, main.zone.zone_id, main.game_mode)
	_wave_t = 0.0
	_heart_t = Deep.HEART_EVERY * 0.5
	apply_team_gifts()
	if gifts.has("bubble"):
		for p in main.players:
			if p.active and not p.is_down:
				p.bubble_t = maxf(p.bubble_t, Deep.BUBBLE_SECS)
	if not _plan.is_empty():
		print("DEEP surprises wave %d: %s" % [wave, _plan.map(func(e: Dictionary) -> String: return "%s@%.0f" % [e.id, e.t])])


func on_wave_cleared() -> void:
	_plan.clear()


## Host: every frame while a wave fights (fighting) or rests.
func host_step(delta: float, fighting: bool) -> void:
	_step_rollers(delta)
	if not fighting:
		return
	_wave_t += delta
	while not _plan.is_empty() and _wave_t >= float(_plan[0].t):
		_start_surprise(_plan.pop_front())
	if gifts.has("helper"):
		_zap_t -= delta
		if _zap_t <= 0.0:
			_zap_t = Deep.ZAP_EVERY
			_zap()
	if gifts.has("hearts"):
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = Deep.HEART_EVERY
			var a := randf() * TAU
			main.drop_pickup_kind(Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 7.0), "health")
	if gifts.has("magnet"):
		_magnet(delta)
	for p in main.players:
		if p.active and not p.is_down and main.zone.in_spring(p.global_position) and p.hp < p.stat("max_hp"):
			p.heal(SPRING_HEAL * delta)


func _zap() -> void:
	var nova: Node3D = main.zone.nova
	if nova == null:
		return
	var from := nova.global_position
	var best = null
	var best_d := Deep.ZAP_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "target" or e.dead:
			continue
		var d: float = e.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var to: Vector3 = best.center()
	best.hit(Deep.ZAP_DAMAGE + Deep.ZAP_GROW * main.wave, (to - from).normalized(), 0.3, null)
	zap_fx(from, to)
	if main.net.mode == "host":
		main.net.event("zap", [from, to])


## Every machine: a quick light bolt from Nova.
func zap_fx(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = MeshKit.material(Color(0.6, 0.95, 1.0), 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var len := from.distance_to(to)
	mi.global_position = (from + to) * 0.5
	if len > 0.01:
		var up := (to - from) / len
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		mi.global_basis = Basis(side, up * len, side.cross(up))  # the cylinder's height (y) along the bolt
	var tw := mi.create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(mi.queue_free)
	main.burst(to, Color(0.6, 0.95, 1.0), 8, 0.1)
	main.sfx_local("ping", -8.0, 1.4)


func _magnet(delta: float) -> void:
	for pk in get_tree().get_nodes_in_group("pickups"):
		if pk.ghost:
			continue
		var best = null
		var best_d := Deep.MAGNET_R
		for p in main.players:
			if p.active and not p.is_down:
				var d: float = Vector2(p.global_position.x - pk.global_position.x, p.global_position.z - pk.global_position.z).length()
				if d < best_d:
					best_d = d
					best = p
		if best != null:
			var to: Vector3 = best.global_position - pk.global_position
			to.y = 0.0
			pk.global_position += to.normalized() * minf(Deep.MAGNET_SPEED * delta, to.length())


# --- Told surprises ------------------------------------------------------------------------------------------

## Host: tell one surprise now, round one of the players (who is never a bullseye: deep.gd spot()).
func _start_surprise(e: Dictionary) -> void:
	var targets: Array = main.players.filter(func(p) -> bool: return p.active and not p.is_down)
	var at := Vector3.ZERO
	if not targets.is_empty():
		at = targets[int(e.who) % targets.size()].global_position
	var s := Deep.spot(e, at)
	var tell := Deep.tell_for(main.game_mode)
	var id := String(e.id)
	surprise_fx(id, String(s.kind), s.pos, s.dir, s.size, tell)
	if main.net.mode == "host":
		main.net.event("surp", [id, String(s.kind), s.pos, s.dir, s.size, tell])
	surprises_run += 1
	main.net.state_set("da_surprise", surprises_run)
	var info: Dictionary = Deep.SURPRISES[id]
	if not told_kinds.has(id):
		told_kinds[id] = true
		main._story_for_all(String(info.name).capitalize(), String(info.pic), info.color, true)
		main._show_center(String(info.name), 1.4)
	print("DEEP surprise %s %s at %s, told %.1f s" % [id, s.kind, s.pos, tell])
	var land := get_tree().create_timer(tell, false)
	land.timeout.connect(func() -> void: _land(id, s))


## Host: the told surprise arrives: a drop hits whoever is still in its ring; a roll starts rolling along its band.
func _land(id: String, s: Dictionary) -> void:
	if main.game_over or not is_inside_tree():
		return
	var dmg := Deep.damage_for(main.game_mode)
	if String(s.kind) == "line":
		_rollers.append({"pos": s.pos, "dir": s.dir, "len": float((s.size as Vector2).x), "t": 0.0, "hit": {}, "dmg": dmg})
		return
	var pos: Vector3 = s.pos
	for p in main.players:
		if p.active and not p.is_down and WarnRings.inside("circle", pos, s.dir, s.size, p.global_position, 0.3):
			p.take_damage(dmg, pos)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.kind == "target" or e.is_boss():
			continue
		var off := Vector3(e.global_position.x - pos.x, 0.0, e.global_position.z - pos.z)
		if off.length() < Deep.DROP_R + float(e.radius):
			e.hit(4.0, off.normalized() if off.length() > 0.01 else Vector3.FORWARD, 1.5, null)
	main.add_shake(pos, 0.3)


func _step_rollers(delta: float) -> void:
	for i in range(_rollers.size() - 1, -1, -1):
		var r: Dictionary = _rollers[i]
		r.t = float(r.t) + delta
		var k := clampf(float(r.t) / Deep.ROLL_SECS, 0.0, 1.0)
		var at: Vector3 = (r.pos as Vector3) + (r.dir as Vector3) * float(r.len) * k
		for p in main.players:
			if p.active and not p.is_down and not (r.hit as Dictionary).has(p.index):
				if Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < Deep.ROLL_W * 0.5 + 0.4:
					r.hit[p.index] = true
					p.take_damage(float(r.dmg), at)
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.kind == "target" or e.is_boss() or (r.hit as Dictionary).has(e):
				continue
			if Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() < Deep.ROLL_W * 0.5 + float(e.radius):
				r.hit[e] = true
				e.hit(4.0, r.dir, 2.0, null)
		if k >= 1.0:
			_rollers.remove_at(i)


## Every machine: the tell (a steady warn ring) and what comes: something falls into the ring, or a big roller rolls
## along the band once the tell is over.
func surprise_fx(id: String, kind: String, pos: Vector3, dir: Vector3, size: Vector2, tell: float) -> void:
	var info: Dictionary = Deep.SURPRISES.get(id, {})
	var col: Color = info.get("color", Color(1.0, 0.5, 0.1))
	tells_seen += 1
	main.zone.rings.shape(kind, pos, dir, size, col, tell, {"style": "disc" if kind == "circle" else "flash", "stay": 0.25 if kind == "circle" else Deep.ROLL_SECS})
	main.sfx_local("bubble", -6.0, 0.6)
	var thing := MeshInstance3D.new()
	thing.mesh = _thing_mesh(id)
	thing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(thing)
	var tw := thing.create_tween()
	if kind == "circle":
		var start := pos + Vector3(2.0, 22.0, -2.0)
		thing.global_position = start
		tw.tween_property(thing, "global_position", pos + Vector3.UP * 0.5, tell).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			main.burst(pos + Vector3.UP * 0.4, col, 22, 0.18)
			main.sfx_local("crack", -4.0, 1.1)
			thing.queue_free())
		return
	var from := pos - dir * 1.5 + Vector3.UP * 1.0
	var to := pos + dir * (size.x + 1.5) + Vector3.UP * 1.0
	thing.global_position = from
	thing.scale = Vector3.ZERO
	thing.rotation.y = atan2(dir.x, dir.z)  # the log lies across its band
	tw.tween_property(thing, "scale", Vector3.ONE, minf(0.4, tell))
	tw.tween_interval(maxf(0.0, tell - 0.4))
	tw.tween_callback(func() -> void: main.sfx_local("roar", -8.0, 1.6))
	tw.tween_property(thing, "global_position", to, Deep.ROLL_SECS)
	tw.parallel().tween_property(thing, "rotation:x", -TAU * 2.0, Deep.ROLL_SECS).as_relative()
	tw.tween_callback(thing.queue_free)


static func _thing_mesh(id: String) -> Mesh:
	return ResCache.get_or_make("da_surprise_%s_v1" % id, func() -> Resource:
		var b := MeshKit.builder()
		match id:
			"crate":
				b.box(Vector3(1.1, 1.1, 1.1), MeshKit.at(Vector3.ZERO), Color(0.75, 0.5, 0.25))
				b.box(Vector3(1.15, 0.15, 1.15), MeshKit.at(Vector3.ZERO), Color(0.5, 0.32, 0.15))
			"coconut":
				b.sphere(0.45, MeshKit.at(Vector3.ZERO), Color(0.45, 0.3, 0.15), 10)
				b.sphere(0.07, MeshKit.at(Vector3(0.12, 0.35, 0.25)), Color(0.15, 0.1, 0.05), 6)
			"rock":
				b.sphere(0.55, MeshKit.at(Vector3.ZERO), Color(1.0, 0.45, 0.1), 10, true)
			"comet":
				b.sphere(0.45, MeshKit.at(Vector3.ZERO), Color(1.0, 0.95, 0.5), 10, true)
				b.cone(0.4, 1.4, MeshKit.at(Vector3(-0.5, 0.7, 0.5), Vector3.ONE, Vector3(0.6, 0, 0.6)), Color(1.0, 0.8, 0.3), 8, true)
			"log":  # lies across the band (along x), rolls round x
				b.cylinder(0.5, 0.5, 2.2, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.55, 0.35, 0.18), 12)
				b.cylinder(0.42, 0.42, 2.24, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.85, 0.7, 0.45), 12)
			_:  # snowball
				b.sphere(1.0, MeshKit.at(Vector3.ZERO), Color(0.95, 0.97, 1.0), 14)
		return b.build())


## Host test hook: a surprise of the zone now.
func force_surprise() -> void:
	var kinds: Array = Deep.ZONE_SURPRISES.get(main.zone.zone_id, ["crate"])
	_start_surprise({"t": 0.0, "id": String(kinds[surprises_run % kinds.size()]), "ang": randf() * TAU, "off": 0.6, "who": 0})


# --- Nova's friends ------------------------------------------------------------------------------------------

## Every machine: a new leg's zone is up: a lost friend waits in a bubble (unless saved already).
func on_leg(zone_id: String) -> void:
	if _cage != null:
		_cage.queue_free()
		_cage = null
	_cage_friend = ""
	var f := Deep.friend_for_zone(zone_id)
	if f.is_empty() or friends.has(String(f.id)):
		return
	_cage_friend = String(f.id)
	_cage = Node3D.new()
	_cage.name = "FriendBubble"
	add_child(_cage)
	_cage.position = CAGE_AT
	var bot := MeshInstance3D.new()
	bot.mesh = friend_mesh(String(f.id))
	bot.name = "Friend"
	bot.scale = Vector3.ONE * 1.4
	_cage.add_child(bot)
	var bub := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 2.6
	bub.mesh = sm
	var m := WarnRings.fill_material(Color(f.color).lightened(0.5), 0.22)
	bub.material_override = m
	bub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cage.add_child(bub)
	var ring := MeshInstance3D.new()
	ring.mesh = WarnRings.ring_mesh()
	ring.material_override = MeshKit.material(Color(f.color), 2.0)
	ring.scale = Vector3.ONE * 1.35
	ring.rotation.x = PI * 0.5
	_cage.add_child(ring)
	if main.net.mode != "client":
		main._story_for_all("Help! %s is stuck!" % String(f.name).capitalize(), String(f.pic), f.color)
		main._story_for_all("Beat the boss to save %s!" % String(f.name).capitalize(), String(f.pic), f.color)


## The lost friend of this leg (or "").
func lost_friend() -> String:
	return _cage_friend


## Host: the leg's boss fell in a zone with a lost friend: saved for good.
func rescue(zone_id: String) -> void:
	var f := Deep.friend_for_zone(zone_id)
	if f.is_empty() or friends.has(String(f.id)):
		return
	var id := String(f.id)
	friends[id] = 1
	friends_run.append(id)
	main.save.data.friends = friends.duplicate()
	main.save.mark_dirty()
	main.net.state_set("da_friend", id)
	if main.net.mode == "host":
		main.net.event("friend", [id])
	free_friend(id)
	main._story_for_all("We saved %s!" % String(f.name).capitalize(), String(f.pic), f.color)
	var g := Deep.gift(String(f.gift))
	main._story_for_all("%s brings %s!" % [String(f.name).capitalize(), String(g.name).capitalize()], String(g.pic), g.color)
	print("DEEP friend saved: %s" % id)


## Every machine: the bubble pops and the friend flies to Nova.
func free_friend(id: String) -> void:
	friends[id] = 1
	if _cage != null and _cage_friend == id:
		var at := _cage.global_position
		main.burst(at, Deep.friend(id).color, 40, 0.22)
		main.sfx_local("cheer", -4.0, 1.3)
		_cage.queue_free()
		_cage = null
		_cage_friend = ""
	_build_followers()
	_city_key = ""
	set_city(int(main.save.data.waves) if main.save != null else 0)


## Every machine: the saved friends (from the host's "keep").
func set_friends(d: Dictionary) -> void:
	var changed := false
	for k in d:
		if not friends.has(k):
			friends[k] = 1
			changed = true
	if changed:
		_build_followers()
	if _cage != null and friends.has(_cage_friend):  # (a client's "zone" came before the host's "keep")
		_cage.queue_free()
		_cage = null
		_cage_friend = ""


static func friend_mesh(id: String) -> Mesh:
	return ResCache.get_or_make("da_friend_%s_v1" % id, func() -> Resource:
		var c: Color = Deep.friend(id).get("color", Color.WHITE)
		var b := MeshKit.builder()
		b.sphere(0.35, MeshKit.at(Vector3.ZERO), c, 14)
		b.disc(0.24, MeshKit.at(Vector3(0, 0.02, 0.33), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.08, 0.09, 0.16), 16)
		b.sphere(0.05, MeshKit.at(Vector3(-0.08, 0.06, 0.35)), c.lightened(0.5), 6, true)
		b.sphere(0.05, MeshKit.at(Vector3(0.08, 0.06, 0.35)), c.lightened(0.5), 6, true)
		b.cylinder(0.02, 0.02, 0.22, MeshKit.at(Vector3(0, 0.44, 0)), Color(0.8, 0.85, 0.95), 5)
		b.sphere(0.07, MeshKit.at(Vector3(0, 0.58, 0)), c.lightened(0.3), 8, true)
		return b.build())


func _build_followers() -> void:
	for n in _followers:
		if is_instance_valid(n):
			n.queue_free()
	_followers.clear()
	for f in Deep.FRIENDS:
		if friends.has(String(f.id)):
			var mi := MeshInstance3D.new()
			mi.mesh = friend_mesh(String(f.id))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Follower_" + String(f.id)
			add_child(mi)
			_followers.append(mi)


# --- Nova's city ---------------------------------------------------------------------------------------------

## Every machine: new towers (waves cleared ever) and the saved friends' houses round the arena.
func set_city(waves_total: int) -> void:
	var n := Deep.towers(waves_total)
	var key := "%d/%s" % [n, str(friends.keys())]
	if key == _city_key:
		return
	var grew := _city_key != "" and n > int(_city_key.get_slice("/", 0))
	_city_key = key
	if _city_root != null:
		_city_root.queue_free()
	_city_root = Node3D.new()
	_city_root.name = "NovaCity"
	add_child(_city_root)
	var r := Seeded.rng(77, "city")
	var bodies: Array[Transform3D] = []
	var windows: Array[Transform3D] = []
	var wcols: Array[Color] = []
	for i in n:
		# Spread round the ring (golden angle), leaving the friends' houses (far side) and the trophies (behind) clear.
		var a := fmod(i * 2.39996, TAU)
		if absf(angle_difference(a, -PI * 0.5)) < 0.45 or absf(angle_difference(a, PI * 0.5)) < 0.35:
			a += 0.9
		var d := CITY_R + r.randf_range(-1.0, 1.0)
		var h := r.randf_range(5.0, 12.0)
		var w := r.randf_range(1.6, 2.6)
		var at := Vector3(cos(a) * d, h * 0.5, sin(a) * d)
		var rot := Basis(Vector3.UP, -a)
		bodies.append(Transform3D(rot.scaled(Vector3(w, h, w)), at))
		for k in int(h / 2.2):
			windows.append(Transform3D(rot.scaled(Vector3(w + 0.06, 0.35, w * 0.6)), at + Vector3(0, -h * 0.5 + 1.2 + k * 2.2, 0)))
			wcols.append(Color(0.35, 0.85, 1.0) if (i + k) % 3 != 0 else Color(1.0, 0.85, 0.4))
	if n > 0:
		var dark: StandardMaterial3D = main.make_material(Color(0.1, 0.11, 0.18), 0.0)
		_city_root.add_child(DecorScript.multimesh(BoxMesh.new(), dark, bodies, []))
		_city_root.add_child(DecorScript.multimesh(BoxMesh.new(), DecorScript.glow_material(2.4), windows, wcols))
	var k2 := 0
	for f in Deep.FRIENDS:
		if not friends.has(String(f.id)):
			k2 += 1
			continue
		var at := Vector3(-9.0 + k2 * 6.0, 0.0, -CITY_R)
		var house := MeshInstance3D.new()
		house.mesh = ResCache.get_or_make("da_friend_house_v1", func() -> Resource:
			var b := MeshKit.builder()
			b.cylinder(1.6, 1.8, 3.0, MeshKit.at(Vector3(0, 1.5, 0)), Color(0.85, 0.85, 0.9), 16)
			b.sphere(1.7, MeshKit.at(Vector3(0, 3.0, 0), Vector3(1.0, 0.8, 1.0)), Color.WHITE, 14)
			b.box(Vector3(0.9, 1.4, 0.2), MeshKit.at(Vector3(0, 0.7, 1.75)), Color(0.15, 0.15, 0.25))
			return b.build())
		house.material_override = MeshKit.material(Color(f.color), 0.6)
		house.position = at
		_city_root.add_child(house)
		var bot := MeshInstance3D.new()
		bot.mesh = friend_mesh(String(f.id))
		bot.position = at + Vector3(0, 5.6, 0)
		bot.scale = Vector3.ONE * 2.0
		bot.name = "Home_" + String(f.id)
		_city_root.add_child(bot)
		k2 += 1
	if grew:
		main.burst(Vector3(0, 10.0, -CITY_R), Color(0.35, 0.85, 1.0), 30, 0.3)


func _process(delta: float) -> void:
	_t += delta
	if _cage != null:
		_cage.position = CAGE_AT + Vector3(0.0, 0.25 * sin(_t * 1.5), 0.0)
		var bot := _cage.get_node_or_null("Friend") as Node3D
		if bot != null:
			bot.rotation.y = 0.4 * sin(_t * 2.0)
			bot.position.y = 0.1 * sin(_t * 5.0)  # wiggles: "let me out!"
	var nova: Node3D = main.zone.nova if main != null and main.zone != null else null
	for i in _followers.size():
		var f := _followers[i]
		if not is_instance_valid(f) or nova == null:
			continue
		var a := _t * 0.9 + TAU * i / float(maxi(1, _followers.size()))
		f.position = nova.position + Vector3(cos(a) * 1.4, 0.3 * sin(_t * 2.0 + i), sin(a) * 1.4)
		f.rotation.y = -a
	if _city_root != null:
		for c in _city_root.get_children():
			if String(c.name).begins_with("Home_"):
				(c as Node3D).rotation.y = 0.5 * sin(_t + c.position.x)


## For the RUN line.
func telemetry() -> Dictionary:
	return {"season": season, "gifts": gifts.duplicate(), "surprises": surprises_run, "friends_saved": friends_run.duplicate(),
		"friends": friends.size(), "shape": String(main.zone.lay.get("shape", ""))}
