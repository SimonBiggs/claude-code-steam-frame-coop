extends Node
## Headless bot test: every game started as a Steam Deck would start it alone (DUO_MACHINE_KIND=deck, local play).
## Simon: "when I open the game it has two players on the one deck screen - but when I play on the deck I normally
## just have one player per deck". Per game:
## - the Deck's own controls (a pad connecting, then pressing A) give ONE player and at most ONE view on screen;
## - a second pad pressing A still drops in a second player (split screen, 2 views);
## - zero SCRIPT ERRORs (dev.bots greps them).
## Split in PARTS scenes (deck_bot, deck2_bot .. deck4_bot: every 4th game) so each fits dev.bots' 3600 frames.
## DECK_BOT_ONLY=id,id runs just those games (in any part). Run: dev.bots.all({only: ["deck", "deck2", "deck3", "deck4"]}), or
##   godot-test --headless --path . --fixed-fps 60 --quit-after 3600 res://tests/deck_bot.tscn

const BotKit := preload("res://tests/bot_kit.gd")
const PAD1 := 41  # the Deck's built-in controls
const PAD2 := 42  # a friend's pad
const PARTS := 4

## Which share of the games this scene runs (0..PARTS-1).
@export var part := 0


func _ready() -> void:
	var r := Runner.new()
	r.part = part
	r.name = "DeckBotRunner"
	get_tree().root.add_child.call_deferred(r)


