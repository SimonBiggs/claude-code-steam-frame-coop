extends Node
## FIRST GOAL (a service, core/services.gd): a first-time player sees, within seconds of play starting, WHAT THEY ARE
## and THE ONE THING TO DO FIRST, as a prompt with the right button for their device (TV / Deck pad glyph, VR trigger),
## plus an arrow over the thing to do it to. It fades with a cheer after their first small win and is remembered per
## profile, so it never nags again. Evidence: most arcade rounds ended within 1-4 min (telemetry); a VR guest on
## 2026-11-19 kept asking "What do I do?".
## Every game has ONE data file, found by itself (no game code changes):
##   games/<id>/first_goal.gd
##     const GOAL := {
##       "you": "a Balloon Popper",                    # what they are ("you_vr" / "you_tv" when it differs)
##       "do": {"tv": ["A", "Pop the balloon near you!"],         # [button glyph, the one thing to do]
##              "deck": [...],                                    # optional (default: tv)
##              "vr": ["TRIGGER", "Point at a balloon and pull!"]},
##       "start": "phase() == 'play'",       # optional: play has begun (default: no pick / intro / story card up)
##       "rise": "st('score0', 0)",          # the small win: this number goes up (or "done": a true/false expression)
##       "target": "nearest('balloons')",    # optional: a Node3D / Vector3 to put the arrow over
##       (any of start / rise / done / target / miss may have a "_vr" or "_tv" version: the VR player's own win)
##       "miss": "v('misses')",              # optional: a rising count of misses (core/rescue.gd struggling signal)
##       "flat_y": 0.5,                      # optional: where the TV / Deck card sits (share of the screen height,
##                                           #   default 0.82) when the game's own UI lives low (answer tiles)
##       "wordless": true, "icon": "star",   # optional: a game made without how-to words on purpose (the family found
##     }                                     #   games too text-driven; its bot fails on words): button glyph + icon
##                                           #   on the TV, only the arrow in VR. Needs a "target" or an "icon".
## Expressions (Godot Expression) run on this node with `main` (the game's main node) in scope, plus helpers:
##   v(prop, def)  main.get(prop)        st(key, def)  main.net state      phase()  net phase or main.phase
##   count(group)  nodes in a group      nearest(group) / nearest_of(array or dict)  the nearest to the player's camera
##   node(name)    main.find_child(name)  sum(x)  sum of an Array / Dictionary's numbers   local_slot()
## (Expression gotcha: a ternary inside parentheses doesn't parse; a top-level "a if c else b" does. `device` is in scope.)
## A broken expression is an engine ERROR from res:// (fails every bot), so all game bots check the data.
## Rescue: while the goal waits, core/rescue.gd ticks (time waiting without the win = struggling); a game's "miss"
## counter feeds it too. When help kicks in, the prompt pulses back bigger with its arrow (also after the first win,
## if the misses pile up). tests/first_goal_test.gd fails any game without data, or with missing / broken fields.
## Telemetry: RUN lines carry fg_secs (seconds to the first win, -1 = never) and fg_dev (core/telemetry.gd).

const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Rescue := preload("res://core/rescue.gd")
const Save := preload("res://core/save.gd")
const Machine := preload("res://core/machine.gd")
const VrViewCheck := preload("res://core/vr_view_check.gd")
const SAVE_PATH := "user://first_goals.cfg"
const DEVICES := ["tv", "deck", "vr"]
const REQUIRED := ["you", "do", "rise|done"]
## Seconds play must have been running (no pick / intro / story card) before the prompt shows.
const SETTLE := 0.6
## The prompt waits this long for its win, then shrinks to a corner reminder (rescue still pulses it back).
const SHRINK_AFTER := 40.0

