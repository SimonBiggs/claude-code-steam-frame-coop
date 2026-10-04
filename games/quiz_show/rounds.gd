extends RefCounted
## The six rounds of a QUIZ SHOW: titles, colours, how-to cards (core/hints.gd intro data), how many
## questions each round asks for each show length, and the show's timings.
## Show lengths: "quick" (~8 min), "full" (~15 min); "short" is the bots' QS_SHORT=1 express show.

const ORDER: Array[String] = ["warmup", "buzzer", "picture", "lightning", "category", "final"]

const INFO := {
	"warmup": {"title": "WARM-UP", "sub": "Everyone answers - quick is best!", "icon": "bolt", "color": Color(0.45, 0.8, 1.0)},
	"buzzer": {"title": "BUZZER BATTLE", "sub": "Buzz in first, then answer!", "icon": "exclaim", "color": Color(1.0, 0.4, 0.4)},
	"picture": {"title": "PICTURE PUZZLE", "sub": "What is hiding behind the tiles?", "icon": "eye", "color": Color(0.5, 0.9, 1.0)},
	"lightning": {"title": "LIGHTNING ROUND", "sub": "True or false? Super fast!", "icon": "bolt", "color": Color(1.0, 0.85, 0.3)},
	"category": {"title": "CATEGORY BOARD", "sub": "Pick a category, pick the points!", "icon": "star", "color": Color(0.72, 0.52, 1.0)},
	"final": {"title": "THE BIG FINAL", "sub": "Bet your points on one last question!", "icon": "crown", "color": Color(1.0, 0.82, 0.3)},
}

## Questions per round (category: picks from the board; final: always one question).
const COUNTS := {
	"short": {"warmup": 2, "buzzer": 2, "picture": 1, "lightning": 2, "category": 1, "final": 1},
	"quick": {"warmup": 4, "buzzer": 4, "picture": 2, "lightning": 6, "category": 3, "final": 1},
	"full": {"warmup": 7, "buzzer": 7, "picture": 4, "lightning": 10, "category": 6, "final": 1},
}

## Seconds. Answer times depend on the question tier (little kids read slower).
const TIMES := {
	"title": 5.0, "show_intro": 4.5, "round_intro": 3.4, "howto": 11.0, "ask_min": 1.8, "ask_per_char": 0.045,
	"ask_max": 4.2, "lock": 0.9, "reveal": 3.2, "round_end": 5.0, "buzz_open": 14.0, "buzz_answer": 7.0,
	"buzz_window": 0.15, "pic_answer": 18.0, "tf_reveal": 1.7, "pick": 14.0, "final_cat": 4.5, "wager": 15.0,
	"final_step": 2.4, "winner": 7.5, "results": 75.0,
}
const ANSWER_TIME := {1: 20.0, 2: 15.0, 3: 12.0}
const TF_TIME := {1: 8.0, 2: 6.5, 3: 5.5}
const FINAL_TIME := {1: 25.0, 2: 20.0, 3: 18.0}

## Level names (players' own difficulty) and the show's age setting.
const LEVEL_NAMES := {1: "KIDS", 2: "FAMILY", 3: "BRAINIAC"}
const AGE_NAMES := {1: "KIDS (5-8)", 2: "FAMILY", 3: "BRAINIACS"}
const LENGTH_NAMES := {"quick": "QUICK (8 MIN)", "full": "FULL (15 MIN)"}

## Answer buttons: A B X Y everywhere (TV pads, the VR desk, the video wall), always these colours.
const LETTERS: Array[String] = ["A", "B", "X", "Y"]
const LETTER_COLORS: Array[Color] = [Color(0.36, 0.78, 0.33), Color(0.92, 0.32, 0.3), Color(0.3, 0.55, 0.95), Color(0.95, 0.78, 0.2)]


## Which rounds the show plays (the final is always last).
static func order() -> Array[String]:
	return ORDER.duplicate()


static func count(length: String, kind: String) -> int:
	var c: Dictionary = COUNTS.get(length, COUNTS["full"])
	return int(c.get(kind, 1))


## The how-to card for a round: core/hints.gd intro data (VR role card and TV card).
static func howto(kind: String) -> Dictionary:
	var info: Dictionary = INFO.get(kind, INFO["warmup"])
	var d := {"title": "ROUND: " + String(info["title"])}
	match kind:
		"warmup":
			d["goal"] = "Everyone answers every question. Answer fast for BONUS points!"
			d["vr"] = {"role": "YOUR DESK", "controls": [["SLAP", "a coloured button"], ["OR POINT", "at the big screen + TRIGGER"]]}
			d["tv"] = {"role": "ANSWER BUTTONS", "controls": [["A", "green"], ["B", "red"], ["X", "blue"], ["Y", "yellow"]],
				"tips": ["Little quizzers get easier questions on their own screen!"]}
		"buzzer":
			d["goal"] = "Buzz in first, then answer. Wrong? Your buzzer sleeps until the next question."
			d["vr"] = {"role": "BUZZER BATTLE", "controls": [["SLAP", "the big red BUZZER (or TRIGGER)"], ["THEN SLAP", "your answer"]]}
			d["tv"] = {"role": "BUZZER BATTLE", "controls": [["A", "Buzz in!"], ["A B X Y", "Then pick your answer"]],
				"tips": ["Brainiacs' buzzers wake up a moment later, so everyone gets a chance."]}
		"picture":
			d["goal"] = "Something is hiding behind the tiles on the big screen. Answer early for MORE points!"
			d["vr"] = {"role": "PICTURE PUZZLE", "controls": [["SLAP", "a coloured button"], ["LOOK", "at the big screen"]]}
			d["tv"] = {"role": "PICTURE PUZZLE", "controls": [["A B X Y", "Answer"]], "tips": ["The tiles drop away one by one."]}
		"lightning":
			d["goal"] = "TRUE or FALSE - quick as lightning! Get them right in a row for a STREAK bonus."
			d["vr"] = {"role": "LIGHTNING", "controls": [["GREEN", "TRUE"], ["RED", "FALSE"]]}
			d["tv"] = {"role": "LIGHTNING", "controls": [["A", "TRUE"], ["B", "FALSE"]], "tips": ["3 in a row: double points!"]}
		"category":
			d["goal"] = "Take turns picking a category and how many points. Everyone answers! Find the GOLDEN question for double points."
			d["vr"] = {"role": "CATEGORY BOARD", "controls": [["SLAP", "a colour to pick a category"], ["THEN", "pick the points"]]}
			d["tv"] = {"role": "CATEGORY BOARD", "controls": [["A B X Y", "Pick a category"], ["A B X", "Pick 100, 200 or 300"]]}
		"final":
			d["goal"] = "Bet some of your points, then answer the last question. Right: win your bet! Wrong: lose it."
			d["vr"] = {"role": "THE BIG FINAL", "controls": [["GREEN", "bet nothing"], ["RED", "a quarter"], ["BLUE", "half"], ["YELLOW", "ALL IN!"]]}
			d["tv"] = {"role": "THE BIG FINAL", "controls": [["A", "bet nothing"], ["B", "a quarter"], ["X", "half"], ["Y", "ALL IN!"]]}
	d["tv"]["color"] = info["color"]
	return d
