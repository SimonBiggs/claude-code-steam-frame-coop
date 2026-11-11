extends Node3D
## CANNON COVE warned deck events (deep.gd events()): told first by core/warn_rings.gd on our deck, then they happen:
##   ARM     red rings: a purple Kraken arm rises out of the sea over the rail and hangs over them while they are told,
##           then slams down there (and slides back into the sea).
##   SQUALL  a steady blue band across the deck with a rain cloud over it: the gust blows anyone in it along the deck.
## The host tells an event `t` seconds into a wave, sends "hazard" [packed event, warn] and decides who was caught
## (main.gd on_hazard); every machine draws the tells. Nothing flashes: the rings and band glow steadily.
##   host: reset(list); due(wave_t) -> the events whose tell starts now; gone_off(delta, warn) -> the events going off now
##   every machine: announce(e, warn); clear(); tells_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const Deep := preload("res://games/cannon_cove/deep.gd")
const World := preload("res://games/cannon_cove/world.gd")

const ARM_SEGS := 20
const DROPS := 14

var main
var list: Array = []  # host: this wave's events (deep.gd)
var told := {}  # host: index -> seconds since its tell started
var off := {}  # host: index -> true once it went off
var fired := {}  # host: kind -> tells over the whole session (bots)
var live: Array = []  # every machine: [{e, t, secs, rings, arm, cloud, drops}]
var seen := 0  # every machine: tells drawn (bots)
var rings: WarnRings
var seg_mesh: SphereMesh
var skin_mat: StandardMaterial3D
var sucker_mat: StandardMaterial3D
var cloud_mat: StandardMaterial3D
var drop_mesh: BoxMesh
var drop_mat: StandardMaterial3D


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)
	seg_mesh = SphereMesh.new()
	seg_mesh.radius = 1.0
	seg_mesh.height = 2.0
	seg_mesh.radial_segments = 10
	seg_mesh.rings = 5
	skin_mat = World.mat(Deep.ARM_SKIN, 0.15)
	sucker_mat = World.mat(Deep.ARM_SKIN.lightened(0.45), 0.1)
	cloud_mat = World.mat(Color(0.42, 0.45, 0.55), 0.05)
	drop_mesh = BoxMesh.new()
	drop_mesh.size = Vector3(0.05, 0.5, 0.05)
	drop_mat = World.mat(Color(0.75, 0.88, 1.0), 0.8)


## Host: a new wave's events (none between waves).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	told = {}
	off = {}


## Host: the events whose tell starts now (wave_t seconds into the wave).
func due(wave_t: float, delta: float) -> Array:
	var out: Array = []
	for i in told.keys():
		told[i] = float(told[i]) + delta
	for i in list.size():
		if told.has(i) or wave_t < float(list[i].t):
			continue
		told[i] = 0.0
		fired[String(list[i].kind)] = int(fired.get(String(list[i].kind), 0)) + 1
		out.append(list[i])
	return out


## Host: the told events going off now (their warning is over).
func gone_off(warn: float) -> Array:
	var out: Array = []
	for i in told.keys():
		if not off.has(i) and float(told[i]) >= warn:
			off[i] = true
			out.append(list[int(i)])
	return out


## Every machine: draw the tell now; it goes off after `warn` seconds and stays Deep.STAY more.
func announce(e: Dictionary, warn: float) -> void:
	seen += 1
	var p: Vector3 = e.pos
	var entry := {"e": e, "t": 0.0, "secs": warn, "arm": null, "cloud": null, "drops": []}
	match String(e.kind):
		"arm":
			rings.shape("circle", p, Vector3.BACK, Vector2(float((e.size as Vector2).x), 0.0), Deep.ARM_COLOR, warn,
				{"style": "rings", "stay": Deep.STAY, "y": 0.1})
			var arm := Node3D.new()
			arm.name = "KrakenArm"
			for k in ARM_SEGS:
				var m := MeshInstance3D.new()
				m.mesh = seg_mesh
				m.material_override = skin_mat if k % 3 != 1 else sucker_mat
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				arm.add_child(m)
			add_child(arm)
			entry.arm = arm
			main.local_sound("tentacle", -6.0, 1.2)
		"squall":
			var sz: Vector2 = e.size
			rings.shape("line", p + Vector3(-sz.x * 0.5, 0.0, 0.0), Vector3.RIGHT, sz, Deep.SQUALL_COLOR, warn,
				{"style": "disc", "stay": Deep.STAY + 0.6, "alpha": 0.35, "y": 0.1})
			var cloud := Node3D.new()
			cloud.name = "SquallCloud"
			for k in 5:
				var m := MeshInstance3D.new()
				m.mesh = seg_mesh
				m.material_override = cloud_mat
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				m.position = Vector3((k - 2) * 1.6, 0.0 if k % 2 == 0 else 0.4, 0.0)
				m.scale = Vector3(1.4, 0.8, 1.2) * (1.0 if k % 2 == 0 else 0.8)
				cloud.add_child(m)
			for k in DROPS:
				var d := MeshInstance3D.new()
				d.mesh = drop_mesh
				d.material_override = drop_mat
				d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				d.position = Vector3((float(k) / (DROPS - 1) - 0.5) * sz.x * 0.9, -1.0, sin(k * 2.3) * sz.y * 0.35)
				cloud.add_child(d)
				(entry.drops as Array).append(d)
			add_child(cloud)
			cloud.position = p + Vector3(0.0, 7.5, 0.0)  # high over the deck: never in a deckhand's or the gunner's face
			entry.cloud = cloud
			main.local_sound("thunder", -16.0, 1.5)
	live.append(entry)


