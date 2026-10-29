extends RefCounted
## RHYTHM BAND generator: every song is made from a SEED, so the same seed gives the same song on every
## machine (the host sends one int "song code" per song; TV machines and Decks rebuild the whole song),
## and tests/rhythm_band_gen_test.gd proves over many seeds that every song can be played by small kids.
##   var d := SongGen.song(seed, level, daily)   # {seed, level, daily, code, name, bpm, key, prog, style, busy}
##   var s := SongGen.build(code, pos)           # the Song (song.gd) for show position pos (0 = warm-up)
##   SongGen.check(code, pos) -> Array of reasons (empty = a small kid can play it)
## Story: DOODLE the frog sings with the band from the top of the speaker stack. Every song the band
## finishes brings a new animal FAN to the FAN CLUB stands beside the stage (saved): fans grow a little
## each day the family plays, and the TODAY'S SONG fans are golden. TODAY'S SONG: the second song of the
## first show each day (after the two-lane warm-up) is the same song on every machine all day.
## The show gets gently harder song by song (level_for(pos)): faster tempos, busier drums, more styles.
## A song code packs (seed, level, daily) in one int: ((seed * 8 + level) * 2 + daily).

const Seeded := preload("res://core/seeded.gd")
const Song := preload("res://games/rhythm_band/song.gd")

const GAME_ID := "rhythm_band"
const MAX_LEVEL := 6
const DAILY_LEVEL := 2
const DAILY_POS := 1  # TODAY'S SONG: the second song (song 1 is the two-lane warm-up)
const SIMPLE_BARS: Array[int] = [12, 16, 20, 24]  # == main.gd: bars of notes for songs 1, 2, 3, 4+
const STYLES: Array[String] = ["pop", "stomp", "bongo", "rock", "disco"]
## Style weights per level (pop, stomp, bongo, rock, disco): warm-ups are bouncy and stompy, rock and disco
## come in as the band gets going.
const STYLE_W: Array = [[4, 3, 2, 0, 0], [3, 3, 3, 1, 1], [2, 2, 3, 2, 2], [2, 1, 2, 3, 3], [1, 1, 2, 3, 3], [1, 1, 1, 3, 3]]
const STYLE_PICS := {"pop": "musicnote", "stomp": "dino", "bongo": "bongos", "rock": "guitar", "disco": "discoball"}
const STYLE_COLORS := {"pop": Color(1.0, 0.55, 0.75), "stomp": Color(0.45, 0.85, 0.35), "bongo": Color(1.0, 0.65, 0.25),
	"rock": Color(0.95, 0.3, 0.3), "disco": Color(0.6, 0.5, 1.0)}
## Tempo range (beats per minute) per level: slow and steady for little hands, faster later.
const BPM: Array[Vector2] = [Vector2(78, 88), Vector2(84, 96), Vector2(90, 104), Vector2(96, 112), Vector2(102, 120), Vector2(108, 128)]
const KEYS: Array[int] = [52, 55, 57, 60, 62]
## Chord progressions (2 bars per chord): [root offset, minor?] x4. All happy-sounding pop shapes.
const PROGS: Array = [
	[[0, false], [7, false], [9, true], [5, false]],
	[[0, true], [8, false], [5, true], [7, false]],
	[[0, false], [5, false], [7, false], [5, false]],
	[[9, true], [5, false], [0, false], [7, false]],
	[[0, true], [5, true], [10, false], [3, false]],
	[[0, true], [8, false], [3, false], [10, false]],
	[[0, false], [9, true], [5, false], [7, false]],
	[[0, false], [5, false], [9, true], [7, false]],
]
## Song names: a friendly word + a fun thing (kids' words only).
const ADJ: Array[String] = ["Sunny", "Bouncy", "Happy", "Sparkly", "Wiggly", "Jolly", "Fizzy", "Giggly", "Twinkly", "Zippy",
	"Rainbow", "Snappy", "Cosy", "Funky", "Groovy", "Dizzy", "Cheeky", "Golden", "Silly", "Starry", "Jumpy", "Tiptoe"]
const NOUN: Array[String] = ["Skip", "Stomp", "Banana", "Rocket", "Bubble", "Dino", "Jelly", "Puddle", "Monkey", "Teapot",
	"Moon", "Pancake", "Robot", "Kitten", "Dragon", "Disco", "Boogie", "Parade", "Popcorn", "Dance", "Froggy", "Muffin"]

