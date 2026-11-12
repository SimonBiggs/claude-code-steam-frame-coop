extends Node3D
## PAINT AND GUESS: SMUDGE'S BRUSH GIFT on show (deep.gd GIFTS; the game's gift comes in the "deep" state). Every
## machine hangs the gift's picture on a little gold tag by the easel's left edge (everyone sees what the team has),
## and it bounces when the gift does something (a stamp, a crossed-out answer). What the gifts DO is in main.gd /
## artist.gd: BIG BRUSH (wider paint), RAINBOW BRUSH (every round starts on the rainbow paint), STAMPS (a quick tap
## stamps a star), SLOW CLOCK (longer rounds), PEEK GLASS (one wrong answer goes, Smudge guesses sooner).
##   set_gift(id), bounce()

const Deep := preload("res://games/paint_and_guess/deep.gd")

const AT := Vector3(-0.78, -0.02, 0.03)  # (canvas metres: left of the board, under the palette)
const SIZE := 0.17

var main
var gift := ""
var tag: Node3D
var pop := 0.0


func _ready() -> void:
	name = "Gifts"


## Every machine: this game's gift ("" none).
func set_gift(id: String) -> void:
	if id == gift:
		return
	gift = id
	if tag != null and is_instance_valid(tag):
		tag.queue_free()
	tag = null
	var gd := Deep.gift(id)
	if gd.is_empty():
		return
	tag = Node3D.new()
	tag.name = "GiftTag"
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = SIZE * 0.62
	cm.bottom_radius = SIZE * 0.62
	cm.height = 0.012
	cm.radial_segments = 20
	cm.rings = 1
	disc.mesh = cm
	disc.material_override = main.make_material(Color(1.0, 0.8, 0.3), 0.4)
	disc.rotation.x = PI * 0.5
	disc.position.z = -0.008
	tag.add_child(disc)
	var pic: Sprite3D = main.canvas.picture_sprite(String(gd.pic), SIZE, 1)
	tag.add_child(pic)
	main.canvas.board_root.add_child(tag)
	tag.position = AT
	pop = 1.0


## Every machine: the tag hops (the gift just helped).
func bounce() -> void:
	pop = 1.0


func _process(delta: float) -> void:
	if tag == null or not is_instance_valid(tag):
		return
	pop = maxf(0.0, pop - delta * 1.6)
	tag.scale = Vector3.ONE * (1.0 + 0.3 * sin(pop * PI))
