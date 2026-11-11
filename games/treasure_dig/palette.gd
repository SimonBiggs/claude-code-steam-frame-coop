extends RefCounted
## What must be seen in Treasure Dig, and every island it is on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Story := preload("res://games/treasure_dig/story.gd")
const Props := preload("res://games/treasure_dig/props.gd")
const Deep := preload("res://games/treasure_dig/deep.gd")


static func key_colors() -> Dictionary:
	var out := Contrast.humanoids(Party.COLORS, Story.LOOKS)
	out["peg"] = Story.PEG_COLOR
	for r in Story.RELICS:  # (outlined: props.gd RELIC_OUTLINE)
		out[String(r[0]).to_lower()] = {"color": r[1], "rim": Props.RELIC_OUTLINE}
	# Second pass (deep.gd): every warning ring on the sand, and what falls / washes up.
	out["tide warning"] = Deep.TIDE_COLOR
	out["drop warning"] = Deep.DROP_COLOR
	out["gold warning"] = Deep.GOLD_COLOR
	for k in Deep.DROPS:  # (ink-outlined as they fall: events.gd)
		out[String(k)] = {"color": Deep.DROPS[k][1], "rim": Props.RELIC_OUTLINE}
	return out


## Every island's sand and its rim.
static func backgrounds() -> Dictionary:
	return Contrast.merge(Contrast.field("sand", Story.ISLANDS, "sand"), Contrast.field("rim", Story.ISLANDS, "rim"))