class Runner extends Node:
	var kit: Node
	var game: Node
	var part := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		kit = BotKit.new()
		add_child(kit)
		kit.verbose = false
		OS.set_environment("DUO_MACHINE_KIND", "deck")
		OS.set_environment("DUO_SOLO", "1")
		if not OS.has_environment("DUO_PORT"):
			OS.set_environment("DUO_PORT", str(20000 + randi() % 10000))  # never the real 7777 (kids' Decks play there)
		for k in ["DUO_JOIN", "DUO_HOST", "BOT_VR"]:
			OS.unset_environment(k)
		_run()

	func frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	## A pad (dis)connects. Party games (core/party.gd) only seat bot pad ids (>= VIRTUAL_PAD_BASE) that are
	## plugged in as virtual pads (stale presses from unplugged pads are ignored), so register it there too.
	func plug(device: int, on: bool) -> void:
		var meta := "core_party_virtual_pads"  # core/party.gd VIRTUAL_META
		var pads: Array = Engine.get_meta(meta, [])
		if on and not pads.has(device):
			pads.append(device)
		elif not on:
			pads.erase(device)
		Engine.set_meta(meta, pads)
		Input.joy_connection_changed.emit(device, on)

	func press(device: int, button: JoyButton) -> void:
		for down in [true, false]:
			var e := InputEventJoypadButton.new()
			e.device = device
			e.button_index = button
			e.pressed = down
			Input.parse_input_event(e)
			await frames(3)

	## Split-screen views showing (visible SubViewportContainers with a real size).
	func views() -> int:
		var n := 0
		for c in game.find_children("*", "SubViewportContainer", true, false):
			var svc := c as SubViewportContainer
			if svc.is_visible_in_tree() and svc.size.x > 8.0 and svc.size.y > 8.0:
				n += 1
		return n

	## Every view on screen shows the game, not the plain grey clear colour of a SubViewport with no camera
	## (a split view whose Camera3D isn't current, e.g. a hidden prebuilt view: Deck mode builds the second
	## player's view before anyone joins). Headless: a current camera per view. Rendering (godot.launch of this
	## scene at 1280x800): also most sampled pixels must not be the default clear colour.
	func _views_render(id: String) -> void:
		var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.3, 0.3, 0.3))
		var drawn := DisplayServer.get_name() != "headless"
		if drawn:
			await RenderingServer.frame_post_draw
		for c in game.find_children("*", "SubViewportContainer", true, false):
			var svc := c as SubViewportContainer
			if not svc.is_visible_in_tree() or svc.size.x <= 8.0 or svc.size.y <= 8.0:
				continue
			for vp in svc.get_children():
				if not vp is SubViewport:
					continue
				var v := vp as SubViewport
				var cam3: Camera3D = v.get_camera_3d()
				var has_cam := (cam3 != null and cam3.is_inside_tree()) or _draws_2d(v)
				kit.assert_true(has_cam, "%s: view %s has a camera (no camera = a plain grey view)" % [id, svc.name])
				if not drawn or not has_cam:
					continue
				var img := v.get_texture().get_image()
				if img == null or img.is_empty():
					continue
				var greyish := 0
				var n := 0
				for yi in 12:
					for xi in 12:
						var px := img.get_pixel(int((xi + 0.5) * img.get_width() / 12.0), int((yi + 0.5) * img.get_height() / 12.0))
						n += 1
						if absf(px.r - clear.r) < 0.02 and absf(px.g - clear.g) < 0.02 and absf(px.b - clear.b) < 0.02:
							greyish += 1
				kit.assert_true(greyish * 10 < n * 6, "%s: view %s shows the game, not plain grey (%d/%d clear-colour pixels)" % [id, svc.name, greyish, n])

	## A view with no 3D camera at all is fine when it draws 2D (a Camera2D, or Node2D content of its own);
	## a view holding Camera3Ds none of which is current renders plain grey.
	func _draws_2d(v: SubViewport) -> bool:
		if not v.find_children("*", "Camera3D", true, false).is_empty():
			return false
		return not v.find_children("*", "Node2D", true, false).is_empty()

	## Players this machine controls: party seats, or classic players that have a view.
	func local_players() -> int:
		var party: Variant = game.get("party")
		if party is Node and (party as Node).has_method("local_slots"):
			return (party as Node).local_slots().size()
		return views()

	func _run() -> void:
		await frames(2)
		var only := OS.get_environment("DECK_BOT_ONLY").split(",", false) if OS.has_environment("DECK_BOT_ONLY") else PackedStringArray()
		var ids: Array[String] = []
		for d in DirAccess.get_directories_at("res://games"):
			if d != "engine_template" and FileAccess.file_exists("res://games/%s/main.tscn" % d) and (only.is_empty() or only.has(d)):
				ids.append(d)
		ids.sort()
		if only.is_empty():
			var mine: Array[String] = []
			for i in ids.size():
				if i % PARTS == part:
					mine.append(ids[i])
			ids = mine
		if part == 0:
			_source_checks()
		var bad: Array[String] = []
		for id in ids:
			var before: int = kit.failures
			await _game(id)
			if kit.failures > before:
				bad.append(id)
		kit.info("deck bot: %d games, %d with problems %s" % [ids.size(), bad.size(), str(bad)])
		kit.finish()

	func _game(id: String) -> void:
		if get_tree().current_scene != null:
			get_tree().unload_current_scene()
		await frames(2)
		get_tree().paused = false
		for m in Engine.get_meta_list():
			if str(m).begins_with("core_party"):
				Engine.remove_meta(m)  # a fresh launch: nobody seated from the previous game
		game = load("res://games/%s/main.tscn" % id).instantiate()
		get_tree().root.add_child(game)
		get_tree().current_scene = game
		kit.main = game
		await frames(60)
		# The Deck's controls appear (connected) and press A, like someone starting to play.
		plug(PAD1, true)
		await frames(10)
		await press(PAD1, JOY_BUTTON_A)
		await frames(40)
		var v1 := views()
		var p1 := local_players()
		kit.assert_true(v1 <= 1, "%s: the Deck shows one view, not split screen (%d views)" % [id, v1])
		kit.assert_true(p1 <= 1, "%s: one player on the Deck (%d local players)" % [id, p1])
		await _views_render(id)
		await press(PAD1, JOY_BUTTON_A)
		await frames(20)
		kit.assert_true(views() <= 1, "%s: pressing A again on the Deck's own controls adds nobody (%d views)" % [id, views()])
		# A friend's pad drops in: split screen.
		plug(PAD2, true)
		await frames(10)
		await press(PAD2, JOY_BUTTON_A)
		await frames(60)
		var p2 := local_players()
		kit.assert_true(p2 == 2 or views() == 2, "%s: a second pad pressing A drops in a second player (%d players, %d views)" % [id, p2, views()])
		await _views_render(id)
		kit.info("%s: deck alone %d view(s) / %d player(s); with a friend %d view(s) / %d player(s)" % [id, v1, p1, views(), p2])
		# Start's pause menu: it alone says PAUSED (a game's own PAUSED card used to show through its buttons).
		var menus := get_tree().get_nodes_in_group("pause_menu")
		if not menus.is_empty() and is_instance_valid(menus[0]):
			kit.allow_pause = true
			menus[0]._open(PAD1)
			await frames(10)
			var paused_labels := 0
			for l in get_tree().root.find_children("*", "Label", true, false):
				if (l as Label).is_visible_in_tree() and (l as Label).text.strip_edges().begins_with("PAUSED"):
					paused_labels += 1
			kit.assert_true(paused_labels == 1, "%s: the pause menu says PAUSED once (%d PAUSED labels on screen)" % [id, paused_labels])
			menus[0]._resume()
			await frames(5)
			kit.allow_pause = false
		plug(PAD2, false)
		plug(PAD1, false)
		await frames(5)

	## Pattern guard (one ant -> the whole nest): every split-screen (classic) game goes through core/classic_seats.gd's
	## deck_solo() on a Deck alone, and no game re-adds its own Deck keyboard rule (it lives in core/party.gd).
	func _source_checks() -> void:
		for d in DirAccess.get_directories_at("res://games"):
			var path := "res://games/%s/main.gd" % d
			if not FileAccess.file_exists(path):
				continue
			var src := FileAccess.get_file_as_string(path)
			if src.contains("func _layout_views") and not src.contains("deck_solo("):
				kit.assert_true(false, "%s lays out split views but never calls seats.deck_solo() (core/classic_seats.gd): a Deck would show two players" % path)
			for line in src.split("\n"):
				if line.contains("allow_keyboard") and line.contains("deck") and not line.strip_edges().begins_with("#"):
					kit.assert_true(false, "%s sets its own Deck keyboard rule (core/party.gd does it): %s" % [path, line.strip_edges()])
