extends RefCounted
## What must be seen in Elemental Bender, and every arena ground it is on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Elem := preload("res://games/elemental_bender/elem.gd")
const Arenas := preload("res://games/elemental_bender/arenas.gd")
const Deep := preload("res://games/elemental_bender/deep.gd")


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


## Kiko's warned island surprises (deep.gd TRICKS): each island's two warning colours on that island's ground and shore.
static func groups() -> Array:
	var out := []
	for a in Arenas.LIST:
		var id := String(a.id)
		var keys := {}
		for k in ["rain", "sweep"]:
			var tr := Deep.trick(id, k)
			keys["%s tell" % String(tr.name).to_lower()] = tr.color
		out.append({"keys": keys, "bgs": {"%s ground" % id: a.ground, "%s shore" % id: a.shore}})
	return out
