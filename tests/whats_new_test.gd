extends SceneTree
## WHAT'S NEW board (arcade/whats_new.gd): the data is sound (arcade games with a story friend, real pictures, short
## lines, newest first), every game that got a feature lately has a fresh entry (git log: a commit whose subject
## starts with the game's name, after WhatsNew.CHECK_FROM, needs an entry from the FRESH_DAYS before it: add one at
## the top of ENTRIES), seen ids save / merge like one family, unseen tiles come first with a NEW! badge and seen ones
## lose it, the tiles fit inside their cards at TV and Deck size, and in VR the board's wall (and the Trophy Hall's)
## pass core/vr_view_check.gd from the lobby's head position.
##   godot-test --headless --path . -s res://tests/whats_new_test.gd     Prints WHATS NEW: PASS / FAIL.

const WhatsNew := preload("res://arcade/whats_new.gd")
const VrViewCheck := preload("res://core/vr_view_check.gd")
const LayoutCheck := preload("res://core/layout_check.gd")

var fails := 0
var frames := 0
var games: Array = []
var boards: Array = []  # [SubViewport, tiles: Array[Button]]
var arcade: Node


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("WHATS NEW: FAIL ", what)


func _initialize() -> void:
	Engine.set_meta("save_test_mode", true)  # never the family's saves
	OS.set_environment("DUO_SOLO", "1")
	if not OS.has_environment("DUO_PORT"):
		OS.set_environment("DUO_PORT", str(20000 + randi() % 10000))
	games = load("res://arcade/arcade.gd").GAMES
	var ids: Array = []
	var names := {}
	for g in games:
		ids.append(String(g.id))
		names[String(g.id)] = String(g.name)
	# The data.
	for p in WhatsNew.check(ids):
		_expect(false, p)
	var n := WhatsNew.ENTRIES.size()
	_expect(n >= 1, "there is news (%d entries)" % n)
	_expect(not WhatsNew.check(ids, [{"id": "x", "date": "2026-1-1", "game": "nope", "pic": "nothing", "line": "This line is far too long for a little one to read"}]).size() < 4,
		"the data check catches a bad date, game, picture and a long line")
	_expect(not WhatsNew.check(ids, [{"id": "a", "date": "2026-10-01", "game": "tower_stack", "pic": "wren", "line": "Hi"},
		{"id": "b", "date": "2026-10-05", "game": "tower_stack", "pic": "wren", "line": "Hi"}]).is_empty(), "the data check wants newest first")
	# Fresh entries for every game's latest feature (git history; Decks have no git: skipped there).
	var log := WhatsNew.git_log()
	if log == "":
		print("WHATS NEW: no git here, skipping the freshness check")
	for p in WhatsNew.stale(log, names, int(Time.get_unix_time_from_system())):
		_expect(false, p)
	# ...and that check can fail: a fake feature commit now, with and without its entry.
	var now := maxi(int(Time.get_unix_time_from_system()), int(Time.get_unix_time_from_datetime_string(WhatsNew.CHECK_FROM)) + 3600)
	var today := Time.get_date_string_from_unix_time(now)
	var fake := "@%d|Bee Garden: a brand new thing\n\ngames/bee_garden/main.gd\n@%d|VR fix everywhere\n\ngames/kart_race/main.gd\n" % [now, now]
	var no_bee: Array = []
	for e in WhatsNew.ENTRIES:
		if String(e.game) != "bee_garden" and String(e.game) != "kart_race":
			no_bee.append(e)
	var got := WhatsNew.stale(fake, names, now, no_bee)
	_expect(got.size() == 1 and got[0].begins_with("bee_garden"), "a feature commit without an entry fails the check (and a mass fix doesn't): %s" % str(got))
	_expect(WhatsNew.stale(fake, names, now, no_bee + [{"id": "t", "date": today, "game": "bee_garden"}]).is_empty(), "an entry for it passes")
	_expect(WhatsNew.stale(fake.replace("Bee Garden:", "Bee Garden deep 2:"), names, now, no_bee).size() == 1, "\"Bee Garden deep 2:\" counts as a feature")
	var old := "@%d|Giant's Table: ladders\n\ngames/giants_table/main.gd\n" % (now - 20 * 86400)
	_expect(WhatsNew.stale(old, names, now, []).is_empty(), "a feature older than %d days is old news" % WhatsNew.FRESH_DAYS)
	var named := "@%d|Giant's Table: ladders\n\ngames/giants_table/main.gd\n" % now
	_expect(WhatsNew.stale(named, names, now, []).size() == 1, "a subject with the game's display name (Giant's Table) counts")
	# Seen: save, merge, order.
	var seen := {}
	var first := WhatsNew.order(games, seen)
	_expect(first.size() >= 1 and String(games[first[0]].id) == String(WhatsNew.ENTRIES[0].game), "the newest, biggest news comes first")
	_expect(WhatsNew.unseen(seen) == WhatsNew.current().size(), "nothing seen: everything is NEW")
	var g0 := String(games[first[0]].id)
	_expect(WhatsNew.merge(seen, WhatsNew.ids_of(g0)), "opening a tile marks its news seen")
	_expect(not WhatsNew.merge(seen, WhatsNew.ids_of(g0) + ["no-such-entry"]), "seeing it again (or unknown ids) changes nothing")
	_expect(WhatsNew.unseen(seen, g0) == 0, "its sparkle is gone")
	var after := WhatsNew.order(games, seen)
	_expect(after[after.size() - 1] == first[0], "a seen game moves after the unseen ones")
	WhatsNew.store_seen(seen)
	_expect(WhatsNew.load_seen() == seen, "seen survives a save and load")
	var other := {}
	WhatsNew.merge(other, WhatsNew.pack(seen))
	_expect(other == seen, "pack / merge carries the family's seen news across the lobby")
	var tried := WhatsNew.try_of("dungeon_delve", {})
	_expect(not tried.is_empty(), "Dungeon Delve's tile has a try-this (got %s)" % str(tried))
	# Tiles at TV and Deck sizes (the project's stretch makes both 1920 wide; a Deck is 1200 high).
	for size in [Vector2i(1920, 1080), Vector2i(1920, 1200)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child.call_deferred(vp)
		var grid := GridContainer.new()
		grid.columns = 3
		vp.add_child(grid)
		var tiles: Array = []
		for i in after:
			var bt := Button.new()
			bt.name = String(games[i].id)
			bt.custom_minimum_size = Vector2(600, 136)
			WhatsNew.fill_tile(bt, String(games[i].id), seen, ImageTexture.create_from_image(Image.create(160, 90, false, Image.FORMAT_RGB8)))
			tiles.append(bt)
			grid.add_child(bt)
		boards.append([vp, tiles])
	# VR: the real lobby's walls from the head of a standing player.
	arcade = load("res://arcade.tscn").instantiate()
	root.add_child.call_deferred(arcade)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 4:
		arcade._build_vr_view()
		arcade.vr_cam.position = Vector3(0, 1.6, 0)
	if frames < 12:
		return false
	for b in boards:
		var unseen_badges := 0
		for bt in b[1]:
			var news: Control = bt.get_node("News")
			var cr: Rect2 = (bt as Control).get_global_rect().grow(1.0)
			for part in news.find_children("*", "Control", true, false):
				if part.name in ["NewBadge", "Friend", "Pictures", "Line", "Shot"]:
					_expect(cr.encloses((part as Control).get_global_rect()), "%s: %s sticks out of the tile %s (%s)" % [bt.name, part.name, cr, (part as Control).get_global_rect()])
			var fresh := WhatsNew.unseen(WhatsNew.load_seen(), String(bt.name)) > 0
			var has_badge := news.find_child("NewBadge", true, false) != null
			_expect(fresh == has_badge, "%s: NEW! badge only on unseen news (unseen %s, badge %s)" % [bt.name, fresh, has_badge])
			if has_badge:
				unseen_badges += 1
		_expect(unseen_badges >= 1, "some tiles sparkle")
		for p in LayoutCheck.problems(b[0]):
			_expect(false, "board %s: %s" % [str((b[0] as SubViewport).size), p])
	_expect(arcade.news_wall != null and arcade.hall_wall != null, "the VR lobby has the What's New and Trophy Hall walls")
	for p in VrViewCheck.problems(arcade):
		_expect(false, "VR: " + p)
	if arcade.news_wall != null:
		var vp: SubViewport = arcade.news_wall.get_node("NewsView")
		_expect(vp.size.x > 0 and vp.get_child_count() > 0, "the VR news wall is drawn")
		var h: float = float(vp.size.y) * float(arcade.news_wall.pixel_size)
		_expect(h < 1.6, "the VR news wall is %.2f m high (fits between the floor and the head)" % h)
	print("WHATS NEW: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true
