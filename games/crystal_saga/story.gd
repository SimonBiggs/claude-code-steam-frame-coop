extends RefCounted
## CRYSTAL SAGA story: every conversation as plain core/dialogue.gd line dictionaries (strings only,
## so the host can send them to the TV machine through the state store), the current goals for the
## objective tracker, and the credits. Lines raise "event"s that main.gd turns into game effects
## (quest_given, shop_pip, inn, tobi_reward...). Story flags live in the replicated "flags" store key.
## Tone: kind, funny, encouraging. Nobody dies: monsters "poof" into sparkles, heroes get "KO'd".

const C_HERO := "accent"
const NARRATOR := {"speaker": "", "color": "dim", "portrait": "star"}


static func _l(speaker: String, color: Variant, text: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"speaker": speaker, "color": color, "text": text}
	d.merge(extra, true)
	return d


static func _n(text: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"speaker": "", "color": "dim", "portrait": "star", "text": text}
	d.merge(extra, true)
	return d


static func has(f: Dictionary, flag: String) -> bool:
	return bool(f.get(flag, false))


## What NPC `id` says, given the story flags. ctx: {hero: name, chooser: slot answering choices}.
static func npc_lines(id: String, f: Dictionary, ctx: Dictionary) -> Array:
	var chooser := int(ctx.get("chooser", 0))
	match id:
		"elder":
			if not has(f, "quest"):
				return [
					_l("ELDER OAK", "good", "Ah, you're awake! And you brought friends. Good, good."),
					_l("ELDER OAK", "good", "Last night the Shadow King shattered our Crystal of Light. The shards flew far away."),
					_l("ELDER OAK", "good", "One to the CRYSTAL CAVERNS, one to the SKY BRIDGE... and one to his own SHADOW CASTLE."),
					_l("ELDER OAK", "good", "Each shard holds a giant guardian spirit. Free them, and they will fight beside you!"),
					_l("ELDER OAK", "good", "Will you bring the light back to Willowbrook?", {"slot": chooser, "choices": [
						{"text": "Yes! Let's go!", "id": "yes"}, {"text": "We're a bit scared...", "id": "scared", "goto": "scared"}]}),
					_l("ELDER OAK", "good", "Wonderful! I knew it.", {"goto": "gift"}),
					_l("ELDER OAK", "good", "Being a little scared is fine. Brave people feel scared too, and go anyway!", {"label": "scared"}),
					_l("ELDER OAK", "good", "Take these Potions and some gil. Pip's shop has better swords!", {"label": "gift", "event": "quest_given"}),
					_l("ELDER OAK", "good", "Captain Rook will open the North Gate for you. Be brave, and be kind!"),
				]
			if not has(f, "wyrm_done"):
				return [_l("ELDER OAK", "good", "The Whispering Forest is north, and the Crystal Caverns lie beyond it."),
					_l("ELDER OAK", "good", "Remember: monsters glow white when they're WEAK to something. Try different spells!")]
			if not has(f, "roc_done"):
				return [_l("ELDER OAK", "good", "Titan is with you! When the CRYSTAL gauge is full, call him!"),
					_l("ELDER OAK", "good", "The Sky Bridge is past the caverns. Hold on tight when the wind blows!")]
			return [_l("ELDER OAK", "good", "The Phoenix flies again! Only the Shadow Castle remains. We believe in you!")]
		"pip":
			return [_l("PIP", "info", "Hiya! Welcome to Pip's Pots and Pointy Things!"),
				_l("PIP", "info", "Potions, swords, rods, bows... want to have a look?", {"slot": chooser, "choices": [
					{"text": "Let's shop!", "id": "shop", "event": "shop_pip"}, {"text": "Maybe later", "id": "no"}]})]
		"rosa":
			return [_l("ROSA", "bad", "Welcome to the Sleepy Sheep Inn! A cosy bed for the whole party is 10 gil."),
				_l("ROSA", "bad", "Would you like to rest?", {"slot": chooser, "choices": [
					{"text": "Yes, please (10 gil)", "id": "rest", "event": "inn"}, {"text": "No thanks", "id": "no"}]})]
		"lina":
			if has(f, "tobi_saved") and not has(f, "tobi_thanked"):
				return [_l("LINA", "magic", "You found my Tobi! Thank you, thank you, THANK you!"),
					_l("LINA", "magic", "Please take these. A hero needs snacks... I mean, potions!", {"event": "lina_reward"})]
			if has(f, "tobi_saved"):
				return [_l("LINA", "magic", "Tobi hasn't stopped talking about you. He wants a sword now. Oh dear.")]
			if has(f, "quest"):
				return [_l("LINA", "magic", "Hero! My little Tobi ran into the Whispering Forest to look for a crystal shard!"),
					_l("LINA", "magic", "He went WEST off the path. Please bring him home safe!", {"event": "tobi_quest"})]
			return [_l("LINA", "magic", "Have you seen my Tobi? He was so excited about the shooting stars last night...")]
		"rook":
			if not has(f, "quest"):
				return [_l("CAPTAIN ROOK", "info", "Halt! The North Gate stays shut until Elder Oak says so. Orders!")]
			return [_l("CAPTAIN ROOK", "info", "The Elder told me everything. Good luck out there, and stay together!")]
		"hal":
			return [_l("FARMER HAL", "good", "Baa! Oh, sorry. I talk to my sheep too much."),
				_l("FARMER HAL", "good", "Tip from an old farmer: slimes and mushrooms HATE fire. Toasty!")]
		"pell":
			return [_l("PELL", "accent", "When I grow up I'm gonna be a hero just like you! Swish! Swoosh!"),
				_l("PELL", "accent", "Heroes BLOCK too! When a monster gets ready to hit you, hold up your shield!")]
		"dot":
			return [_l("DOT", "accent", "Psst! Secret tip!"),
				_l("DOT", "accent", "Point your sword at a monster. When the ring turns GOLD, swing for a super hit!")]
		"tobi":
			return [_l("TOBI", "accent", "That King Slime was SO big! And you were SO cool!"),
				_l("TOBI", "accent", "Mom says I can't go on adventures until I'm nine. That's FOREVER.")]
		"tobi_lost":
			return [_l("TOBI", "accent", "Help! These slimes won't let me go home!")]
		"hopper":
			return [_l("HOPPER", "gold", "Hop hop! Hopper's Sky Shop, highest shop in the world!"),
				_l("HOPPER", "gold", "Mythril swords, magic rods, fancy harps... want a look?", {"slot": chooser, "choices": [
					{"text": "Let's shop!", "id": "shop", "event": "shop_hopper"}, {"text": "Maybe later", "id": "no"}]})]
	return [_l("VILLAGER", "text", "What a lovely day! Well... apart from the shadows.")]


