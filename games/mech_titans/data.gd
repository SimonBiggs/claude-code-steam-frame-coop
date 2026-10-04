extends RefCounted
## MECH TITANS: game data (missions, kaiju, support vehicles, upgrades, paints, texts). Plain constants
## only, so every machine reads the same tables and the scripts hot-reload cleanly.
## Units: metres. The Titan is ~10.5 m tall, kaiju 7-15 m, citizens ~0.55 m: a toy-like city.

const GAME_ID := "mech_titans"
const SAVE_VERSION := 1

## Map half-size (the playable square is +-MAP on X and Z).
const MAP := 72.0
## Where the Titan starts each mission (feet), facing -Z (north, where the kaiju come from).
const MECH_START := Vector3(0.0, 0.0, 46.0)

# --- Visual layers ------------------------------------------------------------------------------
## Layer 2: the Titan's head / canopy shell. The pilot sits inside it: the VR camera skips it.
const LAYER_EXTERIOR := 1 << 1
## Layer 3: the pilot's holo displays, aim dot and hand laser (VR camera + VR mirror only).
const LAYER_VR_ONLY := 1 << 2
## Layer 4: TV-only world markers (billboarded "HELP!" signs, name tags): the VR camera skips them.
const LAYER_TV_ONLY := 1 << 3

# --- Arm tools ----------------------------------------------------------------------------------
const TOOLS: Array[String] = ["fist", "claw", "foam", "drill"]
const TOOL_INFO := {
	"fist": {"name": "MEGA FIST", "color": Color(0.35, 0.75, 1.0), "desc": "Punch! The beam fires from your chest."},
	"claw": {"name": "CLAW GRABBER", "color": Color(1.0, 0.78, 0.25), "desc": "Touch a mini kaiju or boulder to grab it, swing to throw."},
	"foam": {"name": "FOAM CANNON", "color": Color(0.9, 0.95, 1.0), "desc": "Trigger sprays foam: puts out fires and makes kaiju slip."},
	"drill": {"name": "MEGA DRILL", "color": Color(1.0, 0.45, 0.3), "desc": "Double punch power, cracks shells and armour."},
}

# --- Support vehicles (TV players) --------------------------------------------------------------
const VEHICLES: Array[String] = ["jet", "truck", "drone", "tank"]
const VEHICLE_INFO := {
	"jet": {"name": "SKY JET", "color": Color(0.4, 0.75, 1.0), "icon": "arrow_up", "speed": 21.0, "fly": true, "alt": 17.0,
		"desc": "Fly fast, shoot mini kaiju, paint weak spots and keep the kaiju busy.",
		"a": "Shoot", "x": "Target laser", "b": "Afterburner"},
	"truck": {"name": "RESCUE TRUCK", "color": Color(1.0, 0.45, 0.35), "icon": "person", "speed": 15.0, "fly": false, "alt": 0.0,
		"desc": "Drive to citizens shouting HELP and take them to the green shelters. Hose out fires.",
		"a": "Water hose", "x": "Target laser", "b": "Honk!"},
	"drone": {"name": "REPAIR DRONE", "color": Color(0.45, 0.95, 0.55), "icon": "plus", "speed": 17.0, "fly": true, "alt": 9.0,
		"desc": "Fly to the Titan or a broken building and hold A to fix it with sparks.",
		"a": "Repair beam", "x": "Target laser", "b": "Boost"},
	"tank": {"name": "STUN TANK", "color": Color(0.75, 0.6, 1.0), "icon": "bolt", "speed": 11.0, "fly": false, "alt": 0.0,
		"desc": "Lob stun shells: they make kaiju dizzy (and knock moths out of the sky).",
		"a": "Stun shell", "x": "Target laser", "b": "Rocket hop"},
}