var game := ""
var main: Node = null
var data: Dictionary = {}
var device := "tv"
var state := "idle"  # idle (no game) / wait (play not started) / show / done / off (already won before)
var t := 0.0
var play_t := 0.0
var win_secs := -1.0
var on_screen_t := -1.0  ## seconds after the game started that the prompt was first really on screen
var _on_screen := false
var rescue: Rescue = null
var _poll := 0.0
var _settle := 0.0
var _exprs := {}  # text -> Expression
var _failed := {}  # text -> true (reported once)
var _base := 0.0
var _miss_base := 0.0
var _rise_last := 0.0
var _layer: CanvasLayer = null
var _ui: Control = null
var _card: Control = null
var _vr_card: Node3D = null
var _arrow: Node3D = null
var _pulse := 0.0
var _small := false
var _after_t := 0.0
var _band := 0.82  ## where the TV card sits (share of the height): data flat_y, else the first band free of the game's HUD
var _band_t := 0.0
## Bands tried in turn: low (under the action), a little higher, then up under the top HUD.
const BANDS := [0.82, 0.66, 0.3]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.25:
		var dt := _poll
		_poll = 0.0
		_step(dt)
	_animate(delta)


# --- Finding the game ------------------------------------------------------------------------------------------------

static func game_of(n: Node) -> String:
	if n == null:
		return ""
	var p := n.scene_file_path
	if p.begins_with("res://games/") and p.ends_with("/main.tscn"):
		return p.get_slice("/", 3)
	return ""


func _find_main() -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	if game_of(cs) != "":
		return cs
	for c in cs.get_children():  # bots: tests/<id>_bot.tscn adds the game's main under itself
		if game_of(c) != "":
			return c
	return null


## The data of a game (empty when it has none).
static func data_of(id: String) -> Dictionary:
	var path := "res://games/%s/first_goal.gd" % id
	if not ResourceLoader.exists(path):
		return {}
	var s := load(path) as GDScript
	if s == null:
		return {}
	var c: Dictionary = s.get_script_constant_map()
	return c.get("GOAL", {})


## Problems with a game's data (tests/first_goal_test.gd): missing file / fields, unparsable expressions.
static func problems_of(id: String) -> Array[String]:
	var out: Array[String] = []
	var d := data_of(id)
	if d.is_empty():
		return ["%s: no games/%s/first_goal.gd with a GOAL (core/first_goal.gd)" % [id, id]]
	if String(d.get("you", "")).strip_edges() == "":
		out.append("%s: no \"you\" (what the player is)" % id)
	for dev in ["tv", "vr"]:
		var has_win := false
		for k in ["rise", "done", "rise_" + dev, "done_" + dev]:
			has_win = has_win or d.has(k)
		if not has_win:
			out.append("%s: no \"rise\" or \"done\" (the small win) for %s" % [id, dev])
	if bool(d.get("wordless", false)) and not d.has("target") and not d.has("icon"):
		out.append("%s: wordless needs a \"target\" (arrow) or an \"icon\"" % id)
	var dd: Dictionary = d.get("do", {})
	for dev in ["tv", "vr"]:
		var pair: Array = dd.get(dev, [])
		if pair.size() != 2 or String(pair[1]).strip_edges() == "":
			out.append("%s: \"do\".%s must be [button, text]" % [id, dev])
		elif String(pair[1]).length() > 44:
			out.append("%s: \"do\".%s text is %d letters (keep it under 45: one glance)" % [id, dev, String(pair[1]).length()])
	for k in d:
		var base := String(k).trim_suffix("_vr").trim_suffix("_tv")
		if base in ["start", "rise", "done", "target", "miss"]:
			var e := Expression.new()
			if e.parse(String(d[k]), ["main"]) != OK:
				out.append("%s: \"%s\" doesn't parse: %s" % [id, k, e.get_error_text()])
	return out


## Which games exist (every games/<id>/main.tscn).
static func game_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://games")
	if dir == null:
		return out
	for d in dir.get_directories():
		if ResourceLoader.exists("res://games/%s/main.tscn" % d) and d != "engine_template":
			out.append(d)
	out.sort()
	return out


# --- The loop -------------------------------------------------------------------------------------------------------

