extends RefCounted
## MECH TITANS frames: the Titan's body, picked at the start of a session from glowing FRAME PODS (picks.gd)
## once the family has more than one. Each frame has its own paint (data.gd PAINTS: you see it at once, in
## the cockpit and on the TV) and its own feel. New frames unlock for good as the Kaiju Sanctuary grows.
##   TITAN     classic blue    just right at everything
##   SPRINTER  jungle green    walks and dashes further, punches a bit softer
##   BRUISER   fire red        big punches, tough armour, a bit slower
##   ZAPPER    midnight        a much stronger beam, softer punches
##   STARLIGHT gold            a little better at everything
## The numbers multiply the Titan's (main.gd frame_stat()).

const ORDER: Array[String] = ["titan", "sprinter", "bruiser", "zapper", "starlight"]
const INFO := {
	"titan": {"name": "TITAN", "paint": "classic", "hearts": 0, "punch": 1.0, "beam": 1.0, "speed": 1.0, "dash": 1.0, "armour": 1.0},
	"sprinter": {"name": "SPRINTER", "paint": "jungle", "hearts": 6, "punch": 0.85, "beam": 1.0, "speed": 1.3, "dash": 1.35, "armour": 0.9},
	"bruiser": {"name": "BRUISER", "paint": "fire", "hearts": 12, "punch": 1.45, "beam": 0.9, "speed": 0.85, "dash": 1.0, "armour": 1.4},
	"zapper": {"name": "ZAPPER", "paint": "midnight", "hearts": 20, "punch": 0.85, "beam": 1.55, "speed": 1.0, "dash": 1.0, "armour": 1.0},
	"starlight": {"name": "STARLIGHT", "paint": "gold", "hearts": 40, "punch": 1.15, "beam": 1.15, "speed": 1.1, "dash": 1.1, "armour": 1.15},
}


static func info(id: String) -> Dictionary:
	return INFO.get(id, INFO["titan"])


static func valid(id: String) -> bool:
	return INFO.has(id)


static func unlocked(hearts: int) -> Array:
	var out: Array = []
	for id in ORDER:
		if hearts >= int(INFO[id]["hearts"]):
			out.append(id)
	return out


## Why the frames aren't fair (empty = fine): every frame is a trade (nothing is worse at everything than the
## TITAN, nothing but STARLIGHT is better at everything), stats stay in range, names are one capital word.
static func check(paints: Dictionary) -> Array:
	var out: Array = []
	for id in ORDER:
		var f: Dictionary = INFO[id]
		if not paints.has(String(f["paint"])):
			out.append("%s paint %s missing" % [id, f["paint"]])
		var better := 0
		var worse := 0
		for k in ["punch", "beam", "speed", "dash", "armour"]:
			var v := float(f[k])
			if v < 0.8 or v > 1.6:
				out.append("%s %s %.2f out of range" % [id, k, v])
			better += 1 if v > 1.001 else 0
			worse += 1 if v < 0.999 else 0
		if id != "titan" and better == 0:
			out.append("%s is no better at anything" % id)
		if id != "starlight" and id != "titan" and worse == 0:
			out.append("%s is better at everything" % id)
		if String(f["name"]).split(" ", false).size() != 1 or String(f["name"]) != String(f["name"]).to_upper():
			out.append("frame name %s" % f["name"])
	return out
