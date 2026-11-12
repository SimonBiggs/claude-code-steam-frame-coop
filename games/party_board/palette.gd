extends RefCounted
## What must be seen in Party Board, and what it stands on (core/contrast.gd; tests/contrast_test.gd).
## On the board the tokens stand on the space tiles, and the tiles sit on each board's ground (sampled under the
## classic island's spaces with board_data.gd ground_color, every board theme). In the minigames the walkers
## stand on each little island (minigames/floors.gd).

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const BD := preload("res://games/party_board/board_data.gd")
const Boards := preload("res://games/party_board/boards.gd")
const Token := preload("res://games/party_board/token.gd")
const Floors := preload("res://games/party_board/minigames/floors.gd")
const Deep := preload("res://games/party_board/deep.gd")


## The players as drawn (token.gd LOOKS: the class per slot), on the board and in every minigame.
static func key_colors() -> Dictionary:
	var classes := []
	for l in Token.LOOKS:
		classes.append(String(l[0]))
	return Contrast.humanoids(Party.COLORS, classes)


## The space tiles the tokens stand on, and every minigame floor.
static func backgrounds() -> Dictionary:
	var out := _tiles()
	out.merge(Contrast.named("minigame grass", Floors.GRASS))
	out.merge({"minigame sand": Floors.SAND, "memory tile": Floors.MEMORY_BLANK, "platform top": Floors.PLATFORM_TOP})
	out.merge(Contrast.named("kart lane", Floors.KART_ROAD))
	return out


## Every space's tile colour (its plinth rings it in a darker edge: BD.tile_base).
static func _tiles() -> Dictionary:
	var out := {}
	for t in BD.TYPE_COLORS:
		out["%s space" % t] = BD.TYPE_COLORS[t][0]
	for t in Boards.SPECIALS:
		out["%s space" % t] = Boards.SPECIALS[t].tile
	out["gift space"] = Boards.GIFT_COLORS[0]
	return out


## The ground under the classic island's spaces on one board (distinct colours only).
static func _grounds(bd, theme: String) -> Dictionary:
	var out := {}
	var seen := {}
	for s in bd.spaces:
		var p: Vector3 = s["pos"]
		var c: Color = BD.ground_color(p.x, p.z, p.y, theme)
		var q := "%d_%d_%d" % [roundi(c.r * 25.0), roundi(c.g * 25.0), roundi(c.b * 25.0)]
		if not seen.has(q):
			seen[q] = true
			out["%s ground %d" % [theme, seen.size()]] = c
	return out


static func _edged(name: String, tile: Color) -> Dictionary:
	return {name: {"color": tile, "rim": BD.tile_base(tile)}}


static func groups() -> Array:
	var out := []
	var bd = BD.new()
	for b in Boards.BOARDS:
		# Every board's spaces (the usual ones, the presents and its own special) on its ground.
		var keys := {}
		for t in BD.TYPE_COLORS:
			keys.merge(_edged("%s space" % t, BD.TYPE_COLORS[t][0]))
		keys.merge(_edged("gift space", Boards.GIFT_COLORS[0]))
		keys.merge(_edged("%s space" % b.special, Boards.SPECIALS[b.special].tile))
		out.append({"keys": keys, "bgs": _grounds(bd, String(b.id))})
	# Mango's warned SURPRISES (deep.gd): steady discs on blue / red spaces only (deep.gd plain()); a disc is bigger than
	# its tile, so its edge sits on the board's ground too.
	var tells := {"rock tell": Deep.ROCK_COLOR, "splash tell": Deep.WAVE_COLOR}
	var under := {"blue space": BD.TYPE_COLORS.blue[0], "red space": BD.TYPE_COLORS.red[0]}
	for b in Boards.BOARDS:
		under.merge(_grounds(bd, String(b.id)))
	out.append({"keys": tells, "bgs": under})
	# FALLING PLATFORMS: the warning ring round a stone that is about to drop.
	out.append({"keys": {"platform warning": Floors.PLATFORM_WARN}, "bgs": {"platform top": Floors.PLATFORM_TOP}})
	return out
