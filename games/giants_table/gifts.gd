extends Node3D
## GIANT'S TABLE: SPARKY'S GIFTS at work (deep.gd GIFTS; the gift of the wave comes in the "deep" state, so every
## machine shows it the same):
##   BIG FIRE      the fire fills up at the wave's start (host) and its flames burn big (main.fire_boost()).
##   EMBER SHIELD  a glowing see-through dome over the fire: the first SHIELD_HITS goblins that try to steal bounce
##                 off it dizzy ("shield" state: hits left; host: main.goblin_steals asks block()).
##   KNIGHT HELPERS three little toy knights stand round the fire; a goblin that comes near one gets bonked dizzy
##                 and pushed back (host; the "helper" event swings the sword on every machine).
##   SLEEPY DUST   goblins walk slowly this wave (host: main._spawn_goblin, Deep.goblin_speed).
##   BIG HANDS     the Giant reaches further and its hands look bigger (giant.gd: main.grab_reach / hand_scale).
## Cheap: one merged mesh per helper, one dome mesh.

const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Deep := preload("res://games/giants_table/deep.gd")
const W := preload("res://games/giants_table/world.gd")

var main
var gift := ""
var dome: MeshInstance3D
var helpers: Array = []  # Node3D (each with an "Arm")
var swing: Array = []  # seconds left of each helper's swing
var cd: Array = []  # host: seconds before each helper can bonk again
var shield_left := 0
var t := 0.0
var bonks := 0  # host: helper bonks this wave (telemetry)
var blocks := 0  # host: shield bounces this wave (telemetry)


func _ready() -> void:
	name = "Gifts"


## Every machine: this wave's gift ("" none).
func set_gift(id: String) -> void:
	if id == gift:
		return
	gift = id
	for n in helpers:
		if is_instance_valid(n):
			n.queue_free()
	helpers = []
	swing = []
	cd = []
	if dome != null and is_instance_valid(dome):
		dome.queue_free()
	dome = null
	if id == "helpers":
		for i in Deep.HELPERS:
			var h := _helper(i)
			add_child(h)
			var p := Deep.helper_spot(i)
			h.position = Vector3(p.x, maxf(0.0, W.height(p.x, p.z)), p.z)
			UiKit.look(h, h.position + Vector3(p.x, 0.0, p.z), Vector3.UP)  # facing out, guarding the fire
			helpers.append(h)
			swing.append(0.0)
			cd.append(0.0)
	elif id == "shield":
		dome = MeshInstance3D.new()
		dome.name = "EmberShield"
		var sm := SphereMesh.new()
		sm.radius = Deep.SHIELD_R
		sm.height = Deep.SHIELD_R * 2.0
		sm.is_hemisphere = true
		sm.radial_segments = 24
		sm.rings = 8
		dome.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		UiKit.see_through(m)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.35, 0.85, 1.0, 0.22)
		dome.material_override = m
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dome)
	_show_shield()


## Every machine: the shield's hits left.
func set_shield(n: int) -> void:
	if n < shield_left and dome != null and is_instance_valid(dome):
		main.burst(Vector3(0, 1.5, 0), Color(0.35, 0.85, 1.0), 16, 0.2, false)
		main.sound("boing", -2.0, 1.1, false)
	shield_left = n
	_show_shield()


func _show_shield() -> void:
	if dome != null and is_instance_valid(dome):
		dome.visible = shield_left > 0
		var a := 0.12 + 0.05 * shield_left
		(dome.material_override as StandardMaterial3D).albedo_color.a = a


## Every machine: helper i swings its sword.
func swing_fx(i: int) -> void:
	if i >= 0 and i < swing.size():
		swing[i] = 0.35


func _process(delta: float) -> void:
	t += delta
	if dome != null and is_instance_valid(dome):
		var s := 1.0 + 0.02 * sin(t * 3.0)
		dome.scale = Vector3(s, s, s)
	for i in helpers.size():
		var h: Node3D = helpers[i]
		if not is_instance_valid(h):
			continue
		swing[i] = maxf(0.0, float(swing[i]) - delta)
		var arm := h.get_node_or_null("Arm") as Node3D
		if arm != null:
			arm.rotation.x = -1.6 * sin(float(swing[i]) / 0.35 * PI) if float(swing[i]) > 0.0 else 0.15 * sin(t * 2.0 + i)
		h.get_child(0).position.y = absf(sin(t * 3.0 + i)) * 0.05  # a little bob on the spot


