extends Node3D
## PICK ORBS (shared by every game with picture-first picks: Duo Arena, Snowball Blitz, Elemental Bender's altar,
## Mech Titans' pods ...): a row of picks, each with a big picture and a short name under it. Players SHOOT / THROW
## at one (an Orb body: hit() -> on_hit(index, by)), WALK INTO one (touches() / at_point()), or a game's own
## projectiles ask nearest_hit(). take(i, colour) / show_takers() put little dots in a player's colour round it. The
## default pick (the middle one unless opts.def says) glows brightest: the game takes it for whoever doesn't choose
## in time (little ones are never stuck).
##   var orbs := PickOrbs.new(); add_child(orbs); orbs.on_hit = func(i, by): ...
##   orbs.show_orbs(stage, [{id, name, pic, color}, ...], origin, gap, y, opts)   # a row along +X centred on origin
##   orbs.take(i, color) -> the orb's position (Vector3.INF if none) for the game's own burst
##   orbs.show_takers({slot: index}, {slot: Color})   # the same, idempotent (rebuild from net state every frame)
##   orbs.touches(players) -> [[i, player], ...]  (players: .active, .is_down, .global_position)
##   orbs.at_point(p) -> index or -1      orbs.nearest_hit(pos, radius) -> index or -1      orbs.clear()
## (show() is Node3D's own, so it's show_orbs.)
## A GAME'S OWN LOOK goes through opts (never its own pick code: tests/shared_picks_test.gd), e.g. stone stands
## with spinning mesh pictures (Elemental Bender) or giant light pods (Mech Titans):
##   at: [Vector3] (places instead of a row)   def: the default index   scale: everything bigger (1)
##   body: func(entry, is_default) -> Node3D (the stand; replaces the glass ball; a child named "Glow" throbs)
##   icon: func(entry) -> Node3D (the picture; replaces the StoryCard billboard)   spin: icon turn speed (rad/s)
##   icon_y, icon_scale, bob (m), label_y, label_px, font, two_lines (one word a line), dot_r, dot_y, dot_size
##   touch (m, walking in), hit_r / hit_height (shots), max_y (at_point ignores players above), group (node group),
##   pop (the picks grow in one after another), punch (picture pops this much on a take)
## MODES: the GENTLE / BRAVE / HARD team pick every game uses (one place: names, pictures, colours, lines). Games
## that had their own ids keep them in saves and net state; ALIASES maps them (mega / heroic -> hard, zoom -> brave).

