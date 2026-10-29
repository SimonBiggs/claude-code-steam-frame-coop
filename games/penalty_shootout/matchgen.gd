extends RefCounted
## PENALTY SHOOTOUT generator: every match's plan (how fast each kick may go, where LEO'S STAR shines in the goal on
## each turn, the computer striker's kicks for a VR keeper playing alone, the practice rings and how many stars Leo
## asks for) as plain data from a seed, so the host and every TV machine build the same match from [cup seed, match]
## and tests/penalty_shootout_gen_test.gd proves over many seeds that every match is fair and winnable by small kids.
##   var plan := MatchGen.plan(cup_seed, match_n)
##   plan = {n, speeds: [top kick speed per turn k (m/s)], stars: [Vector2 star spot in the goal per turn, or
##           Vector2.INF on a turn without a star], cpu: [Vector3(x offset from the keeper (or the star's x when
##           cpu_star), height, power) per turn], cpu_star: [bool per turn], rings: [Vector2 striker practice rings]}
##   MatchGen.star_goal(plan, turns) = the stars Leo asks for when the match has `turns` kicks.
## Story: LEO THE LION (the mascot by the left post) loves stars. A kick aimed at the glowing star that doesn't
## miss (a goal through it, or the keeper saving it) sends the star to Leo. Reach Leo's star goal and he puts a
## PRIZE in his corner (saved: scarf, balloon, drum, bunting, foam hand, trophy...); a LION CUB joins his fan club
## each play-day; with ten prizes he wears a crown. TODAY'S MATCH: the first match each day uses the day's seed on
## every machine and its prize gets a gold star.
## check(plan) is the validator: match 1 starts plain (no star for the first two kicks, then every other kick), one
## new thing at a time (match 2: more stars, 3+: a star every kick after the first), stars sit well inside the posts
## and under the bar (a kick aimed there can't miss), off the keeper's middle (a striker can score) and swap sides;
## kick speeds start slow, rise by small steps and never pass the cap; every computer kick a small keeper must face
## alone is checked against a slow kid keeper (reaction, arm reach, shuffle speed): the first kicks and every star
## kick are all saveable and most of the rest are; practice rings start in the middle and sit inside the goal; and
## Leo's star goal needs a small kid to hit the star on well under half the star kicks, for 1-6 strikers or the
## computer striker.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "penalty_shootout"
const GOAL_HALF := 3.66  # == ball.gd
const GOAL_H := 2.44  # == ball.gd
const SPOT_Z := 11.0  # == main.gd spot
const SPD_MIN := 6.5  # == main.gd
const AIM_X := 4.4  # == striker.gd
const AIM_Y_MAX := 3.0  # == striker.gd
const MAX_TURNS := 40  # 6 strikers x 5 rounds plus room for late joiners (later turns repeat the last)
const STAR_R := 0.8  # an aim this close to the star sends it to Leo
const STAR_X := Vector2(0.95, 2.5)  # |x| of a star: off the keeper's middle, well inside the posts
const STAR_Y := Vector2(0.5, 1.75)
const POST_GAP := 0.75  # a star (and a kick aimed at it) is at least this far inside a post
const BAR_GAP := 0.6
const SPEED_FIRST := 8.0  # the first kicks
const SPEED_CAP := 15.0  # never faster (simple mode's old top speed)
const SPEED_STEP := 0.9  # the most the top speed rises from one kick to the next
const RAMP := 14  # kicks to reach the match's top speed
# The slow kid keeper (a little VR keeper or a small kid on the stick).
const KID_REACT := 0.45  # s before they move
const KID_ARM := 0.9  # m reach either side of their middle (gloves + the auto-fit world scale)
const KID_SHUFFLE := 1.5  # m/s sideways (stepping / half a stick)
const CPU_TURNS := 8  # == main.gd (solo VR: 8 rounds against the computer striker)
const CPU_SAVE_SHARE := 0.6  # the kid keeper can reach at least this share of the computer's kicks
const CPU_EASY := 3  # the first computer kicks are all saveable
const CPU_STAR_POWER := 0.15  # computer kicks at the star are gentle
const KID_STAR_SHARE := 0.5  # a small kid aims at the star on half their star kicks
const GOAL_SHARE := 0.4  # Leo asks for this share of the star kicks
const GOAL_MAX := 8  # star sockets over Leo
const RINGS := 5
const RING_R := 0.68  # == simple_fx.gd target ring
const MAX_MATCH := 8  # the validator's reach (later matches repeat match 8's rules)

