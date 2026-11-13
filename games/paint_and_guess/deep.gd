extends RefCounted
## PAINT AND GUESS second pass (pure data + small functions; tests/paint_and_guess_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs before the
##             first game: the picture difficulty and the round times (paintgen.gd MODE_* : in the game's code, so every
##             machine builds the same game), how often Smudge's studio plays a warned surprise and how long it is told
##             first, how big a surprise is, and how quickly SMUDGE guesses when nobody else can.
##   SMUDGE GUESSES  nobody to guess (a lone Deck, the VR artist alone, a TV machine whose players all left): Smudge the
##             gallery cat watches the painting and guesses once enough paint is on the canvas (HARD: one wrong guess
##             first), so a lone painter always gets on with the game. TEAM PAINT with nobody to paint is a painting round.
##   GIFTS     SMUDGE'S BRUSH GIFTS for one game, three offered on the pick orbs before every game from a session's
##             second: BIG BRUSH (fatter paint), RAINBOW BRUSH (start every round on the rainbow paint), STAMPS (a quick
##             tap stamps a star), SLOW CLOCK (more time every round) and PEEK GLASS (one wrong answer goes away for every
##             guesser; Smudge guesses sooner) - the last two open as Smudge's museum grows. Gifts only ever add time,
##             paint or help: the right answer is never crossed out and no round gets shorter (the test proves it).
##   SURPRISES warned by steady core/warn_rings.gd shapes ON THE CANVAS (each kind its own colour), only on BARE canvas
##             (never over paint), never in TEAM PAINT, never in a session's first round (bots: PG_TRICKS_NOW), never in a
##             round's first seconds, never two at once:
##               DRIP  an orange circle: a drop of paint drips from the pot on top of the easel into it and dries away.
##               WIND  a blue band: a gust from the window blows across it.
##             From the moment it is told until it is over nobody can paint inside it (the brush lifts there), so it
##             stays bare and nothing anyone painted is ever covered or moved. spot() picks a fair place from the
##             painting (the same on every machine), problems() proves it.
##   SEASONS   Smudge's seasonal studio (Seeded.season): BLOSSOM / SUNNY / LEAFY / SNOWY STUDIO: the view out of the
##             window, seasonal props (core/season_kit.gd) in the back corners and petals / pollen / leaves / snow
##             drifting there (season.gd).
##   MUSEUM    every finished game adds a treasure to SMUDGE'S MUSEUM along the side walls under the family gallery
##             (museum.gd): vases, flower pots, sculptures, trophies, golden frames and a cat statue every tenth, each
##             on a plinth in the mode's colour (saved: museum, museum_n).
##   PICK ROWS with guessers who are people (or a flat artist): three orbs in front of the canvas ("canvas"): a TV
##             player's brush ring (or the artist's brush) rests UNDER one TV_DWELL s. The VR artist alone: three small
##             orbs an arm's reach in front of the artist's eyes ("vr"): the hand moves into one and stays DWELL s.
##             Something already there when they pop up must leave and come back. Nobody in time = the middle one.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const PaintGen := preload("res://games/paint_and_guess/paintgen.gd")
const Canvas := preload("res://games/paint_and_guess/canvas.gd")