# --- Kid play model (the validator) ---
const KID_GAP := 0.85  # EASY guitar notes are at least this far apart (seconds)
const KID_WINDOW := 0.27  # == main.gd WINDOWS[0].y: an EASY press counts within this
const KID_WOBBLE := 0.14  # a small kid presses up to this early / late
const KID_REACT := 0.4  # a small kid needs this long between presses (a lane change: + KID_MOVE)
const KID_MOVE := 0.2
const KID_HAND := 0.36  # a VR drummer's hand needs this long between its own hits (two hands)
const KID_GUITAR_RATE := 0.9  # the kid model must hit at least this share of EASY guitar notes
const KID_DRUM_RATE := 0.85  # ... and of the drums at the drummer's level
const MAX_EASY_PER_SEC := 1.2
const MAX_SECS: Array[float] = [52.0, 60.0, 70.0, 80.0]  # a song is never longer than this (songs 1, 2, 3, 4+)

# --- Fan club (the growth that stays) ---
const FAN_KINDS: Array[String] = ["bunny", "puppy", "penguin", "polarbear", "toucan", "sheep"]
const FAN_SLOTS := 24  # two stands of three rows of four
const FAN_KEEP := 24
const FAN_STAGES := 3  # fans grow a stage a day: 0 little, 1, 2 big with a glow stick
const STAND_X := 5.35  # == stage.gd edge 4.7 + a gap
const ROW_STEP := Vector2(0.62, 0.36)  # each row further out and higher
const SEAT_Z: Array[float] = [-2.4, -1.65, -0.9, -0.15]
const DOODLE_POS := Vector3(-4.3, 3.05, -1.6)  # on top of the left speaker stack (stage.gd)


static func code_of(seed_value: int, level: int, daily: bool) -> int:
	return (posmod(seed_value, Seeded.SEED_MAX) * 8 + clampi(level, 1, MAX_LEVEL)) * 2 + (1 if daily else 0)


static func seed_of(code: int) -> int:
	return (code / 2) / 8


static func level_of(code: int) -> int:
	return clampi((code / 2) % 8, 1, MAX_LEVEL)


static func daily_of(code: int) -> bool:
	return code % 2 == 1


## The song for (seed, level): tempo, key, chords, style and its name.
static func song(seed_value: int, level: int, daily: bool = false) -> Dictionary:
	level = clampi(level, 1, MAX_LEVEL)
	var r := Seeded.rng(seed_value, "song%d" % level)
	var range_v: Vector2 = BPM[level - 1]
	var bpm := float(roundi(r.randf_range(range_v.x, range_v.y)))
	var style: String = STYLES[Seeded.weighted(r, STYLE_W[level - 1])]
	var prog: Array = (PROGS[r.randi() % PROGS.size()] as Array).duplicate(true)
	var key: int = KEYS[r.randi() % KEYS.size()]
	var adj: String = ADJ[r.randi() % ADJ.size()]
	var noun: String = NOUN[r.randi() % NOUN.size()]
	return {"seed": seed_value, "level": level, "daily": daily, "code": code_of(seed_value, level, daily),
		"name": adj + " " + noun, "bpm": bpm, "key": key, "prog": prog, "style": style,
		"busy": clampi((level - 1) / 2, 0, 2)}


static func from_code(code: int) -> Dictionary:
	return song(seed_of(code), level_of(code), daily_of(code))


static func song_name(code: int) -> String:
	return str(from_code(code).name)


static func song_bpm(code: int) -> float:
	return float(from_code(code).bpm)


## How hard song `pos` of a show is (0 = the warm-up): 1, 2, 3, then up one every two songs.
static func level_for(pos: int) -> int:
	if pos < 3:
		return pos + 1
	return mini(MAX_LEVEL, 3 + (pos - 1) / 2)


## The drummer's level for song `pos` (== main.gd simple mode): EASY for the first two, NORMAL after.
static func drum_level_for(pos: int) -> int:
	return 0 if pos < 2 else 1


static func bars_for(pos: int) -> int:
	return SIMPLE_BARS[clampi(pos, 0, SIMPLE_BARS.size() - 1)]


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


static func round_seed(session_seed: int, pos: int) -> int:
	return Seeded.derive(session_seed, "song%d" % pos)


