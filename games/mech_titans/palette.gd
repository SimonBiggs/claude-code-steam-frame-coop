extends RefCounted
## What must be seen in Mech Titans, and where (core/contrast.gd; tests/contrast_test.gd).
## Mechs (paint + trim), kaiju (colour + second colour, and the round generator's repaints) and their minis stand in
## every place's city (ground, road, plaza); the tall kaiju are also seen against each place's skies.

const Contrast := preload("res://core/contrast.gd")
const Data := preload("res://games/mech_titans/data.gd")
const RoundGen := preload("res://games/mech_titans/roundgen.gd")
const Tales := preload("res://games/mech_titans/tales.gd")


static func _kaiju() -> Dictionary:
	var out := {}
	for k in Data.KAIJU:
		var info: Dictionary = Data.KAIJU[k]
		out["kaiju %s" % k] = {"color": info.color, "rim": info.get("color2", info.color)}
	for p in RoundGen.PAINTS + [RoundGen.GOLDEN]:
		if String(p[0]) != "":  # (the last entry is "keep its own colours")
			out["%s kaiju" % String(p[0]).to_lower()] = {"color": p[1], "rim": p[2]}
	return out


static func key_colors() -> Dictionary:
	var out := {}
	for p in Data.PAINTS:
		out["%s mech" % p] = {"color": Data.PAINTS[p].main, "rim": Data.PAINTS[p].trim}
	out.merge(_kaiju())
	for m in Data.MINIS:
		if float(Data.MINIS[m].fly) <= 0.0:
			out["mini %s" % m] = Data.MINIS[m].color
	for t in Tales.ORDER:  # deep2: the lost toys stand on the streets of every place
		out["toy %s" % t] = Tales.info(t).color
	return out


static func backgrounds() -> Dictionary:
	var out := {}
	for k in ["ground", "road", "plaza"]:
		out.merge(Contrast.field(k, Data.PLACES, k))
	return out


## The kaiju towering (and the flying minis flitting) against every sky a place can have.
static func groups() -> Array:
	var skies := {}
	for p in RoundGen.SKIES:
		for s in RoundGen.SKIES[p]:
			skies.merge(Contrast.sky(String(s)))
	var flyers := _kaiju()
	for m in Data.MINIS:
		if float(Data.MINIS[m].fly) > 0.0:
			flyers["flying mini %s" % m] = Data.MINIS[m].color
	return [{"keys": flyers, "bgs": skies}]