# --- Kaiju ----------------------------------------------------------------------------------------
## monster: core/creatures.gd kind; height: target metres; hp; speed m/s; fly: hover altitude (0 = walks);
## weak: [[name, Vector3 position as a fraction of the height (front = +Z), radius fraction, hp (0 = never breaks)]];
## attacks: ids handled by kaiju_ai.gd; home: how it leaves ("walk", "swim", "fly", "space").
const KAIJU := {
	"lizard": {"name": "SIZZLE", "title": "THE FIRE LIZARD", "monster": "dragon", "color": Color(1.0, 0.42, 0.25),
		"color2": Color(1.0, 0.85, 0.35), "eye": Color(0.15, 0.1, 0.1), "height": 10.0, "hp": 520.0, "speed": 3.2, "fly": 0.0,
		"weak": [["BELLY GEM", Vector3(0.0, 0.42, 0.34), 0.11, 0.0], ["TAIL TIP", Vector3(0.0, 0.3, -0.72), 0.1, 0.0]],
		"attacks": ["fire_breath", "tail_swipe", "stomp"], "home": "walk",
		"tip": "Weak spots: its glowing BELLY and TAIL. Watch for the fire breath!"},
	"lizard_queen": {"name": "BLAZE", "title": "QUEEN OF THE VOLCANO", "monster": "dragon", "color": Color(0.95, 0.25, 0.4),
		"color2": Color(1.0, 0.7, 0.2), "eye": Color(0.15, 0.1, 0.1), "height": 12.5, "hp": 900.0, "speed": 3.4, "fly": 0.0,
		"weak": [["BELLY GEM", Vector3(0.0, 0.42, 0.34), 0.1, 0.0], ["CROWN GEM", Vector3(0.0, 0.92, 0.25), 0.08, 0.0],
			["TAIL TIP", Vector3(0.0, 0.3, -0.72), 0.09, 0.0]],
		"attacks": ["fire_breath", "tail_swipe", "lava_bombs", "stomp"], "home": "swim",
		"tip": "Three weak spots! Foam out the fires she starts."},
	"jelly": {"name": "WOBBLES", "title": "THE JELLY BLOB", "monster": "slime", "color": Color(0.95, 0.45, 0.85),
		"color2": Color(1.0, 0.8, 0.95), "eye": Color(0.2, 0.05, 0.2), "height": 10.0, "hp": 300.0, "speed": 2.6, "fly": 0.0,
		"weak": [["JELLY CORE", Vector3(0.0, 0.45, 0.2), 0.14, 0.0]],
		"attacks": ["belly_flop", "goo_spit"], "home": "walk", "split": 2,
		"tip": "It SPLITS when you hit it hard! Paint the glowing core."},
	"crab": {"name": "PINCHY", "title": "THE ARMOURED CRAB", "monster": "crab", "color": Color(1.0, 0.38, 0.3),
		"color2": Color(1.0, 0.75, 0.55), "eye": Color(0.1, 0.1, 0.1), "height": 7.6, "hp": 560.0, "speed": 3.6, "fly": 0.0,
		"weak": [["SHELL GEM", Vector3(-0.42, 0.98, -0.12), 0.13, 70.0], ["SHELL GEM", Vector3(0.42, 0.98, -0.12), 0.13, 70.0],
			["SOFT BELLY", Vector3(0.0, 0.42, 0.42), 0.16, 0.0]],
		"attacks": ["pinch", "bubble_blast", "shell_guard"], "home": "swim", "shell": true,
		"tip": "Its shell is tough: break the two SHELL GEMS on top (jets and tanks can reach them)."},
	"eel": {"name": "ZAPPY", "title": "THE ELECTRIC EEL-DRAGON", "monster": "fish", "color": Color(0.35, 0.55, 1.0),
		"color2": Color(1.0, 0.95, 0.35), "eye": Color(0.05, 0.05, 0.15), "height": 7.0, "hp": 520.0, "speed": 4.2, "fly": 6.0,
		"weak": [["SPARK HORN", Vector3(0.0, 0.85, 0.55), 0.13, 0.0], ["TAIL FIN", Vector3(0.0, 0.5, -0.95), 0.15, 0.0]],
		"attacks": ["zap_bolt", "electric_ring", "drain"], "home": "swim",
		"tip": "It floats! Paint its SPARK HORN and TAIL FIN for the beam."},
	"moth": {"name": "DUSTY", "title": "THE GIANT MOTH", "monster": "bee", "color": Color(0.88, 0.82, 0.62),
		"color2": Color(0.62, 0.5, 0.9), "eye": Color(0.15, 0.1, 0.3), "height": 8.0, "hp": 480.0, "speed": 5.0, "fly": 11.0,
		"weak": [["ANTENNA", Vector3(-0.16, 1.0, 0.42), 0.1, 0.0], ["ANTENNA", Vector3(0.16, 1.0, 0.42), 0.1, 0.0],
			["FUZZY BELLY", Vector3(0.0, 0.32, 0.05), 0.15, 0.0]],
		"attacks": ["wing_gust", "sleepy_dust", "swoop"], "home": "fly",
		"tip": "Too high to punch: the STUN TANK knocks it down, then PUNCH!"},
	"mega": {"name": "GIGA GRUMBLE", "title": "THE MEGA KAIJU", "monster": "golem", "color": Color(0.55, 0.4, 0.85),
		"color2": Color(0.3, 0.95, 0.85), "eye": Color(1.0, 0.4, 0.3), "height": 15.0, "hp": 1500.0, "speed": 2.8, "fly": 0.0, "boss": true,
		"weak": [["LEFT CRYSTAL", Vector3(-0.42, 0.86, 0.0), 0.08, 160.0], ["RIGHT CRYSTAL", Vector3(0.42, 0.86, 0.0), 0.08, 160.0],
			["MEGA CORE", Vector3(0.0, 0.62, 0.2), 0.1, 0.0]],
		"attacks": ["ground_pound", "rock_throw", "eye_laser", "summon", "mega_roar"], "home": "space", "phases": 3,
		"tip": "Phase 1: break the shoulder CRYSTALS. Phase 2: watch the sky. Phase 3: hit the MEGA CORE!"},
}

