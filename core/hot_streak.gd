extends RefCounted
## HOT STREAK: difficulty that ramps with the family, shared by every game that wants it (Marble Maze, Sky Bots).
## 2026-11-25 measured: the family's real runs of the two most-picked arcade games were nearly all clean (Marble Maze
## 9 mazes, 0 falls; Sky Bots 5 of 7 islands, 0 falls, 17-48 s), so they ramp now: every EVERY-th clean round in a row
## (nobody fell) heats the next rounds up one step (the game's generator turns heat into more holes / wider gaps /
## faster foes, and its validator proves every heat fair); a round with lots of falls cools a step. Heat is saved per
## game and capped per mode (CAPS); a new sitting starts one step cooler (session_start). Pure functions.
##   const HotStreak := preload("res://core/hot_streak.gd")
##   var r := HotStreak.step(heat, streak, falls, players, mode)   # [heat, streak, change -1 / 0 / +1]

const CAPS := {"gentle": 1, "brave": 2, "hard": 3}
const EVERY := 2  # clean rounds in a row per step up


## The highest heat a mode allows (an unknown mode: brave's).
static func cap(mode: String) -> int:
	return int(CAPS.get(mode, CAPS["brave"]))


## After a finished round: [heat, streak, change]. falls: everyone's falls that round; players: how many played.
## Clean (no falls): the streak grows and every EVERY-th one heats up (change +1, up to the mode's cap). A fall ends
## the streak; falls >= max(2, players) cool a step (change -1). Heat over the cap (a mode picked lower) drops to it.
static func step(heat: int, streak: int, falls: int, players: int, mode: String) -> Array:
	var c := cap(mode)
	var h := clampi(heat, 0, c)
	if falls <= 0:
		streak += 1
		if streak % EVERY == 0 and h < c:
			return [h + 1, streak, 1]
		return [h, streak, 0]
	if falls >= maxi(2, players) and h > 0:
		return [h - 1, 0, -1]
	return [h, 0, 0]


## A new sitting: one step cooler than the saved heat (whoever picks up the pad next warms up first).
static func session_start(heat: int) -> int:
	return maxi(0, heat - 1)


## The card line when the streak heats up (short: a story card).
static func line(streak: int) -> String:
	return "%d clean in a row! Trickier now!" % streak


## Problems with the rules (empty = fine): tests call this (marble_maze_deep_test, sky_bots_gen_test).
static func problems() -> Array:
	var out: Array = []
	var want := [[[0, 0, 0, 2, "brave"], [0, 1, 0]], [[0, 1, 0, 2, "brave"], [1, 2, 1]], [[1, 2, 1, 2, "brave"], [1, 0, 0]],
		[[1, 0, 3, 2, "brave"], [0, 0, -1]], [[0, 0, 9, 2, "brave"], [0, 0, 0]], [[1, 1, 0, 2, "gentle"], [1, 2, 0]],
		[[3, 0, 0, 2, "gentle"], [1, 1, 0]], [[1, 3, 1, 6, "hard"], [1, 0, 0]], [[2, 3, 0, 1, "hard"], [3, 4, 1]],
		[[3, 5, 0, 1, "hard"], [3, 6, 0]]]
	for w in want:
		var a: Array = w[0]
		var got := step(int(a[0]), int(a[1]), int(a[2]), int(a[3]), str(a[4]))
		if var_to_str(got) != var_to_str(w[1]):
			out.append("step%s = %s, want %s" % [str(a), str(got), str(w[1])])
	if session_start(0) != 0 or session_start(2) != 1:
		out.append("session_start")
	if line(12).length() > 40:
		out.append("line too long for a story card")
	return out