## Every machine: all gone (a new wave).
func clear() -> void:
	for en in live:
		for k in ["arm", "cloud"]:
			if en[k] != null and is_instance_valid(en[k]):
				(en[k] as Node).queue_free()
	live.clear()
	rings.clear()


## Bots: the tells showing now: [{kind, t (s since told), secs, pos, size}].
func tells_now() -> Array:
	var out: Array = []
	for en in live:
		out.append({"kind": String(en.e.kind), "t": float(en.t), "secs": float(en.secs), "pos": en.e.pos, "size": en.e.size, "e": en.e})
	return out


func _process(delta: float) -> void:
	for i in range(live.size() - 1, -1, -1):
		var en: Dictionary = live[i]
		en.t = float(en.t) + delta
		var t := float(en.t)
		var secs := float(en.secs)
		var end := secs + Deep.STAY + 1.0
		if t > end:
			for k in ["arm", "cloud"]:
				if en[k] != null and is_instance_valid(en[k]):
					(en[k] as Node).queue_free()
			live.remove_at(i)
			continue
		if en.arm != null and is_instance_valid(en.arm):
			_pose_arm(en.arm, en.e, t, secs)
		if en.cloud != null and is_instance_valid(en.cloud):
			var c: Node3D = en.cloud
			var grow := clampf(t / 0.8, 0.05, 1.0) * clampf((end - t) / 0.8, 0.0, 1.0)
			c.scale = Vector3.ONE * grow
			var blowing := t >= secs and t < secs + Deep.STAY + 0.6
			var e: Dictionary = en.e
			for k in (en.drops as Array).size():  # rain falls steadily; while it blows, it slants the way it pushes
				var d: Node3D = en.drops[k]
				var y := -1.0 - fmod(t * 9.0 + k * 0.77, 6.0)
				d.position.y = y
				d.rotation.x = (-0.5 if blowing else 0.0) * float(e.sign)


## The arm: out of the sea at the rail, up and over, hanging above the rings while told, then a slam and back down.
func _pose_arm(arm: Node3D, e: Dictionary, t: float, secs: float) -> void:
	var root := Deep.arm_root(e)
	var sea: float = main.sea_level
	var base := Vector3(root.x * 1.25, sea, root.z)
	var tip_goal: Vector3 = (e.pos as Vector3)
	var hang := tip_goal + Vector3(0.0, 4.2, 0.0)
	var tip: Vector3
	var rise := clampf(t / 1.0, 0.0, 1.0)
	if t < secs:
		tip = base.lerp(hang, rise) + Vector3(0.0, sin(t * 2.2) * 0.25, 0.0)  # a slow sway (no flashing)
	elif t < secs + 0.18:
		tip = hang.lerp(tip_goal + Vector3(0.0, 0.3, 0.0), (t - secs) / 0.18)
	elif t < secs + Deep.STAY:
		tip = tip_goal + Vector3(0.0, 0.3, 0.0)
	else:
		tip = (tip_goal + Vector3(0.0, 0.3, 0.0)).lerp(base, clampf((t - secs - Deep.STAY) / 0.9, 0.0, 1.0))
	var over := Vector3(root.x * 1.05, maxf(tip.y, 1.0) + 1.6, root.z)  # the arch over the rail
	for k in ARM_SEGS:
		var f := float(k) / (ARM_SEGS - 1)
		var a := base.lerp(over, f)
		var b := over.lerp(tip, f)
		var m := arm.get_child(k) as Node3D
		m.global_position = a.lerp(b, f)
		m.scale = Vector3.ONE * lerpf(0.6, 0.22, f)  # (overlapping: one chunky arm, thinning to the tip)


## Bots / main / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.ARM_COLOR if kind == "arm" else Deep.SQUALL_COLOR
