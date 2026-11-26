extends SceneTree
## DUNGEON DELVE: draws generated deep floors as top-down maps (a PNG sheet), to look at what floorgen.gd makes.
##   godot-test --headless --path . -s res://tools/dungeon_delve_maps.gd            (writes user://dd_maps.png)
##   DD_MAP_OUT=/path/sheet.png DD_MAP_SEEDS=11,22,33 DD_MAP_FLOORS=0,5,10,15 DD_MAP_HEROIC=1 godot-test ...
##   DD_MAP_DAILY=1: the rows are TODAY'S DUNGEON for today and the next two days.
## One row per seed, one column per floor (global floor number: 0..15 = 4 biomes x 4 floors, 3/7/11/15 = boss floors).
## Each tile: rooms in the biome's floor colour with a coloured rim by role (start green, exit white, boss red,
## secret purple, key room gold), doors by kind (open grey, locked gold, secret purple, puzzle cyan, boss red),
## monsters red dots (bigger = tougher), chests gold squares, the key a yellow diamond, stairs white, switches
## cyan, trap tiles orange, the friend's cage pink, and the label "seed zone-floor" in the corner. The thin bar
## under each tile is the floor's monster strength (cost x strength, full = the deepest tile on the sheet).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const Friends := preload("res://games/dungeon_delve/friends.gd")
const Deep := preload("res://games/dungeon_delve/deep.gd")

const ROLE_RIM := {"start": Color(0.4, 1.0, 0.5), "exit": Color(1, 1, 1), "boss": Color(1.0, 0.3, 0.3), "secret": Color(0.75, 0.45, 1.0), "shop": Color(1.0, 0.85, 0.3), "vault": Color(1.0, 0.4, 0.6)}
const DOOR_COL := [Color(0.75, 0.75, 0.8), Color(1.0, 0.82, 0.25), Color(0.75, 0.45, 1.0), Color(0.3, 0.95, 1.0), Color(1.0, 0.3, 0.3)]
const GLYPHS := {"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111", "4": "101101111001001",
	"5": "111100111001111", "6": "111100111101111", "7": "111001001001001", "8": "111101111101111", "9": "111101111001111",
	"-": "000000111000000", " ": "000000000000000", "S": "111100111001111", "H": "101101111101101"}

func _initialize() -> void:
	var seeds: Array = []
	for s in OS.get_environment("DD_MAP_SEEDS").split(",", false):
		seeds.append(int(s))
	if OS.get_environment("DD_MAP_DAILY") == "1":  # TODAY'S DUNGEON for today and the next two days
		var now := int(Time.get_unix_time_from_system())
		for k in 3:
			seeds.append(Deep.daily_seed(Time.get_date_string_from_unix_time(now + k * 86400)))
	if seeds.is_empty():
		seeds = [101, 202, 303]
	var floors: Array = []
	for s2 in OS.get_environment("DD_MAP_FLOORS").split(",", false):
		floors.append(int(s2))
	if floors.is_empty():
		floors = [0, 3, 6, 11, 15]
	var heroic := OS.get_environment("DD_MAP_HEROIC") == "1"
	var cell_px := 64
	var tile_w := cell_px * FloorGen.GRID + 16
	var tile_h := tile_w + 18
	var sheet := Image.create(tile_w * floors.size() + 8, tile_h * seeds.size() + 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.08, 0.1))
	var strengths := {}
	var max_s := 0.001
	for sd in seeds:
		for g in floors:
			var f := FloorGen.generate(int(sd), int(g) / FloorGen.FLOORS_PER_ZONE, int(g) % FloorGen.FLOORS_PER_ZONE, heroic)
			var s_total := 0.0
			var sc := FloorGen.scaling(1.25, 1.08, heroic, int(f["zone"]), int(f["floor"]), 1, String(f.get("mod", "")))
			for r in f["rooms"]:
				for fo in (r as Dictionary)["foes"]:
					s_total += float(FloorGen.FOE_COST.get(int((fo as Array)[0]), 6.0)) * FloorGen.strength(sc)
			strengths[[sd, g]] = s_total
			max_s = maxf(max_s, s_total)
	for yi in seeds.size():
		for xi in floors.size():
			var sd2: int = seeds[yi]
			var g2: int = floors[xi]
			var f2 := FloorGen.generate(sd2, g2 / FloorGen.FLOORS_PER_ZONE, g2 % FloorGen.FLOORS_PER_ZONE, heroic)
			var ox := 4 + xi * tile_w + 8
			var oy := 4 + yi * tile_h + 8
			_draw_floor(sheet, f2, ox, oy, cell_px)
			_text(sheet, "%d %d-%d%s" % [sd2, g2 / 4 + 1, g2 % 4 + 1, " H" if heroic else ""], ox + 2, oy + 2, 2, Color(1, 1, 1))
			var frac := float(strengths[[sd2, g2]]) / max_s
			sheet.fill_rect(Rect2i(ox, oy + cell_px * FloorGen.GRID + 2, int((cell_px * FloorGen.GRID - 4) * frac), 5), Color(1.0, 0.4, 0.3))
	var out := OS.get_environment("DD_MAP_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://dd_maps.png")
	sheet.save_png(out)
	print("DD MAPS: wrote ", out)
	quit()


