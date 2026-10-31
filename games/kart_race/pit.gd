extends Node3D
## KART RACE PIT STOP: before every cup (after TODAY'S TRACK and after each cup / tour place) the drivers line up on
## the track they just raced and drive through three rows of picture GATES on the start straight (where the practice
## rings were), one lane per choice. No words, no menus: drive through the picture you want.
##   row 1 KART:  LIGHT / MEDIUM / HEAVY kart (+ a SPANNER lane once a part is unlocked: fits your next part)
##   row 2 SPEED: GENTLE (snail) / ZOOM (rocket, 150cc) / TIME TRIAL (clock: no CPUs, race your best lap)
##   row 3 CUP:   BOLT'S TOUR / CANDY / JUNGLE / ICE / SPACE cup
## Row 1 is everyone's own pick (it changes your kart at once). Rows 2 and 3 are votes: the lane most people drove
## through wins (a tie goes to whoever was first). Nobody has to do anything: after PIT_TIME (or once every person
## has driven through row 3) it starts, keeping last time's speed and going on to the next cup.
## The host runs it (main.gd calls start / update); every machine draws the gates from the same rows (snapshot), and
## glows a lane when someone picks it (main.gd pit_flash events).

const StoryCard := preload("res://core/story_card.gd")
const UiKit := preload("res://core/ui_kit.gd")

const ROW_D: Array[float] = [22.0, 44.0, 66.0]  # metres past the start line (the practice rings' clear stretch)
const PIT_TIME := 32.0
const ROAD := 11.0  # track.gd WIDTH: the lanes split it evenly
const SIGN_PX := 192

var main
var rows: Array = []  # [{"kind": "kart" / "speed" / "cup", "lanes": [[id, picture, Color], ...]}]
var built_key := ""
var built_track := -1
var t := 0.0
var last_total := {}  # kart index -> total last frame (host)
var picks := {}  # kart index -> {kind: id}
var votes := {}  # kind -> {id: [count, first time]}
var done := {}  # kart index -> true once through row 3
var stripes := {}  # "row/lane" -> StandardMaterial3D (glows when picked)
var glow := {}  # "row/lane" -> seconds left of the pick glow
var viewports: Array[SubViewport] = []


## Host: begin a pit stop with these rows.
func start(r: Array) -> void:
	rows = r
	t = 0.0
	picks.clear()
	votes.clear()
	done.clear()
	last_total.clear()
	show_rows(rows)


func stop() -> void:
	rows = []
	show_rows([])


## Host, every frame of the pit stop: who drove through which lane. Returns true when the pit stop is over.
func update(dt: float, humans: Array) -> bool:
	t += dt
	for k in humans:
		var prev: float = last_total.get(k.index, k.total)
		last_total[k.index] = k.total
		for ri in rows.size():
			var d: float = ROW_D[ri]
			if prev < d and k.total >= d:
				var lanes: Array = rows[ri].lanes
				var lane := clampi(int(floorf((k.lat + ROAD * 0.5) / (ROAD / lanes.size()))), 0, lanes.size() - 1)
				_pick(k, ri, lane)
	var all_done := not humans.is_empty()
	for k in humans:
		if not done.has(k.index):
			all_done = false
	return t > PIT_TIME or (all_done and t > 3.0)


func _pick(k, ri: int, lane: int) -> void:
	var row: Dictionary = rows[ri]
	var id := String(row.lanes[lane][0])
	var kind := String(row.kind)
	if not picks.has(k.index):
		picks[k.index] = {}
	picks[k.index][kind] = id
	if kind != "kart":
		if not votes.has(kind):
			votes[kind] = {}
		var v: Array = votes[kind].get(id, [0, t])
		v[0] = int(v[0]) + 1
		votes[kind][id] = v
	if ri == rows.size() - 1:
		done[k.index] = true
	main.pit_pick(k, kind, id, ri, lane)


## The winning id of a vote ("" when nobody voted).
func winner(kind: String) -> String:
	var best := ""
	var bc := 0
	var bt := INF
	for id in votes.get(kind, {}):
		var v: Array = votes[kind][id]
		if int(v[0]) > bc or (int(v[0]) == bc and float(v[1]) < bt):
			best = id
			bc = int(v[0])
			bt = float(v[1])
	return best


