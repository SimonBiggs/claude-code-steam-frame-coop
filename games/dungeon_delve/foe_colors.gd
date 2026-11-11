extends RefCounted
## DUNGEON DELVE: every foe's colour in every zone (foes.gd _look builds them; palette.gd checks each on its zone's
## floor, core/contrast.gd). kind -> zone id -> colour; a zone left out uses a creature without a colour of its
## own (the crypt's skeletons). 2026-11: the crypt's bats and wolves, the caves' wolves and the forge's golems
## were lightened: they vanished on their dark floors.

const FOES := {
	"slime": {"caves": Color(0.45, 0.9, 0.45), "crypt": Color(0.7, 0.5, 1.0), "crystal": Color(0.45, 0.85, 1.0), "forge": Color(1.0, 0.55, 0.25)},
	"spitter": {"caves": Color(0.55, 0.85, 0.35), "crystal": Color(0.5, 0.8, 1.0), "forge": Color(1.0, 0.45, 0.25)},
	"shield": {"caves": Color(1.0, 0.5, 0.4), "crystal": Color(0.55, 0.75, 0.95), "forge": Color(0.6, 0.6, 0.7)},
	"swarm": {"caves": Color(0.55, 0.4, 0.75), "crypt": Color(0.6, 0.55, 0.85), "crystal": Color(0.4, 0.75, 0.9), "forge": Color(1.0, 0.6, 0.2)},
	"healer": {"caves": Color(0.4, 0.9, 0.6), "crypt": Color(0.7, 1.0, 0.8), "crystal": Color(1.0, 0.7, 0.95), "forge": Color(1.0, 0.85, 0.5)},
	"charger": {"caves": Color(0.72, 0.72, 0.78), "crypt": Color(0.68, 0.68, 0.85), "crystal": Color(0.75, 0.9, 1.0), "forge": Color(0.7, 0.48, 0.38)},
	"bomber": {"caves": Color(0.5, 0.78, 0.35), "crypt": Color(0.5, 0.78, 0.35), "crystal": Color(0.5, 0.78, 0.35), "forge": Color(0.85, 0.5, 0.35)},
	"boss": {"caves": Color(0.5, 0.85, 1.0), "crystal": Color(0.45, 0.8, 1.0), "forge": Color(0.62, 0.42, 0.36)},
}


static func of(kind: String, zone: String) -> Color:
	var by_zone: Dictionary = FOES[kind]
	return by_zone.get(zone, by_zone.values()[0])