## Mini kaiju: small, quick, bonk-able. They nibble buildings until bonked home.
const MINIS := {
	"slimelet": {"name": "BABY SLIME", "monster": "slime", "color": Color(0.5, 0.9, 0.5), "height": 2.4, "hp": 18.0, "speed": 4.0, "fly": 0.0},
	"crablet": {"name": "CRABLET", "monster": "crab", "color": Color(1.0, 0.55, 0.35), "height": 2.2, "hp": 26.0, "speed": 4.6, "fly": 0.0},
	"batlet": {"name": "ZAP BAT", "monster": "bat", "color": Color(0.5, 0.45, 0.95), "height": 2.6, "hp": 16.0, "speed": 6.5, "fly": 9.0},
	"froglet": {"name": "FIRE FROG", "monster": "frog", "color": Color(1.0, 0.5, 0.2), "height": 2.4, "hp": 20.0, "speed": 4.0, "fly": 0.0, "fire": true},
	"mothlet": {"name": "MOTHLET", "monster": "bee", "color": Color(0.85, 0.8, 0.6), "height": 2.6, "hp": 16.0, "speed": 6.0, "fly": 10.0},
	"jellylet": {"name": "JELLY BIT", "monster": "slime", "color": Color(0.95, 0.5, 0.85), "height": 2.6, "hp": 20.0, "speed": 3.6, "fly": 0.0},
}

