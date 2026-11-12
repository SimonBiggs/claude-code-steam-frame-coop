extends RefCounted
## RHYTHM BAND second pass (pure data + small functions; tests/rhythm_band_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked once a session on the pick orbs after practice:
##             how wide the timing windows are, how often a song has a warned change, how far ahead it is told and how
##             fast a FAST part goes.
##   GIFTS     DOODLE'S INSTRUMENT GIFTS, three offered on the pick orbs before every song from the second: BIG DRUM
##             (the drums grow and the drummer's timing gets easier), SHAKER (easier timing for the guitars), GOLDEN MIC
##             (the song brings two fans), SLOW SONG (the whole song a little slower, no fast parts) and CONFETTI (the
##             crowd never gets sad, confetti on every combo) - the last two open as the festival grows. A gift lasts
##             one song.
##   CHANGES   some stretches of a song are warned, told by steady core/warn_rings.gd shapes on the stage floor from
##             `warn` seconds before they start until they end:
##               FAST  an orange disc round the band: these bars play faster (the music goes up too).
##               SLOW  a sky-blue disc round the band: these bars play slower.
##               SOLO  a pale gold disc under one player, then a spotlight on them: the SPOTLIGHT SOLO - their hits
##                     count double for the crowd; a good solo is cheered (and counted for the festival).
##             changes(code, pos, spec) is the same list on every machine; problems() proves it fair (never in the
##             count-in or the first note bars, never two at once, told long enough, the warped song still playable by
##             a small kid at every mode, a solo always for someone who is there).
##   SEASONS   the stage is dressed for the season (Seeded.season): blossom, sunflowers, leaves, snow drift over the
##             crowd and seasonal things stand by the stage; the season leans the changes (autumn: more fast parts).
##   FESTIVAL  every FEST_EVERY songs Doodle's fan club grows into a festival round the stage: bunting, an ice-cream
##             cart, a balloon arch, a tent, a carousel, a big wheel... (saved, for good; festival.gd).
##   PICK ROW  three orbs float in front of the drummer at arm's reach. The VR drummer REACHES into one on purpose (a
##             hand moves in and stays a moment), the flat drummer and the guitarists press X / A / B (their screen shows
##             the three pictures over the buttons). Nobody in time = the middle one (it glows).

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const SongGen := preload("res://games/rhythm_band/songgen.gd")
const Song := preload("res://games/rhythm_band/song.gd")

