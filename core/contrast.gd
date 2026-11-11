extends RefCounted
## ONE colour-contrast check for every game: can you SEE the thing you must play with on what it sits on?
## (2026-11: white sheep vanished on Sheep Round-Up's snow, blue balloons on Balloon Pop's day sky, green balloons
## on its grass; Marble Maze checked its marbles on its floors. Each made its own check: now there is this one.)
##
## Measure: Oklab (a perceptual colour space). score(fg, bg) = the Oklab distance = lightness difference plus the
## chroma / hue difference (the a/b plane), so a pale-blue thing on a pale-blue sky scores low however "different"
## the RGB numbers look. A see-through fg (alpha < 1, e.g. a warn stripe) is blended over bg first.
##   Contrast.score(fg, bg) -> float      0 = the same colour, ~0.1 = barely, 0.2+ = clear at a glance
##   Contrast.distinct(fg, bg) -> bool    score >= MIN
##   Contrast.problems(fgs, bgs, min) -> Array[String]   fgs / bgs: {name: Color}; a fg may be {"color": C, "rim": R}
##                                        (an outline / glow / rim, or a second part it always shows such as a
##                                        dark face or dark trousers): it is distinct when either is.
##
## Every game declares what must be seen and where: games/<game>/palette.gd (found by itself, like
## story_pictures.gd) with
##   static func key_colors() -> Dictionary    # name -> Color (or {"color", "rim"}): players, balls, pickups, hazards
##   static func backgrounds() -> Dictionary   # name -> Color: every floor / ground / sky / table it can produce
##                                             # (all seasons, worlds, themes, times of day, modes)
##   optional static func groups() -> Array    # [{"keys": {...}, "bgs": {...}}]: extra pairs for things only ever
##                                             # seen on some backgrounds (e.g. a sky bird that never sits on grass)
## READ them from the game's real consts / data (preload the game's scripts), never copy numbers, so they can't drift.
## tests/contrast_test.gd runs every declaration and fails a game in arcade GAMES without one.
##
## MIN: the known bad cases score 0.044-0.087 (white sheep on snow 0.060, lamb on snow 0.079, the old blue balloon on
## the day sky 0.087, the old green balloon on spring grass 0.083, the old ice balloon on snow 0.044); their fixes
## score 0.138 and up (frosty grass under white sheep 0.195, the new green balloon on grass 0.169, the new ice
## balloon on snow 0.138). 0.12 sits between them (tests/contrast_test.gd keeps these as its own samples).

const MIN := 0.12
## The usual outline (outline()): a soft dark ink line round a key thing that must show on light AND dark grounds.
const OUTLINE := Color(0.12, 0.1, 0.16)
const OUTLINE_WIDTH := 0.02  # metres the outline shell grows out of the surface

static var _outline_mats: Dictionary = {}

const _GAMES_DIR := "res://games"


## Oklab of an sRGB colour: x = lightness L (0..1), y = a (green-red), z = b (blue-yellow).
static func oklab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var a := pow(maxf(0.0, 0.4122214708 * l.r + 0.5363325363 * l.g + 0.0514459929 * l.b), 1.0 / 3.0)
	var m := pow(maxf(0.0, 0.2119034982 * l.r + 0.6806995451 * l.g + 0.1073969566 * l.b), 1.0 / 3.0)
	var s := pow(maxf(0.0, 0.0883024619 * l.r + 0.2817188376 * l.g + 0.6299787005 * l.b), 1.0 / 3.0)
	return Vector3(0.2104542553 * a + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * a - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * a + 0.7827717662 * m - 0.8086757660 * s)


## What you see of fg over bg (a see-through fg is blended in by its alpha).
static func over(fg: Color, bg: Color) -> Color:
	if fg.a >= 1.0:
		return Color(fg.r, fg.g, fg.b)
	return Color(bg.r, bg.g, bg.b).lerp(Color(fg.r, fg.g, fg.b), clampf(fg.a, 0.0, 1.0))


