extends Node3D
## PARTY BOARD: Mango's warned BOARD SURPRISES (deep.gd zones). Every machine draws the "hz" state (the host sets it
## when a round starts and clears it once the surprises went off at the round's end), steady from the tell until then:
##   ROCK    an orange disc on one space (core/warn_rings.gd circle, disc style); when the round's last turn is over a
##           rock drops out of the sky onto it.
##   SPLASH  cyan discs on a few spaces in a row; at the round's end a wave splashes over them.
## Nothing flashes: the discs glow steadily in their own colours (deep.gd ROCK_COLOR / WAVE_COLOR), never the gold of
## the STAR or a pick; their see-through parts draw under the VR cards (warn_rings fill_material). Lives under
## main.stage (board units), so it is the same size on the TV and on the VR giant's table. The host moves the tokens
## (turn_flow.gd _surprises_fall); this only shows it.
##   show_now(hz), fall_fx(hz), tells_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const StoryCard := preload("res://core/story_card.gd")
const Deep := preload("res://games/party_board/deep.gd")

const STAY := 600.0  # (the tell stays until the host clears it)
const DROP_H := 7.0  # a rock starts this high over its space
const DROP_T := 0.55
const PIC_SIZE := 1.8  # the surprise's picture bobbing over its first space (board units)
const PIC_Y := 3.2

var main
var rings: WarnRings
var key := ""
var now: Array = []
var seen := {}  # kind -> tells drawn here (bots)
var fell := 0  # surprises that went off here (bots)
var pics: Array = []  # [Sprite3D, base position]


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


func show_now(hz: Variant) -> void:
	var zs: Array = hz if hz is Array else []
	var nk := str(zs)
	if nk == key:
		return
	key = nk
	rings.clear()
	for pp in pics:
		if is_instance_valid(pp[0]):
			(pp[0] as Node).queue_free()
	pics.clear()
	now = zs.duplicate(true)
	for z in zs:
		var kind := String((z as Dictionary).get("kind", ""))
		var col := Deep.color_of(kind)
		seen[kind] = int(seen.get(kind, 0)) + 1
		for s in (z as Dictionary).get("spaces", []):
			var id := int(s)
			if id < 0 or id >= main.data.count():
				continue
			var p: Vector3 = main.data.pos(id)
			var y := p.y + Deep.RING_Y
			rings.shape("circle", Vector3(p.x, y, p.z), Vector3.FORWARD, Vector2(Deep.RING_R, 0.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.42, "y": y, "hot": col})
		var sp: Array = (z as Dictionary).get("spaces", [])
		if not sp.is_empty() and int(sp[0]) >= 0 and int(sp[0]) < main.data.count():  # a picture says what is coming
			var s := StoryCard.sprite(String(Deep.KIND_PICS.get(kind, "boulder")), 128, col)
			s.name = "SurprisePic"
			s.pixel_size = PIC_SIZE / 128.0
			add_child(s)
			var at: Vector3 = main.data.pos(int(sp[sp.size() / 2])) + Vector3(0, PIC_Y, 0)
			s.position = at
			pics.append([s, at])
	if not zs.is_empty():
		main.sfx.play("whoosh", -10.0, 0.7)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for pp in pics:
		if is_instance_valid(pp[0]):
			(pp[0] as Node3D).position = (pp[1] as Vector3) + Vector3(0, 0.25 * sin(t * 2.5), 0)


## Where the camera looks while the surprises are told / go off (the middle of their spaces; INF none).
func focus() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for z in now:
		for s in (z as Dictionary).get("spaces", []):
			if int(s) >= 0 and int(s) < main.data.count():
				sum += main.data.pos(int(s))
				n += 1
	return sum / float(n) if n > 0 else Vector3.INF


## Bots: the surprises told now.
func tells_now() -> Array:
	return now.duplicate(true)


## Every machine: the surprises go off (a rock drops, a wave splashes).
func fall_fx(hz: Variant) -> void:
	var zs: Array = hz if hz is Array else []
	for z in zs:
		var kind := String((z as Dictionary).get("kind", ""))
		var col := Deep.color_of(kind)
		fell += 1
		for s in (z as Dictionary).get("spaces", []):
			var id := int(s)
			if id < 0 or id >= main.data.count():
				continue
			var p: Vector3 = main.data.pos(id)
			if kind == "rock":
				_drop_rock(p)
			else:
				main.burst(p + Vector3(0, 0.5, 0), col, 20)
		if kind == "wave":
			main.sfx.play("splash", -2.0, 0.9)


func _drop_rock(p: Vector3) -> void:
	var b := MeshKit.Builder.new()
	b.sphere(0.7, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.8, 1.0)), Color(0.5, 0.4, 0.35), 10)
	b.sphere(0.35, MeshKit.at(Vector3(0.35, 0.25, 0.2)), Color(0.6, 0.5, 0.42), 8)
	var rock := MeshKit.instance(b.build(), false)
	rock.name = "Rock"
	add_child(rock)
	rock.position = p + Vector3(0, DROP_H, 0)
	var tw := rock.create_tween()
	tw.tween_property(rock, "position", p + Vector3(0, 0.6, 0), DROP_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		main.burst(p + Vector3(0, 0.6, 0), Deep.ROCK_COLOR, 18)
		main.sfx.play("land", -2.0, 0.6)
		if main.cam != null:
			main.cam.shake(0.12))
	tw.tween_property(rock, "scale", Vector3.ONE * 0.05, 0.5).set_delay(0.5)
	tw.tween_callback(rock.queue_free)