## win: timing windows share; every: one change in this many note bars; warn: seconds told first; fast: a FAST part's
## speed; slow: a SLOW part's speed.
const MODES := {
	"gentle": {"win": 1.25, "every": 10, "warn": 4.0, "fast": 1.08, "slow": 0.86},
	"brave": {"win": 1.0, "every": 7, "warn": 3.4, "fast": 1.14, "slow": 0.88},
	"hard": {"win": 0.88, "every": 5, "warn": 2.8, "fast": 1.2, "slow": 0.9},
}
const MIN_WARN := 2.5
const MAX_RATE := 1.25
const MIN_RATE := 0.8
const FIRST_POS := 1  # no changes in song 1 (one new thing at a time)
const FIRST_BAR := 4  # ... nor in a song's first note bars
const PART_BARS := 2  # how long a fast / slow part lasts
const SOLO_BARS := 2  # ... and a spotlight solo
const GAP_BARS := 2  # at least this many plain bars between two changes
const KINDS: Array[String] = ["fast", "slow", "solo"]
const FAST_COLOR := Color(1.0, 0.5, 0.12)  # orange
const SLOW_COLOR := Color(0.35, 0.78, 1.0)  # sky blue
const SOLO_COLOR := Color(1.0, 0.95, 0.62)  # pale spotlight gold
const BAND_R := 3.2  # the fast / slow disc round the band (stage floor)
const SOLO_R := 0.75  # the disc under the soloist
const SOLO_GOOD := 0.6  # a soloist who hits this share of their solo notes: a GREAT SOLO
const KID_RATE := {"gentle": 0.85, "brave": 0.82, "hard": 0.72}  # the kid model must still hit this share (warped)
## Season -> change weights (fast, slow, solo), the drifting things' colour, a picture, Doodle's line.
const SEASONS := {
	"spring": {"weights": [1.0, 1.2, 1.0], "drift": Color(1.0, 0.72, 0.85), "pic": "daisy", "line": "Spring show!", "name": "spring"},
	"summer": {"weights": [1.2, 0.8, 1.2], "drift": Color(1.0, 0.93, 0.5), "pic": "sunflower", "line": "Summer show!", "name": "summer"},
	"autumn": {"weights": [1.5, 1.0, 0.9], "drift": Color(0.95, 0.5, 0.15), "pic": "acorn", "line": "Autumn show!", "name": "autumn"},
	"winter": {"weights": [0.9, 1.4, 1.0], "drift": Color(1.0, 1.0, 1.0), "pic": "snowflake", "line": "Snowy show!", "name": "winter"},
}
## Doodle's gifts: id, name, picture, a short line, a colour, festival pieces needed.
const GIFTS: Array[Dictionary] = [
	{"id": "bigdrum", "name": "BIG DRUM", "pic": "drum", "line": "Giant drums!", "color": Color(1.0, 0.4, 0.4), "unlock": 0},
	{"id": "shaker", "name": "SHAKER", "pic": "shaker", "line": "Shake shake!", "color": Color(0.45, 0.95, 0.45), "unlock": 0},
	{"id": "goldmic", "name": "GOLD MIC", "pic": "goldmic", "line": "Two new fans!", "color": Color(1.0, 0.82, 0.25), "unlock": 0},
	{"id": "snail", "name": "SLOW SONG", "pic": "snail", "line": "Nice and slow!", "color": Color(0.5, 0.75, 1.0), "unlock": 2},
	{"id": "confetti", "name": "CONFETTI", "pic": "confetti", "line": "Party time!", "color": Color(1.0, 0.5, 0.9), "unlock": 4},
]
const BIGDRUM_WIN := 1.3  # BIG DRUM: the drummer's timing windows
const BIGDRUM_SIZE := 1.35  # ... and the drums' size (and reach)
const SHAKER_WIN := 1.3  # SHAKER: the guitars' timing windows
const SHAKER_DRUM := 1.12  # ... and a little for the drummer
const SNAIL_RATE := 0.88  # SLOW SONG: the whole song
const CONFETTI_EVERY := 8  # CONFETTI: a burst every this many combo
## Doodle's festival: one piece every FEST_EVERY songs.
const FEST_EVERY := 3
const FESTIVAL: Array[String] = ["bunting", "icecream", "balloons", "tent", "lights", "carousel", "ferris", "fireworks"]
const FEST_PICS := {"bunting": "bunting", "icecream": "icecream", "balloons": "balloon", "tent": "tent", "lights": "lantern",
	"carousel": "carousel", "ferris": "ferris", "fireworks": "rocket"}
## Where festival piece i stands (world): left and right of the stage, beside the crowd (seen from the TV views and by
## the drummer looking out), never on the stage, the crowd or the TV cameras' line to the band.
const FEST_SPOTS: Array[Vector3] = [Vector3(-7.0, 0, -1.0), Vector3(7.0, 0, -1.0), Vector3(-7.6, 0, -4.4), Vector3(7.6, 0, -4.4),
	Vector3(-10.5, 0, 0.5), Vector3(10.5, 0, 0.5), Vector3(-11.5, 0, -5.0), Vector3(11.5, 0, -5.0)]
## The pick row: three orbs in front of the drummer (kit-relative: x across, y from the rig, z out from the kit).
const ROW_X: Array[float] = [-0.42, 0.0, 0.42]
## (up from -0.12: a seated player's outer orbs sat on the hi-hat and the crash, core/vr_view_check.gd pick_hidden)
const ROW_Y := -0.02
const ROW_Z := -0.72
const ORB_SCALE := 0.2
const HAND_R := 0.06  # a hand this near an orb's edge is in it
const DWELL := 0.25  # seconds a hand must stay in an orb (a swing through never picks)
const ROW_WAIT := {"mode": 20.0, "gift": 16.0}  # nobody took one: the middle
const SOLO_WAIT := 14.0  # a lone player: sooner


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


static func season_data(s: String) -> Dictionary:
	return SEASONS.get(s, SEASONS.spring)


