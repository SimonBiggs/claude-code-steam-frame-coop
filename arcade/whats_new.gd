extends RefCounted
## The arcade's "What's New" picture board: what changed in the games lately, so the family finds it. Pictures first
## (the little ones can't read yet): each tile is a game's story friend with a sparkly NEW! badge, a picture for each
## new thing and ONE short line. Pressing a tile plays the game (and "try" jumps straight to the new thing); a tile
## the family has opened loses its sparkle (seen ids saved with core/save.gd, shared over the lobby like the Trophy
## Hall: one family, so what David opened on his Deck isn't NEW on the TV either).
## TV / Deck: the arcade's first tab (a sparkle and "NEW! 5"), one tile per game, unseen first.
## VR: vr_panel(), a picture wall on the right (the Trophy Hall's is on the left).
##
## ADDING NEWS (every landed deep/feature branch): put a line at the TOP of ENTRIES (newest first, biggest first):
##   {"id": "<game>-<word>", "date": "YYYY-MM-DD", "game": "<arcade game id>", "pic": "<story picture>",
##    "line": "Few words!", "try": {"ENV_VAR": "value"}}   # try: optional env the game reads when it starts (hosting)
## tests/whats_new_test.gd fails when a game got a feature commit (subject starting with the game's name, e.g.
## "Bee Garden: ...") after CHECK_FROM and within the last FRESH_DAYS, but has no entry dated within FRESH_DAYS of it.

const UiKit := preload("res://core/ui_kit.gd")
const StoryCard := preload("res://core/story_card.gd")
const Progress := preload("res://core/progress.gd")
const Save := preload("res://core/save.gd")
const Seeded := preload("res://core/seeded.gd")

const SAVE_ID := "arcade_whats_new"
const GOLD := Color(1.0, 0.86, 0.3)
const SPARKLE := Color(1.0, 0.95, 0.55)
## News older than this many days leaves the board.
const SHOW_DAYS := 60
## A game's feature needs an entry dated no more than this many days before it (tests/whats_new_test.gd).
const FRESH_DAYS := 14
## Feature commits before this (UTC) were announced by the first board (the 26-30 Oct catch-up below).
const CHECK_FROM := "2026-10-30T08:30:00"
const MAX_LINE := 28  # characters: one short line, two at most on a tile
const MAX_PICS := 4  # pictures on a tile

