extends SceneTree
## FAMILY TROPHY HALL: every deepened game (one with a daily seed) has games/<game>/progress.gd, its pictures exist,
## its summary reads an empty save as nothing grown and its own sample save as grown with today's golden star; the
## lobby's pack / unpack / merge keep one family's numbers; reading every save is fast (the lobby must start quickly);
## the hall tiles and the VR wall build without errors.
##   godot-test --headless --path . -s res://tests/progress_test.gd     Prints PROGRESS: PASS / FAIL.

const Progress := preload("res://core/progress.gd")
const Hall := preload("res://arcade/hall.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0
var frames := 0
var box: Control
var tiles: Array = []


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("PROGRESS: FAIL ", what)


func _initialize() -> void:
	Engine.set_meta("save_test_mode", true)  # never the family's saves
	var games: Array = load("res://arcade/arcade.gd").GAMES
	var ids: Array = []
	for g in games:
		ids.append(String(g.id))
	Progress.ids()
	print("PROGRESS: found %d games in %.1f ms" % [Progress.ids().size(), Progress.scan_ms])
	_expect(Progress.scan_ms < 5.0, "finding the games' progress.gd took %.1f ms (want < 5: the lobby does it at startup)" % Progress.scan_ms)
	_expect(Progress.load_ms == 0.0, "finding them loads no script")
	# The lobby loads them a few a frame: one step stays near its budget.
	var t_step := Time.get_ticks_usec()
	Progress.load_some(3.0)
	var step_ms := (Time.get_ticks_usec() - t_step) / 1000.0
	_expect(step_ms < 8.0, "one load_some(3 ms) step took %.1f ms" % step_ms)
	for e in Progress.check(ids):
		_expect(false, e)
	# The check can fail: a game with a daily seed but no progress.gd.
	_expect(not Progress.check(["tower_stack"], ["tower_stack"]).is_empty(), "the check fails for a deepened game without progress.gd")
	for id in Progress.ids():
		_expect(ids.has(id), "games/%s/progress.gd belongs to a game the arcade shows" % id)
	_expect(Progress.ids().size() >= 30, "%d games are in the hall (want >= 30)" % Progress.ids().size())
	# Network round trip and one-family merge.
	var today := Seeded.today()
	var a := {"tower_stack": {"grown": 5, "daily": true, "played": true}, "fruit_catch": {"grown": 1, "daily": false, "played": false}}
	var b := {"tower_stack": {"grown": 2, "daily": false, "played": false}, "fruit_catch": {"grown": 7, "daily": true, "played": true}}
	_expect(Progress.unpack(Progress.pack(a)) == a, "pack / unpack keeps the numbers")
	var m := Progress.merge(a, b)
	_expect(int(m.tower_stack.grown) == 5 and int(m.fruit_catch.grown) == 7 and m.fruit_catch.daily and m.tower_stack.daily, "merge keeps the further-grown and either's golden star")
	var stale := Progress.pack(a)
	stale[0] = "2000-01-01"
	_expect(not Progress.unpack(stale).tower_stack.daily, "yesterday's golden star is not today's")
	_expect(Progress.unpack([]).is_empty() and Progress.unpack([today, "x"]).is_empty(), "short packets read as nothing")
	# Speed: every game's save read (empty test saves here; a Deck reads small real ones). Scripts load once.
	var t0 := Time.get_ticks_usec()
	var rows := Progress.summaries()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("PROGRESS: read %d games in %.1f ms" % [rows.size(), ms])
	_expect(ms < 50.0, "reading the hall took %.1f ms (want < 50)" % ms)
	# Tiles (TV) and the VR wall build for every game, with and without progress.
	box = Control.new()
	box.size = Vector2(1920, 1080)
	root.add_child.call_deferred(box)
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	var order := Hall.order(games, rows)
	_expect(order.size() == Progress.ids().size(), "the hall shows every game with progress")
	for i in order:
		var bt := Button.new()
		bt.name = String(games[i].id)
		bt.custom_minimum_size = Vector2(600, 136)
		var id := String(games[i].id)
		Hall.fill_tile(bt, id, {"grown": [0, 3, 999, 12345][i % 4], "daily": i % 2 == 0}, ImageTexture.create_from_image(Image.create(160, 90, false, Image.FORMAT_RGB8)))
		tiles.append(bt)
		grid.add_child(bt)
	box.add_child(Hall.tab(rows, true, Color.GOLD))
	var wall := Hall.vr_panel()
	var n3 := Node3D.new()
	root.add_child.call_deferred(n3)
	n3.add_child(wall)
	Hall.vr_update(wall, games, Progress.merge(rows, a), 0)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	for bt in tiles:  # a big family number never pushes the star out of the tile
		var hall: Control = bt.get_node("Hall")
		var cr: Rect2 = bt.get_global_rect().grow(1.0)
		for part in hall.get_children():
			_expect(cr.encloses(part.get_global_rect()), "%s: %s sticks out of the tile %s (%s)" % [bt.name, part.name, cr, part.get_global_rect()])
	print("PROGRESS: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true