static func wait_for(stage: String, solo: bool) -> float:
	return SOLO_WAIT if solo else float(ROW_WAIT.get(stage, 16.0))


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	if not (float(g.fast) <= float(b.fast) and float(b.fast) <= float(h.fast)):
		out.append("fast not gentle <= brave <= hard")
	for k in ["win", "every", "warn"]:  # more is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not most on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(h.fast) > MAX_RATE or float(g.slow) < MIN_RATE:
		out.append("speeds out of %.2f..%.2f" % [MIN_RATE, MAX_RATE])
	if float(KID_RATE.gentle) < float(KID_RATE.brave) or float(KID_RATE.brave) < float(KID_RATE.hard):
		out.append("kid model shares not gentle >= brave >= hard")
	return out


## Timing window share for a player (drummer or guitar) with this mode and gift.
static func win_share(mode: String, gift_id: String, drummer: bool) -> float:
	var w := float(mode_data(mode).win)
	if gift_id == "bigdrum" and drummer:
		w *= BIGDRUM_WIN
	elif gift_id == "shaker":
		w *= SHAKER_DRUM if drummer else SHAKER_WIN
	return w


## The whole song's speed share from the gift.
static func base_rate(gift_id: String) -> float:
	return SNAIL_RATE if gift_id == "snail" else 1.0


# --- Changes --------------------------------------------------------------------------------------------------

## A song's bars: [first note bar, last note bar + 1] (Song.COUNT_IN bars of count-in first, OUTRO after).
static func note_bars(code: int, pos: int, bars: int) -> Vector2i:
	var b := maxi(2, bars if bars > 0 else SongGen.bars_for(pos))
	return Vector2i(Song.COUNT_IN, Song.COUNT_IN + b)


## The warned changes of song `code` at show position pos: [{kind, bar, bars, rate, who}] in song order. bar: the
## song bar it starts (count-in included); who: for a solo, an index into spec.band (the players there when the song
## starts: 0 = the drummer, then guitarists' indices) - the host turns it into a player. spec: {mode, season, gift,
## bars (note bars), band: [player indices], from (bots: an earlier song), first (bots: an earlier bar)}.
static func changes(code: int, pos: int, spec: Dictionary) -> Array:
	var out: Array = []
	if pos < int(spec.get("from", FIRST_POS)):
		return out
	var mode := String(spec.get("mode", "brave"))
	var md := mode_data(mode)
	var gift_id := String(spec.get("gift", ""))
	var nb := note_bars(code, pos, int(spec.get("bars", -1)))
	var band: Array = spec.get("band", [0])
	var r := Seeded.rng(Seeded.derive(SongGen.seed_of(code), "changes%d" % pos), mode)
	var weights: Array = (season_data(String(spec.get("season", "spring"))).weights as Array).duplicate()
	if gift_id == "snail":
		weights[0] = 0.0  # SLOW SONG: no fast parts
	var every := int(md.every)
	var first := nb.x + int(spec.get("first", FIRST_BAR))
	var spb := 60.0 / SongGen.song_bpm(code)
	var warn_bars := int(ceil(float(md.warn) / (4.0 * spb * MIN_RATE)))  # (told within the plain bars before)
	var last_end := nb.x - 99
	var solos := 0
	var block := first
	while block < nb.y:
		var b := block + r.randi_range(0, maxi(0, every - PART_BARS - 1))
		b = maxi(b, last_end + maxi(GAP_BARS, warn_bars))
		var w := weights.duplicate()
		if solos > 0:
			w[2] = 0.0  # one spotlight solo a song
		var kind: String = KINDS[Seeded.weighted(r, w)]
		var len_b := SOLO_BARS if kind == "solo" else PART_BARS
		if b + len_b > nb.y:  # (a short song still gets its change: as late as it fits)
			b = maxi(nb.y - len_b, maxi(first, last_end + maxi(GAP_BARS, warn_bars)))
			if b + len_b > nb.y:
				break
		var e := {"kind": kind, "bar": b, "bars": len_b, "rate": 1.0, "who": -1}
		match kind:
			"fast":
				e.rate = float(md.fast)
			"slow":
				e.rate = float(md.slow)
			"solo":
				e.who = r.randi_range(0, maxi(0, band.size() - 1))
				solos += 1
		out.append(e)
		last_end = b + len_b
		block += every
	return out


## Song time (seconds) where bar b starts.
static func bar_t(code: int, b: int) -> float:
	return float(b) * 4.0 * 60.0 / SongGen.song_bpm(code)