static func sign_lines(title: String, text: String) -> Array:
	return [_l(title, "accent", text, {"portrait": "flag"})]


## The opening cutscene's words (events drive the visuals in cutscenes.gd).
static func opening_lines() -> Array:
	return [
		_n("Long ago, the Crystal of Light kept the little village of Willowbrook safe and sunny.", {"auto": 3.2}),
		_n("But one night, a cold shadow crept over the rooftops...", {"auto": 2.6, "event": "shadow_comes"}),
		_l("SHADOW KING", "magic", "Ha ha HA! The Crystal of Light is MINE!", {"portrait": "skull", "auto": 2.4}),
		_n("CRASH!", {"event": "shatter", "auto": 1.8}),
		_l("ELDER OAK", "good", "Oh no! The Crystal has shattered! Its shards are flying everywhere!", {"auto": 3.0}),
		_l("ELDER OAK", "good", "Hero! Only you and your friends can bring them back. Come and find me at the shrine!", {"auto": 3.4}),
		_n("The next morning...", {"event": "morning", "auto": 2.0}),
	]


static func tobi_after() -> Array:
	return [_l("TOBI", "accent", "Wow! You beat the King Slime! You're a REAL hero!"),
		_l("TOBI", "accent", "I found this shiny thing. You can have it!", {"event": "tobi_reward"}),
		_l("TOBI", "accent", "I'm going home to Mom now. Bye-bye!", {"event": "tobi_home"})]


static func wyrm_intro() -> Array:
	return [_l("CRYSTAL WYRM", "info", "Grrrr... who woke me from my shiny, sparkly nap?!", {"portrait": "gem"}),
		_l("CRYSTAL WYRM", "info", "The glittery shard is MINE. Go away or I'll... I'll be very grumpy!", {"portrait": "gem"})]


static func roc_intro() -> Array:
	return [_l("THUNDER ROC", "accent", "SKREEEE! Nobody crosses MY bridge without a fight!", {"portrait": "bolt"})]


static func king_intro(chooser: int) -> Array:
	return [_l("SHADOW KING", "magic", "So, the little hero and friends came all this way. How adorable.", {"portrait": "skull"}),
		_l("SHADOW KING", "magic", "The last shard is MINE. Soon my shadows will cover the whole world!", {"portrait": "skull"}),
		_l("SHADOW KING", "magic", "Any last words, hero?", {"portrait": "skull", "slot": chooser, "choices": [
			{"text": "Give back the Crystal!", "id": "give"}, {"text": "We're not scared of you!", "id": "brave"}]}),
		_l("SHADOW KING", "magic", "Then face the darkness!", {"portrait": "skull"})]


