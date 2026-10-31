extends SceneTree
## STORY CARD PICTURES: every picture has a drawing, no name is in two places, core/story_card.gd's shared list
## stays frozen (a game's new picture goes in games/<game>/story_pictures.gd, found by core/story_pictures.gd, so
## two games never edit the same line), every picture draws without a script error, and a VR story card shows its
## picture (StoryCard.show_vr: the "StoryPicture" medallion) - VR players never lose the picture the TV shows.
## Every polygon of every picture can be drawn (no self-crossing shapes: Godot draws nothing for them).
##   godot-test --headless --path . -s res://tests/story_pictures_test.gd     Prints STORY PICTURES: PASS / FAIL.

const StoryCard := preload("res://core/story_card.gd")
const Registry := preload("res://core/story_pictures.gd")
const FROZEN: Array[String] = ["bird", "envelope", "cloud", "storm", "house", "sprite", "sun", "wave", "tree", "penguin", "snowman", "tophat", "beanie", "kaiju", "gift", "rocket", "toyrocket", "castle"]

var fails := 0
var frames := 0
var box: Control
var vr_cards: Array = []


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("STORY PICTURES: FAIL ", what)


func _initialize() -> void:
	for e in StoryCard.check():
		_expect(false, e)
	_expect(StoryCard.SHARED_PICTURES == FROZEN, "core/story_card.gd SHARED_PICTURES changed: put a game's new picture in games/<game>/story_pictures.gd (NAMES + a case in draw)")
	var nope: Array[String] = ["nopicture"]
	_expect(not Registry.check(nope, "res://core/story_card.gd").is_empty(), "the check can fail (a name with no drawing)")
	var names := StoryCard.names()
	_expect(names.size() >= 75, "%d pictures (want >= 75)" % names.size())
	for n in ["castle", "granny", "kart", "apple", "beaver", "lumi", "queenbee", "engineer"]:
		_expect(StoryCard.has_picture(n), "picture %s exists" % n)
	_expect(not StoryCard.has_picture("nopicture"), "an unknown name is not a picture")
	_expect(Registry.files().size() >= 14, "%d games have story_pictures.gd" % Registry.files().size())
	box = Control.new()
	box.size = Vector2(1280, 800)
	root.add_child.call_deferred(box)
	for n in names:
		box.add_child(StoryCard.picture(n, 64.0, Color(0.9, 0.5, 0.3)))
	var world := Node3D.new()
	var cam := Camera3D.new()
	world.add_child(cam)
	root.add_child.call_deferred(world)
	world.ready.connect(func() -> void:
		for pic in ["beaver", "castle", "star", ""]:
			vr_cards.append([pic, StoryCard.show_vr(world, cam, {"who": "TEST", "line": "a line", "pic": pic, "duration": 30.0})]))


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 40:  # (pictures move: draw them over a while, at many clock values)
		for pic in box.get_children():
			pic.set("t", frames * 0.37)
		return false
	_expect(StoryCard.Picture.bad_polys.is_empty(), "pictures with polygons that can't be drawn (they cross themselves): %s" % str(StoryCard.Picture.bad_polys.keys()))
	_expect(vr_cards.size() == 4, "VR cards made")
	for pc in vr_cards:
		var card: Node = pc[1]
		var sp := card.find_child("StoryPicture", false, false) as Sprite3D if card != null else null
		if String(pc[0]) == "":
			_expect(sp == null, "a VR card without a picture has no medallion")
		else:
			_expect(sp != null and sp.texture != null, "the VR story card shows its picture %s" % pc[0])
	print("STORY PICTURES: %s (%d pictures, %d games)" % ["PASS" if fails == 0 else "FAIL", StoryCard.names().size(), Registry.files().size()])
	quit(1 if fails > 0 else 0)
	return true
