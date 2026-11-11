extends RefCounted
## What must be seen in Cannon Cove, and the deck, sea and skies it is seen on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/cannon_cove/looks.gd")
const World := preload("res://games/cannon_cove/world.gd")
const EnemyShip := preload("res://games/cannon_cove/enemy_ship.gd")


## Deckhands and boarders on our deck.
static func key_colors() -> Dictionary:
	var out := {"gunner": Looks.PLAYER_COLORS[0]}
	for i in range(1, Looks.PLAYER_COLORS.size()):  # deckhands: coat + dark trousers
		out["deckhand %d" % (i + 1)] = {"color": Looks.PLAYER_COLORS[i], "rim": Looks.DECKHAND_TROUSERS}
	return Contrast.merge(out, {"boarder": Looks.BOARDER_SHIRT,
		"cannonball (carried)": Looks.BALL})


static func backgrounds() -> Dictionary:
	return {"deck plank": Looks.DECK_WOOD, "deck seam": Looks.DECK_DARK}


## The sea's deep and shallow water in every sky mood.
static func seas() -> Dictionary:
	var out := {}
	for m in World.MOODS:
		var night := float(World.MOODS[m].get("night", 0.0))
		out["%s deep sea" % m] = Looks.sea_at(Looks.SEA_DEEP, night)
		out["%s shallow sea" % m] = Looks.sea_at(Looks.SEA_SHALLOW, night)
	return out


## Every mood's sky (top and horizon).
static func skies() -> Dictionary:
	return Contrast.merge(Contrast.field("sky", World.MOODS, "top"), Contrast.field("horizon", World.MOODS, "horizon"))


static func groups() -> Array:
	var ships := {}
	for k in EnemyShip.KINDS:  # a ship shows its sail and its hull
		ships["%s ship" % k] = {"color": EnemyShip.KINDS[k][6], "rim": Looks.TREASURE_HULL if k == "treasure" else Looks.HULL}
	var on_sea := Contrast.merge(ships, {"tentacle": Looks.TENTACLE_SKIN, "kraken": Looks.KRAKEN_SKIN,
		"practice raft": {"color": Looks.BULLSEYE, "rim": Looks.RAFT}, "supply barrel": {"color": Looks.SUPPLY_RING, "rim": Looks.RAFT},
		"treasure chest": {"color": Looks.CHEST_GOLD, "rim": Looks.RAFT}})
	# Cannonballs fly through the sky and splash down on the sea, each trailing its smoke.
	var balls := {"cannonball": {"color": Looks.BALL, "rim": Looks.SMOKE},
		"pirate cannonball": {"color": Looks.ENEMY_BALL, "rim": Looks.ENEMY_SMOKE},
		"golden cannonball": {"color": Looks.MEGA_BALL, "rim": Looks.OUTLINE}}
	return [
		{"keys": on_sea, "bgs": seas()},
		{"keys": ships, "bgs": Contrast.field("horizon", World.MOODS, "horizon")},  # far ships stand against the horizon
		{"keys": balls, "bgs": Contrast.merge(skies(), seas())},
		{"keys": {"pirate cannonball": {"color": Looks.ENEMY_BALL, "rim": Looks.ENEMY_SMOKE}}, "bgs": backgrounds()},
	]
