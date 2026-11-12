extends SceneTree
## KART RACE second pass (games/kart_race/deep.gd, trackgen.gd surprise spots, town.gd): no game, no window.
##   godot-test --headless --path . -s res://tests/kart_deep_test.gd     (GEN_QUICK=1: the landing sample)
## Proves: the gifts / surprises / town data (Deep.check: pictures, three different gifts at every pit stop, a
## surprise for every cup and season, tells long enough); what drops when (never on today's track, a series' first
## race or a time trial); over many seeds of every cup race and the tour's races, every surprise spot passes
## TrackGen.check (a circle on one side of the road leaving a clear lane, on a gentle stretch seen coming, away from
## ramps / splits / arrows / boxes / hazards / the start) and nearly every track gets spots; Bolt's race town always
## finds room by the start, clear of every road. Prints "KART DEEP: PASS" or "FAIL".

const TrackGen := preload("res://games/kart_race/trackgen.gd")
const Story := preload("res://games/kart_race/story.gd")
const Cups := preload("res://games/kart_race/cups.gd")
const Deep := preload("res://games/kart_race/deep.gd")
const Town := preload("res://games/kart_race/town.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0
const UI_ICONS: Array[String] = ["star", "flag", "fire", "clock", "crown", "trophy", "shield"]


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var pic_ok := func(n: String) -> bool: return StoryCard.has_picture(n) or UI_ICONS.has(n)
	for w in Deep.check(pic_ok):
		_fail("DATA: " + w)
	# What drops when.
	_expect(Deep.surprise_kind("daily", "", 3, "zoom", "winter") == "", "nothing drops on today's track")
	_expect(Deep.surprise_kind("cup", "candy", 0, "zoom", "winter") == "", "nothing drops in a cup's first race")
	_expect(Deep.surprise_kind("cup", "candy", 1, "trial", "winter") == "", "nothing drops in a time trial")
	_expect(Deep.surprise_kind("cup", "jungle", 1, "gentle", "summer") == "coconut", "the jungle cup drops coconuts")
	_expect(Deep.surprise_kind("tour", "", 2, "gentle", "autumn") == "acorn", "the tour drops the season's thing")
	for c in Cups.CUPS:
		_expect(Deep.CUP_SURPRISE.has(String(c.hz)), "%s cup has a surprise" % c.id)
	# Surprise spots + the town over many tracks.
	var seeds := Seeded.test_count(8, 1)
	var tracks := 0
	var with_spots := 0
	var spots := 0
	var no_town := 0
	var specs: Array = []
	for c in Cups.CUPS.size():
		for race in [1, 2]:
			for m in ["gentle", "zoom"]:
				specs.append(["cup %s race %d %s" % [Cups.cup(c).id, race, m], Cups.spec(c, race, m)])
	for i in Story.PLACES.size() * Story.RACES_PER_PLACE:
		if i % Story.RACES_PER_PLACE != 0:  # (the tour's first race of a place has no surprises)
			specs.append(["tour race %d" % i, Story.spec(i)])
	for si in specs.size():
		if not Seeded.sampled(si, 3):
			continue
		var sp: Dictionary = specs[si][1]
		var name := String(specs[si][0])
		for k in seeds:
			var seed_v := 4100 + si * 97 + k * 13
			var info := TrackGen.generate(seed_v, sp)
			tracks += 1
			if info.has("fallback"):
				_fail("%s seed %d: fell back" % [name, seed_v])
				continue
			var why := TrackGen.check(info)
			for w in why:
				_fail("%s seed %d: %s" % [name, seed_v, w])
			var n := (info.get("surprises", []) as Array).size()
			spots += n
			if n > 0:
				with_spots += 1
			var t := TrackGen.Track.new()
			t.prepare(info)
			if Town.place(t, Deep.TOWN.size()).is_empty():
				no_town += 1
				_fail("%s seed %d: no room for Bolt's town" % [name, seed_v])
			t.free()
	var frac := float(with_spots) / maxf(1.0, float(tracks))
	print("KART DEEP: %d tracks, %d with surprise spots (%.0f%%), %.1f spots each, town placed on %d; %d ms" % [tracks, with_spots,
		frac * 100.0, float(spots) / maxf(1.0, float(tracks)), tracks - no_town, Time.get_ticks_msec() - t0])
	_expect(frac >= 0.9, "surprise spots on nearly every track (%.0f%%)" % (frac * 100.0))
	# The town grows and stops growing.
	_expect(Deep.town_size(2).x == 0 and Deep.town_size(3).x == 1 and Deep.town_size(30).x == Deep.TOWN.size(), "town_size()")
	_expect(Deep.town_size(30 + Deep.TOWN_EVERY * 2).y == 1, "balloons after the town is built")
	print("KART DEEP: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails <= 40:
		print("SCRIPT ERROR: KART DEEP: " + what)