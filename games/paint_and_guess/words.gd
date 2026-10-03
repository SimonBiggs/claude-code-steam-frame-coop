extends RefCounted
## Kid-friendly things to draw, in themed packs. Short, concrete and easy to recognise from a doodle.
## Every round picks a new theme (shown to everyone, which helps the guessers); decoy answers come
## partly from the same theme, more of them as the game goes on (the difficulty arc).

const PACKS: Array = [
	["ANIMALS", ["cat", "dog", "pig", "cow", "horse", "frog", "duck", "rabbit", "snake", "mouse", "lion",
		"elephant", "giraffe", "penguin", "owl", "bird", "spider", "bee", "butterfly", "turtle", "monkey", "bear"]],
	["YUMMY FOOD", ["pizza", "cake", "ice cream", "cookie", "carrot", "egg", "banana", "apple", "donut", "burger",
		"cupcake", "lollipop", "cheese", "sandwich", "watermelon", "cherry", "hot dog", "popcorn", "pear", "grapes"]],
	["THINGS THAT GO", ["car", "bus", "train", "plane", "boat", "rocket", "bike", "tractor", "helicopter",
		"submarine", "fire truck", "skateboard", "hot air balloon", "scooter", "ship", "race car"]],
	["MAGIC AND MONSTERS", ["dragon", "ghost", "unicorn", "monster", "alien", "wizard", "witch", "castle", "crown",
		"magic wand", "robot", "pirate", "mermaid", "fairy", "treasure", "sword", "shield", "dinosaur"]],
	["AT HOME", ["house", "door", "chair", "bed", "lamp", "clock", "phone", "book", "cup", "spoon", "teddy bear",
		"candle", "key", "umbrella", "sock", "shoe", "hat", "glasses", "toothbrush", "bath", "window", "television"]],
	["OUTDOORS", ["sun", "tree", "flower", "rainbow", "mountain", "volcano", "island", "cloud", "lightning",
		"snowman", "snowflake", "fire", "tent", "bridge", "mushroom", "cactus", "pumpkin", "kite", "worm", "leaf"]],
	["SPACE AND SKY", ["moon", "star", "rocket", "planet", "alien", "astronaut", "comet", "sun", "cloud",
		"rainbow", "bird", "plane", "kite", "balloon", "satellite", "ufo"]],
	["PARTY AND PLAY", ["balloon", "present", "ball", "drum", "guitar", "kite", "yo-yo", "cake", "candle",
		"crown", "puppet", "slide", "swing", "teddy bear", "robot", "trumpet", "piano", "paint brush"]],
	["UNDER THE SEA", ["fish", "whale", "shark", "octopus", "crab", "starfish", "jellyfish", "seahorse", "shell",
		"submarine", "boat", "mermaid", "treasure", "turtle", "anchor", "dolphin"]],
]


static func pack_count() -> int:
	return PACKS.size()


static func pack_name(i: int) -> String:
	var p: Array = PACKS[posmod(i, PACKS.size())]
	return str(p[0])


static func pack_words(i: int) -> Array:
	var p: Array = PACKS[posmod(i, PACKS.size())]
	var w: Array = p[1]
	return w


## Every word of every pack (no duplicates), for the off-theme decoys.
static func all_words() -> Array:
	var out: Array = []
	for p in PACKS:
		var a: Array = p
		for w in a[1]:
			if not out.has(w):
				out.append(w)
	return out
