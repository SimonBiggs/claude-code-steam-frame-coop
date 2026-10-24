extends Control
## DUNGEON DELVE deep HUD (TV / Deck screens): icons first, few words.
##  top left: zone + floor, gold, keys      top right: the map of rooms you've seen
##  top middle: the boss's name and health  bottom: one card per hero: hearts, potions, bombs, ability
##  a prompt pill (A attack, X ability, B bomb, Y potion) when something new can be done.

const UiKit := preload("res://core/ui_kit.gd")
const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const Loot := preload("res://games/dungeon_delve/loot.gd")

var party: Node
var zone_label: Label
var gold_label: Label
var key_label: Label
var top_card: PanelContainer
var boss_box: VBoxContainer
var boss_name: Label
var boss_bar: UiKit.Bar
var cards: HBoxContainer
var pill: PanelContainer
var pill_key := ""
var pill_t := 0.0
var map: MiniMap
var _stats_key := ""
var _known := {}  ## slot -> what they could do last time (to show the pill again for new things)


func setup(root: Control, p_party: Node) -> void:
	party = p_party
	name = "DeepHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_card = UiKit.panel("card")
	add_child(top_card)
	top_card.position = Vector2(20.0, 16.0)
	var row := UiKit.hbox(10)
	top_card.add_child(row)
	row.add_child(UiKit.icon("flag", "accent", 28.0))
	zone_label = UiKit.label("", "small", "accent")
	row.add_child(zone_label)
	row.add_child(UiKit.spacer(8.0))
	row.add_child(UiKit.icon("coin", "gold", 28.0))
	gold_label = UiKit.label("0", "small", "gold")
	row.add_child(gold_label)
	row.add_child(UiKit.spacer(8.0))
	row.add_child(UiKit.icon("key", "gold", 28.0))
	key_label = UiKit.label("0", "small", "gold")
	row.add_child(key_label)
	map = MiniMap.new()
	add_child(map)
	boss_box = UiKit.vbox(4)
	boss_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(boss_box)
	UiKit.pin(boss_box, Control.PRESET_CENTER_TOP)
	boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_box.offset_top = 18.0
	boss_name = UiKit.label("", "small", "magic", HORIZONTAL_ALIGNMENT_CENTER)
	boss_box.add_child(boss_name)
	boss_bar = UiKit.bar("hp", 420.0, 22.0)
	boss_box.add_child(boss_bar)
	boss_box.visible = false
	cards = UiKit.hbox(10)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(cards)
	cards.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cards.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cards.offset_bottom = -12.0
	cards.offset_top = -12.0
	pill = UiKit.panel("pill")
	add_child(pill)
	UiKit.pin(pill, Control.PRESET_CENTER_BOTTOM)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.offset_top = -118.0
	pill.offset_bottom = -118.0
	pill.visible = false


func set_floor(f: Dictionary) -> void:
	var z := int(f["zone"]) % FloorGen.ZONES.size()
	var zd: Dictionary = FloorGen.ZONES[z]
	if String(f["kind"]) == "shop":
		zone_label.text = "SHOP"
	else:
		zone_label.text = "%s %d-%d" % [String(zd["short"]), z + 1, int(f["floor"]) + 1]
	map.f = f
	map.queue_redraw()
	pill_t = 10.0
	pill_key = ""


func on_state(key: String, value: Variant, deep: Node) -> void:
	match key:
		"d_gold":
			gold_label.text = str(int(value))
			UiKit.pulse(gold_label, 1.15, 0.15)
		"d_keys":
			key_label.text = str(int(value))
		"d_boss":
			var a: Array = value if value is Array else []
			boss_box.visible = a.size() >= 2
			if a.size() >= 2:
				boss_name.text = String(a[0])
				boss_bar.set_value(float(a[1]) * 100.0, 100.0)
		"d_seen", "d_cleared", "d_open", "d_lock":
			map.seen = int(deep.net.state_get("d_seen", 1))
			map.cleared = int(deep.net.state_get("d_cleared", 1))
			map.open = int(deep.net.state_get("d_open", 0))
			map.queue_redraw()
		"d_stats":
			_rebuild_cards(value if value is Dictionary else {}, deep)