static func king_phase2() -> Array:
	return [_l("SHADOW KING", "magic", "Enough! Behold my TRUE form!", {"portrait": "skull", "auto": 2.2})]


static func shard_lines(summon: String) -> Array:
	match summon:
		"titan":
			return [_l("TITAN", "gold", "Little hero... you freed me from the dark crystal. My strength is yours!", {"portrait": "shield"}),
				_n("TITAN joined! Fill the CRYSTAL gauge in battle, then raise BOTH hands to call a guardian!")]
		"phoenix":
			return [_l("PHOENIX", "warn", "Thank you, brave ones! My fire burns shadows and warms friends.", {"portrait": "fire"}),
				_n("PHOENIX joined! She burns monsters AND heals the whole party.")]
		"leviathan":
			return [_l("LEVIATHAN", "info", "The waters remember you, hero. Call, and the tide will answer!", {"portrait": "drop"}),
				_n("LEVIATHAN joined! A giant wave washes the monsters away.")]
	return []


static func ending_lines() -> Array:
	return [
		_n("The four shards flew home, and the Crystal of Light shone brighter than ever.", {"auto": 3.4}),
		_l("ELDER OAK", "good", "You did it! Willowbrook is safe, and the sun is shining again!", {"auto": 3.0}),
		_l("SHADOW KING", "magic", "Um... hello. I'm sorry I was so grumpy. It was very dark in that castle.", {"portrait": "skull", "auto": 3.4}),
		_l("ELDER OAK", "good", "Then stay here with us! Everyone deserves a little light.", {"auto": 3.0}),
		_n("And so the Shadow King moved to Willowbrook and opened a bakery. His shadow cookies are delicious.", {"auto": 4.0}),
		_n("THE END. Thank you for playing, heroes!", {"auto": 3.0}),
	]


## Defeat: the Crystal carries everyone back to the last save crystal (no game over).
static func wipe_lines() -> Array:
	return [_n("Everyone is KO'd... but the Crystal's light carries you back to safety!", {"auto": 3.0}),
		_n("Heal up, try another plan, and give it another go. You've got this!", {"auto": 3.0})]


## The goals shown in the objective tracker.
static func objectives(f: Dictionary, area: String) -> Array:
	var out: Array = []
	if not has(f, "quest"):
		out.append("Talk to Elder Oak at the shrine")
		return out
	if has(f, "tobi_quest") and not has(f, "tobi_saved"):
		out.append("Side quest: find Tobi in the forest")
	if has(f, "tobi_saved") and not has(f, "tobi_thanked"):
		out.append("Side quest: tell Lina that Tobi is safe")
	if not has(f, "titan"):
		match area:
			"village":
				out.append("Head north to the Whispering Forest")
			"forest":
				out.append("Find the Crystal Caverns in the north")
			"caverns":
				if not has(f, "seal_open"):
					out.append("Light the crystals in the mural's order")
				elif not has(f, "wyrm_done"):
					out.append("Find the Earth Shard in the deep cave")
				else:
					out.append("Touch the Earth Shard")
			_:
				out.append("Find the Earth Shard")
	elif not has(f, "phoenix"):
		if area == "skybridge":
			out.append("Cross the bridge (wait out the wind!)" if not has(f, "roc_done") else "Touch the Wind Shard")
		else:
			out.append("Go north to the Sky Bridge")
	elif not has(f, "king_done"):
		if area == "castle":
			if not has(f, "leviathan"):
				out.append("Find the Water Shard in the courtyard")
			out.append("Defeat the Shadow King")
		else:
			out.append("Storm the Shadow Castle")
	else:
		out.append("Celebrate!")
	return out


## The credits roll (TV) / cards (VR). party: [[name, class title], ...].
static func credits(party: Array) -> Array:
	var out: Array = ["CRYSTAL SAGA", "", "STARRING"]
	for p in party:
		var e: Array = p
		out.append("%s  -  %s" % [String(e[0]), String(e[1])])
	out.append_array(["", "GUARDIANS", "Titan  -  Phoenix  -  Leviathan", "", "SPECIAL GUEST", "The Shadow King (now a baker)", "",
		"VILLAGERS", "Elder Oak, Pip, Rosa, Lina, Tobi, Captain Rook, Farmer Hal, Pell, Dot, Hopper", "",
		"MONSTERS", "Every slime, bat and bonehead who poofed into sparkles", "", "MADE WITH", "Godot Engine and a lot of love", "",
		"THANK YOU FOR PLAYING!"])
	return out
