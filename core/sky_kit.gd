extends RefCounted
## SkyKit: mobile-safe environment presets (sky, sun/moon light, ambient, fog on the TV, and cheap
## extras: stars, moon, clouds, rain, snow, bubbles, dust, fireflies, a planet, light shafts).
##
##   const SkyKit := preload("res://core/sky_kit.gd")
##   var sky := SkyKit.apply(self, "sunset", is_vr)    # adds a "SkyKit" node to `self`
##   sky.set_preset("night", 4.0)                      # blend over 4 s
##   sky.set_time_of_day(18.5)                         # or drive a day/night cycle (hours, 0-24)
##   sky.lightning.connect(func(s: float) -> void: sfx.play("thunder"))
##
## Presets: day, dawn, sunset, night, spooky, dungeon (alias cave), space, underwater, stormy, snowy,
## indoor (alias cosy). VR (vr = true): no fog, SSAO, SSR, SDFGI, glow or directional shadows, fewer
## particles. TV: distance fog where it helps, soft sun shadows (max 60 m), gentle glow.
## The star/cloud dome follows the active camera of the viewport (or the camera given to follow()).
## Draw calls (besides the sky itself): day 1 (clouds), dawn/sunset 1, night 4 (stars, moon, halo,
## clouds), spooky 5 (+ fireflies), dungeon/indoor 1 (dust), space 2 (stars, planet), underwater 2
## (bubbles, shafts), stormy 2 (clouds, rain), snowy 2 (clouds, snow).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Me := preload("res://core/sky_kit.gd")

const DOME := 600.0
const MAX_CLOUDS := 28