func _rebuild_cards(st: Dictionary, deep: Node) -> void:
	var k := var_to_str(st)
	if k == _stats_key:
		return
	_stats_key = k
	for c in cards.get_children():
		c.queue_free()
	var slots: Array = st.keys()
	slots.sort()
	var many := slots.size() > 4
	var px := 18.0 if many else 22.0
	for s in slots:
		var sd: Dictionary = st[s]
		var knight: bool = int(s) == 0 and bool(deep.net.state_get("vr", false))
		var col: Color = party.color_of(int(s)) if not knight else Color(0.75, 0.85, 1.0)
		var card := UiKit.tinted_panel(col.darkened(0.55), 1.0, "card")
		cards.add_child(card)
		var v := UiKit.vbox(2)
		card.add_child(v)
		var top := UiKit.hbox(2)
		v.add_child(top)
		if knight:
			top.add_child(UiKit.icon("sword", col, px))
		var down := bool(sd.get("down", false))
		var hp := int(sd.get("hp", 0))
		var mx := int(sd.get("max", 0))
		for i in mx:
			top.add_child(UiKit.icon("heart", "bad" if i < hp else "off", px))
		var low := UiKit.hbox(6)
		v.add_child(low)
		if down:
			low.add_child(UiKit.label("HELP!", "tiny", "bad"))
		else:
			if int(sd.get("pot", 0)) > 0:
				low.add_child(UiKit.icon("potion", Color(1.0, 0.45, 0.55), px * 0.85))
				low.add_child(UiKit.label(str(int(sd["pot"])), "tiny"))
			if int(sd.get("bomb", 0)) > 0:
				low.add_child(UiKit.icon("fire", "warn", px * 0.85))
				low.add_child(UiKit.label(str(int(sd["bomb"])), "tiny"))
			var ab := String(sd.get("abil", ""))
			if ab != "":
				low.add_child(UiKit.icon(String(Loot.ICONS[Loot.ABILITY_NAMES[ab]]), "info", px * 0.85))
			if int(sd.get("dmg", 1)) > (2 if knight else 1):
				low.add_child(UiKit.icon("sword", "accent", px * 0.85))
				low.add_child(UiKit.label("+%d" % (int(sd["dmg"]) - (2 if knight else 1)), "tiny"))
			if int(sd.get("charm", 0)) > 0:
				low.add_child(UiKit.icon("star", "gold", px * 0.85))
		# Something new to do? Show the prompt pill again.
		if party.is_local(int(s)):
			var can := "%s/%d/%d" % [String(sd.get("abil", "")), mini(1, int(sd.get("bomb", 0))), mini(1, int(sd.get("pot", 0)))]
			if _known.get(int(s), "") != can:
				_known[int(s)] = can
				pill_t = 8.0


func update(delta: float, deep: Node) -> void:
	pill_t -= delta
	var want := ""
	var pairs: Array = []
	var st: Dictionary = deep.net.state_get("d_stats", {})
	for s in party.local_slots():
		if not st.has(s):
			continue
		var sd: Dictionary = st[s]
		if bool(sd.get("down", false)):
			continue
		pairs = [["A", "Hit"]]
		var ab := String(sd.get("abil", ""))
		if ab != "":
			pairs.append(["X", String(Loot.NAMES[Loot.ABILITY_NAMES[ab]])])
		if int(sd.get("bomb", 0)) > 0:
			pairs.append(["B", "Bomb"])
		if int(sd.get("pot", 0)) > 0 and int(sd.get("hp", 0)) < int(sd.get("max", 0)):
			pairs.append(["Y", "Potion"])
		break
	# A friend is down: show how to help.
	var helping := false
	for s in st:
		if bool((st[s] as Dictionary).get("down", false)) and not party.is_local(int(s)):
			helping = true
			break
	if helping:
		want = "help"
	elif pill_t > 0.0 and not pairs.is_empty():
		want = var_to_str(pairs)
	if want != pill_key:
		pill_key = want
		for c in pill.get_children():
			c.queue_free()
		if want == "help":
			var row := UiKit.hbox(10)
			row.add_child(UiKit.icon("person", "good", 30.0))
			row.add_child(UiKit.label("Stand by a friend to help!", "small", "good"))
			pill.add_child(row)
		elif want != "":
			pill.add_child(UiKit.prompts(pairs))
	pill.visible = want != ""
	map.here.clear()
	if not map.f.is_empty():
		for s in deep.main.heroes:
			var r := FloorGen.room_at(map.f, (deep.main.heroes[s] as Node3D).position)
			if r >= 0:
				map.here[r] = party.color_of(int(s))
		map.lock = int(deep.net.state_get("d_lock", -1))
		map.queue_redraw()