func _step(dt: float) -> void:
	var m := _find_main()
	if m != main:
		_reset()
		main = m
		game = game_of(m)
		if main != null:
			data = data_of(game)
			if not data.is_empty():
				state = "wait"
				device = _device()
				rescue = Rescue.new()
	if main == null or data.is_empty() or not is_instance_valid(main):
		return
	t += dt
	if device != "vr" and _device() == "vr":  # the headset joined late (VR watch)
		device = "vr"
		_drop_ui()
	match state:
		"wait":
			if _blocked() or not _truthy("start", true):
				_settle = 0.0
				return
			_settle += dt
			if _settle < SETTLE:
				return
			_base = _num("rise")
			_rise_last = _base
			_miss_base = _num("miss")
			if _remembered():
				state = "off"
				return
			state = "show"
			play_t = 0.0
			print("FIRST GOAL: %s %s shown %.1f s after the game started" % [game, device, t])
			_show()
		"show":
			play_t += dt
			var blocked := _blocked()
			_set_visible(not blocked)
			if blocked:
				return
			_band_t -= dt
			if _band_t <= 0.0 and device != "vr":
				_band_t = 0.5
				_pick_band()
			if not _on_screen:
				_on_screen = true
				on_screen_t = t
				print("FIRST GOAL: %s %s on screen %.1f s after the game started" % [game, device, t])
			_feed_rescue(dt, true)
			if _won():
				_win()
			elif play_t > SHRINK_AFTER and not _small:
				_shrink(true)
		"done", "off":
			_after_t += dt
			if _after_t < 90.0 and data.has(_k("miss")):
				_feed_rescue(dt, false)
	_place_arrow()


func _feed_rescue(dt: float, waiting: bool) -> void:
	if rescue == null:
		return
	var r := _num("rise")
	if data.has(_k("rise")) and r > _rise_last:
		rescue.note(true)
	_rise_last = r
	if data.has(_k("miss")):
		var m := _num("miss")
		while m > _miss_base and m - _miss_base < 50:
			rescue.note(false)
			_miss_base += 1.0
		_miss_base = m
	rescue.tick(dt, waiting and not _blocked())
	if rescue.crossed():
		_help()


func _won() -> bool:
	if data.has(_k("done")) and _truthy("done", false):
		return true
	return data.has(_k("rise")) and _num("rise") > _base + 0.001


func _win() -> void:
	state = "done"
	win_secs = play_t
	print("FIRST GOAL: %s %s first win after %.1f s" % [game, device, play_t])
	_after_t = 0.0
	_remember()
	UiKit.sound("ui_select", -4.0, 1.2)
	if _card != null and is_instance_valid(_card):
		var l: Label = _card.get_meta("text_label") if _card.has_meta("text_label") else null  # (a null default errors)
		if l != null and is_instance_valid(l):
			l.text = "Nice one!"
		var tw := _card.create_tween()
		tw.tween_property(_card, "scale", Vector2(1.12, 1.12), 0.12)
		tw.tween_property(_card, "scale", Vector2.ONE, 0.18)
		tw.tween_interval(1.0)
		tw.tween_property(_card, "modulate:a", 0.0, 0.35)
		tw.tween_callback(_card.queue_free)
	if _vr_card != null and is_instance_valid(_vr_card) and _vr_card.has_method("set_text"):
		_vr_card.call("set_text", "Nice one!", "")
		get_tree().create_timer(1.4).timeout.connect(_drop_vr_card)
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.queue_free()
	_arrow = null


## Help kicks in (core/rescue.gd): the prompt comes back big, with its arrow.
func _help() -> void:
	print("FIRST GOAL: %s %s rescue: help kicks in (%s)" % [game, device, state])
	if state == "show":
		_shrink(false)
		_pulse = 1.0
		UiKit.sound("ui_notify", -6.0, 1.0)
		if device == "vr":
			_drop_vr_card()
			_show()
	elif state == "done" or state == "off":
		state = "show"
		play_t = 0.0
		_base = _num("rise")
		_show("Try this: ")


func _device() -> String:
	if OS.has_environment("BOT_VR") or get_viewport().use_xr or Machine.kind() == "frame":
		if VrViewCheck.vr_camera(get_tree().root) != null:
			return "vr"
	return "deck" if Machine.kind() == "deck" else "tv"