## Newest first; within a day, the biggest first.
const ENTRIES := [
	{"id": "party-boards", "date": "2026-10-31", "game": "party_board", "pic": "hauntedhouse", "line": "Five party boards to visit!", "try": {"PB_BOARD": "haunted"}},
	{"id": "party-minigames", "date": "2026-10-31", "game": "party_board", "pic": "toucan", "line": "Moles, fish, paint, towers!", "try": {"PB_MINIGAME": "fish_pond"}},
	{"id": "party-presents", "date": "2026-10-31", "game": "party_board", "pic": "gift", "line": "Presents: 2 dice, swap, warp", "try": {"PB_BOARD": "sweet"}},
	{"id": "party-trophies", "date": "2026-10-31", "game": "party_board", "pic": "trophywall", "line": "Fill Mango's trophy wall!"},
	{"id": "saga-guardians", "date": "2026-10-31", "game": "crystal_saga", "pic": "guardian", "line": "Beat crystal guardians!", "try": {"CS_TRY": "guardian"}},
	{"id": "saga-realm", "date": "2026-10-31", "game": "crystal_saga", "pic": "lumi", "line": "Pick a road on Lumi's map!"},
	{"id": "saga-heroes", "date": "2026-10-31", "game": "crystal_saga", "pic": "healer", "line": "Be a healer or a bard!"},
	{"id": "kart-cups", "date": "2026-10-31", "game": "kart_race", "pic": "lollipop", "line": "Win cups for Bolt's shelf!", "try": {"KART_PIT": "1"}},
	{"id": "kart-garage", "date": "2026-10-31", "game": "kart_race", "pic": "kartbig", "line": "Pick a light or heavy kart!", "try": {"KART_PIT": "1"}},
	{"id": "kart-zoom", "date": "2026-10-31", "game": "kart_race", "pic": "rocket", "line": "ZOOM speed for big kids!", "try": {"KART_PIT": "1"}},
	{"id": "mech-bosses", "date": "2026-10-31", "game": "mech_titans", "pic": "crownkaiju", "line": "Boss kaiju with crowns!", "try": {"MT_TRY": "boss"}},
	{"id": "mech-pods", "date": "2026-10-31", "game": "mech_titans", "pic": "titanpod", "line": "Pick Titan power-ups!", "try": {"MT_TRY": "pods"}},
	{"id": "mech-sanctuary", "date": "2026-10-31", "game": "mech_titans", "pic": "sanctuary", "line": "Grow the Kaiju Sanctuary!"},
	{"id": "delve-queen", "date": "2026-10-30", "game": "dungeon_delve", "pic": "shard", "line": "Beat the Crystal Queen!", "try": {"DD_TRY": "brave"}},
	{"id": "delve-heroes", "date": "2026-10-30", "game": "dungeon_delve", "pic": "wizard", "line": "Knight, archer or wizard!", "try": {"DD_TRY": "brave"}},
	{"id": "delve-relics", "date": "2026-10-30", "game": "dungeon_delve", "pic": "hoard", "line": "Find magic relics!", "try": {"DD_TRY": "brave"}},
	{"id": "delve-cinder", "date": "2026-10-30", "game": "dungeon_delve", "pic": "cinder", "line": "Today's dungeon with Cinder", "try": {"DD_TRY": "daily"}},
	{"id": "bender-kiko", "date": "2026-10-30", "game": "elemental_bender", "pic": "spirittree", "line": "Grow Kiko's Spirit Tree!"},
	{"id": "paint-smudge", "date": "2026-10-30", "game": "paint_and_guess", "pic": "goldframe", "line": "Fill Smudge's gallery!"},
	{"id": "giants-sparky", "date": "2026-10-30", "game": "giants_table", "pic": "sparky", "line": "Meet Sparky the flame!"},
	{"id": "penalty-leo", "date": "2026-10-30", "game": "penalty_shootout", "pic": "lioncub", "line": "Win cups for Leo!"},
	{"id": "mech-momo", "date": "2026-10-30", "game": "mech_titans", "pic": "momo", "line": "Meet Momo the kaiju!"},
	{"id": "kart-bolt", "date": "2026-10-30", "game": "kart_race", "pic": "boltbot", "line": "Race the Grand Tour!"},
	{"id": "dodge-tumtum", "date": "2026-10-29", "game": "dodge_ball", "pic": "tumtum", "line": "Grow TumTum's park!"},
	{"id": "bath-mamaduck", "date": "2026-10-29", "game": "bubble_bath", "pic": "duckling", "line": "Find Mama Duck's ducklings"},
	{"id": "coaster-buttons", "date": "2026-10-29", "game": "roller_coaster", "pic": "ticket", "line": "Golden tickets!"},
	{"id": "band-doodle", "date": "2026-10-29", "game": "rhythm_band", "pic": "fanclub", "line": "Grow Doodle's fan club!"},
	{"id": "golf-gus", "date": "2026-10-29", "game": "mini_golf_party", "pic": "golfflag", "line": "New holes every day!"},
	{"id": "cove-polly", "date": "2026-10-29", "game": "cannon_cove", "pic": "treasuremap", "line": "Sail with Polly!"},
	{"id": "dig-peg", "date": "2026-10-29", "game": "treasure_dig", "pic": "crown", "line": "Dig up Peg's relics!"},
	{"id": "bee-bea", "date": "2026-10-29", "game": "bee_garden", "pic": "honeyjar", "line": "Fill Queen Bea's jars!"},
	{"id": "balloon-poppy", "date": "2026-10-29", "game": "balloon_pop", "pic": "ferris", "line": "Build Poppy's fair!"},
	{"id": "whack-fig", "date": "2026-10-29", "game": "whack_a_mole", "pic": "carrot", "line": "Grow Farmer Fig's veg!"},
	{"id": "ghost-grannyboo", "date": "2026-10-29", "game": "ghost_lantern", "pic": "grannyboo", "line": "Help Granny Boo!"},
	{"id": "tower-wren", "date": "2026-10-29", "game": "tower_stack", "pic": "tower", "line": "Build Wren's town!"},
]


