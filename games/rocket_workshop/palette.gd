extends RefCounted
## What must be seen in Rocket Workshop: the crew and their jobs on the plank floor and the yard's grass, and the
## pilot's coloured buttons, plugs and shapes on the desk's module panels (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/rocket_workshop/looks.gd")
const P := preload("res://games/rocket_workshop/puzzles.gd")
const PanelScript := preload("res://games/rocket_workshop/panel.gd")


## The crew and their jobs (paint pots: a coloured lid on a pale pot).
static func key_colors() -> Dictionary:
	var out := Contrast.named("crew", Looks.PLAYER_COLORS.slice(1))
	out.merge({"fuel canister": Looks.CANISTER, "bolt": Looks.BOLT, "space cat": Looks.CAT_FUR})
	for i in P.COLORS.size():
		out["%s paint pot" % P.COLOR_NAMES[i].to_lower()] = {"color": P.COLORS[i], "rim": Looks.PAINT_POT}
	return out


## The plank floor (both tones, the darkest mix, a seam) and the yard's grass.
static func backgrounds() -> Dictionary:
	var dark := Looks.FLOOR_A.lerp(Looks.FLOOR_B, Looks.FLOOR_MIX)
	return {"plank": Looks.FLOOR_A, "dark plank": dark, "seam": dark * (1.0 - Looks.SEAM_DARK), "yard grass": Looks.GRASS}


static func groups() -> Array:
	var keys := Contrast.merge(Contrast.named("colour", P.COLORS), Contrast.named("shape", P.SHAPE_COLORS))
	keys.merge(Contrast.merge(Contrast.named("alien", P.ALIEN_COLORS), Contrast.named("hello", P.HELLO_COLORS)))
	var bgs := {}
	for k in PanelScript.AREAS:
		bgs["%s panel" % k] = PanelScript.AREAS[k][3]
	for k in PanelScript.WING_AREAS:
		bgs["%s panel" % k] = PanelScript.WING_AREAS[k][4]
	return [{"keys": keys, "bgs": bgs}]