## Something else has the player's attention: a pick row, a how-to card, a story card, the pause menu.
func _blocked() -> bool:
	var tree := get_tree()
	if tree.paused:
		return true
	if not tree.get_nodes_in_group("pause_menu").filter(func(n: Node) -> bool: return n is CanvasItem and (n as CanvasItem).is_visible_in_tree()).is_empty():
		return true
	for h in tree.get_nodes_in_group("hints"):  # core/hints.gd how-to cards
		if h.has_method("intro_showing") and bool(h.call("intro_showing")):
			return true
	if not tree.get_nodes_in_group("story_card_vr").is_empty():
		return true
	for n in tree.get_nodes_in_group("pick_orb"):  # pick orbs showing (core/pick_orbs.gd PICK_GROUP)
		if n is Node3D and (n as Node3D).is_visible_in_tree():
			return true
	if device != "vr" and not tree.get_nodes_in_group("hint_pill").is_empty():  # a game's own hint is showing
		return true
	for n in tree.get_nodes_in_group("layout_cover"):  # story / how-to panels on the TV, where they'd sit under it
		if n is Control and (n as Control).is_visible_in_tree() and _covers(n as Control):
			return true
	return false


## Does a panel (in any view: split screens are SubViewports) reach the prompt's band low in the screen, or fill most
## of its view (a big story card)? Compared as fractions of each one's own view.
func _covers(c: Control) -> bool:
	var vs := c.get_viewport_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return false
	var r := c.get_global_rect()
	var top := r.position.y / vs.y
	var bottom := r.end.y / vs.y
	return bottom > 0.72 or (bottom - top) > 0.5


# --- Expressions -----------------------------------------------------------------------------------------------------

func _eval(key: String, def: Variant) -> Variant:
	key = _k(key)
	if not data.has(key):
		return def
	var text := String(data[key])
	var e: Expression = _exprs.get(text, null)
	if e == null:
		e = Expression.new()
		if e.parse(text, ["main"]) != OK:
			_fail(key, text, e.get_error_text())
			return def
		_exprs[text] = e
	var out: Variant = e.execute([main], self, false)
	if e.has_execute_failed():
		_fail(key, text, e.get_error_text())
		return def
	return out


## A key's device version when the data has one ("rise_vr" for the VR player, "rise_tv" for TV and Deck).
func _k(key: String) -> String:
	var dk := key + ("_vr" if device == "vr" else "_tv")
	return dk if data.has(dk) else key


func _fail(key: String, text: String, why: String) -> void:
	if _failed.has(text):
		return
	_failed[text] = true
	push_error("FirstGoal %s: \"%s\" (%s) failed: %s (games/%s/first_goal.gd)" % [game, key, text, why, game])


func _truthy(key: String, def: bool) -> bool:
	var v: Variant = _eval(key, def)
	return bool(v) if v != null else false


func _num(key: String) -> float:
	var v: Variant = _eval(key, 0.0)
	if v is int or v is float or v is bool:
		return float(v)
	if v is Array or v is Dictionary:
		return sum(v)
	return 0.0


## Helpers for the expressions.
func v(prop: String, def: Variant = null) -> Variant:
	if main == null:
		return def
	var x: Variant = main.get(prop)
	return def if x == null else x


func st(key: String, def: Variant = null) -> Variant:
	var net: Variant = main.get("net") if main != null else null
	if net is Object and is_instance_valid(net) and (net as Object).has_method("state_get"):
		var x: Variant = (net as Object).call("state_get", key, def)
		return def if x == null else x
	return def


func phase() -> String:
	var p: Variant = st("phase", null)
	if p == null:
		p = v("phase", "")
	return String(p) if p != null else ""


func count(group: String) -> int:
	return get_tree().get_nodes_in_group(group).size()


func node(name: String) -> Node:
	return main.find_child(name, true, false) if main != null else null


func sum(x: Variant) -> float:
	var s := 0.0
	var vals: Array = (x as Dictionary).values() if x is Dictionary else (x as Array) if x is Array else [x]
	for a in vals:
		if a is int or a is float:
			s += float(a)
		elif a is Array or a is Dictionary:
			s += sum(a)
	return s