const StoryCard := preload("res://core/story_card.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
## Every orb is in this group while it shows: VR cards, banners and words move clear of it (UiKit.vr_dodge) and
## core/vr_view_check.gd fails a VR bot whose panel covers one. A game never lifts its orbs out of a card's way.
const KEEP_CLEAR := preload("res://core/vr_view_check.gd").KEEP_CLEAR

const MODES: Array[Dictionary] = [
	{"id": "gentle", "name": "GENTLE", "pic": "heart", "color": Color(0.45, 1.0, 0.55), "waves": 0, "fx": []},
	{"id": "brave", "name": "BRAVE", "pic": "star", "color": Color(0.35, 0.75, 1.0), "waves": 0, "fx": []},
	{"id": "hard", "name": "HARD", "pic": "fireball", "color": Color(1.0, 0.35, 0.25), "waves": 0, "fx": []},
]
const MODE_IDS: Array[String] = ["gentle", "brave", "hard"]
const ALIASES := {"mega": "hard", "heroic": "hard", "zoom": "brave", "normal": "brave"}
const MODE_LINES := {"gentle": "Gentle! Nice and easy!", "brave": "Brave! Let's go!", "hard": "HARD! Wow!"}
const BALL_R := 0.6
const HIT_R := 0.75
const TOUCH := 1.3
const PIC_PX := 192

var on_hit: Callable  # (index, by) when an Orb body is hit by something that knows who threw it
var orbs: Array = []
var stage := ""
var entries: Array = []
var opts := {}
var base_y := 1.4
var collision_layer := 4
var _t := 0.0


## An orb: bullets / shots that call hit(...) on bodies pick it (the game decides). Games whose shots test distance
## read hit_radius / hit_height (from the orb's foot) and skip `dead` things.
class Orb extends StaticBody3D:
	var owner_row
	var index := 0
	var id := ""
	var ball: Node3D  # the stand (glass ball by default)
	var icon: Node3D  # the picture
	var dots: Node3D
	var hit_radius := 0.75
	var hit_height := 1.7
	var dead := false
	var shown_takers := ""

	func hit(_dmg = 0.0, _dir = Vector3.ZERO, _k = 1.0, by = null) -> void:
		if owner_row != null and by != null and owner_row.on_hit.is_valid():
			owner_row.on_hit.call(index, by)


## The MODE entry for an id or an alias ({} if none).
static func mode(id: String) -> Dictionary:
	var want := String(ALIASES.get(id, id))
	for d in MODES:
		if String(d.id) == want:
			return d
	return {}


static func mode_color(id: String, fallback: Color = Color.WHITE) -> Color:
	return mode(id).get("color", fallback)


static func mode_name(id: String) -> String:
	return String(mode(id).get("name", id.to_upper()))


## The mode ids with `middle` (the family's last mode) in the middle.
static func mode_ids(middle: String = "brave") -> Array:
	var ids: Array = MODE_IDS.duplicate()
	if ids.has(middle):
		ids.erase(middle)
		ids.insert(ids.size() / 2, middle)
	return ids


static func spot(i: int, n: int, origin: Vector3, gap: float, y: float) -> Vector3:
	return origin + Vector3((i - (n - 1) * 0.5) * gap, y, 0.0)


func _ready() -> void:
	if name.is_empty() or name.begins_with("@"):
		name = "PickOrbs"


func _o(k: String, def: Variant) -> Variant:
	return opts.get(k, def)


func _custom() -> bool:
	return opts.has("body")


func show_orbs(new_stage: String, list: Array, origin: Vector3, gap: float = 2.6, y: float = 1.4, o: Dictionary = {}) -> void:
	clear()
	stage = new_stage
	entries = list.duplicate(true)
	opts = o.duplicate()
	base_y = origin.y + y
	var sc := float(_o("scale", 1.0))
	var mid := int(_o("def", list.size() / 2))
	var at: Array = _o("at", [])
	for i in list.size():
		var d: Dictionary = list[i]
		var col: Color = d.get("color", Color.WHITE)
		var o2 := Orb.new()
		o2.owner_row = self
		o2.index = i
		o2.id = String(d.get("id", ""))
		o2.name = "Orb%d" % i
		o2.hit_radius = float(_o("hit_r", HIT_R)) * sc
		o2.hit_height = float(_o("hit_height", 1.7)) * sc
		o2.collision_layer = collision_layer
		o2.collision_mask = 0
		o2.add_to_group(KEEP_CLEAR)
		if String(_o("group", "")) != "":
			o2.add_to_group(String(_o("group", "")))
		if collision_layer != 0:
			var cs := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = HIT_R * sc
			cs.shape = sh
			cs.position.y = float(_o("icon_y", 0.0)) * sc
			o2.add_child(cs)
		if _custom():
			o2.ball = (_o("body", Callable()) as Callable).call(d, i == mid)
		else:
			o2.ball = _glass_ball(col, i == mid)
		o2.add_child(o2.ball)
		o2.icon = (_o("icon", Callable()) as Callable).call(d) if opts.has("icon") else _picture(String(d.get("pic", "star")), col)
		o2.icon.scale = Vector3.ONE * float(_o("icon_scale", 1.0)) * sc
		o2.icon.position.y = float(_o("icon_y", 0.0)) * sc
		o2.add_child(o2.icon)
		var l := Label3D.new()
		l.name = "Name"
		l.text = String(d.get("name", o2.id))
		if bool(_o("two_lines", false)):
			l.text = l.text.replace(" ", "\n")
		l.font_size = int(_o("font", 64))
		l.outline_size = 14
		l.pixel_size = float(_o("label_px", 0.005)) * sc
		l.modulate = col.lightened(0.4)
		l.outline_modulate = Color(0.05, 0.05, 0.1)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, float(_o("label_y", -0.95)) * sc, 0)
		o2.add_child(l)
		o2.dots = Node3D.new()
		o2.dots.position.y = float(_o("dot_y", 0.0 if not _custom() else float(_o("icon_y", 0.0)))) * sc
		o2.add_child(o2.dots)
		o2.position = spot(i, list.size(), origin, gap, y)
		add_child(o2)
		if i < at.size():  # places in the world (this node may sit anywhere)
			if o2.is_inside_tree():
				o2.global_position = (at[i] as Vector3) + Vector3(0, y, 0)
			else:
				o2.position = (at[i] as Vector3) + Vector3(0, y, 0)
		orbs.append(o2)
		if bool(_o("pop", false)):
			o2.scale = Vector3.ONE * 0.01
			create_tween().tween_property(o2, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.12)


func _glass_ball(col: Color, is_default: bool) -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	ball.mesh = sm
	var mat := MeshKit.material(col, 2.6 if is_default else 1.2).duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	mat.render_priority = preload("res://core/ui_kit.gd").VR_PRIO_UNDER_UI  # see-through: under VR cards (core/vr_view_check.gd "washed out")
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * float(_o("scale", 1.0))
	return ball


## A billboard picture (StoryCard picture drawn into a small viewport).
func _picture(pic: String, col: Color) -> Sprite3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(PIC_PX, PIC_PX)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(StoryCard.picture(pic, PIC_PX, col))
	var s := Sprite3D.new()
	s.add_child(vp)
	s.texture = vp.get_texture()
	s.pixel_size = 1.0 / PIC_PX
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.render_priority = 2
	return s