## Leo's prizes (one per star goal reached), in order, then round and round.
const PRIZES: Array[String] = ["scarf", "balloon", "drum", "bunting", "foamhand", "trophy"]
const PRIZE_KEEP := 12  # prizes in Leo's corner (the oldest makes room)
const CUBS_MAX := 12  # one lion cub per play-day
const CROWN_PRIZES := 10  # Leo's crown
const LEO := Vector3(-6.2, 0.0, 2.2)  # == world.gd mascot


## The day's cup seed (the same everywhere all day).
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


static func match_seed(cup_seed: int, n: int) -> int:
	return Seeded.derive(cup_seed, "match%d" % n)


## Does kick k (0-based, in the match) of match n have a star? One new thing at a time.
static func has_star(n: int, k: int) -> bool:
	if n <= 1:
		return k >= 2 and k % 2 == 0
	if n == 2:
		return k >= 1 and k % 3 != 0
	return k >= 1


## The match's top kick speed after the ramp.
static func top_speed(n: int) -> float:
	return minf(SPEED_CAP, 12.5 + 1.0 * (n - 1))


static func plan(cup_seed: int, n: int) -> Dictionary:
	n = maxi(1, n)
	var rule_n := mini(n, MAX_MATCH)
	var rng := Seeded.rng(match_seed(cup_seed, n), "match")
	var p := {"n": n}
	# Kick speeds: slow first, a little faster every kick, with a small seeded wobble.
	var speeds: Array = []
	var top := top_speed(rule_n)
	var prev := SPEED_FIRST
	for k in MAX_TURNS:
		var s := lerpf(SPEED_FIRST, top, clampf(float(k) / RAMP, 0.0, 1.0))
		if k >= 2:
			s += rng.randf_range(-0.35, 0.35)
		s = clampf(s, prev - 0.5, prev + SPEED_STEP)
		s = clampf(snappedf(s, 0.01), SPEED_FIRST, top)
		speeds.append(s)
		prev = s
	p.speeds = speeds
	# Leo's stars: swap sides each time, anywhere in the comfy middle band of each half.
	var stars: Array = []
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var last := Vector2.INF
	for k in MAX_TURNS:
		if not has_star(rule_n, k):
			stars.append(Vector2.INF)
			continue
		var st := Vector2.ZERO
		var wide := STAR_X.y
		if k < CPU_TURNS:  # a keeper alone faces the computer's gentle kick at it: keep it in a small kid's reach
			wide = minf(wide, kid_reach(kick_speed(float(speeds[k]), CPU_STAR_POWER)) - 0.05)
		for _i in 20:
			st = Vector2(snappedf(side * rng.randf_range(STAR_X.x, wide), 0.01), snappedf(rng.randf_range(STAR_Y.x, STAR_Y.y), 0.01))
			if last == Vector2.INF or st.distance_to(last) > 1.2:
				break
		stars.append(st)
		last = st
		side = -side
	p.stars = stars
	# The computer striker (a VR keeper alone): near the keeper first, wider later; gentle at the star.
	var cpu: Array = []
	var cpu_star: Array = []
	var misses_left := CPU_TURNS - int(ceil(CPU_TURNS * CPU_SAVE_SHARE))
	for k in MAX_TURNS:
		var st: Vector2 = stars[k]
		if st != Vector2.INF and k < CPU_TURNS:
			cpu.append(Vector3(st.x, st.y, CPU_STAR_POWER))
			cpu_star.append(true)
			continue
		var spread := clampf(0.7 + 0.25 * k, 0.7, 3.2)
		var c := Vector3(snappedf(rng.randf_range(-spread, spread), 0.01), snappedf(rng.randf_range(0.4, minf(2.1, 0.9 + 0.12 * k)), 0.01),
			snappedf(rng.randf_range(0.4, 0.85), 0.01))
		if k < CPU_TURNS:
			var reach := kid_reach(kick_speed(speeds[k], c.z))
			if absf(c.x) > reach and (k < CPU_EASY or misses_left <= 0):
				c.x = snappedf(signf(c.x) * reach * rng.randf_range(0.5, 0.9), 0.01)  # one a small kid can reach
			elif absf(c.x) > reach:
				misses_left -= 1
		cpu.append(c)
		cpu_star.append(false)
	p.cpu = cpu
	p.cpu_star = cpu_star
	# Striker practice rings: the middle first, then side to side.
	var rings: Array = [Vector2(0.0, 1.1)]
	var rside := 1.0 if rng.randf() < 0.5 else -1.0
	while rings.size() < RINGS:
		rings.append(Vector2(snappedf(rside * rng.randf_range(1.0, 2.5), 0.01), snappedf(rng.randf_range(0.75, 1.62), 0.01)))
		rside = -rside
	p.rings = rings
	return p