# --- Places (city themes) -----------------------------------------------------------------------
## ground / road colours, building palette, which side has water, special landmark, props.
const PLACES := {
	"downtown": {"name": "DOWNTOWN", "ground": Color(0.42, 0.62, 0.36), "road": Color(0.3, 0.31, 0.35), "plaza": Color(0.78, 0.74, 0.66),
		"walls": [Color(0.95, 0.78, 0.55), Color(0.62, 0.78, 0.95), Color(0.95, 0.62, 0.6), Color(0.85, 0.85, 0.9), Color(0.7, 0.9, 0.75)],
		"roof": Color(0.45, 0.45, 0.52), "heights": Vector2(5.0, 16.0), "water": "", "trees": "tree", "density": 1.0, "cars": 26},
	"harbour": {"name": "HARBOUR", "ground": Color(0.62, 0.6, 0.52), "road": Color(0.36, 0.35, 0.37), "plaza": Color(0.7, 0.62, 0.5),
		"walls": [Color(0.75, 0.42, 0.32), Color(0.45, 0.62, 0.78), Color(0.9, 0.82, 0.62), Color(0.55, 0.7, 0.55)],
		"roof": Color(0.35, 0.38, 0.45), "heights": Vector2(4.0, 10.0), "water": "north", "trees": "palm", "density": 0.75, "cars": 18},
	"powerplant": {"name": "POWER PLANT", "ground": Color(0.4, 0.55, 0.38), "road": Color(0.28, 0.29, 0.33), "plaza": Color(0.6, 0.6, 0.62),
		"walls": [Color(0.75, 0.78, 0.82), Color(0.95, 0.85, 0.4), Color(0.55, 0.65, 0.75), Color(0.85, 0.6, 0.45)],
		"roof": Color(0.4, 0.42, 0.48), "heights": Vector2(4.0, 12.0), "water": "", "trees": "pine", "density": 0.8, "cars": 14},
	"snowy": {"name": "SNOWY PEAKS", "ground": Color(0.92, 0.94, 0.98), "road": Color(0.62, 0.64, 0.7), "plaza": Color(0.86, 0.88, 0.93),
		"walls": [Color(0.75, 0.45, 0.32), Color(0.9, 0.75, 0.55), Color(0.6, 0.4, 0.3), Color(0.85, 0.35, 0.35)],
		"roof": Color(0.95, 0.97, 1.0), "heights": Vector2(4.0, 9.0), "water": "", "trees": "pine", "density": 0.7, "cars": 10, "mountains": true},
	"volcano": {"name": "VOLCANO ISLAND", "ground": Color(0.72, 0.62, 0.42), "road": Color(0.35, 0.3, 0.3), "plaza": Color(0.85, 0.78, 0.6),
		"walls": [Color(0.95, 0.85, 0.6), Color(0.6, 0.85, 0.75), Color(0.95, 0.65, 0.5), Color(0.85, 0.9, 0.6)],
		"roof": Color(0.75, 0.5, 0.3), "heights": Vector2(3.5, 8.0), "water": "all", "trees": "palm", "density": 0.65, "cars": 8, "volcano": true},
	"moon": {"name": "MOON BASE", "ground": Color(0.62, 0.62, 0.68), "road": Color(0.42, 0.44, 0.5), "plaza": Color(0.72, 0.74, 0.8),
		"walls": [Color(0.9, 0.92, 0.96), Color(0.7, 0.85, 1.0), Color(0.95, 0.85, 0.5), Color(0.75, 0.75, 0.85)],
		"roof": Color(0.55, 0.6, 0.75), "heights": Vector2(4.0, 11.0), "water": "", "trees": "", "density": 0.75, "cars": 6, "domes": true},
}