## every: seconds between surprises; warn: seconds told first; drip_r: a drip's radius (canvas metres); wind_w: half a
## wind band's length; after: seconds a surprise lasts once it goes off; smudge_ink: canvas points painted before
## Smudge guesses; smudge_t: seconds into the round at the earliest; smudge_wrong: wrong guesses Smudge makes first.
const MODES := {
	"gentle": {"every": 45.0, "warn": 3.6, "drip_r": 0.08, "wind_w": 0.15, "after": 3.0, "smudge_ink": 30, "smudge_t": 8.0, "smudge_wrong": 0},
	"brave": {"every": 32.0, "warn": 3.0, "drip_r": 0.1, "wind_w": 0.19, "after": 3.5, "smudge_ink": 60, "smudge_t": 13.0, "smudge_wrong": 0},
	"hard": {"every": 24.0, "warn": 2.6, "drip_r": 0.12, "wind_w": 0.23, "after": 4.0, "smudge_ink": 90, "smudge_t": 18.0, "smudge_wrong": 1},
}
const MIN_WARN := 2.0
const FIRST_T := 14.0  # no surprise in a round's first seconds
const SHORT_FIRST := 3.0  # (bots: PG_TRICKS_NOW)
const RETRY := 2.0  # no bare canvas: look again this much later
const END_GAP := 6.0  # never one that would still be going in the round's last seconds
const EDGE := 0.04  # a zone stays this far inside the canvas
const PAD := 0.06  # bare canvas: no paint this near a zone (plus the paint's half width)
const MAX_HALF_W := 0.03  # the widest paint's half width (BIG BRUSH sparkle)
const CURSOR_AWAY := 0.12  # a zone starts this far from where anyone's brush is now
const WIND_H := 0.06  # half a wind band's height
const GRID := 0.04  # the painting is looked at in squares this big when finding bare canvas
const DRIP_COLOR := Color(1.0, 0.5, 0.08)  # drip orange
const WIND_COLOR := Color(0.25, 0.55, 1.0)  # wind blue
const TELL_DIM := 0.5  # a tell's inside glows this much darker than its edge (so it never looks like paint)
const TELL_EDGE := 0.012  # a wind band's bright edges (canvas metres)
const KINDS: Array[String] = ["drip", "wind"]
const KIND_PICS := {"drip": "paintdrip", "wind": "gust"}
const KIND_NAMES := {"drip": "DRIP!", "wind": "WIND!"}
## SMUDGE GUESSES: a small kid paints at least this many canvas points a second (the test proves Smudge always
## guesses in time); seconds between Smudge's wrong guess and the right one.
const INK_RATE := 6.0
const SMUDGE_GAP := 4.0
const SMUDGE_THINK := 0.5  # Smudge looks this long before a guess
## Season -> studio: name, picture, Smudge's line, drift colour, the window's sky / ground.
const SEASONS := {
	"spring": {"name": "BLOSSOM STUDIO", "pic": "daisy", "line": "Blossom painting!", "drift": Color(1.0, 0.72, 0.86),
		"sky": Color(0.55, 0.8, 1.0), "ground": Color(0.55, 0.85, 0.45)},
	"summer": {"name": "SUNNY STUDIO", "pic": "sun", "line": "Sunny painting!", "drift": Color(1.0, 0.95, 0.6),
		"sky": Color(0.35, 0.7, 1.0), "ground": Color(0.45, 0.8, 0.35)},
	"autumn": {"name": "LEAFY STUDIO", "pic": "pumpkin", "line": "Leafy painting!", "drift": Color(0.95, 0.5, 0.15),
		"sky": Color(0.6, 0.75, 0.95), "ground": Color(0.85, 0.55, 0.2)},
	"winter": {"name": "SNOWY STUDIO", "pic": "snowflake", "line": "Snowy painting!", "drift": Color(0.97, 0.98, 1.0),
		"sky": Color(0.7, 0.8, 0.92), "ground": Color(0.95, 0.97, 1.0)},
}
## Brush gifts: id, name, picture, a short line, a colour, museum treasures needed.
const GIFTS: Array[Dictionary] = [
	{"id": "bigbrush", "name": "BIG BRUSH", "pic": "bigbrush", "line": "Big fat paint!", "color": Color(1.0, 0.55, 0.3), "unlock": 0},
	{"id": "rainbow", "name": "RAINBOW BRUSH", "pic": "rainbowbrush", "line": "Rainbow paint!", "color": Color(0.85, 0.5, 1.0), "unlock": 0},
	{"id": "stamps", "name": "STAMPS", "pic": "stampbrush", "line": "Tap to stamp!", "color": Color(1.0, 0.85, 0.3), "unlock": 0},
	{"id": "clock", "name": "SLOW CLOCK", "pic": "slowclock", "line": "More time!", "color": Color(0.5, 0.9, 1.0), "unlock": 2},
	{"id": "peek", "name": "PEEK GLASS", "pic": "peekglass", "line": "One wrong goes!", "color": Color(0.55, 1.0, 0.6), "unlock": 4},
]
const BIG := 1.7  # BIG BRUSH: paint this much wider
const CLOCK_ADD := 15.0  # SLOW CLOCK: seconds more every round
const PEEK_T := 12.0  # PEEK GLASS: seconds into a round when a wrong answer goes ...
const PEEK_INK := 0.6  # ... and Smudge needs this much of the paint and the time
const STAMP_R := 0.05  # STAMPS: a star this big (canvas metres) ...
const STAMP_TAP := 0.02  # ... for a stroke shorter than this
## Smudge's museum: one treasure per finished game (kinds are story pictures).
const TREASURES: Array[String] = ["vase", "flowerpot", "sculpture", "trophy", "goldframe", "catstatue"]
const TREASURE_NAMES := {"vase": "vase", "flowerpot": "flower pot", "sculpture": "sculpture", "trophy": "trophy",
	"goldframe": "gold frame", "catstatue": "cat statue"}