func local_slot() -> int:
	var net: Variant = main.get("net") if main != null else null
	if net is Object and is_instance_valid(net):
		var s: Variant = (net as Object).get("my_slot")
		if s is int:
			return s
	return 0


func nearest(group: String) -> Node3D:
	return nearest_of(get_tree().get_nodes_in_group(group))


## The nearest Node3D of an Array / Dictionary's values (e.g. main's balloons {id: node}) to the player's camera.
func nearest_of(x: Variant) -> Node3D:
	var cam := _cam()
	var from := cam.global_position if cam != null else Vector3.ZERO
	var best: Node3D = null
	var bd := INF
	var list: Array = (x as Dictionary).values() if x is Dictionary else (x as Array) if x is Array else []
	for n in list:
		if n is Node3D and is_instance_valid(n) and (n as Node3D).is_visible_in_tree():
			var d := (n as Node3D).global_position.distance_squared_to(from)
			if d < bd:
				bd = d
				best = n
	return best


func _cam() -> Camera3D:
	if device == "vr":
		var c := VrViewCheck.vr_camera(get_tree().root)
		if c != null:
			return c
	return get_viewport().get_camera_3d()


# --- Remembering (per profile: the Steam account playing, else this machine's user) ----------------------------------

static func profile() -> String:
	for k in ["SteamAppUser", "SteamUser", "USER"]:
		if OS.get_environment(k) != "":
			return OS.get_environment(k).to_lower()
	return "player"


func _key() -> String:
	return "%s/%s" % [game, device]


func _remembered() -> bool:
	if Save.test_mode() and not OS.has_environment("FIRST_GOAL_REMEMBER"):
		return false
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and bool(cfg.get_value(profile(), _key(), false))


func _remember() -> void:
	if Save.test_mode() and not OS.has_environment("FIRST_GOAL_REMEMBER"):
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value(profile(), _key(), true)
	cfg.save(SAVE_PATH)


## Telemetry (core/telemetry.gd adds these to the game's RUN lines).
func run_fields(id: String) -> Dictionary:
	if id != game or data.is_empty():
		return {}
	var out := {"fg_secs": snappedf(win_secs, 0.1), "fg_dev": device, "fg_shown": snappedf(on_screen_t, 0.1)}
	if state == "off":
		out["fg_secs"] = -2.0  # already learned (remembered): no prompt shown
	if rescue != null:
		out.merge(rescue.run_fields())
	return out


# --- Showing it ------------------------------------------------------------------------------------------------------

func _pair() -> Array:
	var dd: Dictionary = data.get("do", {})
	var pair: Array = dd.get(device, dd.get("tv", ["", ""]))
	return pair


func _you() -> String:
	var you := String(data.get("you_" + ("vr" if device == "vr" else "tv"), data.get("you", "")))
	return "YOU ARE " + you.to_upper() if you != "" else ""


func _show(prefix: String = "") -> void:
	_small = false
	var pair := _pair()
	var wordless := bool(data.get("wordless", false))
	if device == "vr":
		var cam := VrViewCheck.vr_camera(get_tree().root)
		if cam == null or wordless:
			return
		var world: Node = self  # a service under /root: freed with the prompt, never inside the game's own tree
		var body := "%s:  %s" % [String(pair[0]), prefix + String(pair[1])]
		_vr_card = HudKit.vr_card(world, cam, _you(), body,
			{"width": 1.1, "color": "gold", "height": -0.34, "distance": 1.6, "title_size": 0.06, "body_size": 0.05})
		_vr_card.set_meta("first_goal", true)
		_vr_card.set_meta("vr_yields", true)  # it steps aside / hides for the game's cards, never they for it
	else:
		if _layer == null:
			_layer = CanvasLayer.new()
			_layer.layer = 60
			_layer.name = "FirstGoalLayer"
			add_child(_layer)
			_ui = UiKit.ui_root(_layer)
		if _card != null and is_instance_valid(_card):
			_card.queue_free()
		var s := UiKit.scale_of(_ui)
		_card = UiKit.tinted_panel(UiKit.color_of("gold", UiKit.ACCENT), s, "accent")
		_card.name = "FirstGoal"
		_ui.add_child(_card)
		var v := UiKit.vbox(4, s)
		_card.add_child(v)
		var you := "" if wordless else _you()
		if you != "":
			var yl := UiKit.label(you, "small", UiKit.color_of("gold", UiKit.ACCENT).lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER)
			v.add_child(yl)
			_card.set_meta("you_label", yl)
		var h := UiKit.hbox(12, s)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(h)
		if String(pair[0]) != "":
			var gl := UiKit.glyph(String(pair[0]), s)
			gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(gl)
		if wordless:
			if data.has("icon"):
				var ic := UiKit.icon(String(data["icon"]), "gold", 56.0 * s)
				ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(ic)
		else:
			var l := UiKit.label(prefix + String(pair[1]), "heading")
			h.add_child(l)
			_card.set_meta("text_label", l)
		_card.pivot_offset_ratio = Vector2(0.5, 0.5)
		_card.modulate.a = 0.0
		UiKit.fade(_card, 1.0, 0.3)
		UiKit.sound("ui_notify", -6.0, 1.1)
	_pulse = 0.6