# --- Missions -----------------------------------------------------------------------------------
## place, sky, music, protect ("" / "hospital" / "plant" / "dome"), rescue groups, steps (run in order by
## missions.gd): {"wave": [[mini, count], ...]} or {"boss": [kaiju, ...]} plus "say" (commander radio line),
## extra: periodic mini waves during boss steps. stars: [what the 2nd and 3rd star need].
const MISSIONS: Array[Dictionary] = [
	{"name": "DOWNTOWN DASH", "place": "downtown", "sky": "day", "seed": 11, "protect": "", "rescue": 4,
		"steps": [{"wave": [["slimelet", 5]], "say": "Baby slimes in the streets! Bonk them home, Titan!"},
			{"boss": ["lizard"], "say": "Here comes the big one: SIZZLE the Fire Lizard!", "extra": ["slimelet", 2, 35.0]}],
		"star2": ["damage", 40], "star3": ["rescue_all", 0],
		"brief": ["Good morning, Titan team! I'm Commander Sunny.", "A fire lizard is stomping towards Downtown. Nobody gets hurt, but it LOVES knocking over buildings.",
			"Jets: paint its glowing weak spots with your target laser. Titan: blast painted spots for TRIPLE damage!",
			"Rescue trucks: bring the citizens to the green shelters. Let's go!"]},
	{"name": "HARBOUR PINCH", "place": "harbour", "sky": "sunset", "seed": 23, "protect": "", "rescue": 5,
		"steps": [{"wave": [["crablet", 5]], "say": "Crablets on the docks! Pinch-proof punches, please!"},
			{"boss": ["crab"], "say": "PINCHY is climbing out of the sea!", "extra": ["crablet", 2, 30.0]}],
		"star2": ["damage", 35], "star3": ["no_reboot", 0],
		"brief": ["The harbour is full of very grumpy crabs this evening.", "Their big boss PINCHY has a super tough shell.",
			"Break the two SHELL GEMS on its back: the Stun Tank and the jets can reach them from above.", "Then the soft belly is open for business!"]},
	{"name": "POWER SURGE", "place": "powerplant", "sky": "night", "seed": 37, "protect": "plant", "rescue": 4,
		"steps": [{"wave": [["batlet", 6]], "say": "Zap bats! Jets, they're all yours!"},
			{"boss": ["eel"], "say": "ZAPPY the eel-dragon wants to drink our electricity!", "extra": ["batlet", 3, 30.0]}],
		"star2": ["damage", 40], "star3": ["protect", 60],
		"brief": ["It's night, and something sparkly is floating towards the power plant.", "Protect the POWER PLANT: if it runs out of power, the mission fails.",
			"The eel-dragon floats, so aim your beam up high. Watch out for lightning circles on the ground!"]},
	{"name": "JELLY JAM", "place": "downtown", "sky": "sunset", "seed": 41, "protect": "hospital", "rescue": 5,
		"steps": [{"wave": [["jellylet", 4]], "say": "Jelly bits! Sticky but harmless."},
			{"boss": ["jelly"], "say": "WOBBLES the Jelly Blob! Careful, it splits when it gets hit!", "extra": ["jellylet", 2, 40.0]}],
		"star2": ["damage", 35], "star3": ["rescue_all", 0],
		"brief": ["A giant wobbly jelly is bouncing through Downtown.", "Every big hit splits it into smaller jellies. Keep splitting until they're tiny!",
			"Protect the HOSPITAL with the red cross. Repair drones can fix it if it gets bumped."]},
	{"name": "FROSTY FLUTTER", "place": "snowy", "sky": "snowy", "seed": 53, "protect": "", "rescue": 6,
		"steps": [{"wave": [["mothlet", 5]], "say": "Little moths love our street lamps!"},
			{"boss": ["moth"], "say": "DUSTY the Giant Moth! It flies too high to punch...", "extra": ["mothlet", 2, 35.0]}],
		"star2": ["damage", 35], "star3": ["rescue_all", 0],
		"brief": ["Snowy Peaks ski village needs us! A giant moth thinks our lights are a party.", "It flies too high for punches. Stun Tank: hit it with stun shells and it falls down!",
			"Then Titan: PUNCH while it's dizzy on the ground. Rescue trucks: the skiers need a ride!"]},
	{"name": "STORMY DOUBLE", "place": "harbour", "sky": "stormy", "seed": 67, "protect": "", "rescue": 5,
		"steps": [{"wave": [["crablet", 4], ["batlet", 3]], "say": "Crablets AND zap bats. Stormy night!"},
			{"boss": ["crab", "eel"], "say": "TWO kaiju at once: PINCHY and ZAPPY are back!", "extra": ["crablet", 2, 40.0]}],
		"star2": ["damage", 30], "star3": ["time", 330],
		"brief": ["Thunder and lightning over the harbour. And TWO kaiju!", "Split up: jets keep ZAPPY busy in the sky while the Titan cracks PINCHY's shell.",
			"The rain helps put out fires today."]},
	{"name": "LAVA PARTY", "place": "volcano", "sky": "sunset", "seed": 79, "protect": "", "rescue": 5,
		"steps": [{"wave": [["froglet", 6]], "say": "Fire frogs hopping everywhere! Foam the fires!"},
			{"boss": ["lizard_queen"], "say": "BLAZE, Queen of the Volcano, has woken up!", "extra": ["froglet", 3, 30.0]}],
		"star2": ["damage", 40], "star3": ["no_reboot", 0],
		"brief": ["Volcano Island is having a lava party and nobody invited the fire frogs.", "BLAZE throws lava bombs that start fires.",
			"Titan: push the lever for the FOAM CANNON to put out fires. Trucks can hose them too!"]},
	{"name": "MIDNIGHT MOTHS", "place": "snowy", "sky": "night", "seed": 83, "protect": "", "rescue": 6,
		"steps": [{"wave": [["mothlet", 4], ["jellylet", 3]], "say": "Moths and jellies at midnight!"},
			{"boss": ["moth", "jelly"], "say": "DUSTY and WOBBLES teamed up!", "extra": ["mothlet", 2, 40.0]}],
		"star2": ["damage", 35], "star3": ["time", 360],
		"brief": ["Midnight in the mountains. Two old friends are back: DUSTY and WOBBLES.", "Tanks knock the moth down, everybody splits the jelly.",
			"Teamwork, Titans!"]},
	{"name": "MOON BASE MEGA", "place": "moon", "sky": "space", "seed": 97, "protect": "dome", "rescue": 5,
		"steps": [{"wave": [["batlet", 4], ["slimelet", 4]], "say": "Space minis! Clear the base!"},
			{"boss": ["mega"], "say": "GIGA GRUMBLE, the MEGA KAIJU! This is it, team!", "extra": ["slimelet", 2, 45.0]}],
		"star2": ["damage", 35], "star3": ["protect", 50],
		"brief": ["Team, we're on the MOON. The Mega Kaiju lives in a crater nearby and it is VERY grumpy.", "It has THREE phases. First break its shoulder CRYSTALS.",
			"Then it calls friends from the sky. Last, its MEGA CORE opens: paint it and blast it!", "Protect the MOON DOME. Finish with a giant punch!"]},
]