const MUSEUM_SHOWN := 20
const MUSEUM_X := 3.72
const MUSEUM_Z0 := -1.9
const MUSEUM_GAP := 0.62
const PLINTH_H := 0.5
const TREASURE_H := 0.5  # the tallest treasure (its top stays under the window and the shelves)
## The pick rows. Canvas row: orbs in front of the canvas (canvas metres), a ring rests on the spot under one.
const ORB_X: Array[float] = [-0.42, 0.0, 0.42]  # (GENTLE on the left)
const ORB_Y := 0.1
const ORB_Z := 0.2
const UNDER_Y := -0.2
const CANVAS_SCALE := 0.16
const TV_R := 0.14  # a ring this near an orb's spot is under it ...
const TV_DWELL := 0.8  # ... for this long to pick it
const REST_Y := -0.38  # rings start here when the orbs pop up (not under any orb)
## VR row (metres): an arm's reach in front of the artist's eyes, just under eye level; GENTLE on the left.
const VR_X: Array[float] = [-0.3, 0.0, 0.3]
const VR_AHEAD := 0.42
const VR_BELOW := 0.14
const VR_SCALE := 0.11
const HAND_R := 0.05  # a hand this near an orb's ball touches it ...
const DWELL := 0.35  # ... for this long (deliberate: a hand sweeping past never picks)
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const EMPTY_WAIT := 8.0  # nobody here who could pick at all: sooner


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, nobody: bool) -> float:
	return EMPTY_WAIT if nobody else float(ROW_WAIT.get(stage, 16.0))


## A round's seconds in a mode with a gift (paintgen.gd round_time + SLOW CLOCK).
static func round_time(type: String, mode: String, gift_id: String) -> float:
	return PaintGen.round_time(type, mode_of(mode)) + (CLOCK_ADD if gift_id == "clock" else 0.0)


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["drip_r", "wind_w", "after", "smudge_ink", "smudge_t", "smudge_wrong"]:  # more is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["every", "warn"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if int(g.smudge_wrong) != 0:
		out.append("gentle Smudge guesses wrong")
	for t in PaintGen.ROUND_TIMES:
		var tg := PaintGen.round_time(t, "gentle")
		var tb := PaintGen.round_time(t, "brave")
		var th := PaintGen.round_time(t, "hard")
		if not (tg >= tb and tb >= th):
			out.append("%s round time not longest on gentle" % t)
	for ri in PaintGen.ROUNDS:
		if not (PaintGen.max_tier("gentle", ri) <= PaintGen.max_tier("brave", ri) and PaintGen.max_tier("brave", ri) <= PaintGen.max_tier("hard", ri)):
			out.append("round %d pictures not easiest on gentle" % (ri + 1))
		if PaintGen.apart("hard", ri) and not PaintGen.apart("brave", ri) or PaintGen.apart("brave", ri) and not PaintGen.apart("gentle", ri):
			out.append("round %d answers not most different on gentle" % (ri + 1))
	return out


