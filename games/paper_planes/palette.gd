extends RefCounted
## What must be seen in Paper Planes, and every sky and ground it flies over (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Meshes := preload("res://games/paper_planes/meshes.gd")
const Story := preload("res://games/paper_planes/story.gd")


## Hoops and planes, each with the ink outline main.gd gives them (meshes.gd OUTLINE).
static func key_colors() -> Dictionary:
	var cols := Contrast.named("hoop", Meshes.HOOP_COLORS)
	cols.merge(Contrast.named("rainbow hoop", Meshes.RAINBOW))
	cols.merge({"chain hoop": Meshes.CHAIN_COLOR, "tiny hoop": Meshes.TINY_COLOR, "gate": Meshes.GATE_COLOR,
		"gold hoop": Meshes.GOLD_COLOR})
	for i in Party.COLORS.size():
		cols["plane %d" % (i + 1)] = Meshes.plane_tint(Party.COLORS[i])
	var out := {}
	for k in cols:
		out[k] = {"color": cols[k], "rim": Meshes.OUTLINE}
	return out


## Every chapter's sky (top and horizon) and its grass far below.
static func backgrounds() -> Dictionary:
	var out := Contrast.field("ground", Story.CHAPTERS, "ground", "name")
	for c in Story.CHAPTERS:
		out.merge(Contrast.sky(String(c.sky)))
	return out