# --- Data -----------------------------------------------------------------------------------------

## The entries still on the board (newer than SHOW_DAYS), in ENTRIES order.
static func current(today: String = "") -> Array:
	var cut := _day(today if today != "" else Seeded.today()) - SHOW_DAYS
	var out: Array = []
	for e in ENTRIES:
		if _day(String(e.date)) >= cut:
			out.append(e)
	return out


## One game's entries on the board, newest first.
static func entries_of(game: String, today: String = "") -> Array:
	var out: Array = []
	for e in current(today):
		if String(e.game) == game:
			out.append(e)
	return out


static func has(game: String) -> bool:
	return not entries_of(game).is_empty()


## How many of a game's entries (or all of them, game "") nobody in the family has opened yet.
static func unseen(seen: Dictionary, game: String = "") -> int:
	var n := 0
	for e in current():
		if (game == "" or String(e.game) == game) and not seen.has(String(e.id)):
			n += 1
	return n


## The board's games (arcade GAMES indices) in order: games with something unseen first, each in ENTRIES order.
static func order(games: Array, seen: Dictionary) -> Array[int]:
	var idx := {}
	for i in games.size():
		idx[String(games[i].id)] = i
	var fresh: Array[int] = []
	var old: Array[int] = []
	for e in current():
		var g := String(e.game)
		if not idx.has(g) or fresh.has(idx[g]) or old.has(idx[g]):
			continue
		if unseen(seen, g) > 0:
			fresh.append(idx[g])
		else:
			old.append(idx[g])
	fresh.append_array(old)
	return fresh


## The "try this" env for opening a game's tile: its first unseen entry's, else its newest entry's ({} = just play).
static func try_of(game: String, seen: Dictionary) -> Dictionary:
	var list := entries_of(game)
	for e in list:
		if not seen.has(String(e.id)):
			return (e.get("try", {}) as Dictionary)
	return (list[0].get("try", {}) as Dictionary) if not list.is_empty() else {}


## Every env name any entry may set (the arcade clears them when it comes back).
static func try_keys() -> Array[String]:
	var out: Array[String] = []
	for e in ENTRIES:
		for k in (e.get("try", {}) as Dictionary):
			if not out.has(String(k)):
				out.append(String(k))
	return out


## Opening a game's tile: the ids it marks seen (all its entries on the board).
static func ids_of(game: String) -> Array[String]:
	var out: Array[String] = []
	for e in entries_of(game):
		out.append(String(e.id))
	return out


# --- Seen (core/save.gd; merged across the lobby: anyone opened it = seen) -------------------------

static func load_seen() -> Dictionary:
	var d := Save.load_data(SAVE_ID, {"seen": []})
	var out := {}
	for id in (d.get("seen", []) as Array):
		out[String(id)] = true
	return out


static func store_seen(seen: Dictionary) -> void:
	var arr: Array = []
	for id in seen:
		if _known(String(id)):  # (ids of news long gone are dropped)
			arr.append(String(id))
	arr.sort()
	Save.store(SAVE_ID, {"seen": arr})


## seen + ids: the union, and whether anything was new.
static func merge(seen: Dictionary, ids: Array) -> bool:
	var grew := false
	for id in ids:
		if not seen.has(String(id)) and _known(String(id)):
			seen[String(id)] = true
			grew = true
	return grew


static func pack(seen: Dictionary) -> Array:
	var out: Array = []
	for id in seen:
		out.append(String(id))
	return out


static func _known(id: String) -> bool:
	for e in ENTRIES:
		if String(e.id) == id:
			return true
	return false


# --- Checks (tests/whats_new_test.gd) ------------------------------------------------------------