## The song clock's speed at song time t (the gift's speed times the part's).
static func rate_at(list: Array, spb: float, t: float, gift_id: String = "") -> float:
	var r := base_rate(gift_id)
	for e in list:
		var a := float(e.bar) * 4.0 * spb
		if t >= a and t < a + float(e.bars) * 4.0 * spb:
			return r * float(e.rate)
	return r


## The change showing at song time t: [entry, phase] (phase "warn" before it starts, "on" while it plays), or [].
static func change_at(list: Array, spb: float, t: float, warn: float) -> Array:
	for e in list:
		var a := float(e.bar) * 4.0 * spb
		var z := a + float(e.bars) * 4.0 * spb
		if t >= a - warn and t < a:
			return [e, "warn"]
		if t >= a and t < z:
			return [e, "on"]
	return []


## Real seconds from the song's start to song time t (the clock runs at rate_at).
static func real_t(list: Array, spb: float, t: float, gift_id: String = "") -> float:
	var base := base_rate(gift_id)
	var out := t / base
	for e in list:
		var a := float(e.bar) * 4.0 * spb
		var z := a + float(e.bars) * 4.0 * spb
		var inside := clampf(t, a, z) - a
		out += inside / (base * float(e.rate)) - inside / base
	return out


## Reasons song code's changes are unfair (empty = fine). Plays the song's EASY guitar and EASY drum charts through the
## kid model with the clock warped and the windows as the game widens them.
static func problems(code: int, pos: int, list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var mode := String(spec.get("mode", "brave"))
	var md := mode_data(mode)
	var gift_id := String(spec.get("gift", ""))
	var nb := note_bars(code, pos, int(spec.get("bars", -1)))
	var spb := 60.0 / SongGen.song_bpm(code)
	var band: Array = spec.get("band", [0])
	if float(md.warn) < MIN_WARN:
		why.append("told only %.1f s early" % float(md.warn))
	var first := nb.x + int(spec.get("first", FIRST_BAR))
	var prev_end := -99
	var solos := 0
	for e in list:
		var kind := String(e.get("kind", ""))
		if not KINDS.has(kind):
			why.append("unknown change %s" % str(e))
			continue
		if pos < int(spec.get("from", FIRST_POS)):
			why.append("a change in song %d" % (pos + 1))
		if int(e.bar) < first:
			why.append("a change at bar %d (before bar %d)" % [int(e.bar), first])
		if int(e.bar) + int(e.bars) > nb.y:
			why.append("a change runs past the last note bar")
		# told for `warn` seconds while the song still plays plain (never told during another change)
		var told_from := bar_t(code, int(e.bar)) - float(md.warn) * base_rate(gift_id)
		if prev_end > -99 and told_from < bar_t(code, prev_end) - 0.001:
			why.append("bar %d is told while the last change still plays" % int(e.bar))
		if told_from < bar_t(code, Song.COUNT_IN) - 4.0 * spb - 0.001:
			why.append("bar %d is told before the song starts" % int(e.bar))
		prev_end = int(e.bar) + int(e.bars)
		var rate := float(e.rate) * base_rate(gift_id)
		if rate > MAX_RATE + 0.001 or rate < MIN_RATE * SNAIL_RATE - 0.001:
			why.append("bar %d plays at %.2f" % [int(e.bar), rate])
		if kind == "fast" and gift_id == "snail":
			why.append("a fast part with the SLOW SONG gift")
		if kind == "solo":
			solos += 1
			if int(e.who) < 0 or int(e.who) >= band.size():
				why.append("a solo for nobody there (%d of %d)" % [int(e.who), band.size()])
	if solos > 1:
		why.append("%d solos in one song" % solos)
	# The kid model on the warped clock.
	var s := SongGen.build(code, pos, nb.y - nb.x, true)
	var share := float(KID_RATE[mode_of(mode)])
	var gts: Array[float] = []
	var gls: Array[int] = []
	for i in s.g_t.size():
		if int(s.g_lvl[i]) == 0:
			gts.append(real_t(list, spb, float(s.g_t[i]), gift_id))
			gls.append(int(s.g_lane[i]))
	var gwin := 0.27 * win_share(mode, gift_id, false)  # (== main.gd WINDOWS[0].y, EASY)
	var g_hit := kid_share(gts, gls, code, gwin, false)
	if not gts.is_empty() and g_hit < share:
		why.append("a small kid hits only %d%% of the guitar notes (%s)" % [int(g_hit * 100.0), mode])
	var dts: Array[float] = []
	var dps: Array[int] = []
	var lvl := SongGen.drum_level_for(pos)
	for i in s.d_t.size():
		if int(s.d_lvl[i]) <= lvl:
			dts.append(real_t(list, spb, float(s.d_t[i]), gift_id))
			dps.append(int(s.d_pad[i]))
	var dwin := (0.27 if lvl == 0 else 0.17) * win_share(mode, gift_id, true)
	var d_hit := kid_share(dts, dps, code, dwin, true)
	if not dts.is_empty() and d_hit < share:
		why.append("a small kid hits only %d%% of the drums (%s)" % [int(d_hit * 100.0), mode])
	return why


## The kid model (songgen.gd kid_guitar / kid_drums) with this window, in real seconds.
static func kid_share(ts: Array[float], ls: Array[int], code: int, window: float, drums: bool) -> float:
	if ts.is_empty():
		return 1.0
	var r := Seeded.rng(code, "kiddrum" if drums else "kid")
	var hit := 0
	if drums:
		var hands: Array[float] = [-10.0, -10.0]
		for i in ts.size():
			var press := ts[i] + r.randf_range(-SongGen.KID_WOBBLE * 0.7, SongGen.KID_WOBBLE * 0.7)
			var h := 0 if hands[0] <= hands[1] else 1
			if press - hands[h] >= SongGen.KID_HAND and absf(press - ts[i]) <= window:
				hit += 1
				hands[h] = press
		return float(hit) / ts.size()
	var last := -10.0
	var last_lane := -1
	for i in ts.size():
		var press := ts[i] + r.randf_range(-SongGen.KID_WOBBLE, SongGen.KID_WOBBLE)
		var need := SongGen.KID_REACT + (SongGen.KID_MOVE if ls[i] != last_lane else 0.0)
		if press - last >= need and absf(press - ts[i]) <= window:
			hit += 1
			last = press
			last_lane = ls[i]
	return float(hit) / ts.size()


static func pack(list: Array) -> Array:
	var out: Array = []
	for e in list:
		out.append([KINDS.find(String(e.kind)), int(e.bar), int(e.bars), float(e.rate), int(e.who)])
	return out


static func unpack(a: Array) -> Array:
	var out: Array = []
	for v in a:
		var x: Array = v
		if x.size() >= 5 and int(x[0]) >= 0 and int(x[0]) < KINDS.size():
			out.append({"kind": KINDS[int(x[0])], "bar": int(x[1]), "bars": int(x[2]), "rate": float(x[3]), "who": int(x[4])})
	return out


# --- Gifts ----------------------------------------------------------------------------------------------------

static func unlocked(pieces: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if pieces >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return {}


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are others
## (the same on every machine for a seed).
static func gift_choices(pieces: int, last: String, seed_value: int) -> Array:
	var un := unlocked(pieces)
	var newest: String = un[un.size() - 1]
	var pool: Array = []
	for id in un:
		if id != newest and (id != last or un.size() <= 3):
			pool.append(id)
	pool = Seeded.shuffled(Seeded.rng(seed_value, "gifts"), pool)
	var out: Array = [newest] if newest != last or un.size() <= 3 else []
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	if out.size() < 3:
		for id in un:
			if out.size() < 3 and not out.has(id):
				out.append(id)
	return Seeded.shuffled(Seeded.rng(seed_value, "gift order"), out)


# --- Doodle's festival ----------------------------------------------------------------------------------------

static func festival(songs: int) -> int:
	return mini(FESTIVAL.size(), maxi(0, songs) / FEST_EVERY)


# --- The pick row ---------------------------------------------------------------------------------------------

## The orbs' places, kit-relative (the drummer's rig turns them into the world).
static func row_local(n: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var x: float = ROW_X[i] if n == 3 else (i - (n - 1) * 0.5) * 0.42
		out.append(Vector3(x, ROW_Y, ROW_Z))
	return out


## How near a hand must come to an orb's middle to be in it.
static func reach_r() -> float:
	return PickOrbs.BALL_R * ORB_SCALE + HAND_R
