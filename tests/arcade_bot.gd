extends Node
## Headless bot test of the arcade launcher, at Steam Deck size (1280x800, kind "deck") and TV size (1920x1080,
## kind "tv"). Each screen size is emulated with a SubViewport that applies the project's canvas_items/expand
## stretch (so the menu sees the same visible rect as on the real screen). Checks:
## - every category tab opens with all its cards, one of them focused;
## - on the biggest tab (1 PLAYER) moving down/right to the LAST card scrolls so that card is fully on screen;
## - the hint at the bottom is fully inside the screen and below the cards; the title band covers the status line;
## - Start opens "Quit the arcade?" on a Deck (not on the TV kind); B and Start close it;
## - A on a card launches that game.
## Run like every bot test: dev.bots.run("arcade"), or
##   godot-test --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/arcade_bot.tscn

const BotKit := preload("res://tests/bot_kit.gd")
const DEV := 41  # a virtual pad (BotKit swallows the real ones)
const BASE := Vector2(1920, 1080)  # project.godot viewport size (stretch canvas_items, aspect expand)
const SCREENS := [
	{"name": "Deck", "size": Vector2i(1280, 800), "kind": "deck", "can_quit": true},
	{"name": "TV", "size": Vector2i(1920, 1080), "kind": "tv", "can_quit": false},
]


func _ready() -> void:
	# The checks live in a node under the root: launching a game replaces this scene.
	var r := Runner.new()
	r.name = "ArcadeBotRunner"
	get_tree().root.add_child.call_deferred(r)