## Preset values. Colours are sRGB; elev/az in degrees (elev = height of the sun/moon above the horizon,
## az = its rotation round Y; az 0 puts it in the +Z sky).
const PRESETS := {
	"day": {"top": Color(0.3, 0.55, 0.93), "horizon": Color(0.7, 0.85, 0.98), "ground_h": Color(0.63, 0.74, 0.84),
		"ground_b": Color(0.36, 0.42, 0.5), "curve": 0.15, "sun": Color(1.0, 0.96, 0.88), "sun_e": 1.15, "elev": 52.0,
		"az": 35.0, "disk": 1.0, "amb": Color(0.76, 0.83, 0.96), "amb_e": 0.6, "fog": Color(0.72, 0.85, 0.98),
		"fog_d": 0.0035, "fog_sky": 0.0, "exposure": 1.0, "glow": 0.3, "stars": 0, "moon": false, "clouds": 16,
		"cloud_col": Color(1.0, 1.0, 1.0), "fx": ""},
	"dawn": {"top": Color(0.42, 0.52, 0.85), "horizon": Color(1.0, 0.78, 0.72), "ground_h": Color(0.85, 0.7, 0.72),
		"ground_b": Color(0.35, 0.32, 0.42), "curve": 0.13, "sun": Color(1.0, 0.82, 0.7), "sun_e": 0.95, "elev": 12.0,
		"az": 95.0, "disk": 1.0, "amb": Color(0.86, 0.8, 0.9), "amb_e": 0.55, "fog": Color(0.95, 0.82, 0.82),
		"fog_d": 0.004, "fog_sky": 0.0, "exposure": 1.0, "glow": 0.45, "stars": 0, "moon": false, "clouds": 12,
		"cloud_col": Color(1.0, 0.86, 0.88), "fx": ""},
	"sunset": {"top": Color(0.26, 0.28, 0.62), "horizon": Color(1.0, 0.6, 0.4), "ground_h": Color(0.88, 0.52, 0.42),
		"ground_b": Color(0.3, 0.22, 0.34), "curve": 0.12, "sun": Color(1.0, 0.7, 0.45), "sun_e": 1.1, "elev": 9.0,
		"az": 250.0, "disk": 1.0, "amb": Color(0.95, 0.74, 0.68), "amb_e": 0.55, "fog": Color(0.96, 0.66, 0.52),
		"fog_d": 0.004, "fog_sky": 0.0, "exposure": 1.0, "glow": 0.6, "stars": 0, "moon": false, "clouds": 14,
		"cloud_col": Color(1.0, 0.76, 0.7), "fx": ""},
	"night": {"top": Color(0.03, 0.04, 0.12), "horizon": Color(0.1, 0.14, 0.28), "ground_h": Color(0.07, 0.09, 0.17),
		"ground_b": Color(0.02, 0.02, 0.05), "curve": 0.1, "sun": Color(0.62, 0.72, 1.0), "sun_e": 0.4, "elev": 38.0,
		"az": 200.0, "disk": 0.0, "amb": Color(0.38, 0.46, 0.75), "amb_e": 0.5, "fog": Color(0.07, 0.09, 0.17),
		"fog_d": 0.005, "fog_sky": 0.0, "exposure": 1.05, "glow": 0.55, "stars": 320, "moon": true, "clouds": 7,
		"cloud_col": Color(0.36, 0.4, 0.55), "fx": ""},
	"spooky": {"top": Color(0.08, 0.03, 0.15), "horizon": Color(0.32, 0.17, 0.38), "ground_h": Color(0.2, 0.1, 0.24),
		"ground_b": Color(0.04, 0.02, 0.06), "curve": 0.12, "sun": Color(0.62, 0.95, 0.75), "sun_e": 0.35, "elev": 30.0,
		"az": 150.0, "disk": 0.0, "amb": Color(0.5, 0.38, 0.65), "amb_e": 0.5, "fog": Color(0.2, 0.12, 0.26),
		"fog_d": 0.012, "fog_sky": 0.0, "exposure": 1.05, "glow": 0.7, "stars": 140, "moon": true, "clouds": 9,
		"cloud_col": Color(0.32, 0.24, 0.38), "fx": "fireflies"},
	"dungeon": {"top": Color(0.03, 0.03, 0.05), "horizon": Color(0.05, 0.045, 0.07), "ground_h": Color(0.05, 0.045, 0.07),
		"ground_b": Color(0.02, 0.02, 0.03), "curve": 0.2, "sun": Color(0.6, 0.6, 0.8), "sun_e": 0.0, "elev": 60.0,
		"az": 0.0, "disk": 0.0, "amb": Color(0.45, 0.4, 0.55), "amb_e": 0.5, "fog": Color(0.04, 0.035, 0.055),
		"fog_d": 0.03, "fog_sky": 1.0, "exposure": 1.0, "glow": 0.7, "stars": 0, "moon": false, "clouds": 0,
		"cloud_col": Color(1, 1, 1), "fx": "dust"},
	"space": {"top": Color(0.01, 0.01, 0.035), "horizon": Color(0.08, 0.04, 0.15), "ground_h": Color(0.05, 0.03, 0.11),
		"ground_b": Color(0.01, 0.01, 0.03), "curve": 0.3, "sun": Color(1.0, 0.97, 0.92), "sun_e": 1.3, "elev": 25.0,
		"az": 300.0, "disk": 1.0, "amb": Color(0.32, 0.34, 0.5), "amb_e": 0.45, "fog": Color(0, 0, 0),
		"fog_d": 0.0, "fog_sky": 0.0, "exposure": 1.0, "glow": 0.6, "stars": 450, "moon": false, "clouds": 0,
		"cloud_col": Color(1, 1, 1), "fx": "planet"},
	"underwater": {"top": Color(0.12, 0.58, 0.68), "horizon": Color(0.05, 0.32, 0.47), "ground_h": Color(0.03, 0.19, 0.31),
		"ground_b": Color(0.02, 0.08, 0.16), "curve": 0.25, "sun": Color(0.62, 0.95, 1.0), "sun_e": 0.85, "elev": 70.0,
		"az": 20.0, "disk": 0.0, "amb": Color(0.38, 0.72, 0.82), "amb_e": 0.65, "fog": Color(0.05, 0.33, 0.44),
		"fog_d": 0.035, "fog_sky": 1.0, "exposure": 1.0, "glow": 0.4, "stars": 0, "moon": false, "clouds": 0,
		"cloud_col": Color(1, 1, 1), "fx": "bubbles"},
	"stormy": {"top": Color(0.2, 0.22, 0.27), "horizon": Color(0.4, 0.42, 0.47), "ground_h": Color(0.31, 0.33, 0.37),
		"ground_b": Color(0.15, 0.16, 0.2), "curve": 0.1, "sun": Color(0.75, 0.8, 0.9), "sun_e": 0.45, "elev": 45.0,
		"az": 60.0, "disk": 0.0, "amb": Color(0.52, 0.57, 0.67), "amb_e": 0.6, "fog": Color(0.34, 0.36, 0.41),
		"fog_d": 0.01, "fog_sky": 0.0, "exposure": 1.0, "glow": 0.3, "stars": 0, "moon": false, "clouds": 26,
		"cloud_col": Color(0.45, 0.47, 0.52), "fx": "rain"},
	"snowy": {"top": Color(0.55, 0.65, 0.8), "horizon": Color(0.85, 0.88, 0.93), "ground_h": Color(0.8, 0.84, 0.9),
		"ground_b": Color(0.5, 0.55, 0.62), "curve": 0.12, "sun": Color(0.95, 0.96, 1.0), "sun_e": 0.8, "elev": 30.0,
		"az": 140.0, "disk": 0.0, "amb": Color(0.82, 0.86, 0.96), "amb_e": 0.65, "fog": Color(0.85, 0.88, 0.93),
		"fog_d": 0.008, "fog_sky": 0.0, "exposure": 1.0, "glow": 0.3, "stars": 0, "moon": false, "clouds": 20,
		"cloud_col": Color(0.9, 0.92, 0.96), "fx": "snow"},
	"indoor": {"top": Color(0.24, 0.18, 0.14), "horizon": Color(0.32, 0.24, 0.18), "ground_h": Color(0.3, 0.22, 0.16),
		"ground_b": Color(0.12, 0.08, 0.06), "curve": 0.2, "sun": Color(1.0, 0.86, 0.66), "sun_e": 0.5, "elev": 35.0,
		"az": 60.0, "disk": 0.0, "amb": Color(1.0, 0.86, 0.72), "amb_e": 0.6, "fog": Color(0, 0, 0),
		"fog_d": 0.0, "fog_sky": 0.0, "exposure": 1.0, "glow": 0.5, "stars": 0, "moon": false, "clouds": 0,
		"cloud_col": Color(1, 1, 1), "fx": "dust"},
}
const ALIASES := {"cave": "dungeon", "cosy": "indoor", "cozy": "indoor", "storm": "stormy", "snow": "snowy",
	"morning": "dawn", "evening": "sunset"}