## The little map: rooms you've seen (cleared ones dim), where everyone is, the stairs and the boss.
class MiniMap extends Control:
	const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
	const UiKit := preload("res://core/ui_kit.gd")
	var f: Dictionary = {}
	var seen := 1
	var cleared := 1
	var open := 0
	var lock := -1
	var here := {}
	var _s := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_s = UiKit.scale_of(self)
		custom_minimum_size = Vector2(150, 150) * _s
		anchor_left = 1.0
		anchor_right = 1.0
		offset_left = -168.0 * _s
		offset_right = -18.0 * _s
		offset_top = 16.0 * _s
		offset_bottom = 166.0 * _s

	func _draw() -> void:
		if f.is_empty() or (f["rooms"] as Array).size() <= 1:
			return
		var cs := 26.0 * _s
		var rooms: Array = f["rooms"]
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.07, 0.72), true)
		var off := Vector2(size.x - FloorGen.GRID * cs, size.y - FloorGen.GRID * cs) * 0.5
		var doors: Array = f["doors"]
		for di in doors.size():
			var d: Dictionary = doors[di]
			var a := int(d["a"])
			var b := int(d["b"])
			if seen & (1 << a) == 0 and seen & (1 << b) == 0:
				continue
			var t := int(d["type"])
			if t == FloorGen.SECRET and open & (1 << di) == 0:
				continue
			var ca: Vector2i = (rooms[a] as Dictionary)["cell"]
			var cb: Vector2i = (rooms[b] as Dictionary)["cell"]
			var pa := off + (Vector2(ca) + Vector2(0.5, 0.5)) * cs
			var pb := off + (Vector2(cb) + Vector2(0.5, 0.5)) * cs
			var col := Color(0.7, 0.7, 0.8)
			if open & (1 << di) == 0:
				col = UiKit.GOLD if t in [FloorGen.LOCKED, FloorGen.BOSS] else Color(0.4, 0.8, 1.0)
			draw_line(pa, pb, col, 3.0 * _s)
		for i in rooms.size():
			var r: Dictionary = rooms[i]
			var vis := seen & (1 << i) != 0
			if not vis:
				continue
			var c: Vector2i = r["cell"]
			var rect := Rect2(off + Vector2(c) * cs + Vector2(3, 3) * _s, Vector2(cs, cs) - Vector2(6, 6) * _s)
			var fill := Color(0.35, 0.38, 0.5) if cleared & (1 << i) != 0 else Color(0.55, 0.25, 0.3)
			if i == lock:
				fill = Color(0.85, 0.3, 0.3)
			draw_rect(rect, fill, true)
			if here.has(i):
				draw_rect(rect, here[i], false, 3.0 * _s)
			var role := String(r["role"])
			var mid := rect.get_center()
			if r.has("stairs"):
				draw_circle(mid, 5.0 * _s, Color(0.5, 1.0, 0.7))
			elif role == "boss":
				draw_circle(mid, 6.0 * _s, Color(0.85, 0.45, 1.0))
			elif role == "secret":
				draw_circle(mid, 4.0 * _s, UiKit.GOLD)