## When Smudge guesses right (seconds into a round) for a small kid painting INK_RATE points a second; -1: too late
## for the round.
static func smudge_right_at(type: String, mode: String, gift_id: String) -> float:
	var md := mode_data(mode)
	var f := PEEK_INK if gift_id == "peek" else 1.0
	var t := maxf(float(md.smudge_t) * f, float(md.smudge_ink) * f / INK_RATE) + SMUDGE_THINK + SMUDGE_GAP * int(md.smudge_wrong)
	return t if t <= round_time(type, mode, gift_id) - 2.0 else -1.0


# --- Surprises on the canvas ------------------------------------------------------------------------------

static func _make(kind: String, x: float, y: float, md: Dictionary) -> Dictionary:
	var e := {"kind": kind, "x": snappedf(x, 0.001), "y": snappedf(y, 0.001), "warn": float(md.warn), "after": float(md.after)}
	if kind == "drip":
		e["w"] = float(md.drip_r)
		e["h"] = float(md.drip_r)
	else:
		e["w"] = float(md.wind_w)
		e["h"] = WIND_H
	return e


## Is canvas point p inside zone e (pad: this much bigger)?
static func inside(e: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	if e.is_empty():
		return false
	var d := p - Vector2(float(e.x), float(e.y))
	if String(e.kind) == "drip":
		return d.length() <= float(e.w) + pad
	return absf(d.x) <= float(e.w) + pad and absf(d.y) <= float(e.h) + pad


## Does paint from a to b (a brush of half width hw) come near zone e? (Painting is blocked there.)
static func blocks(e: Dictionary, a: Vector2, b: Vector2, hw: float = MAX_HALF_W) -> bool:
	if e.is_empty():
		return false
	var n := maxi(1, ceili(a.distance_to(b) / 0.01))
	for i in n + 1:
		if inside(e, a.lerp(b, float(i) / float(n)), PAD + hw):
			return true
	return false


## The zone fits on the canvas (EDGE in).
static func on_canvas(e: Dictionary) -> bool:
	var hx := float(e.w)
	var hy := float(e.h)
	return float(e.x) - hx >= -Canvas.W * 0.5 + EDGE - 0.0001 and float(e.x) + hx <= Canvas.W * 0.5 - EDGE + 0.0001 \
		and float(e.y) - hy >= -Canvas.H * 0.5 + EDGE - 0.0001 and float(e.y) + hy <= Canvas.H * 0.5 - EDGE + 0.0001


## Exact: no paint (any stroke, as canvas.gd export_strokes() gives them) near zone e.
static func bare(e: Dictionary, strokes: Array) -> bool:
	for s in strokes:
		var pts: PackedVector2Array = s[3]
		var hw := float(s[2]) * 0.5
		for i in pts.size():
			if inside(e, pts[i], PAD + hw):
				return false
			if i > 0 and pts[i - 1].distance_to(pts[i]) > 0.01 and blocks(e, pts[i - 1], pts[i], hw):
				return false
	return true


## The painting in GRID squares: a square is marked when paint (with its width) comes into it.
static func paint_grid(strokes: Array) -> Dictionary:
	var cols := ceili(Canvas.W / GRID)
	var rows := ceili(Canvas.H / GRID)
	var g := PackedByteArray()
	g.resize(cols * rows)
	g.fill(0)
	for s in strokes:
		var pts: PackedVector2Array = s[3]
		var r := float(s[2]) * 0.5 + 0.004  # (+ a little: the paint between two samples)
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i - 1] if i > 0 else a
			var n := maxi(1, ceili(a.distance_to(b) / 0.006))  # (samples close enough that their squares cover the line)
			for k in n + 1:
				var q := a.lerp(b, float(k) / float(n))
				for cx in range(floori((q.x - r + Canvas.W * 0.5) / GRID), floori((q.x + r + Canvas.W * 0.5) / GRID) + 1):
					for cy in range(floori((q.y - r + Canvas.H * 0.5) / GRID), floori((q.y + r + Canvas.H * 0.5) / GRID) + 1):
						if cx >= 0 and cy >= 0 and cx < cols and cy < rows:
							g[cy * cols + cx] = 1
	return {"g": g, "cols": cols, "rows": rows}


