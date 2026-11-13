extends Node3D
## ROCKET WORKSHOP meteors (deep.gd events()): told first by core/warn_rings.gd on the workshop floor, steady (the
## rings glow and breathe a little, they never flash), then a space rock drops into each ring:
##   METEOR  one big hot-pink ring: one big rock.        SHOWER  three small blue rings: three little rocks.
## A crew member still inside when it lands gets bumped out and goes dizzy for a moment (every machine bumps its OWN
## crew: player.gd bump(); stars circle the head on every machine). Sprocket's SHIELD gift: the rocks pop on a
## bubble over the ring instead (nobody bumped). The host tells an event `t` seconds into a rocket's work and sends
## "meteor" [packed event, warn, shield]; every machine draws it.
##   host: reset(list); due(work_t) -> the events whose tell starts now
##   every machine: announce(e, warn, shield); clear(); tells_now() (bots); landed (bots, telemetry)

const WarnRings := preload("res://core/warn_rings.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Contrast := preload("res://core/contrast.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Deep := preload("res://games/rocket_workshop/deep.gd")

const DROP_FROM := 9.0  # metres up a rock starts falling, seen in the last FALL seconds of the tell
const FALL := 0.9
const SHIELD_Y := 2.4  # the shield bubble the rocks pop on

var main
var list: Array = []  # host: this rocket's events
var told := {}
var fired := {}  # host: kind -> tells over the session (bots, telemetry)
var live: Array = []  # every machine: [{e, t, secs, shield, rings, rocks: [Node3D], bubbles, landed}]
var seen := 0  # every machine: tells drawn
var landed := 0  # every machine: rocks that came down
var bumps := 0  # this machine: its own crew bumped


func _ready() -> void:
	name = "Hazards"


## A space rock: a lumpy purple-grey rock with a glowing orange crack, 1 m across (scaled per ring).
static func rock_mesh() -> ArrayMesh:
	return ResCache.get_or_make("rw_rock_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.ellipsoid(Vector3(0.5, 0.42, 0.46), MeshKit.at(Vector3.ZERO), Deep.ROCK)
		b.sphere(0.24, MeshKit.at(Vector3(0.28, 0.18, 0.1)), Deep.ROCK.lightened(0.1))
		b.sphere(0.2, MeshKit.at(Vector3(-0.3, -0.12, -0.12)), Deep.ROCK.darkened(0.15))
		b.box(Vector3(0.62, 0.06, 0.06), MeshKit.at(Vector3(0.0, 0.1, 0.42), Vector3.ONE, Vector3(0.0, 0.0, 0.5)), Deep.ROCK_GLOW)
		b.box(Vector3(0.4, 0.06, 0.06), MeshKit.at(Vector3(0.05, -0.12, 0.4), Vector3.ONE, Vector3(0.0, 0.0, -0.6)), Deep.ROCK_GLOW)
		return b.build()) as ArrayMesh


static func color_of(kind: String) -> Color:
	return Deep.METEOR_COLOR if kind == "meteor" else Deep.SHOWER_COLOR


## Host: a new rocket's events (none while picking).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	told = {}


## Host: the events whose tell starts now.
func due(work_t: float) -> Array:
	var out: Array = []
	for i in list.size():
		if told.has(i) or work_t < float(list[i].t):
			continue
		told[i] = true
		fired[String(list[i].kind)] = int(fired.get(String(list[i].kind), 0)) + 1
		out.append(list[i])
	return out


## Every machine: draw the tell now; the rocks land after `warn` seconds.
func announce(e: Dictionary, warn: float, shield: bool) -> void:
	seen += 1
	var rings := WarnRings.new()
	add_child(rings)
	var col := color_of(String(e.kind))
	var en := {"e": e, "t": 0.0, "secs": warn, "shield": shield, "rings": rings, "rocks": [], "bubbles": [], "landed": false}
	for s in e.spots:
		rings.warn(s, float(e.r), col, warn, 0.06, {"style": "rings", "stay": Deep.STAY})
		var rk := Contrast.outline(MeshKit.instance(rock_mesh(), false)) as MeshInstance3D
		rk.name = "SpaceRock"
		rk.scale = Vector3.ONE * (0.9 if String(e.kind) == "meteor" else 0.5)
		rk.visible = false
		add_child(rk)
		rk.global_position = (s as Vector3) + Vector3.UP * DROP_FROM
		(en.rocks as Array).append(rk)
		if shield:
			var bub := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = float(e.r) + 0.2
			sm.height = sm.radius
			sm.is_hemisphere = true
			bub.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(Deep.gift("shield").color, 0.22)
			UiKit.see_through(m)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			bub.material_override = m
			bub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(bub)
			bub.global_position = Vector3((s as Vector3).x, SHIELD_Y - sm.radius * 0.5, (s as Vector3).z)
			(en.bubbles as Array).append(bub)
	main.local_sound("uhoh" if String(e.kind) == "meteor" else "comet", -6.0, 1.2)
	live.append(en)


## Every machine: all gone (a new rocket, a pick).
func clear() -> void:
	for en in live:
		_free(en)
	live.clear()


func _free(en: Dictionary) -> void:
	if is_instance_valid(en.rings):
		(en.rings as Node).queue_free()
	for n in (en.rocks as Array) + (en.bubbles as Array):
		if is_instance_valid(n):
			(n as Node).queue_free()


## Bots: the tells showing now: [{kind, t (s since told), secs, e}].
func tells_now() -> Array:
	var out: Array = []
	for en in live:
		if not bool(en.landed):
			out.append({"kind": String(en.e.kind), "t": float(en.t), "secs": float(en.secs), "e": en.e})
	return out


func _process(delta: float) -> void:
	for i in range(live.size() - 1, -1, -1):
		var en: Dictionary = live[i]
		en.t = float(en.t) + delta
		var t := float(en.t)
		var secs := float(en.secs)
		if t > secs + Deep.STAY + 1.2:
			_free(en)
			live.remove_at(i)
			continue
		var e: Dictionary = en.e
		var stop_y := SHIELD_Y if bool(en.shield) else 0.35
		for k in (en.rocks as Array).size():
			var rk: Node3D = en.rocks[k]
			if not is_instance_valid(rk):
				continue
			var s: Vector3 = e.spots[k]
			var fall := clampf((t - (secs - FALL)) / FALL, 0.0, 1.0)
			rk.visible = t >= secs - FALL and (not bool(en.landed) or not bool(en.shield)) and t < secs + Deep.STAY + 1.0
			rk.global_position = s + Vector3.UP * lerpf(DROP_FROM, stop_y, fall * fall)
			rk.rotation = Vector3(t * 3.0, t * 2.0, 0.0)
		if t >= secs and not bool(en.landed):
			en.landed = true
			_land(en)


## The rocks are down: a thump and dust (or a pop on the shield), and this machine's own crew in a ring get bumped.
func _land(en: Dictionary) -> void:
	var e: Dictionary = en.e
	landed += (e.spots as Array).size()
	for s in e.spots:
		var at: Vector3 = s
		if bool(en.shield):
			main.burst(Vector3(at.x, SHIELD_Y, at.z), Deep.gift("shield").color, 16, 0.06)
		else:
			main.burst(at + Vector3.UP * 0.3, Deep.ROCK.lightened(0.4), 18, 0.12)
	for b in en.bubbles:
		if is_instance_valid(b):
			(b as Node).queue_free()
	en.bubbles = []
	main.local_sound("pop" if bool(en.shield) else "burp", -2.0, 1.4 if bool(en.shield) else 0.6)
	if bool(en.shield):
		return
	var md := Deep.mode_data(String(main.play_mode))
	for p in main.players:
		if p.index == 0 or not p.active or not Deep.caught(e, p.global_position):
			continue
		p.dizzy_fx(float(md.dizzy))  # every machine: stars round the head
		if not p.ghost and not p.remote:  # this machine's own crew member gets bumped out
			bumps += 1
			p.bump(Deep.out_dir(e, p.global_position) * float(md.push), float(md.dizzy))
	main.on_meteor_landed(e)
