extends SceneTree
## STORY CARD PICTURES: every picture has a drawing, no name is in two places, core/story_card.gd's shared list
## stays frozen (a game's new picture goes in games/<game>/story_pictures.gd, found by core/story_pictures.gd, so
## two games never edit the same line), every picture draws without a script error, and a VR story card shows its
## picture (StoryCard.show_vr: the "StoryPicture" medallion) - VR players never lose the picture the TV shows.
## Every polygon of every picture can be drawn (no self-crossing shapes: Godot draws nothing for them).
## Cards take turns (TV and VR): a newer card waits until the one showing has been up StoryCard.MIN_READ s, opts.urgent
## replaces at once, a pile-up keeps at most MAX_WAITING waiting, and a card knocked off early is counted (bot_kit
## finish() fails on it). Games never free / hide their VR story card before show_vr: show_vr replaces it in turn.
##   godot-test --headless --path . -s res://tests/story_pictures_test.gd     Prints STORY PICTURES: PASS / FAIL.

const StoryCard := preload("res://core/story_card.gd")
const Registry := preload("res://core/story_pictures.gd")
const FROZEN: Array[String] = ["bird", "envelope", "cloud", "storm", "house", "sprite", "sun", "wave", "tree", "penguin", "snowman", "tophat", "beanie", "kaiju", "gift", "rocket", "toyrocket", "castle"]

var fails := 0
var frames := 0
var box: Control
var vr_cards: Array = []
var qbox: Control
var qworld: Node3D
var qcam: Camera3D
var q := {}


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
	qbox = Control.new()
	qbox.size = Vector2(1280, 800)
	root.add_child.call_deferred(qbox)
	qworld = Node3D.new()
	qcam = Camera3D.new()
	qworld.add_child(qcam)
	root.add_child.call_deferred(qworld)
	_scan_games()
	world.ready.connect(func() -> void:
		for pic in ["beaver", "castle", "star", ""]:
			vr_cards.append([pic, StoryCard.show_vr(world, cam, {"who": "TEST", "line": "a line", "pic": pic, "duration": 30.0})]))


func _process(_delta: float) -> bool:
	frames += 1
	_queue_step()
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
	_expect(q.get("done", false), "the card queue checks ran")
	print("STORY PICTURES: %s (%d pictures, %d games)" % ["PASS" if fails == 0 else "FAIL", StoryCard.names().size(), Registry.files().size()])
	quit(1 if fails > 0 else 0)
	return true


func _card(line: String, extra: Dictionary = {}) -> Dictionary:
	var o := {"who": "TEST", "line": line, "pic": "star", "duration": 30.0, "sound": ""}
	o.merge(extra, true)
	return o


## The turn-taking, step by step over frames (clocks set by hand: no waiting on real time).
func _queue_step() -> void:
	match frames:
		2:
			Engine.set_meta(StoryCard.SHORT_META, 0)
			q.a = StoryCard.show(qbox, _card("first"))
			q.b = StoryCard.show(qbox, _card("second"))
			q.va = StoryCard.show_vr(qworld, qcam, _card("vr first"))
			q.vb = StoryCard.show_vr(qworld, qcam, _card("vr second"))
		5:
			_expect(not q.a.waiting and q.a.visible and not q.a.leaving, "the first card shows")
			_expect(q.b.waiting and not q.b.visible, "a second card shown at once waits its turn (the first is being read)")
			_expect(q.va.visible and not q.va.has_meta("story_waiting"), "the first VR card shows")
			_expect(q.vb.has_meta("story_waiting") and not q.vb.visible, "a second VR card waits its turn")
			q.a.t = StoryCard.MIN_READ + 0.05  # read long enough
			q.va.t = StoryCard.MIN_READ + 0.05
		8:
			_expect(q.a.leaving, "the first card leaves once read for MIN_READ s")
			_expect(not q.b.waiting and q.b.visible, "then the second card shows")
			_expect(bool(q.va.get("_hiding")), "the first VR card fades once read")
			_expect(q.vb.visible and not q.vb.has_meta("story_waiting"), "then the second VR card shows")
			q.c = StoryCard.show(qbox, _card("countdown", {"urgent": true}))
			q.vc = StoryCard.show_vr(qworld, qcam, _card("vr countdown", {"urgent": true}))
		10:
			_expect(q.b.leaving and not q.c.waiting and q.c.visible, "an urgent card replaces the one showing at once")
			_expect(bool(q.vb.get("_hiding")) and q.vc.visible, "an urgent VR card replaces the one showing at once")
			for i in 6:
				StoryCard.show(qbox, _card("pile %d" % i))
		12:
			var w := 0
			for c in qbox.get_children():
				if c is StoryCard.Card and (c as StoryCard.Card).waiting and not (c as StoryCard.Card).leaving:
					w += 1
			_expect(w <= StoryCard.MAX_WAITING, "at most MAX_WAITING cards wait (%d)" % w)
			_expect(int(Engine.get_meta(StoryCard.SHORT_META, 0)) == 0, "turn-taking and urgent replaces knock nothing off (%d)" % int(Engine.get_meta(StoryCard.SHORT_META, 0)))
			q.c.leave()  # a game taking a card away after 0.1 s: knocked off
		16:
			_expect(int(Engine.get_meta(StoryCard.SHORT_META, 0)) == 1, "a card taken away before it was read is counted (bot_kit finish() fails on it)")
			Engine.set_meta(StoryCard.SHORT_META, 0)
			q.done = true


## Games never free or hide their VR story card just before StoryCard.show_vr: that knocks the card being read off
## (show_vr replaces it in turn, after MIN_READ s; 20 games did it, 2026-11-13).
func _scan_games() -> void:
	var re := RegEx.create_from_string("vr_story\\.(queue_free\\(\\)|call\\(\"hide_card\"\\)|hide_card\\()")
	for d in DirAccess.get_directories_at("res://games"):
		for f in DirAccess.get_files_at("res://games/" + d):
			if not f.ends_with(".gd"):
				continue
			var lines := FileAccess.get_file_as_string("res://games/%s/%s" % [d, f]).split("\n")
			for i in lines.size():
				if lines[i].contains("StoryCard.show_vr("):
					for j in range(maxi(0, i - 5), i):
						if re.search(lines[j]) != null:
							_expect(false, "games/%s/%s:%d frees / hides the VR story card before StoryCard.show_vr: drop it, show_vr replaces the card in turn (opts.urgent: at once)" % [d, f, j + 1])