# --- Host -----------------------------------------------------------------------------------------------------

## Host: a new wave with this gift.
func host_begin() -> void:
	bonks = 0
	blocks = 0
	main.net.state_set("shield", Deep.SHIELD_HITS if gift == "shield" else 0)


## Host: does the shield bounce goblin g off the fire? (one hit used)
func block(g) -> bool:
	if gift != "shield" or int(main.net.state_get("shield", 0)) <= 0:
		return false
	main.net.state_set("shield", int(main.net.state_get("shield", 0)) - 1)
	blocks += 1
	_push_back(g, 1.4, 1.8)
	return true


## Host, every frame of a wave: helpers bonk goblins that come near.
func host_tick(delta: float) -> void:
	if gift != "helpers":
		return
	for i in helpers.size():
		cd[i] = float(cd[i]) - delta
		if float(cd[i]) > 0.0:
			continue
		var hp: Vector3 = Deep.helper_spot(i)
		for g in get_tree().get_nodes_in_group("goblins"):
			if g.held or g.flying or g.floating or g.has_meta("dead") or g.practice:
				continue
			var gp: Vector3 = g.global_position
			if Vector2(gp.x - hp.x, gp.z - hp.z).length() < Deep.HELPER_R:
				cd[i] = Deep.HELPER_CD
				bonks += 1
				_push_back(g, 0.9, Deep.HELPER_DIZZY)
				swing_fx(i)
				main.net.event("helper", [i])
				main.sound("smack", -4.0, 1.3)
				main.burst(g.grab_center(), Color(1.0, 0.9, 0.5), 10, 0.15)
				break


func _push_back(g, dist: float, dizzy: float) -> void:
	var gp: Vector3 = g.global_position
	var out := Vector3(gp.x, 0.0, gp.z)
	out = out.normalized() if out.length() > 0.1 else Vector3.BACK
	var np := W.push_out(gp + out * dist, g.radius)
	var h := W.height(np.x, np.z)
	np.y = h if h > -50.0 else gp.y
	g.global_position = np
	g.dizzy_t = maxf(g.dizzy_t, dizzy)


## A little toy knight (wooden base, silver body, a red plume, a sword arm), facing +Z.
func _helper(i: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Helper%d" % i
	var body := Node3D.new()
	n.add_child(body)
	var b := MeshKit.Builder.new()
	var steel := Color(0.85, 0.88, 0.95)
	b.cylinder(0.35, 0.4, 0.15, MeshKit.at(Vector3(0, 0.075, 0)), Color(0.55, 0.34, 0.16), 12)
	b.cylinder(0.2, 0.25, 0.6, MeshKit.at(Vector3(0, 0.45, 0)), steel, 10)
	b.sphere(0.2, MeshKit.at(Vector3(0, 0.92, 0)), steel, 10)
	b.box(Vector3(0.26, 0.05, 0.05), MeshKit.at(Vector3(0, 0.92, 0.19)), Color(0.15, 0.15, 0.2))  # the visor slit
	b.ellipsoid(Vector3(0.06, 0.16, 0.18), MeshKit.at(Vector3(0, 1.17, -0.02)), [Color(0.95, 0.25, 0.25), Color(0.3, 0.55, 1.0), Color(1.0, 0.8, 0.2)][i % 3], 8)
	b.box(Vector3(0.08, 0.36, 0.3), MeshKit.at(Vector3(-0.26, 0.5, 0.05)), [Color(0.95, 0.25, 0.25), Color(0.3, 0.55, 1.0), Color(1.0, 0.8, 0.2)][i % 3])  # shield
	body.add_child(MeshKit.instance(b.build(), false))
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0.27, 0.62, 0.0)
	var ab := MeshKit.Builder.new()
	ab.box(Vector3(0.1, 0.1, 0.25), MeshKit.at(Vector3(0, 0, 0.1)), steel)
	ab.box(Vector3(0.05, 0.05, 0.6), MeshKit.at(Vector3(0, 0.0, 0.5)), Color(0.95, 0.95, 1.0))
	ab.box(Vector3(0.2, 0.05, 0.05), MeshKit.at(Vector3(0, 0, 0.22)), Color(0.8, 0.6, 0.2))
	arm.add_child(MeshKit.instance(ab.build(), false))
	body.add_child(arm)
	n.scale = Vector3.ONE * 1.25
	return n
