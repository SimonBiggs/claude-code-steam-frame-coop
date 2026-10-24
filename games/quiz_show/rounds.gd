extends RefCounted
## The rounds of a QUIZ SHOW: titles, colours, how many questions, and the timings. Kept simple
## (docs/GAME_DEV_GUIDE.md "Keep it simple"): everyone answers every question with the four coloured
## buttons, every round. Only the kind of question changes.
## LEVEL vote (teaches the buttons) -> WARM-UP -> PICTURE PUZZLE -> TRUE OR FALSE -> BIG FINAL.

const ORDER: Array[String] = ["warmup", "picture", "lightning", "final"]

const INFO := {
	"level": {"title": "QUIZ SHOW!", "sub": "Pick a level!", "icon": "question", "color": Color(1.0, 0.8, 0.3)},
	"warmup": {"title": "WARM-UP", "sub": "Quick answers get bonus points!", "icon": "bolt", "color": Color(0.45, 0.8, 1.0)},
	"picture": {"title": "PICTURE PUZZLE", "sub": "Who is hiding? Answer early!", "icon": "eye", "color": Color(0.5, 0.9, 1.0)},
	"lightning": {"title": "TRUE OR FALSE", "sub": "Green is TRUE, red is FALSE!", "icon": "bolt", "color": Color(1.0, 0.85, 0.3)},
	"final": {"title": "THE BIG FINAL", "sub": "Double points!", "icon": "crown", "color": Color(1.0, 0.6, 0.85)},
}

## Questions per round. "short" is the bots' express show.
const COUNTS := {
	"show": {"warmup": 5, "picture": 3, "lightning": 6, "final": 1},
	"short": {"warmup": 2, "picture": 1, "lightning": 2, "final": 1},
}

## Seconds to answer, by question tier (little kids read slower), and for the other steps.
const ANSWER_TIME := {1: 20.0, 2: 16.0, 3: 14.0}
const TF_TIME := {1: 9.0, 2: 8.0, 3: 7.0}
const PIC_TIME := 18.0
const LEVEL_TIME := 12.0
const ROUND_INTRO := 3.2
const REVEAL := 3.4
const ALL_IN_LOCK := 0.7  ## everyone answered: lock this long after the last answer
const RESULTS_AUTO := 40.0  ## nobody pressed continue: start a new show

## The level vote: four choices on the four buttons.
const LEVELS: Array[String] = ["KIDS", "FAMILY", "BRAINIACS", "SURPRISE ME"]

## Answer buttons: A B X Y everywhere (pads, the VR desk, the big screen), always these colours.
const LETTERS: Array[String] = ["A", "B", "X", "Y"]
const LETTER_COLORS: Array[Color] = [Color(0.36, 0.78, 0.33), Color(0.92, 0.32, 0.3), Color(0.3, 0.55, 0.95), Color(0.95, 0.78, 0.2)]
const COLOR_NAMES: Array[String] = ["GREEN", "RED", "BLUE", "YELLOW"]


static func count(length: String, kind: String) -> int:
	var c: Dictionary = COUNTS.get(length, COUNTS["show"])
	return int(c.get(kind, 1))


## Question tier for the n-th question at a level choice (0 KIDS, 1 FAMILY, 2 BRAINIACS, 3 mixed).
## The final is one step harder (but never above BRAINIACS).
static func tier_for(level: int, n: int, kind: String) -> int:
	var t := level + 1 if level < 3 else (n % 3) + 1
	if kind == "final":
		t = mini(t + 1, 3) if level < 3 else 2
	return t


static func answer_time(kind: String, tier: int) -> float:
	match kind:
		"lightning":
			return float(TF_TIME.get(tier, 8.0))
		"picture":
			return PIC_TIME
		"level":
			return LEVEL_TIME
	return float(ANSWER_TIME.get(tier, 16.0))
