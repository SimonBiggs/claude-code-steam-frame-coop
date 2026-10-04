extends RefCounted
## QUIZ SHOW scoring rules (pure functions, host only). Kid-friendly: wrong answers never cost points,
## except a bet in the final, and nobody's score goes below zero.
## - WARM-UP: 100 for a right answer + up to 100 for speed.
## - BUZZER: 200 to whoever buzzes in and gets it right.
## - PICTURE: 300 while the tiles are all up, sliding to 100 when the picture is almost uncovered.
## - LIGHTNING: 50 a statement, x2 after 2 right in a row, x3 after 4 in a row.
## - CATEGORY BOARD: the cell's value (100 / 200 / 300), doubled on the GOLDEN question.
## - FINAL: win or lose your bet (a quarter, half or all of max(score, 200)).
## - COMEBACK: anyone with less than half the leader's points (once the leader has 400) gets x1.5.

const WAGER_FRACS: Array[float] = [0.0, 0.25, 0.5, 1.0]
const WAGER_NAMES: Array[String] = ["NOTHING", "A QUARTER", "HALF", "ALL IN!"]
const BOARD_VALUES: Array[int] = [100, 200, 300]
## Lowest amount the final bet is based on, so players with few points can still win big.
const WAGER_FLOOR := 200


static func round10(v: float) -> int:
	return int(round(v / 10.0)) * 10


static func warmup(time_left_frac: float) -> int:
	return 100 + round10(100.0 * clampf(time_left_frac, 0.0, 1.0))


static func buzzer() -> int:
	return 200


static func picture(reveal_frac: float) -> int:
	return round10(lerpf(300.0, 100.0, clampf(reveal_frac, 0.0, 1.0)))


## Streak multiplier for a lightning answer, given how many were right in a row before it.
static func streak_mult(streak_before: int) -> int:
	if streak_before >= 4:
		return 3
	if streak_before >= 2:
		return 2
	return 1


static func lightning(streak_before: int) -> int:
	return 50 * streak_mult(streak_before)


static func board(value: int, golden: bool) -> int:
	return value * (2 if golden else 1)


## x1.5 for players well behind the leader.
static func comeback(score: int, leader_score: int) -> float:
	if leader_score >= 400 and float(score) < float(leader_score) * 0.5:
		return 1.5
	return 1.0


## The bet for a wager choice (0..3).
static func wager(score: int, choice: int) -> int:
	var frac: float = WAGER_FRACS[clampi(choice, 0, 3)]
	return round10(float(maxi(score, WAGER_FLOOR)) * frac)


## Which question tier a board value asks, for the show's age setting (1 KIDS, 2 FAMILY, 3 BRAINIACS).
static func board_tier(value_index: int, age: int) -> int:
	var table := {1: [1, 1, 2], 2: [1, 2, 3], 3: [2, 3, 3]}
	var row: Array = table.get(clampi(age, 1, 3), [1, 2, 3])
	return int(row[clampi(value_index, 0, 2)])


## Seconds a player's buzzer stays asleep after the question appears: harder levels wait a moment so
## little ones get a fair chance. Relative to the easiest level playing.
static func buzz_delay(level: int, lowest_level: int) -> float:
	return 0.9 * float(maxi(0, level - lowest_level))


## Win (+bet) or lose (-bet) in the final, never below zero.
static func apply_wager(score: int, bet: int, right: bool) -> int:
	return score + bet if right else maxi(0, score - bet)
