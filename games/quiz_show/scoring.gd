extends RefCounted
## QUIZ SHOW scoring (pure functions, host only). Kid-friendly: a wrong answer never costs points.
## - WARM-UP: 100 for a right answer + up to 50 for speed.
## - PICTURE: 300 while the tiles are all up, sliding to 100 as they drop away.
## - TRUE OR FALSE: 50 a statement, x2 after 2 right in a row, x3 after 4 in a row.
## - FINAL: double a warm-up answer (200 + up to 100 for speed).


static func round10(v: float) -> int:
	return int(round(v / 10.0)) * 10


## Points for a right answer. time_frac: share of the answer time still left when they answered;
## reveal_frac: picture round, share of tiles already gone; streak: right answers in a row before it.
static func points(kind: String, time_frac: float, reveal_frac: float, streak: int) -> int:
	match kind:
		"picture":
			return round10(lerpf(300.0, 100.0, clampf(reveal_frac, 0.0, 1.0)))
		"lightning":
			return 50 * streak_mult(streak)
		"final":
			return 2 * (100 + round10(50.0 * clampf(time_frac, 0.0, 1.0)))
		"level":
			return 0
	return 100 + round10(50.0 * clampf(time_frac, 0.0, 1.0))


## Streak multiplier for a true/false answer, given how many were right in a row before it.
static func streak_mult(streak_before: int) -> int:
	if streak_before >= 4:
		return 3
	if streak_before >= 2:
		return 2
	return 1
