extends Node3D
## SNOWMAN MAKER seasons (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state): every machine dresses
## the world the same. WINTER is a real snowy garden: snowmen of the season stand round the far edge. Out of season
## (spring, summer, autumn) the whole garden and Tumble's village sit inside a MAGIC SNOW GLOBE: a faint glass dome
## (see-through, under the VR cards) on a golden stand, the season's ground outside it with the season's props
## (tulips, sunflowers, pumpkins: core/season_kit.gd) and its drifting things falling outside the glass while it keeps
## snowing inside. One merged mesh for the props + stand, one dome, one CPUParticles3D: cheap on the Frame.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Deep := preload("res://games/snowman_maker/deep.gd")

const PROPS := 14  # seasonal props round the outside of the globe (or round the far edge in winter)
const PROP_R := 28.0  # (outside the globe: its stand reaches Deep.GLOBE_R + STAND_W)
const STAND_W := 3.4  # (covers the garden snow disc's edge at 25 m)
const WINTER_R := 19.0

var main
var season := ""
var props: MeshInstance3D
var dome: MeshInstance3D
var outside: MeshInstance3D
var drift: CPUParticles3D


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, dome, outside, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	props = null
	dome = null
	outside = null
	drift = null
	var sd := Deep.season_data(s)
	var globe := bool(sd.globe)
	var b := MeshKit.Builder.new()
	var ring_r := PROP_R if globe else WINTER_R
	for i in PROPS:
		var a := float(i) * TAU / PROPS + 0.2
		var p := Vector3(cos(a), 0.0, sin(a)) * ring_r
		SeasonKit.prop(b, s, p, i, 2.4 if globe else 1.8, -Vector3(p.x, 0.0, p.z).normalized())  # facing the garden
	if globe:
		# The golden stand: a low ring round the glass, with a darker band and little stars.
		var segs := 48
		for i in segs:
			var a := float(i) * TAU / segs
			var p := Vector3(cos(a), 0.0, sin(a)) * (Deep.GLOBE_R + STAND_W * 0.5)
			var xf := Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p)
			var w := TAU * (Deep.GLOBE_R + STAND_W * 0.5) / segs + 0.05
			b.box(Vector3(w, 0.9, STAND_W), xf * MeshKit.at(Vector3(0, 0.45, 0)), Deep.STAND_COLOR)
			b.box(Vector3(w, 0.18, STAND_W + 0.1), xf * MeshKit.at(Vector3(0, 0.75, 0)), Deep.STAND_COLOR.darkened(0.35))
			if i % 4 == 0:
				b.sphere(0.22, xf * MeshKit.at(Vector3(0, 0.75, -STAND_W * 0.5 - 0.05)), Color(1.0, 0.95, 0.6), 6)
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	if globe:
		# The season's ground outside the glass (under the garden's snow disc, which ends under the stand).
		outside = MeshInstance3D.new()
		outside.name = "OutsideGround"
		var disc := CylinderMesh.new()
		disc.top_radius = 70.0
		disc.bottom_radius = 70.0
		disc.height = 0.1
		disc.radial_segments = 32
		outside.mesh = disc
		outside.material_override = MeshKit.material(sd.ground)
		outside.position.y = -0.16
		outside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(outside)
		# The glass dome: faint, shiny towards the top, never in the way of a VR card.
		dome = MeshInstance3D.new()
		dome.name = "GlobeGlass"
		var sm := SphereMesh.new()
		sm.radius = Deep.GLOBE_R
		sm.height = Deep.GLOBE_R
		sm.is_hemisphere = true
		sm.radial_segments = 32
		sm.rings = 10
		dome.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.75, 0.9, 1.0, 0.07)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.rim_enabled = false
		m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under VR cards
		dome.material_override = m
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dome)
		drift = SeasonKit.drift(sd.drift, s, {"amount": 90, "lifetime": 9.0, "box": Vector3(30.0, 0.5, 30.0),
			"at": Vector3(0.0, 9.0, 0.0), "size": 0.35, "speed": Vector2(0.7, 1.3)})
		drift.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING  # outside the glass only
		drift.emission_ring_axis = Vector3.UP
		drift.emission_ring_radius = Deep.GLOBE_R + 9.0
		drift.emission_ring_inner_radius = Deep.GLOBE_R + 2.0
		drift.emission_ring_height = 0.5
		add_child(drift)
	print("Snowman Maker: %s garden%s" % [s, " in the magic snow globe" if globe else ""])
