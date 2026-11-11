extends RefCounted
## What must be seen in Elemental Bender, and every arena ground it is on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Elem := preload("res://games/elemental_bender/elem.gd")
const Arenas := preload("res://games/elemental_bender/arenas.gd")


## The four elements' blasts, the benders' robes (their bodies) and thrown rock.
static func key_colors() -> Dictionary:
	var out := {}
	for i in Elem.NAMES.size():
		out["%s blast" % Elem.NAMES[i].to_lower()] = Elem.COLORS[i]
		out["%s robe" % Elem.NAMES[i].to_lower()] = Elem.ROBES[i]
	out["rock"] = Elem.ROCK
	return out


## Every arena's ground and shore (fights happen on them).
static func backgrounds() -> Dictionary:
	return Contrast.merge(Contrast.field("ground", Arenas.LIST, "ground"), Contrast.field("shore", Arenas.LIST, "shore"))
