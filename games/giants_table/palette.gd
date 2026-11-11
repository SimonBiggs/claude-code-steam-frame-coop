extends RefCounted
## What must be seen on Giant's Table, and every ground of the meadow (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/giants_table/looks.gd")
const World := preload("res://games/giants_table/world.gd")
const Goblin := preload("res://games/giants_table/goblin.gd")


## The knights (P2..; P1 is the giant) and every goblin, outlined (goblin.gd).
static func key_colors() -> Dictionary:
	var out := {}
	for i in range(1, Looks.PLAYER_COLORS.size()):  # each knight wears a steel helmet
		out["knight %d" % (i + 1)] = {"color": Looks.PLAYER_COLORS[i], "rim": Looks.KNIGHT_HELM}
	for k in Goblin.KINDS:
		out["%s goblin" % k] = {"color": Goblin.KINDS[k].color, "rim": Looks.GOBLIN_OUTLINE}
	out["armour"] = {"color": Looks.ARMOR, "rim": Looks.GOBLIN_OUTLINE}
	return out


## The meadow's grounds, with the grass lightened as far as the hills lift it.
static func backgrounds() -> Dictionary:
	var out := Contrast.named("ground", World.GROUND)
	out["ground grass (hill)"] = (World.GROUND.grass as Color).lightened(World.GRASS_LIFT)
	out["ground grass 2 (hill)"] = (World.GROUND["grass 2"] as Color).lightened(World.GRASS_LIFT)
	return out