func clear() -> void:
	for o in orbs:
		if is_instance_valid(o):
			o.queue_free()
	orbs.clear()
	entries.clear()
	stage = ""


func showing() -> bool:
	return not orbs.is_empty()


func _dot(color: Color) -> MeshInstance3D:
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r := float(_o("dot_size", 0.12)) * float(_o("scale", 1.0))
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	dot.mesh = sm
	dot.material_override = MeshKit.material(color, 3.0)
	return dot


func _punch(o: Orb) -> void:
	var target: Node3D = o.icon if _custom() else o.ball
	var base := target.scale
	target.scale = base * float(_o("punch", 1.25))
	if _custom():
		var tw := create_tween()
		tw.tween_property(target, "scale", base, 0.3)


## Every machine: someone took orb i (a dot in their colour circles it). Returns where it is (INF: no orb).
func take(i: int, color: Color) -> Vector3:
	if i < 0 or i >= orbs.size() or not is_instance_valid(orbs[i]):
		return Vector3.INF
	var o: Orb = orbs[i]
	o.dots.add_child(_dot(color))
	_punch(o)
	return o.global_position if o.is_inside_tree() else o.position


## Every machine: show who took which orb from shared state. taken: {slot: orb index}, colors: {slot: Color}.
## Cheap to call every frame (only redraws an orb whose takers changed).
func show_takers(taken: Dictionary, colors: Dictionary) -> void:
	for o in orbs:
		var st: Orb = o
		if not is_instance_valid(st):
			continue
		var who: Array = []
		for slot in taken:
			if int(taken[slot]) == st.index:
				who.append(int(slot))
		who.sort()
		var key := str(who)
		if key == st.shown_takers:
			continue
		var more := who.size() > st.dots.get_child_count()
		st.shown_takers = key
		for c in st.dots.get_children():
			st.dots.remove_child(c)
			c.queue_free()
		for s in who:
			st.dots.add_child(_dot(colors.get(s, Color.WHITE)))
		if more:
			_punch(st)


## The colour of orb i (white if none).
func color_of(i: int) -> Color:
	return entries[i].get("color", Color.WHITE) if i >= 0 and i < entries.size() else Color.WHITE


## Host: players walking into an orb. Returns [[orb index, player], ...].
func touches(players: Array) -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for p in players:
		if not p.active or p.is_down or not p.is_inside_tree():
			continue
		var i := at_point(p.global_position)
		if i >= 0:
			out.append([i, p])
	return out


## Host: the orb a point (a player's feet, a vehicle) is in (-1 = none). r: reach (default opts.touch).
func at_point(p: Vector3, r: float = -1.0) -> int:
	var reach := r if r >= 0.0 else float(_o("touch", TOUCH)) * float(_o("scale", 1.0))
	var max_y := float(_o("max_y", INF))
	for o in orbs:
		if not is_instance_valid(o) or not o.is_inside_tree():
			continue
		if p.y > max_y:
			continue
		if Vector2(p.x - o.global_position.x, p.z - o.global_position.z).length() < reach:
			return o.index
	return -1


## A projectile (not a physics body) at pos with radius r: the orb it hits, or -1.
func nearest_hit(pos: Vector3, r: float) -> int:
	var best := -1
	var best_d := INF
	for o in orbs:
		if not is_instance_valid(o) or not o.is_inside_tree():
			continue
		var c: Vector3 = o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else o.global_position
		var dd: float = c.distance_to(pos)
		if dd < float(o.hit_radius) + r and dd < best_d:
			best_d = dd
			best = o.index
	return best


func _process(delta: float) -> void:
	_t += delta
	var custom := _custom()
	var sc := float(_o("scale", 1.0))
	var bob := float(_o("bob", 0.12)) * sc
	var spin := float(_o("spin", 0.0))
	var icon_y := float(_o("icon_y", 0.0)) * sc
	var dot_r := float(_o("dot_r", 0.85)) * sc
	for o in orbs:
		if not is_instance_valid(o):
			continue
		if custom:  # the stand stays on the ground: the picture bobs and spins above it
			o.icon.position.y = icon_y + bob * sin(_t * 2.0 + o.index)
			o.icon.rotation.y += delta * spin
			var glow := o.ball.get_node_or_null("Glow") as Node3D
			if glow != null:
				var s := 1.0 + 0.06 * sin(_t * 4.0 + o.index * 1.3)
				glow.scale = Vector3(s, 1.0, s)
		else:
			o.position.y = base_y + bob * sin(_t * 2.2 + o.index)
			o.ball.scale = o.ball.scale.lerp(Vector3.ONE * sc, minf(1.0, delta * 4.0))
			if spin != 0.0:
				o.icon.rotation.y += delta * spin
		var n: int = o.dots.get_child_count()
		for j in n:
			var a := _t * 2.0 + j * TAU / maxf(1.0, n)
			(o.dots.get_child(j) as Node3D).position = Vector3(cos(a) * dot_r, 0.25 * sc * sin(a * 2.0), sin(a) * dot_r)