# --- Every machine: the gates --------------------------------------------------------------

func show_rows(r: Array) -> void:
	var key := var_to_str(r)
	if key == built_key and main.track.build_n == built_track:
		return
	built_key = key
	built_track = main.track.build_n
	for c in get_children():
		c.queue_free()
	stripes.clear()
	glow.clear()
	viewports.clear()
	for ri in r.size():
		_build_row(ri, r[ri])


func flash(ri: int, lane: int) -> void:
	glow["%d/%d" % [ri, lane]] = 1.2


func _process(delta: float) -> void:
	var ms := Time.get_ticks_msec()
	for key in stripes:
		var m: StandardMaterial3D = stripes[key]
		var g: float = glow.get(key, 0.0)
		if g > 0.0:
			glow[key] = g - delta
		m.emission_energy_multiplier = 0.6 + 0.25 * sin(ms * 0.006 + float(key.hash() % 7)) + g * 2.5


func _build_row(ri: int, row: Dictionary) -> void:
	var tr = main.track
	var lanes: Array = row.lanes
	var n := lanes.size()
	var w := ROAD / n
	var gp: Array = tr.point_at(ROW_D[ri], 0.0)
	var root := Node3D.new()
	root.name = "Row%d" % ri
	add_child(root)
	root.position = gp[0]
	root.rotation.y = float(gp[1])
	var post_mat: StandardMaterial3D = main.make_material(Color(1, 1, 1), 0.2)
	var beam_mat: StandardMaterial3D = main.make_material(Color(0.2, 0.22, 0.3), 0.0)
	for k in n + 1:
		var post := MeshInstance3D.new()
		post.mesh = main.cyl_mesh(0.12, 0.14, 4.6, 8)
		post.material_override = post_mat
		post.position = Vector3(-ROAD * 0.5 + k * w, 2.3, 0.0)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(post)
	var beam := MeshInstance3D.new()
	beam.mesh = main.box_mesh(Vector3(ROAD + 0.4, 0.3, 0.3))
	beam.material_override = beam_mat
	beam.position = Vector3(0, 4.6, 0)
	root.add_child(beam)
	for li in n:
		var lane: Array = lanes[li]
		var col: Color = lane[2]
		var cx := -ROAD * 0.5 + (li + 0.5) * w
		# A glowing stripe across the lane (it flashes when someone picks it).
		var sm := StandardMaterial3D.new()
		sm.albedo_color = col
		sm.emission_enabled = true
		sm.emission = col
		sm.emission_energy_multiplier = 0.6
		var stripe := MeshInstance3D.new()
		stripe.mesh = main.box_mesh(Vector3(w - 0.25, 0.04, 1.4))
		stripe.material_override = sm
		stripe.position = Vector3(cx, 0.06, 0)
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(stripe)
		stripes["%d/%d" % [ri, li]] = sm
		# The picture sign on the beam, facing the karts coming up the road (+Z is back towards the grid).
		var sign := _sign(String(lane[1]), col)
		var size := minf(w * 0.92, 2.6)
		sign.pixel_size = size / SIGN_PX
		sign.position = Vector3(cx, 4.75 + size * 0.5, 0.2)
		root.add_child(sign)


## A round picture disc (core/story_card.gd pictures) drawn into a little SubViewport on a Sprite3D.
func _sign(kind: String, col: Color) -> Sprite3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIGN_PX, SIGN_PX)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var disc := PanelContainer.new()
	disc.add_theme_stylebox_override("panel", UiKit.stylebox(col.darkened(0.5), 1.0, 200.0, col.lightened(0.35), 8.0, 0.0, Vector2(10, 10)))
	disc.size = Vector2(SIGN_PX, SIGN_PX)
	disc.add_child(StoryCard.picture(kind, SIGN_PX * 0.78, col.lightened(0.15)))
	vp.add_child(disc)
	var s := Sprite3D.new()
	s.name = "Sign_" + kind
	s.add_child(vp)
	s.texture = vp.get_texture()
	s.shaded = false
	s.double_sided = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewports.append(vp)
	return s