## The code of song `pos` in a show: TODAY'S SONG at DAILY_POS when it's still due today.
static func code_at(session_seed: int, pos: int, daily_due: bool, date: String = "") -> int:
	if daily_due and pos == DAILY_POS:
		return code_of(daily_seed(date), DAILY_LEVEL, true)
	return code_of(round_seed(session_seed, pos), level_for(pos), false)


## The first three songs of a show (more are added as the show goes on).
static func setlist(session_seed: int, daily_due: bool) -> Array[int]:
	var out: Array[int] = []
	for pos in 3:
		out.append(code_at(session_seed, pos, daily_due))
	return out


## The SETLIST menu tour (not simple mode): a slow, a middle and a fast song.
static func make_setlist(rng_seed: int) -> Array[int]:
	var out: Array[int] = []
	for k in 3:
		out.append(code_of(Seeded.derive(rng_seed, k), 1 + k * 2, false))
	return out


## The Song for `code`, set up the way the show plays it at position `pos` (simple mode: no gold notes,
## song 1 with only the outer lanes). bars < 0: the simple-mode length for pos.
static func build(code: int, pos: int, bars: int = -1, simple: bool = true) -> Song:
	var s := Song.new()
	if simple:
		s.no_stars = true
		s.two_lanes = pos == 0
	s.setup_desc(from_code(code), bars if bars > 0 else bars_for(pos))
	return s


## Which animal fan a finished song brings (the same on every machine).
static func fan_kind(code: int, fans_total: int) -> int:
	return (Seeded.rng(seed_of(code), "fan%d" % fans_total).randi() + fans_total) % FAN_KINDS.size()


## Where fan number i stands: the FAN CLUB stands left and right of the stage, three rows each, the front
## rows filling first. Returns the position (Vector3.INF past the end).
static func fan_slot(i: int) -> Vector3:
	if i < 0 or i >= FAN_SLOTS:
		return Vector3.INF
	var side := -1.0 if i % 2 == 0 else 1.0
	var k := i / 2
	var row := k / SEAT_Z.size()
	var seat := k % SEAT_Z.size()
	return Vector3(side * (STAND_X + row * ROW_STEP.x), 0.25 + row * ROW_STEP.y, SEAT_Z[seat])


## A fan's size stage: one more for each day the family has played since it joined.
static func fan_stage(joined_day: int, days: int) -> int:
	return clampi(days - joined_day, 0, FAN_STAGES - 1)


# --- The validator --------------------------------------------------------------------------