## Problems with the data (empty = fine): unknown games / pictures, long lines, bad or out-of-order dates, repeats.
static func check(game_ids: Array, entries: Array = ENTRIES) -> Array[String]:
	var out: Array[String] = []
	var ids := {}
	var last := 1 << 30
	for e in entries:
		var id := String(e.get("id", ""))
		for k in ["id", "date", "game", "pic", "line"]:
			if String(e.get(k, "")) == "":
				out.append("entry %s has no %s" % [id, k])
		if ids.has(id):
			out.append("entry id %s twice" % id)
		ids[id] = true
		var d := _day(String(e.get("date", "")))
		if d < 0:
			out.append("entry %s: date %s is not YYYY-MM-DD" % [id, e.get("date")])
		elif d > last:
			out.append("entry %s: newer than the entry above it (newest first)" % id)
		else:
			last = d
		if not game_ids.has(String(e.get("game", ""))):
			out.append("entry %s: %s is not an arcade game" % [id, e.get("game")])
		elif not Progress.has(String(e.game)):
			out.append("entry %s: %s has no progress.gd (no story friend for the tile)" % [id, e.game])
		if not StoryCard.has_picture(String(e.get("pic", ""))):
			out.append("entry %s: %s is not a story picture" % [id, e.get("pic")])
		var line := String(e.get("line", ""))
		if line.length() > MAX_LINE:
			out.append("entry %s: line \"%s\" is longer than %d letters (pictures first, few words)" % [id, line, MAX_LINE])
		var t: Variant = e.get("try", {})
		if not t is Dictionary:
			out.append("entry %s: try must be a Dictionary of env vars" % id)
	return out


## Games with a feature that has no fresh entry. `log_text`: `git log --no-merges --format=@%ct|%s --name-only -- games/`
## output; `names`: {game id: display name}; `now`: unix time. A feature commit = one touching games/<id>/ whose
## subject starts with the game's id or name ("Bee Garden: ...", "Kart Race deep 3: ..."), after CHECK_FROM and
## within FRESH_DAYS of now; it needs an entry for that game dated at most FRESH_DAYS before the commit's day.
static func stale(log_text: String, names: Dictionary, now: int, entries: Array = ENTRIES) -> Array[String]:
	var from := int(Time.get_unix_time_from_datetime_string(CHECK_FROM))
	var newest := {}  # game -> [unix time, subject]
	var t := 0
	var subj := ""
	for line in log_text.split("\n"):
		if line.begins_with("@"):
			var bar := line.find("|")
			t = int(line.substr(1, bar - 1))
			subj = _norm(line.substr(bar + 1))
			continue
		if not line.begins_with("games/"):
			continue
		var g := line.get_slice("/", 1)
		if t < from or t < now - FRESH_DAYS * 86400 or (newest.has(g) and int(newest[g][0]) >= t):
			continue
		for n in [_norm(g), _norm(String(names.get(g, g)))]:
			if subj == n or subj.begins_with(n + " "):
				newest[g] = [t, subj]
				break
	var out: Array[String] = []
	for g in newest:
		var day := int(newest[g][0]) / 86400
		var ok := false
		for e in entries:
			if String(e.game) == g and _day(String(e.date)) >= day - FRESH_DAYS:
				ok = true
				break
		if not ok:
			out.append("%s got a feature on %s (\"%s\") but arcade/whats_new.gd has no entry for it from the %d days before: add one at the top of ENTRIES" % [
				g, Time.get_date_string_from_unix_time(int(newest[g][0])), String(newest[g][1]).left(60), FRESH_DAYS])
	return out


## git log for stale(), or "" where there's no git (Decks).
static func git_log() -> String:
	var repo := ProjectSettings.globalize_path("res://")
	var out: Array = []
	var code := OS.execute("git", ["-C", repo, "log", "--no-merges", "--since=%d.days" % (FRESH_DAYS + 1), "--format=@%ct|%s", "--name-only", "--", "games/"], out, true)
	return String(out[0]) if code == 0 and not out.is_empty() else ""


static func _norm(s: String) -> String:
	var low := s.to_lower().replace("_", " ").replace("-", " ")
	var out := ""
	for ch in low:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == " ":
			out += ch
	return out


## Days since 1970 of "YYYY-MM-DD" (-1 if it isn't one).
static func _day(date: String) -> int:
	if date.length() != 10 or date[4] != "-" or date[7] != "-":
		return -1
	return int(Time.get_unix_time_from_datetime_string(date + "T00:00:00")) / 86400


# --- TV / Deck -----------------------------------------------------------------------------------

