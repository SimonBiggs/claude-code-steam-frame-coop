extends Node3D
## PICK ORBS (shared by every game with picture-first picks: Duo Arena, Snowball Blitz, ...): glowing balls
## floating in a row, each with a big billboard picture (StoryCard) and a short name under it. Players SHOOT /
## THROW at one (an Orb body: hit() -> on_hit(index, by)), or WALK INTO one (touches()), or a game's own
## projectiles ask nearest_hit(). take(i, colour) adds a little dot in that colour circling it. The middle orb
## glows brightest: the game takes it for whoever doesn't choose in time (little ones are never stuck).
##   var orbs := PickOrbs.new(); add_child(orbs); orbs.on_hit = func(i, by): ...
##   orbs.show_orbs(stage, [{id, name, pic, color}, ...], origin, gap, y)   # a row along +X centred on origin
##   orbs.take(i, color) -> the orb's position (Vector3.INF if none) for the game's own burst
##   orbs.touches(players) -> [[i, player], ...]  (players: .active, .is_down, .global_position)
##   orbs.nearest_hit(pos, radius) -> index or -1      orbs.clear()
## (show() is Node3D's own, so it's show_orbs.)
## MODES: the GENTLE / BRAVE / HARD team pick every game uses (one place: names, pictures, colours).

const StoryCard := preload("res://core/story_card.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const MODES: Array[Dictionary] = [
	{"id": "gentle", "name": "GENTLE", "pic": "heart", "color": Color(0.45, 1.0, 0.55), "waves": 0, "fx": []},
	{"id": "brave", "name": "BRAVE", "pic": "star", "color": Color(0.35, 0.75, 1.0), "waves": 0, "fx": []},
	{"id": "hard", "name": "HARD", "pic": "fireball", "color": Color(1.0, 0.35, 0.25), "waves": 0, "fx": []},
]
const MODE_IDS: Array[String] = ["gentle", "brave", "hard"]
const MODE_LINES := {"gentle": "Gentle! Nice and easy!", "brave": "Brave! Let's go!", "hard": "HARD! Wow!"}
const BALL_R := 0.6
const HIT_R := 0.75
const TOUCH := 1.3
const PIC_PX := 192

var on_hit: Callable  # (index, by) when an Orb body is hit by something that knows who threw it
var orbs: Array = []
var stage := ""
var entries: Array = []
var base_y := 1.4
var collision_layer := 4
var _t := 0.0


## An orb: bullets / shots that call hit(...) on bodies pick it (the game decides).
class Orb extends StaticBody3D:
	var owner_row
	var index := 0
	var id := ""
	var ball: MeshInstance3D
	var dots: Node3D

	func hit(_dmg = 0.0, _dir = Vector3.ZERO, _k = 1.0, by = null) -> void:
		if owner_row != null and by != null and owner_row.on_hit.is_valid():
			owner_row.on_hit.call(index, by)


## The MODE entry for an id ({} if none).
static func mode(id: String) -> Dictionary:
	for d in MODES:
		if String(d.id) == id:
			return d
	return {}


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


func show_orbs(new_stage: String, list: Array, origin: Vector3, gap: float = 2.6, y: float = 1.4) -> void:
	clear()
	stage = new_stage
	entries = list.duplicate(true)
	base_y = origin.y + y
	var mid := list.size() / 2
	for i in list.size():
		var d: Dictionary = list[i]
		var col: Color = d.get("color", Color.WHITE)
		var o := Orb.new()
		o.owner_row = self
		o.index = i
		o.id = String(d.get("id", ""))
		o.name = "Orb%d" % i
		o.collision_layer = collision_layer
		o.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = HIT_R
		cs.shape = sh
		o.add_child(cs)
		o.ball = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = BALL_R
		sm.height = BALL_R * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		o.ball.mesh = sm
		var mat := MeshKit.material(col, 2.6 if i == mid else 1.2).duplicate() as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.55
		o.ball.material_override = mat
		o.ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.add_child(o.ball)
		o.add_child(_picture(String(d.get("pic", "star")), col))
		var l := Label3D.new()
		l.text = String(d.get("name", o.id))
		l.font_size = 64
		l.outline_size = 14
		l.pixel_size = 0.005
		l.modulate = col.lightened(0.4)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, -0.95, 0)
		o.add_child(l)
		o.dots = Node3D.new()
		o.add_child(o.dots)
		o.position = spot(i, list.size(), origin, gap, y)
		add_child(o)
		orbs.append(o)


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


## Every machine: someone took orb i (a dot in their colour circles it). Returns where it is (INF: no orb).
func take(i: int, color: Color) -> Vector3:
	if i < 0 or i >= orbs.size() or not is_instance_valid(orbs[i]):
		return Vector3.INF
	var o: Orb = orbs[i]
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	dot.mesh = sm
	dot.material_override = MeshKit.material(color, 3.0)
	o.dots.add_child(dot)
	o.ball.scale = Vector3.ONE * 1.25
	return o.global_position if o.is_inside_tree() else o.position


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
		for o in orbs:
			if not is_instance_valid(o) or not o.is_inside_tree():
				continue
			var d := Vector2(p.global_position.x - o.global_position.x, p.global_position.z - o.global_position.z)
			if d.length() < TOUCH:
				out.append([o.index, p])
	return out


## A projectile (not a physics body) at pos with radius r: the orb it hits, or -1.
func nearest_hit(pos: Vector3, r: float) -> int:
	var best := -1
	var best_d := INF
	for o in orbs:
		if not is_instance_valid(o) or not o.is_inside_tree():
			continue
		var dd: float = o.global_position.distance_to(pos)
		if dd < HIT_R + r and dd < best_d:
			best_d = dd
			best = o.index
	return best


func _process(delta: float) -> void:
	_t += delta
	for o in orbs:
		if not is_instance_valid(o):
			continue
		o.position.y = base_y + 0.12 * sin(_t * 2.2 + o.index)
		o.ball.scale = o.ball.scale.lerp(Vector3.ONE, minf(1.0, delta * 4.0))
		var n: int = o.dots.get_child_count()
		for j in n:
			var a := _t * 2.0 + j * TAU / maxf(1.0, n)
			(o.dots.get_child(j) as Node3D).position = Vector3(cos(a) * 0.85, 0.25 * sin(a * 2.0), sin(a) * 0.85)