## Why this song is NOT fine for small kids at show position `pos` (empty = fine).
static func check(code: int, pos: int) -> Array:
	var why: Array = []
	var d := from_code(code)
	var lv := int(d.level)
	var rng_v: Vector2 = BPM[lv - 1]
	var max_lv := DAILY_LEVEL if bool(d.daily) else level_for(pos)
	if bool(d.daily) and pos != DAILY_POS:
		why.append("TODAY'S SONG at song %d (it is song %d)" % [pos + 1, DAILY_POS + 1])
	if lv > max_lv:
		why.append("level %d is too hard for song %d (at most %d)" % [lv, pos + 1, max_lv])
	if float(d.bpm) < rng_v.x or float(d.bpm) > rng_v.y or float(d.bpm) > 128.0:
		why.append("tempo %d out of range for level %d" % [int(d.bpm), lv])
	var name_parts := str(d.name).split(" ")
	if name_parts.size() != 2 or not ADJ.has(name_parts[0]) or not NOUN.has(name_parts[1]) or str(d.name).length() > 16:
		why.append("song name '%s' not from the kids' word lists" % str(d.name))
	if not STYLES.has(str(d.style)) or not STYLE_PICS.has(str(d.style)):
		why.append("unknown style %s" % str(d.style))
	var s := build(code, pos)
	var spb: float = s.spb
	var first_t := Song.COUNT_IN * 4.0 * spb - 0.01
	if s.length > MAX_SECS[mini(pos, MAX_SECS.size() - 1)]:
		why.append("song %d too long (%.0f s)" % [pos + 1, s.length])
	# Guitar: what a small kid sees on EASY.
	var easy_t: Array[float] = []
	var easy_lane: Array[int] = []
	var lanes := {}
	for i in s.g_t.size():
		var t: float = s.g_t[i]
		var ln := int(s.g_lane[i])
		if ln < 0 or ln > 2:
			why.append("guitar note in lane %d" % ln)
		if t < first_t or t > s.length - spb:
			why.append("guitar note at %.2f s outside the song (%.2f..%.2f)" % [t, first_t, s.length - spb])
		if int(s.g_star[i]) != 0:
			why.append("a gold note in simple mode")
		if s.g_pitch[i] < 48 or s.g_pitch[i] > 92:
			why.append("pitch %d too low / high" % s.g_pitch[i])
		if pos == 0 and ln == 1:
			why.append("a middle-lane note in the two-lane warm-up")
		if int(s.g_lvl[i]) == 0:
			if not easy_t.is_empty() and t - easy_t[-1] < KID_GAP:
				why.append("EASY notes only %.2f s apart at %.2f s" % [t - easy_t[-1], t])
			easy_t.append(t)
			easy_lane.append(ln)
			lanes[ln] = true
	var bars := int(s.bars)
	if easy_t.size() < bars:
		why.append("only %d EASY notes in %d bars" % [easy_t.size(), bars])
	var play_secs := bars * 4.0 * spb
	if easy_t.size() / play_secs > MAX_EASY_PER_SEC:
		why.append("EASY too busy (%.2f notes a second)" % (easy_t.size() / play_secs))
	if lanes.size() < 2:
		why.append("EASY uses only %d lane(s)" % lanes.size())
	var g_rate := kid_guitar(easy_t, easy_lane, code)
	if g_rate < KID_GUITAR_RATE:
		why.append("a small kid hits only %d%% of the EASY guitar" % int(g_rate * 100.0))
	# Drums at the level the drummer plays at this point of the show.
	var dl := drum_level_for(pos)
	var dt: Array[float] = []
	var dp: Array[int] = []
	for i in s.d_t.size():
		var t2: float = s.d_t[i]
		if int(s.d_pad[i]) < 0 or int(s.d_pad[i]) > 3:
			why.append("drum note on pad %d" % int(s.d_pad[i]))
		if t2 < first_t or t2 > s.length - spb:
			why.append("drum note at %.2f s outside the song" % t2)
		if int(s.d_star[i]) != 0:
			why.append("a gold drum in simple mode")
		if int(s.d_lvl[i]) <= dl:
			if not dt.is_empty() and t2 - dt[-1] < 0.05:
				why.append("two drums at once at %.2f s" % t2)
			dt.append(t2)
			dp.append(int(s.d_pad[i]))
	if dt.size() < bars * 2:
		why.append("only %d drum notes at level %d" % [dt.size(), dl])
	var d_rate := kid_drums(dt, dp, code)
	if d_rate < KID_DRUM_RATE:
		why.append("a small VR drummer hits only %d%% of the drums" % int(d_rate * 100.0))
	return why


## The kid model on guitar: presses each EASY note a little early or late, needs KID_REACT between
## presses (+ KID_MOVE to change lane). Returns the share of notes hit.
static func kid_guitar(ts: Array[float], ls: Array[int], code: int) -> float:
	if ts.is_empty():
		return 0.0
	var r := Seeded.rng(code, "kid")
	var last := -10.0
	var last_lane := -1
	var hit := 0
	for i in ts.size():
		var press := ts[i] + r.randf_range(-KID_WOBBLE, KID_WOBBLE)
		var need := KID_REACT + (KID_MOVE if ls[i] != last_lane else 0.0)
		if press - last >= need and absf(press - ts[i]) <= KID_WINDOW:
			hit += 1
			last = press
			last_lane = ls[i]
	return float(hit) / ts.size()


## The kid model on the VR drums: two hands, each needs KID_HAND between its own hits; the free hand
## nearer in time takes the note. Returns the share hit.
static func kid_drums(ts: Array[float], pads: Array[int], code: int) -> float:
	if ts.is_empty():
		return 0.0
	var r := Seeded.rng(code, "kiddrum")
	var hands: Array[float] = [-10.0, -10.0]
	var hit := 0
	for i in ts.size():
		var press := ts[i] + r.randf_range(-KID_WOBBLE * 0.7, KID_WOBBLE * 0.7)
		var h := 0 if hands[0] <= hands[1] else 1
		if press - hands[h] >= KID_HAND:
			hit += 1
			hands[h] = press
	return float(hit) / ts.size()
