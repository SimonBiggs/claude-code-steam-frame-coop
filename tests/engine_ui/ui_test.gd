extends "res://tests/engine_ui/part_base.gd"
## UI part of the engine test: ui_kit widgets, per-device menus driven by injected joypad/keyboard
## events, the VR menu with a fake pointing hand, dialogue with choices (TV + VR), HUD popups, hints
## and the awards results screen.

const UiKit := preload("res://core/ui_kit.gd")
const UiInput := preload("res://core/ui_input.gd")
const UiMenu := preload("res://core/ui_menu.gd")
const VrMenu := preload("res://core/vr_menu.gd")

const Party := preload("res://core/party.gd")
const VrRig := preload("res://core/vr_rig.gd")
const SplitView := preload("res://core/split_view.gd")

const PAD_A := 61  # fake controllers (real pads on this machine use low ids)
const PAD_B := 62

var root: Control
var world: Node3D
var cam: Camera3D
var hand: Node3D


func run() -> void:
	tag = "ui"
	_setup_world()
	await _test_kit()
	await _test_input()
	await _test_menus()
	await _test_grid_tabs()
	await _test_vr_menu()
	for extra in ["_test_dialogue", "_test_hud", "_test_hud_extra", "_test_hints", "_test_awards", "_test_systems"]:
		if has_method(extra):
			await call(extra)
	await frames(2)


func _setup_world() -> void:
	root = UiKit.ui_root(self)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	cam = Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 1.6, 0)
	cam.current = true
	hand = Node3D.new()
	hand.name = "FakeHand"
	world.add_child(hand)
	hand.position = Vector3(0.2, 1.3, -0.3)


# --- helpers ---------------------------------------------------------------------------------------