func _shrink(on: bool) -> void:
	_small = on
	if _card != null and is_instance_valid(_card) and _card.has_meta("you_label"):
		(_card.get_meta("you_label") as Control).visible = not on


func _set_visible(on: bool) -> void:
	if _card != null and is_instance_valid(_card) and state == "show":
		_card.visible = on
	if _vr_card != null and is_instance_valid(_vr_card):
		_vr_card.visible = on and not _vr_covered()
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.visible = on


## Is the VR prompt over one of the game's own panels (after stepping aside)? Then it waits, hidden.
func _vr_covered() -> bool:
	var cam := VrViewCheck.vr_camera(get_tree().root)
	if cam == null or _vr_card == null:
		return false
	for o in VrViewCheck.shown_panels(get_tree().root):
		if o != _vr_card and not _vr_card.is_ancestor_of(o) and VrViewCheck.overlap(cam.global_position, _vr_card, o):
			return true
	return false


func _animate(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta)
	if _card != null and is_instance_valid(_card) and state == "show":
		var vs := _card.get_viewport_rect().size
		var sz := _card.get_combined_minimum_size()
		_card.size = sz
		var k := (0.78 if _small else 1.0) + 0.1 * sin(_pulse * PI * 4.0) * _pulse
		_card.scale = Vector2(k, k)
		# low in the view (story toasts and scores live at the top; core/hints.gd pills at 0.74 hide it while they show)
		var y := vs.y * (_band if not _small else 0.9) - sz.y * 0.5
		_card.position = Vector2((vs.x - sz.x) * 0.5, y)


## The game's own words and pictures on screen (HUD cues, answer tiles, help lines) in screen pixels: Controls under
## main, mapped out of split-screen SubViewports through their SubViewportContainer.
func _hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if main == null:
		return out
	var vs := get_viewport().get_visible_rect().size
	for n in main.find_children("*", "Control", true, false):
		var c := n as Control
		if not (c is Label or c is TextureRect or c is Button or c is RichTextLabel) or not c.is_visible_in_tree():
			continue
		if c.modulate.a < 0.2 or c.get_global_rect().size.x * c.get_global_rect().size.y < 64.0:
			continue
		var r := c.get_global_rect()
		var vp := c.get_viewport()
		if vp is SubViewport:
			var box := vp.get_parent() as Control
			if box == null or not box.is_visible_in_tree():
				continue
			var k := box.get_global_rect().size / Vector2(maxf(1.0, (vp as SubViewport).size.x), maxf(1.0, (vp as SubViewport).size.y))
			r = Rect2(box.get_global_rect().position + r.position * k, r.size * k)
		elif r.size.x >= vs.x * 0.9 and r.size.y >= vs.y * 0.9:
			continue  # full-screen backdrops
		out.append(r)
	return out