class Runner extends Node:
	var kit: Node
	var vp: SubViewport
	var arcade: Node
	var label := ""

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		kit = BotKit.new()
		add_child(kit)
		kit.verbose = false
		OS.set_environment("DUO_SOLO", "1")  # no lobby networking in the test
		OS.unset_environment("ARCADE_GAME")
		_run()

	func frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func pad(button: JoyButton, down: bool) -> void:
		var e := InputEventJoypadButton.new()
		e.device = DEV
		e.button_index = button
		e.pressed = down
		vp.push_input(e)

	func tap(button: JoyButton) -> void:
		pad(button, true)
		await frames(1)
		pad(button, false)
		await frames(2)

	## A pad press through Godot's Input, like a real pad (the game runs in the main window).
	func press(button: JoyButton) -> void:
		for down in [true, false]:
			var e := InputEventJoypadButton.new()
			e.device = DEV
			e.button_index = button
			e.pressed = down
			Input.parse_input_event(e)
			await frames(2)

	func check(cond: bool, msg: String) -> bool:
		return kit.assert_true(cond, "[%s] %s" % [label, msg])

	## The visible size the project's stretch (canvas_items, expand) gives a window of this size.
	static func stretched(window: Vector2i) -> Vector2:
		var s := minf(window.x / BASE.x, window.y / BASE.y)
		return (Vector2(window) / s).round()

	func _run() -> void:
		await frames(2)
		for sc in SCREENS:
			await _screen(sc)
		kit.finish()

	func _screen(sc: Dictionary) -> void:
		label = str(sc.name)
		OS.set_environment("DUO_MACHINE_KIND", str(sc.kind))
		if get_tree().current_scene != null:
			get_tree().unload_current_scene()  # this test's scene / what the previous screen ended on
		vp = SubViewport.new()
		vp.size = sc.size
		vp.size_2d_override = Vector2i(stretched(sc.size))
		vp.size_2d_override_stretch = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		arcade = load("res://arcade.tscn").instantiate()
		vp.add_child(arcade)
		await frames(10)
		var screen := Rect2(Vector2.ZERO, vp.get_visible_rect().size)
		kit.info("%s: window %s, visible %s, %d columns" % [label, str(sc.size), str(screen.size), arcade.grid.columns])
		check(arcade.my_kind == str(sc.kind), "machine kind is %s" % sc.kind)
		check(arcade.grid.columns >= 1 and arcade.grid.columns * 618.0 <= screen.size.x + 1.0,
			"the card columns fit across the screen (%d columns, %.0f px wide)" % [arcade.grid.columns, screen.size.x])

		# Every tab opens with all its cards.
		var tabs: Array[int] = arcade.tabs()
		check(tabs.size() >= 2, "there are category tabs (%d)" % tabs.size())
		var biggest := 0
		for k in tabs.size():
			arcade._show_category(k, true)
			await frames(2)
			var want: int = arcade._games_in(k).size()
			var name := str(arcade.CATEGORIES[tabs[k]].name)
			check(want > 0 and arcade.cards.size() == want and arcade.grid.get_child_count() == want,
				"tab %s opens with all %d cards (shows %d)" % [name, want, arcade.cards.size()])
			var f := vp.gui_get_focus_owner()
			check(f != null and arcade.grid.is_ancestor_of(f), "tab %s has a highlighted card" % name)
			if want > arcade._games_in(biggest).size():
				biggest = k
		# LB / RB move between tabs.
		arcade._show_category(0, true)
		await frames(2)
		await tap(JOY_BUTTON_RIGHT_SHOULDER)
		check(arcade.cat == 1, "RB opens the next tab")
		await tap(JOY_BUTTON_LEFT_SHOULDER)
		check(arcade.cat == 0, "LB goes back")

		# Biggest tab: walk the highlight to the last card with the d-pad; the card must be fully on screen.
		arcade._show_category(biggest, true)
		await frames(3)
		var n: int = arcade.grid.get_child_count()
		var last: Control = arcade.grid.get_child(n - 1)
		var cols: int = arcade.grid.columns
		for i in ceili(float(n) / cols) + 1:
			await tap(JOY_BUTTON_DPAD_DOWN)
		for i in cols:
			if vp.gui_get_focus_owner() == last:
				break
			await tap(JOY_BUTTON_DPAD_RIGHT)
		await frames(6)  # follow_focus scrolls deferred
		var scroll: ScrollContainer = arcade.find_child("Cards", true, false)
		check(scroll != null, "the cards are in a ScrollContainer named Cards")
		var fo := vp.gui_get_focus_owner()
		check(fo == last, "the d-pad reaches the last card (focus on card %d of %d) on the biggest tab %s" % [fo.get_index() if fo != null and fo.get_parent() == arcade.grid else -1, n, arcade.CATEGORIES[tabs[biggest]].name])
		if scroll != null:
			var sr := scroll.get_global_rect().grow(1.0)
			var cr := last.get_global_rect()
			check(sr.encloses(cr), "the highlighted last card %s is fully inside the card area %s (it scrolled)" % [str(cr), str(sr)])
			check(screen.grow(1.0).encloses(cr), "the highlighted last card is fully on screen")
			check(sr.end.y <= screen.end.y + 1.0, "the card area ends on screen")
			# And back up to the first card: it scrolls back.
			for i in ceili(float(n) / cols) + 1:
				await tap(JOY_BUTTON_DPAD_UP)
			await frames(6)
			var first: Control = arcade.grid.get_child(0)
			for i in cols:
				await tap(JOY_BUTTON_DPAD_LEFT)
			await frames(6)
			check(sr.encloses(first.get_global_rect()), "going back up scrolls the first card fully into view")

		# Hint label and title band.
		var hint: Label = arcade.find_child("Hint", true, false)
		check(hint != null, "there is a hint label")
		if hint != null:
			var hr := hint.get_global_rect()
			check(screen.grow(0.5).encloses(hr), "the hint %s is fully inside the screen %s" % [str(hr), str(screen.size)])
			check(scroll == null or hr.position.y >= scroll.get_global_rect().end.y - 0.5, "the hint is below the cards")
			check(hint.text.contains("Start: quit") == bool(sc.can_quit), "the hint mentions Start: quit only where Start quits")
		var band: Control = arcade.find_child("TitleBand", true, false)
		var status: Label = arcade.find_child("Status", true, false)
		check(band != null and status != null, "title band and status line exist")
		if band != null and status != null:
			check(band.get_global_rect().end.y >= status.get_global_rect().end.y, "the title band %s covers the status line %s" % [str(band.get_global_rect()), str(status.get_global_rect())])
			check(band.get_global_rect().size.x >= screen.size.x - 1.0, "the title band spans the screen")

		# The screen changes size (a Deck docked to a monitor, a window resized): the menu rebuilds to fit.
		vp.size_2d_override = Vector2i(1100, 800)
		await frames(6)
		check(arcade.grid != null and is_instance_valid(arcade.grid) and arcade.grid.columns == 1,
			"a narrow screen rebuilds the menu with 1 column (got %d)" % (arcade.grid.columns if is_instance_valid(arcade.grid) else -1))
		vp.size_2d_override = Vector2i(stretched(sc.size))
		await frames(6)
		check(is_instance_valid(arcade.grid) and arcade.grid.get_child_count() > 0, "and back again")

		# Start: the quit dialog (only where quitting is allowed).
		await tap(JOY_BUTTON_START)
		await frames(2)
		var open: bool = arcade.quit_panel != null and is_instance_valid(arcade.quit_panel)
		if bool(sc.can_quit):
			check(open, "Start opens the quit dialog on a %s" % label)
			if open:
				var texts := []
				for l in arcade.quit_panel.find_children("*", "Label", true, false):
					texts.append((l as Label).text)
				check(texts.has("Quit the arcade?"), "it asks \"Quit the arcade?\"")
				check(screen.encloses(arcade.quit_panel.get_global_rect()), "the quit dialog is on screen")
				await tap(JOY_BUTTON_B)
				await frames(2)
				check(arcade.quit_panel == null or not is_instance_valid(arcade.quit_panel), "B closes the quit dialog")
				await tap(JOY_BUTTON_START)
				await frames(2)
				check(arcade.quit_panel != null and is_instance_valid(arcade.quit_panel), "Start opens it again")
				await tap(JOY_BUTTON_START)
				await frames(2)
				check(arcade.quit_panel == null or not is_instance_valid(arcade.quit_panel), "Start closes it")
				await tap(JOY_BUTTON_START)
				await frames(2)
				await tap(JOY_BUTTON_A)  # ONE press on the highlighted "Keep playing"
				await frames(2)
				check(arcade.quit_panel == null or not is_instance_valid(arcade.quit_panel), "one A press on \"Keep playing\" closes it")
		else:
			check(not open, "Start does NOT open a quit dialog on the %s" % label)
			if open:
				arcade._toggle_quit_menu()

		# A on a card launches that game.
		await frames(2)
		var f2 := vp.gui_get_focus_owner()
		var want_scene := ""
		for i in arcade.cards:
			if arcade.cards[i] == f2:
				want_scene = str(arcade.GAMES[i].scene)
		check(want_scene != "", "a card is highlighted before pressing A")
		await tap(JOY_BUTTON_A)
		await frames(40)
		var cur := get_tree().current_scene
		check(cur != null and cur.scene_file_path == want_scene,
			"A launches the highlighted game %s (now running: %s)" % [want_scene, cur.scene_file_path if cur else "nothing"])
		vp.queue_free()
		await frames(30)  # let the game run a moment (its errors count too)
		# The game's pause menu (core/pause_menu.gd): Start, d-pad down twice, ONE A on "Back to Arcade" -> the arcade.
		var menus := get_tree().get_nodes_in_group("pause_menu")
		check(not menus.is_empty(), "the game has the shared pause menu")
		if not menus.is_empty():
			kit.allow_pause = true
			menus[0]._open(DEV)
			await frames(2)
			for i in 2:
				await press(JOY_BUTTON_DPAD_DOWN)
			var fb := get_viewport().gui_get_focus_owner()
			check(fb is Button and (fb as Button).text == "Back to Arcade", "d-pad down twice highlights Back to Arcade (got %s)" % (fb.get("text") if fb else "nothing"))
			await press(JOY_BUTTON_A)
			await frames(60)  # net.go_to_arcade waits 0.4 s
			var now := get_tree().current_scene
			check(now != null and now.scene_file_path == "res://arcade.tscn", "one A press on Back to Arcade goes back to the arcade (now: %s)" % (now.scene_file_path if now else "nothing"))
			check(not get_tree().paused, "the arcade is not paused")
			kit.allow_pause = false