## How different fg looks on bg: Oklab distance (lightness + chroma/hue). 0 = the same.
static func score(fg: Color, bg: Color) -> float:
	return oklab(over(fg, bg)).distance_to(oklab(Color(bg.r, bg.g, bg.b)))


## Lightness gap only (0..1): useful in messages ("make it darker").
static func lightness_gap(fg: Color, bg: Color) -> float:
	return oklab(over(fg, bg)).x - oklab(Color(bg.r, bg.g, bg.b)).x


static func distinct(fg: Color, bg: Color, min_score: float = MIN) -> bool:
	return score(fg, bg) >= min_score


## The best score of a key (a Color, or {"color": C, "rim": R}) on bg.
static func key_score(key, bg: Color) -> float:
	if key is Color:
		return score(key, bg)
	if key is Dictionary and key.has("color"):
		var s := score(key.color, bg)
		if key.has("rim"):
			s = maxf(s, score(key.rim, bg))
		return s
	return -1.0


## Every key colour that isn't distinct from a background: [] = fine.
static func problems(fgs: Dictionary, bgs: Dictionary, min_score: float = MIN) -> Array[String]:
	var out: Array[String] = []
	for fn in fgs:
		var key = fgs[fn]
		if not (key is Color or (key is Dictionary and key.get("color") is Color)):
			out.append("%s is not a Color (or {color, rim})" % fn)
			continue
		for bn in bgs:
			if not (bgs[bn] is Color):
				out.append("background %s is not a Color" % bn)
				continue
			var bg: Color = bgs[bn]
			var s := key_score(key, bg)
			if s < min_score:
				var fc: Color = key if key is Color else key.color
				var lg := lightness_gap(fc, bg)
				out.append("%s #%s is hard to see on %s #%s (%.3f < %.2f; %s)" % [fn, fc.to_html(false), bn,
					bg.to_html(false), s, min_score, "make it lighter or the background darker" if lg >= 0.0
					else "make it darker or the background lighter"])
	return out


## {"<what> 1": c0, "<what> 2": c1, ...} from a list (or {"<what> <key>": c} from a dictionary of Colors), for
## palette.gd files: Contrast.named("player", Party.COLORS).
static func named(what: String, colors) -> Dictionary:
	var out := {}
	if colors is Dictionary:
		for k in colors:
			out["%s %s" % [what, k]] = colors[k]
	else:
		for i in colors.size():
			out["%s %d" % [what, i + 1]] = colors[i]
	return out


## {"<what> <id>": entry[field]} from an Array of Dictionaries (or a Dictionary of Dictionaries), e.g. a game's
## THEMES / BREEDS / TRACKS: Contrast.field("floor", Levels.THEMES_LIST, "floor", "id").
static func field(what: String, entries, key: String, id_key: String = "id") -> Dictionary:
	var out := {}
	if entries is Dictionary:
		for k in entries:
			if entries[k] is Dictionary and entries[k].has(key):
				out["%s %s" % [what, k]] = entries[k][key]
	else:
		for i in entries.size():
			var e = entries[i]
			if e is Dictionary and e.has(key):
				out["%s %s" % [what, e.get(id_key, str(i + 1))]] = e[key]
	return out


## Players drawn as core/creatures.gd humanoids: their outfit colour, with the class's trousers as the rim (a
## humanoid always shows them below the outfit). looks: the game's LOOKS (class per slot, wrapping).
static func humanoids(outfits: Array, looks: Array, what: String = "player") -> Dictionary:
	var classes: Dictionary = load("res://core/creatures.gd").LOOKS
	var out := {}
	for i in outfits.size():
		var cls := String(looks[i % looks.size()])
		var look: Dictionary = classes.get(cls, {})
		out["%s %d" % [what, i + 1]] = {"color": outfits[i], "rim": look.get("pants", outfits[i])}
	return out