## Blendable keys (colours and floats).
const COLOR_KEYS: Array[String] = ["top", "horizon", "ground_h", "ground_b", "sun", "amb", "fog", "cloud_col"]
const FLOAT_KEYS: Array[String] = ["curve", "sun_e", "elev", "disk", "amb_e", "fog_d", "fog_sky", "exposure", "glow"]


## Add a sky/light rig for `preset` under `parent` and return it (see SkyRig for the controls).
static func apply(parent: Node, preset: String = "day", vr: bool = false) -> SkyRig:
	var rig := SkyRig.new()
	rig.name = "SkyKit"
	rig.vr = vr
	parent.add_child(rig)
	rig.set_preset(preset, 0.0)
	return rig


## All preset names (aliases not included).
static func preset_names() -> Array[String]:
	var out: Array[String] = []
	for k in PRESETS:
		out.append(str(k))
	return out


## Resolve aliases ("cave" -> "dungeon"); unknown names fall back to "day".
static func resolve(preset: String) -> String:
	var p := preset.to_lower()
	if ALIASES.has(p):
		p = str(ALIASES[p])
	return p if PRESETS.has(p) else "day"


## A warm flickering OmniLight3D (torches, candles, campfires): add it where you need it.
## Cheap: the flicker just changes light_energy. range in metres.
static func flicker_light(color: Color = Color(1.0, 0.7, 0.4), energy: float = 1.6, light_range: float = 6.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	var f := Flicker.new()
	f.base = energy
	f.name = "Flicker"
	l.add_child(f)
	return l


class Flicker extends Node:
	## Makes the parent light flicker gently around `base` energy.
	var base := 1.6
	var _t := 0.0

	func _ready() -> void:
		_t = randf() * 10.0

	func _process(delta: float) -> void:
		_t += delta
		var l := get_parent() as Light3D
		if l != null:
			l.light_energy = base * (0.88 + 0.08 * sin(_t * 11.0) + 0.05 * sin(_t * 23.7 + 1.3) + 0.03 * sin(_t * 5.1))


# =================================================================================================

class SkyRig extends Node3D:
	## The environment controller returned by SkyKit.apply().

	## Lightning struck (stormy preset or flash()); strength 0-1. Play a thunder sound on it.
	signal lightning(strength: float)

	var vr := false
	var preset := ""
	var env: Environment
	var world_env: WorldEnvironment
	var sun: DirectionalLight3D
	var sky_mat: ProceduralSkyMaterial
	## Camera the dome follows (null = the viewport's current camera).
	var camera: Node3D
	## Rate the clouds drift round the sky (radians per second).
	var cloud_drift := 0.004

	var _dome: Node3D
	var _stars: MultiMeshInstance3D
	var _moon: Node3D
	var _clouds: MultiMeshInstance3D
	var _planet: MeshInstance3D
	var _fx := {}         # name -> Node3D (particles / shafts)
	var _cur := {}        # current blended values
	var _from := {}
	var _to := {}
	var _blend_t := 0.0
	var _blend_len := 0.0
	var _extras_target := ""
	var _lightning_on := false
	var _strike_t := 6.0
	var _flash := 0.0
	var _flash_queue: Array[float] = []
	var _flash_strength := 1.0
	var _shaft_t := 0.0

	func _ready() -> void:
		_build()

	func _build() -> void:
		if env != null:
			return
		sky_mat = ProceduralSkyMaterial.new()
		var sky := Sky.new()
		sky.sky_material = sky_mat
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		env = Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.ssao_enabled = false
		env.ssr_enabled = false
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		env.glow_enabled = not vr
		env.glow_hdr_threshold = 1.0
		env.glow_bloom = 0.04
		env.fog_enabled = false
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		world_env.environment = env
		add_child(world_env)
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		sun.shadow_enabled = not vr
		sun.directional_shadow_max_distance = 60.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.shadow_blur = 1.5
		sun.shadow_opacity = 0.85
		sun.light_angular_distance = 0.6
		add_child(sun)
		_dome = Node3D.new()
		_dome.name = "Dome"
		add_child(_dome)

	# --- Public API ---------------------------------------------------------------------------

	## Switch to a preset (see SkyKit.PRESETS / ALIASES), blending colours and light over `blend` seconds.
	func set_preset(preset_name: String, blend: float = 0.0) -> void:
		_build()
		var p := Me.resolve(preset_name)
		preset = p
		var target: Dictionary = Me.PRESETS[p]
		if _cur.is_empty() or blend <= 0.0:
			_cur = target.duplicate()
			_blend_len = 0.0
			_apply(_cur)
			_set_extras(target)
			_apply(_cur)
			return
		_from = _cur.duplicate()
		_to = target
		_blend_t = 0.0
		_blend_len = blend
		_extras_target = p

	## Drive a day/night cycle: hour 0-24 (6 dawn, 12 noon, 18.5 sunset, 21+ night). Call every frame
	## or whenever the hour changes; it blends the dawn/day/sunset/night presets and moves the sun.
	func set_time_of_day(hour: float) -> void:
		_build()
		hour = fposmod(hour, 24.0)
		var keys: Array = [[0.0, "night"], [5.0, "night"], [6.5, "dawn"], [9.0, "day"], [16.5, "day"], [18.5, "sunset"],
			[20.0, "night"], [24.0, "night"]]
		var a: Array = keys[0]
		var b: Array = keys[1]
		for i in keys.size() - 1:
			var k0: Array = keys[i]
			var k1: Array = keys[i + 1]
			if hour >= float(k0[0]) and hour <= float(k1[0]):
				a = k0
				b = k1
				break
		var span := maxf(0.001, float(b[0]) - float(a[0]))
		var t := clampf((hour - float(a[0])) / span, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var pa: Dictionary = Me.PRESETS[str(a[1])]
		var pb: Dictionary = Me.PRESETS[str(b[1])]
		var v := _lerp_values(pa, pb, t)
		var day := hour >= 5.75 and hour <= 19.25
		if day:
			var f := clampf((hour - 5.75) / 13.5, 0.0, 1.0)
			v["elev"] = maxf(6.0, sin(f * PI) * 62.0)
			v["az"] = lerpf(95.0, 265.0, f)
		else:
			var g := fposmod(hour - 19.25, 24.0) / 10.5
			v["elev"] = maxf(10.0, sin(clampf(g, 0.0, 1.0) * PI) * 50.0)
			v["az"] = lerpf(110.0, 250.0, clampf(g, 0.0, 1.0))
		_blend_len = 0.0
		_cur = v
		_apply(v)
		var nearest := str(a[1]) if t < 0.5 else str(b[1])
		if nearest != preset:
			preset = nearest
			_set_extras(Me.PRESETS[nearest])

	## Make the dome (stars, moon, clouds, rain) follow this camera (null = the viewport's camera).
	func follow(cam: Node3D) -> void:
		camera = cam

	## A lightning flash now (strength 0-1); also emits `lightning`.
	func flash(strength: float = 1.0) -> void:
		_flash_queue = [0.0, 0.18]
		_flash_strength = clampf(strength, 0.0, 1.0)
		lightning.emit(strength)

	## Turn rain on/off regardless of the preset (until the next set_preset).
	func set_rain(on: bool) -> void:
		_fx_visible("rain", on)

	## Turn snowfall on/off regardless of the preset (until the next set_preset).
	func set_snow(on: bool) -> void:
		_fx_visible("snow", on)

	## Number of visible cloud clusters (0-28).
	func set_clouds(count: int) -> void:
		_ensure_clouds()
		_clouds.multimesh.visible_instance_count = clampi(count, 0, Me.MAX_CLOUDS)
		_clouds.visible = count > 0

	## Approximate draw calls of the extras currently shown (the sky background not included).
	func draw_calls() -> int:
		var n := 0
		for node in [_stars, _clouds, _planet]:
			var n3 := node as Node3D
			if n3 != null and n3.visible:
				n += 1
		if _moon != null and _moon.visible:
			n += 2
		for k in _fx:
			var f: Node3D = _fx[k]
			if f.visible:
				n += 1
		return n

	# --- Per frame ----------------------------------------------------------------------------

	func _process(delta: float) -> void:
		var cam := camera
		if cam == null or not is_instance_valid(cam):
			cam = get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null and _dome != null:
			_dome.global_position = cam.global_position
		if _blend_len > 0.0:
			_blend_t += delta
			var t := clampf(_blend_t / _blend_len, 0.0, 1.0)
			var e := t * t * (3.0 - 2.0 * t)
			_cur = _lerp_values(_from, _to, e)
			if t >= 0.5 and _extras_target != "":
				_set_extras(Me.PRESETS[_extras_target])
				_extras_target = ""
			if t >= 1.0:
				_blend_len = 0.0
			_apply(_cur)
		if _clouds != null and _clouds.visible:
			_clouds.rotation.y += cloud_drift * delta
		# lightning
		if _lightning_on:
			_strike_t -= delta
			if _strike_t <= 0.0:
				_strike_t = randf_range(5.0, 12.0)
				flash(randf_range(0.6, 1.0))
		if _flash > 0.0 or not _flash_queue.is_empty():
			_flash = maxf(0.0, _flash - delta * 5.0)
			for i in _flash_queue.size():
				_flash_queue[i] -= delta
			if not _flash_queue.is_empty() and _flash_queue[0] <= 0.0:
				_flash_queue.remove_at(0)
				_flash = _flash_strength
			_apply(_cur)
		var shafts := _fx.get("shafts", null) as Node3D
		if shafts != null and shafts.visible:
			_shaft_t += delta
			shafts.rotation = Vector3(sin(_shaft_t * 0.3) * 0.04, _shaft_t * 0.02, cos(_shaft_t * 0.23) * 0.04)

	# --- Internals ----------------------------------------------------------------------------

	func _lerp_values(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
		var v := b.duplicate()
		for k in Me.COLOR_KEYS:
			var ca: Color = a.get(k, b[k])
			var cb: Color = b[k]
			v[k] = ca.lerp(cb, t)
		for k in Me.FLOAT_KEYS:
			v[k] = lerpf(float(a.get(k, b[k])), float(b[k]), t)
		v["az"] = rad_to_deg(lerp_angle(deg_to_rad(float(a.get("az", b["az"]))), deg_to_rad(float(b["az"])), t))
		return v

	func _apply(v: Dictionary) -> void:
		var fl := _flash
		var white := Color(0.85, 0.88, 1.0)
		var top: Color = v["top"]
		var hor: Color = v["horizon"]
		sky_mat.sky_top_color = top.lerp(white * 0.7, fl * 0.6)
		sky_mat.sky_horizon_color = hor.lerp(white, fl * 0.6)
		var gh: Color = v["ground_h"]
		var gb: Color = v["ground_b"]
		sky_mat.ground_horizon_color = gh
		sky_mat.ground_bottom_color = gb
		sky_mat.sky_curve = float(v["curve"])
		sky_mat.ground_curve = 0.06
		sky_mat.sun_angle_max = 20.0
		sky_mat.sun_curve = 0.1
		var sun_e := float(v["sun_e"])
		sun.light_color = v["sun"]
		sun.light_energy = sun_e + fl * 2.5
		sun.visible = sun_e > 0.01 or fl > 0.0
		sun.basis = Basis.from_euler(Vector3(deg_to_rad(-float(v["elev"])), deg_to_rad(float(v["az"])), 0.0), EULER_ORDER_YXZ)
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if float(v["disk"]) > 0.5 else DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		sun.shadow_enabled = not vr and sun_e > 0.3
		var amb: Color = v["amb"]
		env.ambient_light_color = amb.lerp(white, fl * 0.5)
		env.ambient_light_energy = float(v["amb_e"]) + fl * 0.8
		env.tonemap_exposure = float(v["exposure"])
		env.glow_enabled = not vr and float(v["glow"]) > 0.01
		env.glow_intensity = float(v["glow"])
		var fog_d := float(v["fog_d"])
		env.fog_enabled = not vr and fog_d > 0.0001
		env.fog_light_color = v["fog"]
		env.fog_density = fog_d
		env.fog_sky_affect = float(v["fog_sky"])
		if _clouds != null:
			var cc: Color = v["cloud_col"]
			var mat := _clouds.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = cc.lerp(white, fl * 0.5)
		if _moon != null and _moon.visible:
			_place_moon()

	## The moon sits where the (moon)light comes from, its face and halo turned to the dome centre.
	func _place_moon() -> void:
		var dir := sun.basis.z.normalized()
		_moon.position = dir * Me.DOME * 0.92
		_moon.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD, true)

	func _set_extras(p: Dictionary) -> void:
		var star_n := int(p["stars"])
		if star_n > 0:
			_ensure_stars()
			_stars.multimesh.visible_instance_count = mini(star_n, _stars.multimesh.instance_count)
		if _stars != null:
			_stars.visible = star_n > 0
		if bool(p["moon"]):
			_ensure_moon()
		if _moon != null:
			_moon.visible = bool(p["moon"])
			_place_moon()
		set_clouds(int(p["clouds"]))
		var fx: String = p["fx"]
		for k in ["rain", "snow", "bubbles", "dust", "fireflies", "shafts"]:
			_fx_visible(str(k), false)
		if _planet != null:
			_planet.visible = false
		match fx:
			"rain":
				_fx_visible("rain", true)
			"snow":
				_fx_visible("snow", true)
			"bubbles":
				_fx_visible("bubbles", true)
				_fx_visible("shafts", true)
			"dust":
				_fx_visible("dust", true)
			"fireflies":
				_fx_visible("fireflies", true)
			"planet":
				_ensure_planet()
				_planet.visible = true
		_lightning_on = preset == "stormy"

	func _fx_visible(fx_name: String, on: bool) -> void:
		if not on and not _fx.has(fx_name):
			return
		if not _fx.has(fx_name):
			var made := _make_fx(fx_name)
			if made == null:
				return
			_fx[fx_name] = made
			_dome.add_child(made)
		var node: Node3D = _fx[fx_name]
		node.visible = on
		var parts := node as CPUParticles3D
		if parts != null:
			parts.emitting = on

	func _make_fx(fx_name: String) -> Node3D:
		if fx_name == "shafts":
			return _make_shafts()
		var p := CPUParticles3D.new()
		p.name = fx_name.capitalize()
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		var scale_n := 0.5 if vr else 1.0
		match fx_name:
			"rain":
				p.amount = int(420 * scale_n)
				p.lifetime = 1.1
				p.emission_box_extents = Vector3(18, 1, 18)
				p.position = Vector3(0, 16, 0)
				p.direction = Vector3(0.08, -1, 0.04)
				p.spread = 2.0
				p.gravity = Vector3.ZERO
				p.initial_velocity_min = 24.0
				p.initial_velocity_max = 30.0
				p.mesh = _particle_mesh("rain")
				p.preprocess = 1.0
			"snow":
				p.amount = int(380 * scale_n)
				p.lifetime = 7.0
				p.emission_box_extents = Vector3(16, 1, 16)
				p.position = Vector3(0, 9, 0)
				p.direction = Vector3(0, -1, 0)
				p.spread = 25.0
				p.gravity = Vector3(0.15, -0.2, 0.0)
				p.initial_velocity_min = 1.0
				p.initial_velocity_max = 1.8
				p.scale_amount_min = 0.6
				p.scale_amount_max = 1.3
				p.mesh = _particle_mesh("snow")
				p.preprocess = 6.0
			"bubbles":
				p.amount = int(70 * scale_n)
				p.lifetime = 7.0
				p.emission_box_extents = Vector3(10, 2, 10)
				p.position = Vector3(0, -3, 0)
				p.direction = Vector3(0, 1, 0)
				p.spread = 12.0
				p.gravity = Vector3(0, 0.15, 0)
				p.initial_velocity_min = 0.5
				p.initial_velocity_max = 1.1
				p.scale_amount_min = 0.4
				p.scale_amount_max = 1.4
				p.mesh = _particle_mesh("bubble")
				p.preprocess = 6.0
			"dust":
				p.amount = int(50 * scale_n)
				p.lifetime = 8.0
				p.emission_box_extents = Vector3(6, 2.5, 6)
				p.position = Vector3(0, 1.5, 0)
				p.direction = Vector3(0, 1, 0)
				p.spread = 180.0
				p.gravity = Vector3(0, 0.01, 0)
				p.initial_velocity_min = 0.03
				p.initial_velocity_max = 0.12
				p.scale_amount_min = 0.5
				p.scale_amount_max = 1.2
				p.mesh = _particle_mesh("dust")
				p.preprocess = 6.0
			"fireflies":
				p.amount = int(36 * scale_n)
				p.lifetime = 6.0
				p.emission_box_extents = Vector3(9, 1.2, 9)
				p.position = Vector3(0, 1.0, 0)
				p.direction = Vector3(0, 1, 0)
				p.spread = 180.0
				p.gravity = Vector3.ZERO
				p.initial_velocity_min = 0.15
				p.initial_velocity_max = 0.4
				p.damping_min = 0.05
				p.damping_max = 0.1
				p.mesh = _particle_mesh("firefly")
				p.preprocess = 4.0
			_:
				return null
		return p

	## Small cached particle meshes with their own materials.
	func _particle_mesh(kind: String) -> Mesh:
		var key := "sky_part_%s_v1" % kind
		var cached := ResCache.fetch(key) as Mesh
		if cached != null:
			return cached
		var b := MeshKit.Builder.new()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.disable_receive_shadows = true
		match kind:
			"rain":
				b.box(Vector3(0.018, 0.55, 0.018), Transform3D.IDENTITY, Color(0.75, 0.82, 0.95, 0.45))
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"snow":
				b.sphere(0.05, Transform3D.IDENTITY, Color(1, 1, 1), 5)
			"bubble":
				b.sphere(0.06, Transform3D.IDENTITY, Color(0.75, 0.95, 1.0, 0.45), 6)
				b.sphere(0.018, MeshKit.at(Vector3(-0.025, 0.025, 0.045)), Color(1, 1, 1, 0.9), 4)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"dust":
				b.sphere(0.012, Transform3D.IDENTITY, Color(1.0, 0.92, 0.75, 0.6), 4)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"firefly":
				b.sphere(0.035, Transform3D.IDENTITY, Color(0.75, 1.0, 0.45), 5)
				mat.albedo_color = Color(1.6, 1.6, 1.6)
		var m := b.build(mat)
		ResCache.put(key, m)
		return m

	func _make_shafts() -> Node3D:
		var key := "sky_shafts_v1"
		var mesh := ResCache.fetch(key) as Mesh
		if mesh == null:
			var b := MeshKit.Builder.new()
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in 9:
				var a := rng.randf() * TAU
				var r := rng.randf_range(3.0, 16.0)
				var pos := Vector3(cos(a) * r, 8.0, sin(a) * r)
				var w := rng.randf_range(0.6, 1.6)
				b.cylinder(w, w * 1.8, 26.0, MeshKit.at(pos, Vector3.ONE, Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(0.1, 0.3))),
					Color(0.1, 0.2, 0.2) * rng.randf_range(0.6, 1.0), 6, false, false)
			mesh = b.build(MeshKit.additive_material())
			ResCache.put(key, mesh)
		var mi := MeshInstance3D.new()
		mi.name = "Shafts"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	func _sky_material(boost: float) -> StandardMaterial3D:
		var key := "sky_mat_%.2f" % boost
		var cached := ResCache.fetch(key) as StandardMaterial3D
		if cached != null:
			return cached
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(boost, boost, boost)
		m.disable_fog = true
		m.disable_receive_shadows = true
		ResCache.put(key, m)
		return m

	func _ensure_stars() -> void:
		if _stars != null:
			return
		var key := "sky_star_mesh_v1"
		var star := ResCache.fetch(key) as Mesh
		if star == null:
			var b := MeshKit.Builder.new()
			b.sphere(1.0, Transform3D.IDENTITY, Color(1, 1, 1), 4)
			star = b.build(_sky_material(1.4))
			ResCache.put(key, star)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2024
		var xfs: Array = []
		var cols := PackedColorArray()
		var tints: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.95, 0.8), Color(0.8, 0.88, 1.0), Color(1.0, 0.85, 0.85)]
		for i in 450:
			var a := rng.randf() * TAU
			var el := asin(rng.randf_range(0.02, 1.0))
			var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
			var s := rng.randf_range(0.6, 1.6) * (2.4 if rng.randf() < 0.06 else 1.0)
			xfs.append(Transform3D(Basis().scaled(Vector3.ONE * s), dir * Me.DOME))
			var c: Color = tints[rng.randi() % tints.size()]
			cols.append(c * rng.randf_range(0.55, 1.0))
		_stars = MeshKit.scatter(star, xfs, cols, PackedColorArray(), false)
		_stars.name = "Stars"
		_dome.add_child(_stars)

	func _ensure_moon() -> void:
		if _moon != null:
			return
		var key := "sky_moon_v1"
		var mesh := ResCache.fetch(key) as Mesh
		if mesh == null:
			var b := MeshKit.Builder.new()
			b.sphere(26.0, Transform3D.IDENTITY, Color(1.0, 0.97, 0.86), 16)
			var craters: Array[Vector4] = [Vector4(-8, 6, 23, 5), Vector4(7, -5, 23.5, 4), Vector4(4, 10, 22, 3), Vector4(-6, -9, 23, 3.5)]
			for c in craters:
				b.sphere(c.w, MeshKit.at(Vector3(c.x, c.y, c.z), Vector3(1, 1, 0.35)), Color(0.88, 0.85, 0.76), 8)
			mesh = b.build(_sky_material(1.15))
			ResCache.put(key, mesh)
		var hkey := "sky_halo_v1"
		var halo_mesh := ResCache.fetch(hkey) as Mesh
		if halo_mesh == null:
			var hb := MeshKit.Builder.new()
			for i in 3:
				hb.disc(40.0 + i * 22.0, MeshKit.at(Vector3(0, 0, -2.0 - i), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.07, 0.075, 0.1), 24)
			halo_mesh = hb.build(MeshKit.additive_material())
			ResCache.put(hkey, halo_mesh)
		_moon = Node3D.new()
		_moon.name = "Moon"
		_dome.add_child(_moon)
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_moon.add_child(body)
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		halo.mesh = halo_mesh
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_moon.add_child(halo)

	func _ensure_clouds() -> void:
		if _clouds != null:
			return
		var cloud := MeshKit.prop("cloud")
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var xfs: Array = []
		for i in Me.MAX_CLOUDS:
			var a := TAU * float(i) / Me.MAX_CLOUDS + rng.randf_range(-0.12, 0.12)
			var r := rng.randf_range(230.0, 430.0)
			var s := rng.randf_range(10.0, 22.0)
			var pos := Vector3(cos(a) * r, rng.randf_range(55.0, 140.0), sin(a) * r)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.0), s)), pos))
		_clouds = MeshKit.scatter(cloud, xfs, PackedColorArray(), PackedColorArray(), false)
		_clouds.name = "Clouds"
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.disable_receive_shadows = true
		m.emission_enabled = true
		m.emission = Color(0.35, 0.37, 0.42)
		m.emission_energy_multiplier = 0.6
		_clouds.material_override = m
		_dome.add_child(_clouds)

	func _ensure_planet() -> void:
		if _planet != null:
			return
		var key := "sky_planet_v1"
		var mesh := ResCache.fetch(key) as Mesh
		if mesh == null:
			var b := MeshKit.Builder.new()
			b.sphere(90.0, Transform3D.IDENTITY, Color(0.95, 0.62, 0.48), 20)
			for i in 3:
				var y := -40.0 + i * 38.0
				var rr := sqrt(maxf(0.0, 90.0 * 90.0 - y * y))
				b.cylinder(rr + 0.6, rr + 0.6, 9.0, MeshKit.at(Vector3(0, y, 0)), Color(0.85, 0.48, 0.42) if i != 1 else Color(1.0, 0.82, 0.6), 20, false, false)
			b.torus(150.0, 9.0, MeshKit.at(Vector3.ZERO, Vector3(1, 0.06, 1)), Color(0.82, 0.76, 0.95), 20, 4)
			b.torus(126.0, 6.0, MeshKit.at(Vector3.ZERO, Vector3(1, 0.05, 1)), Color(0.65, 0.6, 0.85), 20, 4)
			mesh = b.build()
			ResCache.put(key, mesh)
		_planet = MeshInstance3D.new()
		_planet.name = "Planet"
		_planet.mesh = mesh
		_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_planet.position = Vector3(-0.55, 0.32, -0.77).normalized() * Me.DOME * 0.85
		_planet.rotation = Vector3(0.35, 0.4, 0.25)
		_dome.add_child(_planet)
