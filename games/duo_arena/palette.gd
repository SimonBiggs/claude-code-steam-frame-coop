extends RefCounted
## What must be seen in Duo Arena, and every zone floor it is on (core/contrast.gd; tests/contrast_test.gd).

const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/duo_arena/looks.gd")
const Gen := preload("res://games/duo_arena/arenagen.gd")
const Bosses := preload("res://games/duo_arena/bosses.gd")
const Enemy := preload("res://games/duo_arena/enemy.gd")
const Deep := preload("res://games/duo_arena/deep.gd")


## Players, pickups, monsters, bosses, hazard pads, the boss slam ring, every told surprise / charge / fireball ring and
## Nova's spring.
static func key_colors() -> Dictionary:
	var out := Contrast.named("player", Looks.PLAYER_COLORS)
	out.merge(Contrast.named("pickup", Looks.PICKUP_COLORS))
	out.merge(Contrast.field("monster", Enemy.KINDS, "color"))
	out.merge(Contrast.field("boss", Bosses.LIST, "color"))
	out.merge(Contrast.field("pad", Gen.HAZARDS, "color"))
	out["boss slam ring"] = Looks.BOSS_WARN
	out.merge(Contrast.field("surprise ring", Deep.SURPRISES, "color"))  # the told surprises' warn rings
	out["dino charge lane"] = Looks.CHARGE_WARN
	out["fireball spot"] = Looks.FIREBALL_WARN
	out["Nova's spring"] = Looks.SPRING_COLOR
	return out


## Every zone's floor (zone.gd sets the floor shader's base colour from it).
static func backgrounds() -> Dictionary:
	return Contrast.field("floor", Gen.ZONES, "base")