## A core/sky_kit.gd preset's sky colours (top + horizon): what flying things are seen against.
static func sky(preset: String) -> Dictionary:
	var sk = load("res://core/sky_kit.gd")
	var p: Dictionary = sk.PRESETS[sk.resolve(preset)]
	return {"%s sky" % preset: p.top, "%s horizon" % preset: p.horizon}


## a + b (later names win).
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


# --- Fixes ------------------------------------------------------------------------------------------------

## Give a key thing an ink outline: an unshaded back-face shell (StandardMaterial3D grow) drawn as the mesh's
## material_overlay, so shared materials are left alone. Contrast.outline(mesh_instance) or (mi, Color.WHITE).
## Declare it in palette.gd as {"color": C, "rim": Contrast.OUTLINE} (or the colour you passed) so the check counts
## it. Smooth meshes (spheres, capsules, blobs) outline cleanly; hard-edged boxes show small gaps at the corners.
## One shared shell material per colour + width. Returns mi.
static func outline(mi: GeometryInstance3D, color: Color = OUTLINE, width: float = OUTLINE_WIDTH) -> GeometryInstance3D:
	if mi == null:
		return mi
	mi.material_overlay = outline_material(color, width)
	return mi


static func outline_material(color: Color = OUTLINE, width: float = OUTLINE_WIDTH) -> StandardMaterial3D:
	var key := "%s_%.3f" % [color.to_html(), width]
	var o: StandardMaterial3D = _outline_mats.get(key)
	if o == null:
		o = StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.albedo_color = color
		o.grow = true
		o.grow_amount = width
		o.disable_receive_shadows = true
		_outline_mats[key] = o
	return o


# --- Per-game declarations ---------------------------------------------------------------------------

## res://games/<id>/palette.gd, or "" when the game has none.
static func palette_path(id: String) -> String:
	var p := "%s/%s/palette.gd" % [_GAMES_DIR, id]
	return p if ResourceLoader.exists(p) else ""


## Every games/<id> with a palette.gd: id -> path.
static func palettes() -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(_GAMES_DIR):
		return out
	for g in DirAccess.get_directories_at(_GAMES_DIR):
		var p := palette_path(g)
		if p != "":
			out[g] = p
	return out


## One game's problems (each line starts with the game id): [] = everything it must show stands out.
static func check_game(id: String) -> Array[String]:
	var out: Array[String] = []
	var path := palette_path(id)
	if path == "":
		out.append("%s: no colour declaration - add games/%s/palette.gd (key_colors() + backgrounds(); core/contrast.gd)" % [id, id])
		return out
	if FileAccess.get_file_as_string(path).contains("/main.gd\")"):
		out.append("%s: games/%s/palette.gd loads main.gd (slow: 100-500 ms each); move the consts it needs into a small data script that main.gd uses too" % [id, id])
		return out
	var s = load(path)
	if s == null or not (s is Script) or not s.can_instantiate():
		out.append("%s: games/%s/palette.gd doesn't compile" % [id, id])
		return out
	var keys = s.key_colors()
	var bgs = s.backgrounds()
	if not (keys is Dictionary) or keys.is_empty():
		out.append("%s: palette.gd key_colors() is empty" % id)
	if not (bgs is Dictionary) or bgs.is_empty():
		out.append("%s: palette.gd backgrounds() is empty" % id)
	if out.is_empty():
		for p in problems(keys, bgs):
			out.append("%s: %s" % [id, p])
	if s.has_method("groups"):
		for gr in s.groups():
			for p in problems(gr.get("keys", {}), gr.get("bgs", {})):
				out.append("%s: %s" % [id, p])
	return out


## Pairs counted (for the test's summary).
static func pair_count(id: String) -> int:
	var path := palette_path(id)
	if path == "":
		return 0
	var s = load(path)
	var n: int = s.key_colors().size() * s.backgrounds().size()
	if s.has_method("groups"):
		for gr in s.groups():
			n += gr.get("keys", {}).size() * gr.get("bgs", {}).size()
	return n