## Quick (and on the safe side): no marked square comes near zone e.
static func grid_bare(e: Dictionary, grid: Dictionary) -> bool:
	var g: PackedByteArray = grid.g
	var cols: int = grid.cols
	var rows: int = grid.rows
	var pad := PAD + 0.002
	var x0 := floori((float(e.x) - float(e.w) - pad + Canvas.W * 0.5) / GRID)
	var x1 := floori((float(e.x) + float(e.w) + pad + Canvas.W * 0.5) / GRID)
	var y0 := floori((float(e.y) - float(e.h) - pad + Canvas.H * 0.5) / GRID)
	var y1 := floori((float(e.y) + float(e.h) + pad + Canvas.H * 0.5) / GRID)
	for cy in range(maxi(0, y0), mini(rows - 1, y1) + 1):
		for cx in range(maxi(0, x0), mini(cols - 1, x1) + 1):
			if g[cy * cols + cx] == 0:
				continue
			# The square's nearest point to the zone's middle: inside the padded zone = not bare.
			var lo := Vector2(cx * GRID - Canvas.W * 0.5, cy * GRID - Canvas.H * 0.5)
			var c := Vector2(float(e.x), float(e.y))
			var q := Vector2(clampf(c.x, lo.x, lo.x + GRID), clampf(c.y, lo.y, lo.y + GRID))
			if inside(e, q, pad):
				return false
	return true


## Every place a surprise could go (before looking at the painting), in the k-th surprise's own order.
static func candidates(kind: String, mode: String, seed_value: int, k: int) -> Array:
	var md := mode_data(mode)
	var out: Array = []
	var y := -0.33
	while y <= 0.331:
		var x := -0.5
		while x <= 0.501:
			var e := _make(kind, x, y, md)
			if on_canvas(e):
				out.append(e)
			x += 0.1
		y += 0.11
	return Seeded.shuffled(Seeded.rng(seed_value, "spot %d %s" % [k, kind]), out)


## The k-th surprise of a round: a fair place for `kind` on this painting ({} none), away from the brushes (avoid:
## canvas points). The same on every machine for the same painting.
static func spot(strokes: Array, kind: String, mode: String, seed_value: int, k: int, avoid: Array = []) -> Dictionary:
	var grid := paint_grid(strokes)
	for e in candidates(kind, mode, seed_value, k):
		var ok := true
		for a in avoid:
			if inside(e, a as Vector2, CURSOR_AWAY):
				ok = false
				break
		if ok and grid_bare(e, grid):
			return e
	return {}


## Reasons a surprise is unfair on this painting (empty = fine).
static func problems(e: Dictionary, strokes: Array, mode: String) -> Array:
	var why: Array = []
	if not KINDS.has(String(e.get("kind", ""))):
		return ["unknown surprise %s" % str(e)]
	var md := mode_data(mode)
	var want := _make(String(e.kind), float(e.x), float(e.y), md)
	var tag := "%s at %.2f,%.2f" % [e.kind, float(e.x), float(e.y)]
	if float(e.warn) < MIN_WARN or float(e.warn) < float(md.warn) - 0.001:
		why.append("%s: told only %.1f s" % [tag, float(e.warn)])
	if not is_equal_approx(float(e.w), float(want.w)) or not is_equal_approx(float(e.h), float(want.h)):
		why.append("%s: the wrong size for %s" % [tag, mode])
	if float(e.after) > float(md.after) + 0.001:
		why.append("%s: lasts too long" % tag)
	if not on_canvas(e):
		why.append("%s: off the canvas" % tag)
	if not bare(e, strokes):
		why.append("%s: over paint" % tag)
	return why


## The k-th surprise's kind in a round (the same on every machine).
static func kind_at(seed_value: int, k: int) -> String:
	return KINDS[Seeded.rng(seed_value, "surprise %d" % k).randi() % KINDS.size()]


static func span(e: Dictionary) -> float:
	return float(e.warn) + float(e.after)


