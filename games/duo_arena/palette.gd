extends RefCounted
## What must be seen in Duo Arena, and every zone floor it is on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/duo_arena/looks.gd")
const Gen := preload("res://games/duo_arena/arenagen.gd")
const Bosses := preload("res://games/duo_arena/bosses.gd")
const Enemy := preload("res://games/duo_arena/enemy.gd")


## Players, pickups, monsters, bosses, hazard pads and the boss slam ring.
static func key_colors() -> Dictionary:
	var out := Contrast.named("player", Looks.PLAYER_COLORS)
	out.merge(Contrast.named("pickup", Looks.PICKUP_COLORS))
	out.merge(Contrast.field("monster", Enemy.KINDS, "color"))
	out.merge(Contrast.field("boss", Bosses.LIST, "color"))
	out.merge(Contrast.field("pad", Gen.HAZARDS, "color"))
	out["boss slam ring"] = Looks.BOSS_WARN
	return out


## Every zone's floor (zone.gd sets the floor shader's base colour from it).
static func backgrounds() -> Dictionary:
	return Contrast.field("floor", Gen.ZONES, "base")