static func still(kind: String, px: float, color: Color) -> Control:
	var p := StoryCard.picture(kind, px, color)
	p.set_process(false)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## The sparkly NEW! badge (a gold tag that gently pulses, two twinkles).
static func badge(s: float = 1.0) -> Control:
	var tag := PanelContainer.new()
	tag.name = "NewBadge"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("panel", UiKit.stylebox(GOLD, 1.0, 12.0 * s, Color(1, 1, 1, 0.9), 2.0 * s, 0.0, Vector2(8, 1) * s))
	var l := Label.new()
	l.text = "NEW!"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(22 * s))
	l.add_theme_color_override("font_color", Color(0.25, 0.08, 0.2))
	tag.add_child(l)
	tag.rotation = deg_to_rad(-10.0)
	tag.ready.connect(func() -> void:
		tag.pivot_offset = tag.size * 0.5
		var tw := tag.create_tween().set_loops()
		tw.tween_property(tag, "scale", Vector2.ONE * 1.1, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tag, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE))
	return tag


static func twinkle(px: float, delay: float) -> Control:
	var st := UiKit.icon("star", Color(SPARKLE, 0.0), px)
	st.name = "Twinkle"
	st.ready.connect(func() -> void:
		var tw := st.create_tween().set_loops()
		tw.tween_interval(delay)
		tw.tween_property(st, "color", Color(SPARKLE, 1.0), 0.35)
		tw.tween_property(st, "color", Color(SPARKLE, 0.0), 0.5)
		tw.tween_interval(1.2 - delay))
	return st


## The game's friend on its disc, with the NEW! badge and twinkles when something is unseen.
static func friend(id: String, px: float, fresh: bool, s: float = 1.0) -> Control:
	var sc = Progress.script_of(id)
	var col: Color = sc.COLOR
	var box := Control.new()
	box.name = "Friend"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(px, px)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var disc := PanelContainer.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_stylebox_override("panel", UiKit.stylebox(col.darkened(0.55), 1.0, px, (GOLD if fresh else col.lightened(0.2)), maxf(2.0, px * (0.05 if fresh else 0.03)), 0.0, Vector2(px * 0.06, px * 0.06)))
	disc.size = Vector2(px, px)
	disc.clip_contents = true  # (a tall friend like Gus the gopher stays on the disc)
	box.add_child(disc)
	disc.add_child(still(String(sc.WHO), px * 0.82, col.lightened(0.15)))
	if fresh:
		var b := badge(s)
		b.position = Vector2(-4, -6) * s
		box.add_child(b)
		for k in 2:
			var tw := twinkle(px * 0.24, 0.5 * k)
			tw.position = Vector2(px * (0.78 - 0.1 * k), px * (0.02 + 0.7 * k))
			box.add_child(tw)
	return box


## A board tile inside the arcade's card Button (600 x 136): friend + NEW!, the new things' pictures and one line,
## the game's screenshot.
static func fill_tile(b: Button, id: String, seen: Dictionary, thumb: Texture2D) -> void:
	var list := entries_of(id)
	var fresh := unseen(seen, id) > 0
	var h := HBoxContainer.new()
	h.name = "News"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -14
	h.offset_top = 12
	h.offset_bottom = -12
	h.add_child(friend(id, 104.0, fresh))
	var col: Color = Progress.script_of(id).COLOR
	var v := VBoxContainer.new()
	v.name = "What"
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var pics := HBoxContainer.new()
	pics.name = "Pictures"
	pics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pics.add_theme_constant_override("separation", 6)
	v.add_child(pics)
	for k in mini(list.size(), MAX_PICS):
		var p := still(String(list[k].pic), 50.0, col.lightened(0.1))
		if seen.has(String(list[k].id)):
			p.modulate = Color(1, 1, 1, 0.6)
		pics.add_child(p)
	var first: Dictionary = list[0] if not list.is_empty() else {}
	for e in list:
		if not seen.has(String(e.id)):
			first = e
			break
	var l := Label.new()
	l.name = "Line"
	l.text = String(first.get("line", ""))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", SPARKLE if fresh else Color(0.85, 0.87, 0.95))
	v.add_child(l)
	if thumb:
		var pic := TextureRect.new()
		pic.name = "Shot"
		pic.texture = thumb
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(128, 112)
		pic.clip_contents = true
		h.add_child(pic)