func pad_button(device: int, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


## Press and release a joypad button over a few frames (polling UIs need to see it held).
func tap_pad(device: int, button: JoyButton) -> void:
	pad_button(device, button, true)
	await frames(2)
	pad_button(device, button, false)
	await frames(2)


func tap_key(key: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := InputEventKey.new()
	u.physical_keycode = key
	u.pressed = false
	Input.parse_input_event(u)
	await frames(2)


func stick(device: int, y: float) -> void:
	var m := InputEventJoypadMotion.new()
	m.device = device
	m.axis = JOY_AXIS_LEFT_Y
	m.axis_value = y
	Input.parse_input_event(m)


# --- tests -----------------------------------------------------------------------------------------

func _test_kit() -> void:
	check(UiKit.scale_for_size(Vector2(1920, 1080)) == 1.0, "scale 1 at 1080p")
	check(UiKit.scale_for_size(Vector2(640, 540)) == 0.55, "small split cell clamps to 0.55")
	var t1 := UiKit.theme(1.0)
	check(t1 == UiKit.theme(1.01), "theme cached per scale step")
	check(t1.get_font_size("font_size", "TitleLabel") == 64, "title size 64 at scale 1")
	check(UiKit.theme(0.5).get_font_size("font_size", "TitleLabel") == 32, "title size scales")
	var p := UiKit.panel("card")
	var v := UiKit.vbox()
	p.add_child(v)
	v.add_child(UiKit.title("HELLO ARCADE"))
	v.add_child(UiKit.label("Body text", "body"))
	v.add_child(UiKit.paragraph("A wrapped paragraph that goes on for a while to test wrapping.", "small", "dim"))
	v.add_child(UiKit.badge("LV 5", "gold", 1.0, "star"))
	v.add_child(UiKit.prompts([["A", "Select"], ["B", "Back"], ["START", "Menu"]]))
	var icons := UiKit.hbox()
	for k in ["heart", "star", "coin", "gem", "sword", "shield", "potion", "skull", "check", "cross", "arrow_up",
			"arrow_down", "arrow_left", "arrow_right", "play", "clock", "bolt", "crown", "lock", "dot", "plus", "minus",
			"flag", "key", "music", "bag", "fire", "drop", "eye", "person", "trophy", "question", "exclaim"]:
		icons.add_child(UiKit.icon(k, "accent", 28.0))
	v.add_child(icons)
	var hp := UiKit.bar("hp", 300, 24)
	hp.show_numbers = true
	hp.prefix = "HP"
	v.add_child(hp)
	var mp := UiKit.stat_bar("MP", "mp", 240)
	v.add_child(mp)
	root.add_child(p)
	UiKit.pop_in(p)
	await frames(3)
	check(p.size.x > 100 and p.size.y > 100, "kit panel laid out (%s)" % p.size)
	hp.set_value(100, 100, false)
	hp.set_value(20)
	await wait(0.3)
	check(hp.ghost > hp.shown, "hp bar ghost chip trails the damage")
	await wait(1.2)
	check(absf(hp.shown - 20.0) < 0.5 and absf(hp.ghost - 20.0) < 0.5, "hp bar settles (%.1f, %.1f)" % [hp.shown, hp.ghost])
	check(UiKit.hp_color(0.1).r > 0.9 and UiKit.hp_color(1.0).g > 0.8, "hp colours")
	var l := UiKit.label("0", "number")
	root.add_child(l)
	UiKit.count_up(l, 0, 250, 0.3, "%d PTS")
	await wait(0.5)
	check(l.text == "250 PTS", "count up reaches target (%s)" % l.text)
	UiKit.shake(p)
	UiKit.pulse(p)
	UiKit.pop_out(p)
	l.queue_free()
	var wrapped := UiKit.wrap_text("one two three four five six seven eight nine ten", 200.0, 30)
	check(wrapped.count("\n") >= 1, "wrap_text breaks lines")
	var pm := UiKit.panel_mesh(Vector2(1, 0.5))
	check(pm.get_surface_count() == 1 and pm.surface_get_array_len(0) > 30, "panel mesh built")
	UiKit.sound("ui_move")
	await frames(2)
	UiKit.sound("ui_select")
	await wait(0.4)


func _test_input() -> void:
	var r := UiInput.new(PAD_A, UiInput.KEYS_NONE)
	pad_button(PAD_A, JOY_BUTTON_A, true)
	await frames(1)
	r.latch()
	var got := r.poll(0.016)
	check(not got.has("confirm"), "latched A held from before is ignored")
	pad_button(PAD_A, JOY_BUTTON_A, false)
	await frames(1)
	r.poll(0.016)
	pad_button(PAD_A, JOY_BUTTON_A, true)
	await frames(1)
	got = r.poll(0.016)
	check(got.has("confirm"), "fresh A press is a confirm")
	pad_button(PAD_A, JOY_BUTTON_A, false)
	var other := UiInput.new(PAD_B, UiInput.KEYS_NONE)
	pad_button(PAD_A, JOY_BUTTON_DPAD_DOWN, true)
	await frames(1)
	check(other.poll(0.016).is_empty(), "another player's reader ignores pad A")
	var repeats := 0
	r.poll(0.016)
	for i in 40:
		repeats += r.poll(0.05).count("down")
	pad_button(PAD_A, JOY_BUTTON_DPAD_DOWN, false)
	await frames(1)
	check(repeats >= 10, "held direction repeats (%d)" % repeats)
	var fake := Node3D.new()
	add_child(fake)
	var vr := UiInput.new(UiInput.PAD_NONE, UiInput.KEYS_NONE, fake)
	vr.poll(0.016)
	fake.set_meta("trigger", 1.0)
	check(vr.poll(0.016).has("confirm"), "fake VR hand trigger confirms")
	fake.queue_free()


func _test_menus() -> void:
	# Two players, two menus, two controllers: each only hears its own pad.
	var chosen_a := []
	var chosen_b := []
	var ma := UiMenu.open(root, {"title": "COMMAND", "player": 1, "device": PAD_A, "keys": UiMenu.KEYS_NONE, "anchor": "left",
		"items": [{"id": "attack", "text": "Attack", "icon": "sword", "desc": "Hit one enemy."},
			{"id": "fire", "text": "Fireball", "icon": "fire", "right": "6 MP", "disabled": true, "reason": "Not enough MP"},
			{"id": "guard", "text": "Guard", "icon": "shield"}, "Run"]})
	var mb := UiMenu.open(root, {"title": "SHOP", "player": 2, "device": PAD_B, "keys": UiMenu.KEYS_NONE, "anchor": "right",
		"items": ["Potion", "Ether", "Sword", "Shield", "Bow", "Arrows", "Map", "Lantern", "Rope", "Bomb"], "max_rows": 4})
	ma.chosen.connect(func(id: String, _it: Dictionary) -> void: chosen_a.append(id))
	mb.chosen.connect(func(id: String, _it: Dictionary) -> void: chosen_b.append(id))
	var rejected := []
	ma.rejected.connect(func(id: String, _it: Dictionary) -> void: rejected.append(id))
	await frames(3)
	check(ma.is_open and mb.is_open, "two menus open")
	check(UiMenu.device_busy(PAD_A) and not UiMenu.device_busy(55), "device_busy registry")
	await tap_pad(PAD_A, JOY_BUTTON_DPAD_DOWN)
	check(ma.focused_id() == "fire" and mb.focused_id() == "Potion", "pad A moves only menu A (%s/%s)" % [ma.focused_id(), mb.focused_id()])
	await tap_pad(PAD_A, JOY_BUTTON_A)
	check(rejected == ["fire"] and ma.is_open, "disabled item rejected with reason")
	check(ma._desc_label.text.contains("Not enough MP"), "reason shown in the description")
	# stick down to 'guard'
	stick(PAD_A, 0.9)
	await frames(2)
	stick(PAD_A, 0.0)
	await frames(2)
	check(ma.focused_id() == "guard", "stick moves focus (%s)" % ma.focused_id())
	# B scrolls down a long list
	for i in 6:
		await tap_pad(PAD_B, JOY_BUTTON_DPAD_DOWN)
	check(mb.focused_id() == "Map", "menu B focus moved 6 (%s)" % mb.focused_id())
	await frames(15)
	check(mb._scroll.scroll_vertical > 0, "long list scrolled (%d)" % mb._scroll.scroll_vertical)
	await tap_pad(PAD_A, JOY_BUTTON_A)
	await tap_pad(PAD_B, JOY_BUTTON_A)
	check(chosen_a == ["guard"] and chosen_b == ["Map"], "both players chose (%s, %s)" % [chosen_a, chosen_b])
	await wait(0.4)
	check(not is_instance_valid(ma) and not is_instance_valid(mb), "menus freed after choosing")
	check(not UiMenu.device_busy(PAD_A), "device released after close")
	# Keyboard menu (arrows set) + cancel + wrap-around
	var cancelled := [false]
	var mk := UiMenu.open(root, {"title": "KEYBOARD", "keys": UiMenu.KEYS_ARROWS, "items": ["One", "Two", "Three"]})
	mk.cancelled.connect(func() -> void: cancelled[0] = true)
	await frames(2)
	await tap_key(KEY_UP)
	check(mk.focused_id() == "Three", "wrap-around up (%s)" % mk.focused_id())
	await tap_key(KEY_W)
	check(mk.focused_id() == "Three", "WASD ignored by an arrows-only menu")
	await tap_key(KEY_BACKSPACE)
	check(cancelled[0], "backspace cancels")
	await wait(0.3)
	# press() injection, set_items, set_disabled, choose_id
	var mi := UiMenu.open(root, {"items": ["a", "b", "c"], "close_on_choose": false, "device": UiMenu.PAD_NONE, "keys": UiMenu.KEYS_NONE})
	var got := []
	mi.chosen.connect(func(id: String, _it: Dictionary) -> void: got.append(id))
	await frames(2)
	mi.press("down")
	mi.press("confirm")
	mi.set_items(["x", "y"])
	mi.set_disabled("y", true, "nope")
	mi.choose_id("x")
	mi.choose_id("y")
	check(got == ["b", "x"] and mi.is_open, "press()/set_items/set_disabled/choose_id (%s)" % [got])
	mi.close()
	await wait(0.3)


func _test_grid_tabs() -> void:
	var inv := []
	for i in 14:
		inv.append({"id": "it%d" % i, "text": "Item %d" % i, "icon": ["potion", "gem", "key", "coin"][i % 4], "badge": "x%d" % (i + 1),
			"disabled": i == 5, "reason": "Too heavy"})
	var m := UiMenu.open(root, {"title": "BAG", "player": 3, "device": PAD_A, "keys": UiMenu.KEYS_NONE, "columns": 4,
		"max_rows": 2, "tabs": [{"title": "ITEMS", "items": inv}, {"title": "GEAR", "items": ["Helmet", "Boots"]}, {"title": "KEY", "items": []}]})
	await frames(3)
	await tap_pad(PAD_A, JOY_BUTTON_DPAD_RIGHT)
	await tap_pad(PAD_A, JOY_BUTTON_DPAD_DOWN)
	check(m.focused_id() == "it5", "grid right+down (%s)" % m.focused_id())
	await tap_pad(PAD_A, JOY_BUTTON_DPAD_DOWN)
	check(m.focused_id() == "it9", "grid down again (%s)" % m.focused_id())
	await tap_pad(PAD_A, JOY_BUTTON_DPAD_DOWN)
	check(m.focused_id() == "it13", "grid last row (%s)" % m.focused_id())
	await tap_pad(PAD_A, JOY_BUTTON_RIGHT_SHOULDER)
	check(m.tab == 1 and m.focused_id() == "Helmet", "RB switches tab (%d %s)" % [m.tab, m.focused_id()])
	await tap_pad(PAD_A, JOY_BUTTON_RIGHT_SHOULDER)
	check(m.tab == 2 and m.items.is_empty(), "empty tab ok")
	await tap_pad(PAD_A, JOY_BUTTON_A)
	await tap_pad(PAD_A, JOY_BUTTON_B)
	await wait(0.3)
	check(not is_instance_valid(m), "B closes the grid menu")


func _test_vr_menu() -> void:
	cam.global_position = Vector3(0, 1.6, 0)
	cam.rotation = Vector3.ZERO
	var m := VrMenu.open(world, {"title": "YOUR TURN", "cam": cam, "hand": hand, "items": [
		{"id": "attack", "text": "Attack", "desc": "Swing your sword"}, {"id": "magic", "text": "Magic", "right": "MP 6"},
		{"id": "item", "text": "Item", "disabled": true, "reason": "Bag is empty"}, "Run"]})
	var got := []
	m.chosen.connect(func(id: String, _it: Dictionary) -> void: got.append(id))
	await frames(3)
	check(m.global_position.z < -1.5 and m.global_position.z > -2.6, "VR menu placed in front at a comfortable distance (%s)" % m.global_position)
	check(m.get_parent() == world, "VR menu is world-space (not on the camera)")
	# Point at the 2nd row: aim the hand at its centre.
	var rect: Rect2 = m._cell_rects[1]
	var target: Vector3 = m.to_global(Vector3(rect.get_center().x, rect.get_center().y, 0))
	hand.look_at(target, Vector3.UP)
	await frames(2)
	check(m.index == 1, "pointing focuses the row (%d)" % m.index)
	check(m._laser.visible and m._dot.visible, "laser and dot visible on the panel")
	hand.set_meta("trigger", 1.0)
	await frames(2)
	hand.set_meta("trigger", 0.0)
	await frames(2)
	check(got == ["magic"], "trigger chooses the pointed row (%s)" % [got])
	await wait(0.3)
	check(not is_instance_valid(m), "VR menu freed after choosing")
	# Stick + A, disabled item, and touch (reach mode)
	var m2 := VrMenu.open(world, {"items": ["Yes", {"id": "no", "text": "No", "disabled": true, "reason": "Too late"}, "Maybe"],
		"cam": cam, "hand": hand, "reach": true, "columns": 1})
	var got2 := []
	var rej := []
	m2.chosen.connect(func(id: String, _it: Dictionary) -> void: got2.append(id))
	m2.rejected.connect(func(id: String, _it: Dictionary) -> void: rej.append(id))
	hand.position = Vector3(0.6, 0.5, 0.5)
	hand.look_at(Vector3(2, 0, 2))
	await frames(2)
	hand.set_meta("primary", Vector2(0, -1))
	await frames(2)
	hand.set_meta("primary", Vector2.ZERO)
	await frames(1)
	hand.set_meta("ax_button", true)
	await frames(2)
	hand.set_meta("ax_button", false)
	await frames(2)
	check(rej == ["no"], "stick + A on a disabled VR item is rejected (%s)" % [rej])
	var r3: Rect2 = m2._cell_rects[2]
	var tip_target: Vector3 = m2.to_global(Vector3(r3.get_center().x, r3.get_center().y, 0))
	hand.look_at(tip_target + Vector3(0, 0, -0.01), Vector3.UP)
	hand.global_position = tip_target + hand.global_basis.z * 0.04
	await frames(3)
	check(got2 == ["Maybe"], "touching a VR option chooses it (%s)" % [got2])
	await wait(0.3)
	hand.position = Vector3(0.2, 1.3, -0.3)
	hand.rotation = Vector3.ZERO


func _test_dialogue() -> void:
	const Dialogue := preload("res://core/dialogue.gd")
	var view2 := UiKit.ui_root(self, 6)
	var dlg: Dialogue = Dialogue.new()
	add_child(dlg)
	dlg.add_tv_view(root)
	dlg.add_tv_view(view2)
	dlg.set_vr(cam, hand, world)
	var events := []
	var choices := []
	dlg.event.connect(func(n: String, _l: Dictionary) -> void: events.append(n))
	dlg.choice_made.connect(func(id: String, _i: int) -> void: choices.append(id))
	var done := [false]
	dlg.finished.connect(func() -> void: done[0] = true)
	var script := [
		{"speaker": "ELDER", "color": "gold", "text": "Welcome, {hero}! The village has waited a long time for you.", "event": "hello"},
		{"speaker": "ELDER", "text": "Will you help us?", "device": PAD_A, "choices": [
			{"text": "Of course!", "id": "yes", "goto": "yes", "set": {"helping": true}},
			{"text": "Not today", "id": "no", "goto": "no"}]},
		{"label": "yes", "if": "helping", "speaker": "ELDER", "text": "Wonderful! Take this map.", "portrait": "star", "event": "got_map"},
		{"goto": "end"},
		{"label": "no", "speaker": "ELDER", "text": "Oh... come back soon."},
		{"label": "end", "set": {"talked": true}},
	]
	dlg.play(script, {"vars": {"hero": "Sir Bun"}, "device": PAD_A, "keys": UiInput.KEYS_NONE})
	await frames(3)
	check(dlg.is_playing() and dlg.pos == 0 and dlg.typing, "dialogue started typing")
	check(dlg._full.begins_with("Welcome, Sir Bun!"), "vars substituted")
	check(dlg._tv.size() == 2 and dlg._vr != null, "boxes on both TV views and in VR")
	await wait(0.4)
	var tv0: Control = dlg._tv[0]
	var partial: int = tv0.get("text").visible_characters
	check(partial > 3 and partial < dlg._full.length(), "typewriter reveals gradually (%d)" % partial)
	await tap_pad(PAD_A, JOY_BUTTON_A)
	check(not dlg.typing, "A finishes the typing")
	await tap_pad(PAD_A, JOY_BUTTON_A)
	check(dlg.pos == 1, "A advances (%d)" % dlg.pos)
	await wait(1.2)
	check(dlg._menu != null and is_instance_valid(dlg._menu), "choice menu opened for the chooser")
	await tap_pad(PAD_A, JOY_BUTTON_A)
	await frames(3)
	check(choices == ["yes"] and bool(dlg.vars.get("helping", false)), "choice made + set (%s)" % [choices])
	check(dlg.pos == 2 and dlg._full.begins_with("Wonderful"), "goto + if followed (%d)" % dlg.pos)
	await tap_pad(PAD_A, JOY_BUTTON_A)
	await tap_pad(PAD_A, JOY_BUTTON_A)
	await frames(3)
	check(done[0] and bool(dlg.vars.get("talked", false)), "conversation finished, end label ran")
	check(events == ["hello", "got_map"], "events fired (%s)" % [events])
	# hold to skip + VR chooser + wait/auto lines
	done[0] = false
	choices.clear()
	var long := []
	for i in 6:
		long.append({"speaker": "NARRATOR", "text": "Line number %d of a long cutscene." % i, "event": "e%d" % i})
	long.append({"speaker": "KNIGHT", "text": "Left or right?", "chooser": "vr", "choices": ["Left", "Right"]})
	long.append({"wait": 0.3})
	long.append({"speaker": "KNIGHT", "text": "Onwards!", "auto": 0.4})
	events.clear()
	dlg.play(long, {"device": PAD_A, "keys": UiInput.KEYS_NONE})
	await frames(2)
	pad_button(PAD_A, JOY_BUTTON_A, true)
	await wait(1.3)
	pad_button(PAD_A, JOY_BUTTON_A, false)
	await frames(2)
	check(dlg.pos == 6, "hold A skips to the choice (%d)" % dlg.pos)
	check(events.size() == 6, "skipping still fires events (%d)" % events.size())
	await wait(0.8)
	check(dlg._vr_menu != null and is_instance_valid(dlg._vr_menu), "VR chooser gets a VR menu")
	if dlg._vr_menu != null:
		dlg._vr_menu.call("press", "down")
		dlg._vr_menu.call("press", "confirm")
	await frames(2)
	check(choices == ["Right"], "VR choice (%s)" % [choices])
	await wait(2.5)
	check(done[0], "wait + auto lines finish by themselves")
	# remote mirror: input requests, host drives
	var mirror: Dialogue = Dialogue.new()
	add_child(mirror)
	mirror.add_tv_view(root)
	var asked := [0]
	mirror.advance_requested.connect(func() -> void: asked[0] += 1)
	mirror.play(script, {"remote": true, "device": PAD_B, "keys": UiInput.KEYS_NONE})
	mirror.show_line(0)
	await wait(2.0)
	await tap_pad(PAD_B, JOY_BUTTON_A)
	check(asked[0] == 1 and mirror.pos == 0, "remote mirror asks the host instead of advancing")
	mirror.show_line(4)
	await frames(2)
	check(mirror.pos == 4, "remote show_line")
	mirror.stop()
	dlg.say("GUARD", "Halt!", "bad")
	await frames(2)
	check(dlg.is_playing() and dlg.line.get("speaker") == "GUARD", "say() one-liner")
	dlg.stop()
	await wait(0.4)
	dlg.queue_free()
	mirror.queue_free()
	view2.get_parent().queue_free()


func _test_hud() -> void:
	const HudKit := preload("res://core/hud_kit.gd")
	var b := HudKit.banner(root, "WAVE 3", "The goblins are angry!", {"duration": 1.0})
	await wait(0.5)
	check(is_instance_valid(b) and b.get_child_count() >= 2, "banner shows")
	var long_b := HudKit.banner(root, "THIS IS A VERY VERY LONG BANNER TITLE INDEED", "", {"style": "victory", "duration": 0.6})
	await wait(1.4)
	check(not is_instance_valid(b) and not is_instance_valid(long_b), "banners close by themselves")
	var stay := HudKit.banner([root], "BOSS", "KING SLIME", {"style": "boss", "duration": 0.0})
	await wait(0.6)
	check(is_instance_valid(stay), "duration 0 banner stays")
	stay.call("dismiss")
	await wait(0.6)
	check(not is_instance_valid(stay), "dismiss() closes it")
	for i in 6:
		HudKit.toast(root, "Toast number %d" % i, {"icon": "star", "color": i, "sub": "a second line", "duration": 0.8})
	await frames(2)
	var stack := root.get_node_or_null("HudToasts_top_right")
	var live := 0
	for c in stack.get_children():
		if not c.is_queued_for_deletion():
			live += 1
	check(live <= 4, "toast stack keeps at most 4 (%d)" % live)
	HudKit.toast(root, "Bottom toast", {"where": "bottom"})
	HudKit.toast(root, "Left toast", {"where": "top_left"})
	await wait(1.5)
	# world popups
	var p1 := HudKit.damage(world, Vector3(0, 1, -3), 42)
	var p2 := HudKit.damage(world, Vector3(0, 1, -3), 99, true)
	var p3 := HudKit.heal(world, Vector3(1, 1, -3), 30)
	var p4 := HudKit.score(world, Vector3(-1, 1, -3), 100)
	var p5 := HudKit.miss(world, Vector3(0, 1, -4))
	var p6 := HudKit.popup(world, Vector3(0, 2, -4), "LEVEL UP!", {"style": "xp", "camera": cam})
	var p7 := HudKit.damage(world, Vector3(0, 1, -3), -15)
	check(p2.text == "99!" and p3.text == "+30" and p7.text == "+15", "popup texts")
	check(p1.billboard == BaseMaterial3D.BILLBOARD_ENABLED and p6.billboard == BaseMaterial3D.BILLBOARD_DISABLED, "billboard on TV, faces a given camera")
	await wait(0.3)
	check(p1.global_position.y > 1.2, "popup rises")
	await wait(1.4)
	check(not is_instance_valid(p1) and not is_instance_valid(p2) and not is_instance_valid(p4) and not is_instance_valid(p5), "popups free themselves")
	# 3D bar
	var enemy := Node3D.new()
	world.add_child(enemy)
	var hp := HudKit.bar3d(enemy, {"max": 30, "name": "GOBLIN"})
	await frames(2)
	check(hp.get_parent() == enemy and hp.mesh_node.mesh.get_surface_count() == 1, "bar3d is one mesh on the target")
	hp.set_value(12)
	await wait(0.3)
	check(hp.ghost > hp.shown, "bar3d ghost chip")
	await wait(1.5)
	check(absf(hp.shown - 12.0) < 0.2, "bar3d settles")
	var hidden := HudKit.bar3d(enemy, {"max": 10, "hide_full": true, "kind": "mp", "offset": Vector3(0, 2.2, 0)})
	await frames(2)
	check(not hidden.visible, "hide_full hides a full bar")
	hidden.set_value(5)
	check(hidden.visible, "and shows it when not full")
	enemy.queue_free()
	# scoreboard
	var rows := [{"id": 0, "name": "KNIGHT", "score": 120, "color": 0}, {"id": 1, "name": "MAGE", "score": 300, "color": 1},
		{"id": 2, "name": "BARD", "score": 300, "color": 2}, {"id": 3, "name": "THIEF", "score": 40, "color": 3}]
	var ranked := HudKit.rank_rows(rows)
	check(int(ranked[0].rank) == 1 and int(ranked[1].rank) == 1 and int(ranked[2].rank) == 3, "ties share a rank")
	var board := HudKit.scoreboard(root, rows, {"title": "ROUND 1"})
	await wait(0.6)
	var knight_card: Control = board._cards["0"]
	var y0 := knight_card.position.y
	rows[0]["score"] = 900
	board.set_rows(rows)
	await wait(0.8)
	check(knight_card.position.y < y0, "rank change moves the row up (%.0f -> %.0f)" % [y0, knight_card.position.y])
	rows.append({"id": 4, "name": "CHEF", "score": 10, "color": 4})
	rows.remove_at(3)
	board.set_rows(rows)
	await wait(0.5)
	check(board._cards.has("4") and not board._cards.has("3"), "rows added/removed")
	board.queue_free()
	var mini_board := HudKit.scoreboard(root, rows, {"compact": true, "ascending": true, "format": "%d s"})
	await frames(3)
	check(mini_board.size.x > 50, "compact scoreboard")
	mini_board.queue_free()
	check(HudKit.ordinal(1) == "1ST" and HudKit.ordinal(12) == "12TH" and HudKit.ordinal(23) == "23RD", "ordinals")
	check(HudKit.clock_text(65.0) == "1:05" and HudKit.clock_text(9.46, true) == "0:09.5", "clock text")
	# countdowns
	var ticks := []
	var go := [false]
	var cd := HudKit.countdown(root, 3, {"step": 0.3})
	cd.tick.connect(func(n: int) -> void: ticks.append(n))
	cd.finished.connect(func() -> void: go[0] = true)
	var vcd := HudKit.vr_countdown(world, cam, 2, {"step": 0.3})
	await wait(1.6)
	check(ticks == [3, 2, 1] and go[0], "countdown ticks then GO (%s)" % [ticks])
	check(not is_instance_valid(cd) and not is_instance_valid(vcd), "countdowns free themselves")
	var timeouts := [0]
	var tp := HudKit.timer(root, {"seconds": 1.0, "warn": 5.0, "label": "TIME"})
	tp.timeout.connect(func() -> void: timeouts[0] += 1)
	await wait(1.4)
	check(timeouts[0] == 1, "timer counts down and fires timeout once")
	tp.queue_free()
	# VR cards
	var vb := HudKit.vr_banner(world, cam, "VICTORY!", "The dragon is defeated", {"style": "victory", "duration": 0.5})
	var vt := HudKit.vr_toast(world, cam, "P2 found a key", {"duration": 0.5})
	await frames(2)
	check(vb.global_position.distance_to(cam.global_position) > 2.0, "VR banner far from the eyes")
	check(vb.title_l.modulate.is_equal_approx(Color(1.0, 0.93, 0.6)), "VR banner title colour from style")
	await wait(1.0)
	check(not is_instance_valid(vb) and not is_instance_valid(vt), "VR cards auto-hide")


func _test_hints() -> void:
	const Hints := preload("res://core/hints.gd")
	var hints: Hints = Hints.new()
	add_child(hints)
	var view2 := UiKit.ui_root(self, 7)
	hints.add_view(root, 1)
	hints.add_view(view2, 2)
	hints.set_vr(cam, world, hand)
	hints.device = PAD_A
	hints.keys = UiInput.KEYS_NONE
	var done := [false]
	hints.intro_done.connect(func() -> void: done[0] = true)
	hints.intro({"title": "DUNGEON DASH", "goal": "Find the key and escape together!",
		"vr": {"role": "THE KNIGHT", "controls": [["TRIGGER", "Swing your sword"], ["STICK", "Walk"]]},
		"tv": {"role": "THE WIZARDS", "color": "magic", "controls": [["A", "Cast"], ["L-STICK", "Move"], ["B", "Dodge"], ["Y", "Potion"]],
			"tips": ["Stay near the knight!"]},
		"slots": {2: {"role": "THE ARCHER", "controls": [["RT", "Shoot"]]}}})
	await frames(3)
	check(hints.intro_showing() and hints._intro_nodes.size() == 3, "intro cards on 2 TV views + VR (%d)" % hints._intro_nodes.size())
	await tap_pad(PAD_A, JOY_BUTTON_A)
	check(hints.intro_showing(), "A too early does not dismiss (min time)")
	await wait(1.6)
	await tap_pad(PAD_A, JOY_BUTTON_A)
	check(done[0] and not hints.intro_showing(), "A dismisses the intro")
	var shown := []
	hints.hint_shown.connect(func(id: String, target: String) -> void: shown.append("%s>%s" % [id, target]))
	check(hints.hint("door", "Doors need a KEY: look for the gold glow!", {"icon": "key"}), "hint accepted")
	await frames(2)
	check(shown.has("door>tv:1") and shown.has("door>tv:2") and shown.has("door>vr"), "hint shown on every target (%s)" % [shown])
	check(not hints.hint("door", "again"), "once-only hint is not repeated")
	hints.hint("potion", "Low health! Drink a potion.", {"to": 2, "button": "Y", "times": 2, "cooldown": 0.5, "duration": 0.5})
	await frames(2)
	check(not shown.has("potion>tv:2"), "busy screen queues the next hint")
	await wait(8.0)
	check(shown.has("potion>tv:2"), "queued hint shows when the screen is free")
	await wait(1.0)
	hints.hint("potion", "Low health! Drink a potion.", {"to": 2, "button": "Y", "times": 2, "cooldown": 0.5, "duration": 0.5})
	await wait(4.0)
	check(shown.count("potion>tv:2") == 2, "times: 2 allows a second showing")
	hints.hint("potion", "Low health! Drink a potion.", {"to": 2, "times": 2, "cooldown": 0.5})
	await wait(4.0)
	check(shown.count("potion>tv:2") == 2, "but not a third")
	hints.hint("vr_only", "Swing!", {"to": 0, "vr_text": "Swing your sword!"})
	await wait(0.5)
	check(shown.has("vr_only>vr"), "slot 0 hint goes to VR")
	check(hints.was_shown("door") and hints.was_shown("door", "vr"), "was_shown")
	hints.reset("door")
	check(not hints.was_shown("door"), "reset")
	await wait(1.0)
	hints.queue_free()
	view2.get_parent().queue_free()


func _test_awards() -> void:
	const Awards := preload("res://core/awards.gd")
	var aw: Awards = Awards.new()
	aw.set_player(0, "KNIGHT", 0)
	aw.set_player(1, "MAGE", 1)
	aw.set_player(2, "BARD", 2)
	aw.set_player(3, "THIEF", 3)
	aw.set_player(4, "CHEF", 4)
	aw.add(0, "score", 1200)
	aw.add(1, "score", 900)
	aw.add(2, "score", 300)
	aw.add(3, "score", 650)
	aw.add(0, "damage", 500)
	aw.add(1, "damage", 120)
	aw.add(2, "revives", 3)
	aw.add(1, "spells", 14)
	aw.add(3, "coins", 77)
	aw.best(3, "best_time", 41.2, true)
	aw.best(3, "best_time", 39.0, true)
	aw.best(1, "best_time", 50.0, true)
	aw.add(4, "drops", 5)
	aw.define("pie_master", "PIE MASTER", "%s pies baked", "pies", "max", 1.0, "star")
	aw.add(4, "pies", 3)
	check(aw.get_stat(3, "best_time") == 39.0, "best() keeps the lowest time")
	var picked := aw.pick(6)
	var winners := {}
	for a in picked:
		winners[int(a.player)] = String(a.title)
	check(winners.size() == 5, "every player gets an award (%s)" % [winners])
	check(String(picked[0].title) == "PIE MASTER", "custom awards come first (%s)" % picked[0].title)
	var data := aw.results({"title": "VICTORY!", "subtitle": "The dragon is defeated", "style": "victory",
		"stats": [["TIME", "4:12"], ["ROUNDS", "3"]], "score_format": "%d PTS"})
	check((data.rows as Array).size() == 5 and String(data.rows[0].name) == "KNIGHT", "standings ranked")
	var bytes := var_to_bytes(data)
	check(bytes_to_var(bytes) is Dictionary, "results data is plain (network safe)")
	var screen := Awards.results_screen(root, data, {"device": PAD_A, "keys": UiInput.KEYS_NONE, "min_time": 1.0})
	var cont := [false]
	screen.continued.connect(func() -> void: cont[0] = true)
	var vrs := Awards.vr_summary(world, cam, data, hand, {"min_time": 0.5})
	var vr_cont := [false]
	vrs.continued.connect(func() -> void: vr_cont[0] = true)
	await frames(3)
	await tap_pad(PAD_A, JOY_BUTTON_A)
	check(not cont[0], "results ignore A before min_time")
	await wait(3.5)
	check(screen._revealed == (data.awards as Array).size(), "award cards revealed one by one (%d)" % screen._revealed)
	await tap_pad(PAD_A, JOY_BUTTON_A)
	check(cont[0], "A continues")
	hand.set_meta("trigger", 1.0)
	await frames(3)
	hand.set_meta("trigger", 0.0)
	check(vr_cont[0], "trigger continues the VR summary")
	await wait(0.5)
	check(not is_instance_valid(screen), "results screen closes")
	# narrow (split-screen) layout
	var sv := SubViewport.new()
	sv.size = Vector2i(640, 540)
	add_child(sv)
	var small_root := UiKit.ui_root(sv)
	await frames(2)
	check(UiKit.scale_of(small_root) < 0.7, "split view root scales down (%.2f)" % UiKit.scale_of(small_root))
	var s2 := Awards.results_screen(small_root, data, {"min_time": 0.1})
	await wait(0.5)
	check(is_instance_valid(s2), "results in a small view")
	var m := UiMenu.open(small_root, {"title": "SMALL", "items": ["A", "B"], "device": PAD_B, "keys": UiMenu.KEYS_NONE})
	await frames(3)
	check(m.size.x <= 640.0, "menu fits a small view (%.0f)" % m.size.x)
	var w_small := m.size.x
	sv.size = Vector2i(1920, 1080)  # split screen re-layout: the view grows
	await frames(4)
	check(absf(UiKit.scale_of(small_root) - 1.0) < 0.01 and m.size.x > w_small * 1.5, "root and menu rescale with the view (%.0f)" % m.size.x)
	sv.queue_free()
	await frames(2)


func _test_hud_extra() -> void:
	const HudKit := preload("res://core/hud_kit.gd")
	var members := []
	for i in 6:
		members.append({"player": i, "name": ["KNIGHT", "MAGE", "BARD", "THIEF", "CHEF", "ROBOT"][i], "level": 3 + i,
			"hp": [80 - i * 10, 100], "mp": [20, 30], "icon": ["sword", "star", "music", "key", "potion", "bolt"][i]})
	var bar := HudKit.party_bar(root, members)
	await frames(3)
	check(bar.get_child_count() == 6, "party bar with 6 status cards")
	var c0: HudKit.StatusCard = bar.get_child(0)
	c0.set_hp(10)
	c0.set_mp(5, 30)
	c0.set_level(4)
	c0.set_status("POISON")
	c0.set_active(true)
	await wait(1.2)
	check(absf(c0.hp_bar.shown - 10.0) < 0.5 and c0.status_label.visible, "status card updates")
	bar.queue_free()
	var npc := Node3D.new()
	world.add_child(npc)
	var np := HudKit.nameplate(npc, "P2 MAGE", 1)
	check(np.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y and np.get_parent() == npc, "nameplate over a target")
	var bub := HudKit.bubble3d(npc, "Hello there, adventurer! Lovely day for a quest.", {"duration": 0.5})
	await wait(0.3)
	check(is_instance_valid(bub) and bub.scale.x > 0.9, "speech bubble pops in")
	await wait(0.8)
	check(not is_instance_valid(bub), "speech bubble hides itself")
	npc.queue_free()
	var goals := HudKit.objectives(root, ["Find the key", {"id": "door", "text": "Open the door"}, {"text": "Escape", "done": false}])
	await frames(2)
	goals.set_done("door")
	check(not goals.all_done(), "objectives not all done")
	goals.set_done("Find the key")
	goals.set_done("Escape")
	check(goals.all_done(), "objectives all done")
	await wait(0.4)
	goals.queue_free()



class FakeMain extends Node:
	## Just enough of a game's main for core/party.gd (local mode, ready to play).
	var ready_to_play := true
	var net: Node = null
	var party: Node = null
	var vr_rig: Node = null


## The presentation modules driven through the engine systems: party seats, the VR rig, split views.
func _test_systems() -> void:
	const Dialogue := preload("res://core/dialogue.gd")
	const Awards := preload("res://core/awards.gd")
	Engine.set_meta(Party.BOT_IGNORE_META, true)  # real pads on this machine stay out of it
	var fm := FakeMain.new()
	fm.name = "FakeMain"
	add_child(fm)
	var party: Party = Party.new()
	party.name = "Party"
	party.auto_join_first_pad = false
	fm.party = party
	fm.add_child(party)
	await frames(2)
	var pa := party.add_virtual_pad()
	var pb := party.add_virtual_pad()
	var sa := party.join_device(pa)
	var sb := party.join_device(pb)
	await frames(3)
	check(sa >= 1 and sb >= 1 and sa != sb, "two party seats (%d, %d)" % [sa, sb])
	var got := []
	var m1 := UiMenu.open(root, {"party": party, "slot": sa, "items": ["Attack", "Magic", "Run"], "anchor": "left"})
	var m2 := UiMenu.open(root, {"party": party, "slot": sb, "items": ["Buy", "Sell"], "anchor": "right"})
	m1.chosen.connect(func(id: String, _it: Dictionary) -> void: got.append("a:" + id))
	m2.chosen.connect(func(id: String, _it: Dictionary) -> void: got.append("b:" + id))
	await frames(3)
	check(m1.player == sa and m1.accent == party.color_of(sa), "party menu takes the seat's colour")
	check(UiMenu.slot_busy(sa) and UiMenu.slot_busy(sb) and not UiMenu.slot_busy(5), "slot_busy registry")
	party.inject_button(pa, JOY_BUTTON_DPAD_DOWN, true)
	await frames(2)
	party.inject_button(pa, JOY_BUTTON_DPAD_DOWN, false)
	await frames(2)
	check(m1.focused_id() == "Magic" and m2.focused_id() == "Buy", "seat A's pad moves only its menu")
	party.inject_axis(pb, JOY_AXIS_LEFT_Y, 0.9)
	await frames(2)
	party.inject_axis(pb, JOY_AXIS_LEFT_Y, 0.0)
	await frames(2)
	check(m2.focused_id() == "Sell", "seat B's stick moves its menu (%s)" % m2.focused_id())
	party.inject_button(pa, JOY_BUTTON_A, true)
	party.inject_button(pb, JOY_BUTTON_A, true)
	await frames(2)
	party.inject_button(pa, JOY_BUTTON_A, false)
	party.inject_button(pb, JOY_BUTTON_A, false)
	await frames(2)
	check(got.has("a:Magic") and got.has("b:Sell"), "both seats chose (%s)" % [got])
	await wait(0.4)
	check(not UiMenu.slot_busy(sa), "seat released after the menu closed")
	# a menu opened while A is still held (it joined / chose with A) must wait for a release
	party.inject_button(pa, JOY_BUTTON_A, true)
	await frames(2)
	var held_got := []
	var m3 := UiMenu.open(root, {"party": party, "slot": sa, "items": ["Yes", "No"]})
	m3.chosen.connect(func(id: String, _it: Dictionary) -> void: held_got.append(id))
	await frames(3)
	check(held_got.is_empty(), "A held from before the menu opened doesn't choose")
	party.inject_button(pa, JOY_BUTTON_A, false)
	await frames(2)
	party.inject_button(pa, JOY_BUTTON_A, true)
	await frames(2)
	party.inject_button(pa, JOY_BUTTON_A, false)
	await frames(2)
	check(held_got == ["Yes"], "a fresh A chooses (%s)" % [held_got])
	await wait(0.3)
	# dialogue: any local seat advances
	var dlg: Dialogue = Dialogue.new()
	add_child(dlg)
	dlg.add_tv_view(root, sa)
	dlg.bind_party(party)
	var choice := []
	dlg.choice_made.connect(func(id: String, _i: int) -> void: choice.append(id))
	dlg.play([{"speaker": "INNKEEPER", "text": "Rooms are ten gold."}, {"text": "Stay the night?", "slot": sb, "choices": ["Yes", "No"]}])
	await wait(0.2)
	for k in 2:
		party.inject_button(pb, JOY_BUTTON_A, true)
		await frames(2)
		party.inject_button(pb, JOY_BUTTON_A, false)
		await frames(2)
	check(dlg.pos == 1, "seat B's A finishes and advances the dialogue (%d)" % dlg.pos)
	await wait(1.0)
	check(dlg._menu != null and int(dlg._menu.get("slot")) == sb, "choices go to the line's seat")
	party.inject_button(pb, JOY_BUTTON_DPAD_DOWN, true)
	await frames(2)
	party.inject_button(pb, JOY_BUTTON_DPAD_DOWN, false)
	party.inject_button(pb, JOY_BUTTON_A, true)
	await frames(2)
	party.inject_button(pb, JOY_BUTTON_A, false)
	await frames(3)
	check(choice == ["No"], "seat B answered (%s)" % [choice])
	dlg.queue_free()
	# the VR rig: pointing + the guarded trigger
	var rig: VrRig = VrRig.new()
	rig.make_mirror = false
	rig.fake_trigger = 1.0  # held over from the previous screen
	fm.vr_rig = rig
	world.add_child(rig)
	await frames(2)
	var vgot := []
	var vm := VrMenu.open(world, {"title": "TURN", "rig": rig, "items": ["Attack", "Defend", "Flee"]})
	vm.chosen.connect(func(id: String, _it: Dictionary) -> void: vgot.append(id))
	await frames(3)
	check(vm.cam == rig.camera and vm.hand == rig.hand_r, "VR menu takes the rig's camera and right hand")
	var rect: Rect2 = vm._cell_rects[2]
	rig.hand_r.look_at(vm.to_global(Vector3(rect.get_center().x, rect.get_center().y, 0)), Vector3.UP)
	await frames(3)
	check(vm.index == 2 and vgot.is_empty(), "held-over trigger doesn't choose while pointing (%d)" % vm.index)
	rig.fake_trigger = 0.0
	await frames(2)
	rig.fake_trigger = 1.0
	await frames(2)
	rig.fake_trigger = 0.0
	await frames(2)
	check(vgot == ["Flee"], "a fresh pull chooses the pointed option (%s)" % [vgot])
	await wait(0.3)
	# results screen (any seat) + VR summary (rig)
	var aw: Awards = Awards.new()
	aw.set_player(0, "HERO")
	aw.set_player(sa, "MAGE")
	aw.add(0, "score", 5)
	aw.add(sa, "score", 9)
	var data := aw.results({"title": "DONE"})
	var scr := Awards.results_screen(root, data, {"party": party, "min_time": 0.2})
	var sum := Awards.vr_summary(world, null, data, null, {"rig": rig, "min_time": 0.2})
	var cont := [0]
	scr.continued.connect(func() -> void: cont[0] += 1)
	sum.continued.connect(func() -> void: cont[0] += 10)
	await wait(0.5)
	party.inject_button(pb, JOY_BUTTON_A, true)
	rig.fake_trigger = 1.0
	await frames(2)
	party.inject_button(pb, JOY_BUTTON_A, false)
	rig.fake_trigger = 0.0
	await frames(2)
	check(cont[0] == 11, "results continue from a party seat and the VR trigger (%d)" % cont[0])
	await wait(0.5)
	# SplitView HUD roots are scaled: a UiKit root inside undoes that
	var split: SplitView = SplitView.new()
	add_child(split)
	split.set_slots([1, 2, 3])
	await frames(3)
	var hud_root := UiKit.ui_root(split.hud(1))
	await frames(3)
	var view_px := split.viewport(1).get_visible_rect().size
	var want := UiKit.scale_for_size(view_px)
	var got_scale := UiKit.scale_of(hud_root) * split.hud_scale(1)
	check(absf(got_scale - want) < 0.06, "UI in a split view ends up at the view's scale (%.2f vs %.2f)" % [got_scale, want])
	var hm := UiMenu.open(hud_root, {"party": party, "slot": sa, "items": ["One", "Two"]})
	await frames(3)
	check(hm.get_global_rect().size.x * split.hud_scale(1) <= view_px.x + 1.0, "a menu fits its split view")
	split.queue_free()
	rig.queue_free()
	fm.queue_free()
	Engine.remove_meta(Party.BOT_IGNORE_META)
	await frames(2)