static func pack(e: Dictionary) -> Array:
	return [] if e.is_empty() else [String(e.kind), float(e.x), float(e.y), float(e.w), float(e.h), float(e.warn), float(e.after)]


static func unpack(a: Array) -> Dictionary:
	return {} if a.size() < 7 else {"kind": String(a[0]), "x": float(a[1]), "y": float(a[2]), "w": float(a[3]), "h": float(a[4]),
		"warn": float(a[5]), "after": float(a[6])}


static func color_of(kind: String) -> Color:
	return DRIP_COLOR if kind == "drip" else WIND_COLOR


# --- Gifts ----------------------------------------------------------------------------------------------

static func unlocked(museum_n: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if museum_n >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are
## others (the same on every machine for a seed).
static func gift_choices(museum_n: int, last: String, seed_value: int) -> Array:
	return PickOrbs.gift_choices(unlocked(museum_n), last, seed_value)  # (the shared gift pick)


static func brush_scale(gift_id: String) -> float:
	return BIG if gift_id == "bigbrush" else 1.0


## PEEK GLASS: the answer to cross out for a seat (one of its four that is wrong and not crossed yet; -1 none).
static func peek_pick(opts: Array, target: String, wrong_mask: int, seed_value: int) -> int:
	var free: Array = []
	for i in opts.size():
		if String(opts[i]) != target and (wrong_mask >> i) & 1 == 0:
			free.append(i)
	if free.is_empty():
		return -1
	return int(free[Seeded.rng(seed_value, "peek").randi() % free.size()])


## STAMPS: a five-pointed star round p (a closed line of canvas points, all on the canvas).
static func stamp_points(p: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c := Vector2(clampf(p.x, -Canvas.W * 0.5 + STAMP_R + 0.01, Canvas.W * 0.5 - STAMP_R - 0.01),
		clampf(p.y, -Canvas.H * 0.5 + STAMP_R + 0.01, Canvas.H * 0.5 - STAMP_R - 0.01))
	for i in 11:
		var a := PI * 0.5 + TAU * float(i) / 10.0
		var r := STAMP_R if i % 2 == 0 else STAMP_R * 0.45
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


# --- Museum ---------------------------------------------------------------------------------------------

## The n-th treasure's kind (0-based): a cat statue every tenth.
static func treasure_kind(n: int) -> String:
	if n % 10 == 9:
		return "catstatue"
	var cycle: Array[String] = ["vase", "flowerpot", "sculpture", "vase", "trophy", "flowerpot", "goldframe", "sculpture", "vase"]
	return cycle[(n - n / 10) % cycle.size()]


## Where the i-th shown treasure stands (on the floor): along both side walls, under the family gallery.
static func museum_spot(i: int) -> Vector3:
	var side := -1.0 if i % 2 == 0 else 1.0
	return Vector3(side * MUSEUM_X, 0.0, MUSEUM_Z0 + float(i / 2) * MUSEUM_GAP)


# --- The pick rows --------------------------------------------------------------------------------------

## The canvas row's orbs (canvas-local x, y, z in front).
static func canvas_spots(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = ORB_X[i] if n == 3 else lerpf(ORB_X[0], ORB_X[2], float(i) / maxf(1.0, n - 1))
		out.append(Vector3(x, ORB_Y, ORB_Z))
	return out


## Which canvas-row orb a canvas point rests under (-1 none).
static func under(spots: Array, p: Vector2) -> int:
	var best := -1
	var bd := TV_R
	for i in spots.size():
		var s: Vector3 = spots[i]
		var d := p.distance_to(Vector2(s.x, UNDER_Y))
		if d < bd:
			bd = d
			best = i
	return best


## The VR row: an arm's reach in front of the artist's eyes (head: its transform; metres).
static func vr_spots(head: Transform3D, n: int = 3) -> Array:
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var out: Array = []
	for i in n:
		var x: float = VR_X[i] if n == 3 else lerpf(VR_X[0], VR_X[2], float(i) / maxf(1.0, n - 1))
		out.append(head.origin + fwd * VR_AHEAD + right * x + Vector3.DOWN * VR_BELOW)
	return out