## The board's tab: a sparkle and "NEW! 5" (unseen count), or a plain "NEW" once everything was opened.
static func tab(seen: Dictionary, on: bool, colour: Color, big: float = 1.0) -> Control:
	var p := PanelContainer.new()
	p.name = "NewsTab"
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour if on else Color(0.1, 0.1, 0.18)
	sb.set_corner_radius_all(int(18 * big))
	sb.content_margin_left = 14 * big
	sb.content_margin_right = 14 * big
	sb.content_margin_top = 4 * big
	sb.content_margin_bottom = 4 * big
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var n := unseen(seen)
	var ink := Color(0.05, 0.05, 0.1) if on else colour
	h.add_child(UiKit.icon("star", ink if on else SPARKLE, (30.0 if on else 26.0) * big))
	var l := Label.new()
	l.name = "Count"
	l.text = "NEW! %d" % n if n > 0 else "NEW"
	l.add_theme_font_size_override("font_size", int((26 if on else 22) * big))
	l.add_theme_color_override("font_color", ink)
	h.add_child(l)
	return p


# --- VR ------------------------------------------------------------------------------------------

const VR_TILE := Vector2(300, 176)
const VR_COLS := 5


## The VR picture wall (a Sprite3D showing a SubViewport). vr_update(wall, games, seen, selected) redraws it.
static func vr_panel() -> Sprite3D:
	var vp := SubViewport.new()
	vp.name = "NewsView"
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var s := Sprite3D.new()
	s.name = "NewsWall"
	s.add_child(vp)
	s.texture = vp.get_texture()
	s.pixel_size = 0.0016
	s.shaded = false
	s.double_sided = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


static func vr_update(wall: Sprite3D, games: Array, seen: Dictionary, selected: int) -> void:
	var vp := wall.get_node("NewsView") as SubViewport
	for c in vp.get_children():
		vp.remove_child(c)
		c.queue_free()
	var list := order(games, seen)
	var n_rows := maxi(1, ceili(float(list.size()) / VR_COLS))
	var pad := 18.0
	var head := 84.0
	var size := Vector2(VR_COLS * (VR_TILE.x + 12) - 12 + pad * 2, head + n_rows * (VR_TILE.y + 12) - 12 + pad * 2)
	vp.size = Vector2i(size)
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.06, 0.04, 0.12, 0.92), 1.0, 28.0, Color(SPARKLE, 0.6), 4.0, 0.0, Vector2(pad, pad)))
	bg.size = size
	vp.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	bg.add_child(v)
	var top := CenterContainer.new()
	top.custom_minimum_size.y = head - 12
	top.add_child(tab(seen, false, SPARKLE, 2.0))
	v.add_child(top)
	var grid := GridContainer.new()
	grid.columns = VR_COLS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for i in list:
		var id := String(games[i].id)
		var col: Color = Progress.script_of(id).COLOR
		var fresh := unseen(seen, id) > 0
		var t := PanelContainer.new()
		t.name = id
		t.custom_minimum_size = VR_TILE
		var on := i == selected
		t.add_theme_stylebox_override("panel", UiKit.stylebox(Color(0.13, 0.12, 0.24) if on else Color(0.08, 0.08, 0.15), 1.0, 16.0,
			col if on else col.darkened(0.45), 6.0 if on else 2.0, 0.0, Vector2(12, 10)))
		grid.add_child(t)
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 10)
		t.add_child(th)
		th.add_child(friend(id, 96.0, fresh, 1.3))
		var pics := GridContainer.new()
		pics.columns = 2
		pics.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pics.add_theme_constant_override("h_separation", 6)
		pics.add_theme_constant_override("v_separation", 6)
		th.add_child(pics)
		var ents := entries_of(id)
		for k in mini(ents.size(), MAX_PICS):
			var p := still(String(ents[k].pic), 64.0, col.lightened(0.1))
			if seen.has(String(ents[k].id)):
				p.modulate = Color(1, 1, 1, 0.6)
			pics.add_child(p)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	wall.set_meta("news_redraws", 3)