## Sit in the first band (BANDS) where the card covers none of the game's HUD; data "flat_y" pins it.
func _pick_band() -> void:
	if data.has("flat_y"):
		_band = float(data["flat_y"])
		return
	if _card == null or not is_instance_valid(_card):
		return
	var vs := _card.get_viewport_rect().size
	var sz := _card.get_combined_minimum_size()
	var rects := _hud_rects()
	for b in BANDS:
		var cr := Rect2(Vector2((vs.x - sz.x) * 0.5, vs.y * float(b) - sz.y * 0.5), sz).grow(8.0)
		var hit := false
		for r in rects:
			if cr.intersects(r):
				hit = true
				break
		if not hit:
			_band = float(b)
			return
	# (all taken: stay where it is, rather than hopping)


## A bobbing arrow over the thing to do it to (in the world: every view and the headset see it).
func _place_arrow() -> void:
	if state != "show" or not data.has(_k("target")):
		if _arrow != null and is_instance_valid(_arrow) and state != "show":
			_arrow.queue_free()
			_arrow = null
		return
	var tg: Variant = _eval("target", null)
	var pos: Variant = null
	if tg is Node3D and is_instance_valid(tg) and (tg as Node3D).is_inside_tree():
		pos = (tg as Node3D).global_position
	elif tg is Vector3:
		pos = tg
	if pos == null or not (main is Node3D or main.get_viewport() != null):
		if _arrow != null and is_instance_valid(_arrow):
			_arrow.visible = false
		return
	if _arrow == null or not is_instance_valid(_arrow):
		_arrow = _make_arrow()
		main.add_child(_arrow)
	var cam := _cam()
	var dist := cam.global_position.distance_to(pos) if cam != null else 10.0
	# about 5% of the view, but never much bigger than the thing itself (a golf ball under a huge arrow)
	var size := clampf(dist * 0.05, 0.15, 6.0)
	if tg is Node3D:
		size = minf(size, maxf(0.15, _size_of(tg as Node3D) * 0.9))
	_arrow.set_meta("base", pos + Vector3.UP * size * 1.8)
	_arrow.set_meta("size", size)
	_arrow.visible = not _blocked()


## A node's rough size in metres: its biggest drawn piece's box (scaled), 0 = unknown (then no cap).
func _size_of(n: Node3D) -> float:
	var best := 0.0
	var list: Array = [n]
	list.append_array(n.find_children("*", "VisualInstance3D", true, false).slice(0, 24))
	for x in list:
		if x is VisualInstance3D:
			var vi := x as VisualInstance3D
			var sz := vi.get_aabb().size * vi.global_transform.basis.get_scale()
			best = maxf(best, maxf(sz.x, maxf(sz.y, sz.z)))
	return best if best > 0.0 else 99.0


func _make_arrow() -> Node3D:
	var a := Arrow.new()
	a.name = "FirstGoalArrow"
	a.set_meta("vr_check_ignore", true)
	return a


class Arrow extends Node3D:
	var tt := 0.0
	var mesh: MeshInstance3D

	func _ready() -> void:
		mesh = MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.5
		cone.bottom_radius = 0.0
		cone.height = 1.0
		cone.radial_segments = 12
		mesh.mesh = cone
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.82, 0.2)
		# (depth-tested like any solid thing: no_depth_test breaks VR depth, docs/GAME_DEV_GUIDE.md; it hid VR card text too)
		mesh.material_override = m
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

	func _process(delta: float) -> void:
		tt += delta
		var s := float(get_meta("size", 1.0))
		global_position = Vector3(get_meta("base", global_position)) + Vector3.UP * sin(tt * 5.0) * s * 0.25
		scale = Vector3.ONE * s
		mesh.rotation.y = tt * 2.0


func _drop_vr_card() -> void:
	if _vr_card != null and is_instance_valid(_vr_card) and _vr_card.has_method("hide_card"):
		_vr_card.call("hide_card")
	_vr_card = null


func _drop_ui() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null
	_drop_vr_card()
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.queue_free()
	_arrow = null


func _reset() -> void:
	_drop_ui()
	state = "idle"
	data = {}
	game = ""
	t = 0.0
	play_t = 0.0
	win_secs = -1.0
	on_screen_t = -1.0
	_on_screen = false
	_settle = 0.0
	_exprs.clear()
	_failed.clear()
	rescue = null
	_small = false
