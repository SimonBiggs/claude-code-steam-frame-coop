extends RefCounted
## What must be seen in Crystal Saga, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The heroes (any class, any player colour) walk the path through every zone of every region; each region's
## monsters (the ones with a colour of their own: slimes, bats, mushrooms), its guardian giant and the giant's
## warning rings are on that region's path, the guardian's stone and the ground round it.
## (Monster skins without a colour of their own - penguins, crabs, frogs ... - keep core/creatures.gd's look.)

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Classes := preload("res://games/crystal_saga/classes.gd")
const Realm := preload("res://games/crystal_saga/realm.gd")
const Creatures := preload("res://core/creatures.gd")


static func key_colors() -> Dictionary:
	var out := {}
	for c in Classes.INFO:
		var inf: Dictionary = Classes.INFO[c]
		var pants: Color = inf.get("pants", Creatures.LOOKS[String(inf.look)].pants)
		for i in Party.COLORS.size():
			out["%s %d" % [c, i + 1]] = {"color": Party.COLORS[i], "rim": pants}
	return out


static func backgrounds() -> Dictionary:
	var out := {"village path": Realm.PATH_VILLAGE, "giant path": Realm.PATH_GIANT, "shrine path": Realm.PATH_SHRINE}
	out.merge(Contrast.named("path", Realm.PATHS_DEFAULT))
	for b in Realm.BIOMES:
		out.merge(Contrast.named("%s path" % b.id, b.path))
	return out


static func _monsters(skins: Array) -> Dictionary:
	var out := {}
	if String(skins[0]) == "slime":
		out.merge(Contrast.named("slime", Realm.SLIME_COLORS))
	if String(skins[1]) == "mushroom":
		out["mushroom"] = Realm.MUSHY_COLOR
	if String(skins[2]) == "bat":
		out["bat"] = Realm.BAT_COLOR
	return out


static func groups() -> Array:
	var tells := Contrast.named("warning", Realm.TELL_COLORS)
	var out := []
	for b in Realm.BIOMES:
		var keys := _monsters(b.skins)
		keys["%s giant" % b.id] = {"color": b.body, "rim": b.glow}
		keys.merge(tells)
		out.append({"keys": keys, "bgs": Contrast.merge(Contrast.named("%s path" % b.id, b.path),
			{"giant path": Realm.PATH_GIANT, "%s ground" % b.id: b.ground})})
	# A journey without a region (the first saga): every skin's default, the saga giants.
	var keys := _monsters(["slime", "mushroom", "bat"])
	for g in Realm.SAGA_GIANTS:
		keys["%s giant" % String(g[0]).to_lower()] = {"color": g[1], "rim": g[2]}
	keys.merge(tells)
	out.append({"keys": keys, "bgs": Contrast.merge(Contrast.named("path", Realm.PATHS_DEFAULT),
		{"giant path": Realm.PATH_GIANT, "meadow": Realm.MEADOW})})
	return out