## The real kick speed for a top speed and power (== main.gd _launch, normal shot).
static func kick_speed(top: float, power: float) -> float:
	return lerpf(SPD_MIN, top, clampf(power, 0.0, 1.0))


## How far either side of their middle a slow kid keeper can get a glove to a kick of this speed.
static func kid_reach(speed: float) -> float:
	var flight := SPOT_Z / maxf(1.0, speed)
	return KID_ARM + KID_SHUFFLE * maxf(0.0, flight - KID_REACT)


## Kick k's top speed (later kicks repeat the last).
static func speed_at(p: Dictionary, k: int) -> float:
	var s: Array = p.speeds
	return float(s[clampi(k, 0, s.size() - 1)])


## Kick k's star (Vector2.INF: none; past the plan: none).
static func star_at(p: Dictionary, k: int) -> Vector2:
	var s: Array = p.stars
	return s[k] if k >= 0 and k < s.size() else Vector2.INF


## Star kicks among the first `turns` kicks.
static func star_turns(p: Dictionary, turns: int) -> int:
	var c := 0
	for k in mini(turns, (p.stars as Array).size()):
		if p.stars[k] != Vector2.INF:
			c += 1
	return c


## The stars Leo asks for in a match of `turns` kicks (at least one).
static func star_goal(p: Dictionary, turns: int) -> int:
	return clampi(int(floor(star_turns(p, turns) * GOAL_SHARE)), 1, GOAL_MAX)


## Does an aim at `aim` take kick k's star?
static func takes_star(p: Dictionary, k: int, aim: Vector2) -> bool:
	var st := star_at(p, k)
	return st != Vector2.INF and aim.distance_to(st) <= STAR_R


## How many kicks a match has: rounds x strikers (== main.gd _rounds_for, simple mode), or the computer's 8.
static func turns_for(strikers: int) -> int:
	if strikers <= 0:
		return CPU_TURNS
	return clampi(int(ceil(10.0 / float(strikers))), 3, 5) * strikers


