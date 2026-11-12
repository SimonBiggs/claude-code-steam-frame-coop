extends RefCounted
## What must be seen in Dungeon Delve, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The heroes go everywhere: the first dungeon's rooms (dungeon.gd) and every zone's floors (floorgen.gd ZONES).
## Each zone's foes (foe_colors.gd) are only met on that zone's floor; the first dungeon's slimes on its rooms.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const FoeColors := preload("res://games/dungeon_delve/foe_colors.gd")
const Hero := preload("res://games/dungeon_delve/hero.gd")
const Dungeon := preload("res://games/dungeon_delve/dungeon.gd")
const Monsters := preload("res://games/dungeon_delve/monsters.gd")
const Friends := preload("res://games/dungeon_delve/friends.gd")


static func key_colors() -> Dictionary:
	return Contrast.humanoids(Party.COLORS, Hero.LOOKS, "hero")


static func _zone_floors(z: Dictionary) -> Dictionary:
	return Contrast.named("%s floor" % z.id, z.floor)


static func _rooms() -> Dictionary:
	return Contrast.merge(Contrast.named("room floor", Dungeon.FLOOR), Contrast.named("treasure floor", Dungeon.GOLD_FLOOR))


static func backgrounds() -> Dictionary:
	var out := _rooms()
	for z in FloorGen.ZONES:
		out.merge(_zone_floors(z))
	return out


static func groups() -> Array:
	var out := [{"keys": Contrast.named("slime", Monsters.SLIME_COLORS), "bgs": Contrast.named("room floor", Dungeon.FLOOR)}]
	for z in FloorGen.ZONES:
		var keys := {}
		for kind in FoeColors.FOES:
			if FoeColors.FOES[kind].has(z.id):
				keys["%s %s" % [z.id, kind]] = FoeColors.FOES[kind][z.id]
		out.append({"keys": keys, "bgs": _zone_floors(z)})
		# Cinder's lost friends (friends.gd) sit in a gold cage on their own zone's floors.
		var fk := {"friend cage": Friends.CAGE_COLOR}
		for fr in Friends.BY_ZONE[z.id]:
			fk["friend " + String(fr.id)] = fr.color
		out.append({"keys": fk, "bgs": _zone_floors(z)})
	return out