const STAR_TEXT := {"damage": "City damage under %d%%", "rescue_all": "Rescue every citizen", "no_reboot": "Titan never needs a reboot",
	"protect": "Keep the landmark above %d%%", "time": "Finish in under %s"}

# --- Upgrades (hangar shop, saved) ----------------------------------------------------------------
## kind: beam / armour / thrust / tool / support / paint. need: mission index that must be cleared first (-1 = none).
const UPGRADES := {
	"claw": {"name": "CLAW GRABBER", "desc": "New arm tool: grab mini kaiju and boulders, then THROW them.", "cost": 100, "kind": "tool", "need": 0},
	"foam": {"name": "FOAM CANNON", "desc": "New arm tool: spray foam on fires (and slippery kaiju).", "cost": 120, "kind": "tool", "need": 1},
	"drill": {"name": "MEGA DRILL", "desc": "New arm tool: double punch power, cracks shells and armour.", "cost": 180, "kind": "tool", "need": 2},
	"beam2": {"name": "BEAM POWER II", "desc": "Chest beam does 40% more damage.", "cost": 160, "kind": "beam", "need": -1},
	"beam3": {"name": "BEAM POWER III", "desc": "Chest beam does 80% more damage (needs BEAM II).", "cost": 320, "kind": "beam", "need": 2, "requires": "beam2"},
	"armour2": {"name": "THICK ARMOUR", "desc": "30% more armour.", "cost": 180, "kind": "armour", "need": -1},
	"armour3": {"name": "MEGA ARMOUR", "desc": "60% more armour (needs THICK ARMOUR).", "cost": 340, "kind": "armour", "need": 3, "requires": "armour2"},
	"thrusters": {"name": "TURBO THRUSTERS", "desc": "Rocket dash goes further and costs less energy.", "cost": 150, "kind": "thrust", "need": -1},
	"battery": {"name": "BIG BATTERY", "desc": "More energy for the beam and dashes.", "cost": 180, "kind": "energy", "need": 1},
	"support": {"name": "SUPPORT TEAM+", "desc": "Drones repair faster, stun shells stun longer, jets shoot faster.", "cost": 200, "kind": "support", "need": 1},
}
const UPGRADE_ORDER: Array[String] = ["claw", "beam2", "armour2", "thrusters", "foam", "battery", "support", "drill", "beam3", "armour3"]