## Problems with one match plan (empty = fair and winnable).
static func check(p: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var n: int = p.n
	var rule_n := mini(n, MAX_MATCH)
	var speeds: Array = p.speeds
	var stars: Array = p.stars
	var cpu: Array = p.cpu
	if speeds.size() < MAX_TURNS or stars.size() < MAX_TURNS or cpu.size() < MAX_TURNS or (p.cpu_star as Array).size() < MAX_TURNS:
		why.append("the plan is too short")
		return why
	# Speeds: slow start, small steps, never past the cap.
	if float(speeds[0]) > SPEED_FIRST + 0.5 or float(speeds[1]) > SPEED_FIRST + 1.0:
		why.append("the first kicks are too fast (%.1f, %.1f)" % [speeds[0], speeds[1]])
	for k in speeds.size():
		var s := float(speeds[k])
		if s > SPEED_CAP + 0.001 or s < SPEED_FIRST - 0.001:
			why.append("kick %d's top speed %.1f is out of range" % [k, s])
		if k > 0 and s - float(speeds[k - 1]) > SPEED_STEP + 0.001:
			why.append("kick %d jumps in speed (%.1f -> %.1f)" % [k, speeds[k - 1], s])
		if k > 0 and float(speeds[k - 1]) - s > 0.51:
			why.append("kick %d drops in speed a lot" % k)
	if float(speeds[speeds.size() - 1]) < float(speeds[0]) + 2.0:
		why.append("the kicks never get faster")
	# Stars: one new thing at a time, well inside the goal, off the middle, side to side.
	var prev := Vector2.INF
	for k in stars.size():
		var st: Vector2 = stars[k]
		if (st != Vector2.INF) != has_star(rule_n, k):
			why.append("kick %d %s a star (match %d)" % [k, "has" if st != Vector2.INF else "hasn't got", n])
			continue
		if st == Vector2.INF:
			continue
		if absf(st.x) + STAR_R > GOAL_HALF - 0.3 or absf(st.x) > GOAL_HALF - POST_GAP - 0.3:
			why.append("a star at (%.1f, %.1f) is too near a post" % [st.x, st.y])
		if st.y > GOAL_H - BAR_GAP or st.y < 0.45:
			why.append("a star at (%.1f, %.1f) is too near the bar or the grass" % [st.x, st.y])
		if absf(st.x) < STAR_X.x - 0.001:
			why.append("a star at (%.1f, %.1f) sits in the keeper's middle" % [st.x, st.y])
		if absf(st.x) > AIM_X or st.y > AIM_Y_MAX:
			why.append("a star the aim can't reach")
		if prev != Vector2.INF and signf(prev.x) == signf(st.x):
			why.append("two stars in a row on the same side (kick %d)" % k)
		prev = st
	# The computer striker vs a slow kid keeper alone.
	var reachable := 0
	for k in CPU_TURNS:
		var c: Vector3 = cpu[k]
		var star := bool(p.cpu_star[k])
		if star != (stars[k] != Vector2.INF):
			why.append("computer kick %d's star doesn't match" % k)
		if star and (not is_equal_approx(c.x, (stars[k] as Vector2).x) or not is_equal_approx(c.y, (stars[k] as Vector2).y)):
			why.append("computer kick %d misses the star it aims at" % k)
		if c.z < 0.0 or c.z > 1.0 or c.y < 0.3 or c.y > 2.2:
			why.append("computer kick %d is wild (%s)" % [k, str(c)])
		var reach := kid_reach(kick_speed(float(speeds[k]), c.z))
		var ok := absf(c.x) <= reach + 0.001
		if ok:
			reachable += 1
		elif k < CPU_EASY:
			why.append("computer kick %d (%.1f m out at %.1f m/s) is too hard for a small keeper" % [k, c.x, kick_speed(float(speeds[k]), c.z)])
		elif star:
			why.append("computer kick %d at the star (%.1f m out) can't be reached by a small keeper" % [k, c.x])
	if reachable < int(ceil(CPU_TURNS * CPU_SAVE_SHARE)):
		why.append("a small keeper alone can reach only %d of %d computer kicks" % [reachable, CPU_TURNS])
	# Practice rings.
	var rings: Array = p.rings
	if rings.size() < RINGS:
		why.append("only %d practice rings" % rings.size())
	elif (rings[0] as Vector2).distance_to(Vector2(0.0, 1.1)) > 0.01:
		why.append("the first practice ring isn't in the middle")
	for r in rings:
		var v: Vector2 = r
		if absf(v.x) + RING_R > GOAL_HALF - 0.3 or v.y - RING_R < 0.0 or v.y + RING_R > GOAL_H - 0.1:
			why.append("a practice ring at (%.1f, %.1f) pokes out of the goal" % [v.x, v.y])
	# Leo's star goal: a small kid hitting the star on half their star kicks gets there with room to spare.
	for strikers in range(0, 7):
		var turns := turns_for(strikers)
		var st_turns := star_turns(p, turns)
		var g := star_goal(p, turns)
		if st_turns < 1:
			why.append("no star kicks at all with %d strikers" % strikers)
		elif strikers > 0 and float(g) > float(st_turns) * KID_STAR_SHARE + 0.001:
			why.append("Leo asks for %d stars from %d star kicks (%d strikers)" % [g, st_turns, strikers])
		elif strikers == 0 and g > st_turns:
			why.append("Leo asks for more stars than the computer kicks at")
	return why


## Problems with a whole cup (matches 1..last): every match fair, and the challenge never drops.
static func check_cup(cup_seed: int, last: int = MAX_MATCH) -> Array[String]:
	var why: Array[String] = []
	var prev_top := 0.0
	var prev_stars := 0
	for n in range(1, last + 1):
		var p := plan(cup_seed, n)
		for r in check(p):
			why.append("match %d: %s" % [n, r])
		var top := float((p.speeds as Array).max())
		if top < prev_top - 0.6:
			why.append("match %d is slower than match %d" % [n, n - 1])
		var sc := star_turns(p, MAX_TURNS)
		if sc < prev_stars:
			why.append("match %d has fewer stars than match %d" % [n, n - 1])
		prev_top = top
		prev_stars = sc
	return why


## The prize the k-th star goal (0-based, over all days) puts in Leo's corner.
static func prize_for(k: int) -> String:
	return PRIZES[posmod(k, PRIZES.size())]


## Lion cubs in Leo's fan club: one per play-day.
static func cubs(days: int) -> int:
	return clampi(days, 0, CUBS_MAX)


## Where cub i sits (world): two rows beside Leo, on the side away from the goal.
static func cub_slot(i: int) -> Vector3:
	return LEO + Vector3(-0.85 - 0.6 * (i % 6), 0.0, 0.55 + 0.7 * (i / 6))


## Where prize i stands (world): two rows on the far side of Leo, Vector3.INF past the end.
static func prize_slot(i: int) -> Vector3:
	if i < 0 or i >= PRIZE_KEEP:
		return Vector3.INF
	return Vector3(-7.4 - 0.95 * (i % 6), 0.0, 0.2 + 1.1 * (i / 6))


## Where star socket i of `count` floats over Leo's head (world), facing the strikers.
static func star_socket(i: int, count: int) -> Vector3:
	var w := 0.5
	return LEO + Vector3((i - (count - 1) * 0.5) * w, 3.0, 0.0)
