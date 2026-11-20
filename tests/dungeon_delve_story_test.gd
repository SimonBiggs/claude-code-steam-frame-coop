extends SceneTree
## DUNGEON DELVE story, heroes and practice room (no game, no window):
##   godot-test --headless --path . -s res://tests/dungeon_delve_story_test.gd
##  - story (story.gd): every beat has a speaker, a known picture and a short kind line (kids read it on a Deck);
##    a run's intro exists for new and old families and after the ending; every biome after the first has an arrival
##    beat, every boss but the last a grumble, the last boss THE ENDING (and a shorter one when it was seen);
##  - heroes (classes.gd): every hero has a statue spot in the practice room, statues stand at least 1 m apart and
##    clear of the pads and the hat stand; exactly one hero is free from the start; the healer's numbers are sane;
##  - the practice room: the practice pot sits near where heroes pop in and clear of every pad, statue and the
##    hoard (the first A a new player presses must work at once).
## Prints "SCRIPT ERROR: STORY ..." for each failure.

const Story := preload("res://games/dungeon_delve/story.gd")
const StoryCard := preload("res://core/story_card.gd")
const Classes := preload("res://games/dungeon_delve/classes.gd")
const Deep := preload("res://games/dungeon_delve/deep.gd")
const Dungeon := preload("res://games/dungeon_delve/dungeon.gd")
const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")

const MAX_LINE := 40

var fails := 0


func _initialize() -> void:
	_check_story()
	_check_heroes()
	_check_practice_room()
	print("STORY: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	fails += 1
	print("SCRIPT ERROR: STORY ", msg)


func _check_beats(tag: String, beats: Array) -> void:
	for b in beats:
		var beat: Dictionary = b
		if String(beat.get("who", "")) == "":
			_fail("%s: a card with no speaker" % tag)
		var line := String(beat.get("line", ""))
		if line == "" or line.length() > MAX_LINE:
			_fail("%s: line '%s' is empty or longer than %d letters" % [tag, line, MAX_LINE])
		if not StoryCard.has_picture(String(beat.get("pic", ""))):
			_fail("%s: unknown picture '%s'" % [tag, String(beat.get("pic", ""))])
		if float(beat.get("duration", 0.0)) < 2.5 or float(beat.get("duration", 0.0)) > Story.GAP + 0.5:
			_fail("%s: '%s' shows for %.1f s (2.5 .. GAP+0.5)" % [tag, line, float(beat.get("duration", 0.0))])
		Color.html(String(beat.get("color", "ffffff")))


func _check_story() -> void:
	_check_beats("all", Story.all_beats())
	for runs in [0, 1, Story.INTRO_FULL_RUNS, 50]:
		for ending in [false, true]:
			if Story.intro(runs, ending).is_empty():
				_fail("no intro for runs=%d ending=%s" % [runs, ending])
	if Story.intro(0, false).size() < 2:
		_fail("a new family's intro should say what happened AND who did it (2 cards)")
	for z in range(1, FloorGen.ZONE_COUNT):
		if Story.zone_beats(z, false).is_empty():
			_fail("biome %d has no arrival beat" % z)
		for b in Story.zone_beats(z, true):
			if String((b as Dictionary)["who"]) == "SOOT":
				_fail("biome %d: after the ending Soot is a friend, he shouldn't tease" % z)
	if Story.zone_beats(FloorGen.ZONE_COUNT, true).is_empty():
		_fail("the endless depths have no arrival beat")
	if not Story.zone_beats(FloorGen.ZONE_COUNT + 3, true).is_empty():
		_fail("deeper endless biomes should stay quiet (one beat when they start)")
	for z2 in range(0, FloorGen.ZONE_COUNT - 1):
		if Story.boss_beats(z2, false).is_empty():
			_fail("boss of biome %d has no grumble" % z2)
	var ending: Array = Story.boss_beats(FloorGen.ZONE_COUNT - 1, false)
	if ending.size() < 3:
		_fail("the last boss should start THE ENDING (3+ cards), got %d" % ending.size())
	if String((ending.back() as Dictionary)["pic"]) != "soot_happy":
		_fail("the ending should finish with a happy Soot")
	if Story.boss_beats(FloorGen.ZONE_COUNT - 1, true).size() >= ending.size():
		_fail("a second win should get a shorter beat than the first ending")
	if not Story.boss_beats(FloorGen.ZONE_COUNT + 1, true).is_empty():
		_fail("endless-depth bosses shouldn't replay story beats")
	for k in ["soot", "soot_happy", "cinder"]:
		if not StoryCard.has_picture(k):
			_fail("picture %s missing" % k)


func _check_heroes() -> void:
	var free := 0
	for id in Classes.ORDER:
		var ci: Dictionary = Classes.info(id)
		if not Deep.CLASS_SPOTS.has(id):
			_fail("hero %s has no statue spot in deep.gd CLASS_SPOTS" % id)
			continue
		if int(ci["hoard"]) == 0:
			free += 1
		if Classes.look_class(id) == "":
			_fail("hero %s has no look" % id)
		var p: Vector3 = Deep.CLASS_SPOTS[id]
		for id2 in Classes.ORDER:
			if id2 != id and Deep.CLASS_SPOTS.has(id2) and p.distance_to(Deep.CLASS_SPOTS[id2]) < 1.0:
				_fail("statues %s and %s stand closer than 1 m" % [id, id2])
		for pad in Deep.PADS:
			if p.distance_to(Deep.PADS[pad]) < 1.6:  # pad 0.9 + plinth 0.42 + a gap
				_fail("statue %s too near the %s pad" % [id, pad])
		if p.distance_to(Deep.HAT_RACK) < 1.2:
			_fail("statue %s too near the hat stand" % id)
	if free != 1:
		_fail("exactly one hero should be free from the start (%d are)" % free)
	if Classes.HEAL_EVERY < 3.0 or Classes.SOLO_HEAL_EVERY < Classes.HEAL_EVERY or Classes.HEAL_R < Deep.REVIVE_R:
		_fail("healer numbers: ring every %.1f s (alone %.1f s), radius %.1f m" % [Classes.HEAL_EVERY, Classes.SOLO_HEAL_EVERY, Classes.HEAL_R])


func _check_practice_room() -> void:
	var pot := Dungeon.PRAC_POT
	var spawn := Dungeon.entrance(0)
	if Vector2(pot.x - spawn.x, pot.z - spawn.z).length() > 2.5:
		_fail("the practice pot is %.1f m from where heroes pop in (2.5 max)" % Vector2(pot.x - spawn.x, pot.z - spawn.z).length())
	for pad in Deep.PADS:
		if Vector2(pot.x - Deep.PADS[pad].x, pot.z - Deep.PADS[pad].z).length() < 1.6:
			_fail("the practice pot sits on the %s pad" % pad)
	for id in Deep.CLASS_SPOTS:
		if pot.distance_to(Deep.CLASS_SPOTS[id]) < 1.5:
			_fail("the practice pot sits by the %s statue" % id)
	if pot.distance_to(Deep.HOARD_SPOT) < 1.4:
		_fail("the practice pot sits under Cinder's hoard (its label covers the pot's ring)")