func _draw_floor(img: Image, f: Dictionary, ox: int, oy: int, cell_px: int) -> void:
	var zd: Dictionary = FloorGen.zone_data(int(f["zone"]))
	var m := float(cell_px) / FloorGen.CELL  # pixels per metre
	var rooms: Array = f["rooms"]
	var key_rooms: Array = f.get("key_rooms", [])
	var cage := Friends.pick(f)
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var cell: Vector2i = r["cell"]
		var cx := ox + cell.x * cell_px + cell_px / 2
		var cy := oy + cell.y * cell_px + cell_px / 2
		var half := int(FloorGen.HALF * m)
		var floor_c: Color = (zd["floor"] as Array)[1]
		var rim: Color = ROLE_RIM.get(String(r["role"]), (zd["wall"] as Color).lightened(0.25))
		if key_rooms.has(i) or bool(r.get("key", false)):
			rim = Color(1.0, 0.85, 0.2)
		img.fill_rect(Rect2i(cx - half - 2, cy - half - 2, half * 2 + 4, half * 2 + 4), rim)
		img.fill_rect(Rect2i(cx - half, cy - half, half * 2, half * 2), floor_c)
		var w := func(p: Vector2) -> Vector2i: return Vector2i(cx + int(p.x * m), cy + int(p.y * m))
		for ti in r.get("traps", []):
			var td: Dictionary = (f["traps"] as Array)[int(ti)]
			for tile in td.get("tiles", []):
				var tp: Vector2i = w.call(tile)
				img.fill_rect(Rect2i(tp.x - 2, tp.y - 2, 5, 5), Color(1.0, 0.55, 0.15))
			if td.has("lane"):  # a boulder's lane
				for k in range(-int(FloorGen.HALF * 10), int(FloorGen.HALF * 10), 3):
					var q := Vector2(k / 10.0, float(td["lane"])) if int(td["axis"]) == 0 else Vector2(float(td["lane"]), k / 10.0)
					var tp2: Vector2i = w.call(q)
					img.fill_rect(Rect2i(tp2.x - 1, tp2.y - 1, 3, 3), Color(1.0, 0.55, 0.15))
		for pt in r.get("pots", []):
			var pp: Vector2i = w.call(pt)
			img.fill_rect(Rect2i(pp.x - 1, pp.y - 1, 2, 2), Color(0.6, 0.4, 0.25))
		for ch in r.get("chests", []):
			var cp: Vector2i = w.call((ch as Array)[0])
			img.fill_rect(Rect2i(cp.x - 3, cp.y - 2, 7, 5), Color(1.0, 0.8, 0.25) if not bool((ch as Array)[1]) else Color(0.9, 0.3, 0.9))
		for fo in r.get("foes", []):
			var fp: Vector2i = w.call((fo as Array)[1])
			var big := int(FloorGen.FOE_COST.get(int((fo as Array)[0]), 6.0))
			var rad := clampi(1 + big, 2, 6)
			_disc(img, fp, rad, Color(1.0, 0.25, 0.3) if not bool((fo as Array)[2]) else Color(1.0, 0.8, 0.2))
		if r.has("key_at"):
			var kp: Vector2i = w.call(r["key_at"])
			_diamond(img, kp, 4, Color(1.0, 1.0, 0.3))
		if r.has("piece_at"):  # a heart piece (behind a gate)
			_disc(img, w.call(r["piece_at"]), 5, Color(1.0, 0.4, 0.6))
		if r.has("tool_at") and int(f.get("tool", -1)) >= 0:  # Cinder's tool lying here
			_diamond(img, w.call(r["tool_at"]), 6, FloorGen.TOOLS[int(f["tool"])]["color"])
		if r.has("stairs"):
			var sp: Vector2i = w.call(r["stairs"])
			for k in 3:
				img.fill_rect(Rect2i(sp.x - 5, sp.y - 4 + k * 3, 10, 2), Color(1, 1, 1))
		for si in r.get("switches", []):
			var sw: Dictionary = (f["switches"] as Array)[int(si)]
			var swp: Vector2i = w.call(sw["p"])
			img.fill_rect(Rect2i(swp.x - 2, swp.y - 2, 5, 5), Color(0.3, 0.95, 1.0))
		if not cage.is_empty() and int(cage.get("room", -1)) == i and cage.has("p"):
			_diamond(img, w.call(cage["p"]), 5, Color(1.0, 0.5, 0.75))
	for d in f["doors"]:
		var dd: Dictionary = d
		var a: Vector2i = (rooms[int(dd["a"])] as Dictionary)["cell"]
		var b: Vector2i = (rooms[int(dd["b"])] as Dictionary)["cell"]
		var mx := ox + (a.x + b.x) * cell_px / 2 + cell_px / 2
		var my := oy + (a.y + b.y) * cell_px / 2 + cell_px / 2
		var horiz := a.y == b.y
		var col: Color = DOOR_COL[clampi(int(dd["type"]), 0, DOOR_COL.size() - 1)]
		if int(dd["type"]) == FloorGen.GATE:  # a gate: its tool's colour
			col = FloorGen.tool_info(int(dd.get("tool", 0))).get("color", Color.WHITE)
		if horiz:
			img.fill_rect(Rect2i(mx - 5, my - 5, 10, 10), col)
		else:
			img.fill_rect(Rect2i(mx - 5, my - 5, 10, 10), col)


func _disc(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				_px(img, c.x + x, c.y + y, col)


func _diamond(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if absi(x) + absi(y) <= r:
				_px(img, c.x + x, c.y + y, col)


func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


func _text(img: Image, s: String, x: int, y: int, sc: int, col: Color) -> void:
	var cx := x
	for ch in s:
		var gl: String = GLYPHS.get(ch, GLYPHS[" "])
		for i in 15:
			if gl[i] == "1":
				img.fill_rect(Rect2i(cx + (i % 3) * sc, y + (i / 3) * sc, sc, sc), col)
		cx += 4 * sc