## Paint jobs: main body, trim, glow. need_stars: total stars needed (0 = just parts).
const PAINTS := {
	"classic": {"name": "CLASSIC BLUE", "main": Color(0.3, 0.55, 0.95), "trim": Color(0.95, 0.95, 0.98), "glow": Color(0.4, 0.9, 1.0), "cost": 0, "stars": 0},
	"fire": {"name": "FIRE RED", "main": Color(0.9, 0.25, 0.22), "trim": Color(1.0, 0.85, 0.3), "glow": Color(1.0, 0.7, 0.3), "cost": 80, "stars": 0},
	"jungle": {"name": "JUNGLE GREEN", "main": Color(0.3, 0.65, 0.35), "trim": Color(0.95, 0.85, 0.55), "glow": Color(0.6, 1.0, 0.5), "cost": 80, "stars": 0},
	"candy": {"name": "CANDY PINK", "main": Color(0.98, 0.55, 0.78), "trim": Color(1.0, 1.0, 1.0), "glow": Color(1.0, 0.75, 0.95), "cost": 80, "stars": 0},
	"midnight": {"name": "MIDNIGHT", "main": Color(0.2, 0.2, 0.32), "trim": Color(0.65, 0.4, 1.0), "glow": Color(0.75, 0.5, 1.0), "cost": 120, "stars": 0},
	"gold": {"name": "GOLD STAR", "main": Color(1.0, 0.78, 0.25), "trim": Color(0.95, 0.95, 1.0), "glow": Color(1.0, 0.95, 0.6), "cost": 150, "stars": 12},
}
const PAINT_ORDER: Array[String] = ["classic", "fire", "jungle", "candy", "midnight", "gold"]

# --- Text ---------------------------------------------------------------------------------------
const COMMANDER := "COMMANDER SUNNY"
const COMMANDER_COLOR := Color(1.0, 0.82, 0.35)

const INTRO := {
	"title": "MECH TITANS",
	"goal": "Giant robot vs cute kaiju! Send every kaiju home dizzy and keep the city standing.",
	"vr": {"role": "PILOT OF TITAN-1", "color": "info", "controls": [["L-STICK", "Walk the Titan"], ["R-STICK", "Turn"],
		["PUNCH!", "Throw real punches"], ["HANDS UP", "Raise both hands to block"], ["TRIGGER", "Chest beam: point with your right hand"],
		["A", "Rocket dash"], ["LEVER", "Push the lever on your left: swap arm tools"]]},
	"tv": {"role": "SUPPORT TEAM", "color": "good", "controls": [["L-STICK", "Move"], ["R-STICK", "Look / aim"], ["A", "Vehicle action"],
		["X", "Target laser: paint weak spots"], ["B", "Boost"], ["Y", "Change vehicle"], ["START", "Pause"]],
		"tips": ["Painted weak spots take TRIPLE damage from the Titan's beam!"]},
}
const PILOT_TV_INTRO := {"role": "PILOT OF TITAN-1", "color": "info", "controls": [["L-STICK", "Walk"], ["R-STICK", "Look / aim"],
	["X", "Punch (use tool)"], ["RT", "Chest beam / foam"], ["LB", "Block"], ["A", "Rocket dash"], ["Y", "Swap arm tool"]],
	"tips": ["Punch a DIZZY kaiju to send it home!"]}


## The mission table entry (clamped index).
static func mission(i: int) -> Dictionary:
	return MISSIONS[clampi(i, 0, MISSIONS.size() - 1)]


## "4:05" style.
static func clock(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]


## Text for a star rule like ["damage", 40].
static func star_text(rule: Array) -> String:
	var kind: String = rule[0]
	var v: int = int(rule[1])
	var fmt: String = STAR_TEXT.get(kind, kind)
	if kind == "time":
		return fmt % clock(float(v))
	if fmt.contains("%d"):
		return fmt % v
	return fmt
