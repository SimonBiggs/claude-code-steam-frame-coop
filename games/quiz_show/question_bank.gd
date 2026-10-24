extends RefCounted
## QuestionBank: every quiz question in one place, plus the rules for picking them.
## - Multiple choice (bank_a/b/c.gd): 13 categories x 3 tiers (1 KIDS, 2 FAMILY, 3 BRAINIACS).
## - LIGHTNING true/false statements (bank_tf.gd) and PICTURE round items (pictures.gd).
## - Never repeats a question within a show, and avoids the questions used in recent shows (the host
##   passes the saved recent ids in; see main.gd / core/save.gd). Ids are hashes of the text, so they
##   stay valid when questions are added or reordered.
## - validate() checks the whole bank (the bot runs it): no duplicates, four distinct answers with
##   exactly one correct, every category has every tier, at least MIN_QUESTIONS questions.
## Host only: TV machines never need the bank (the question text arrives through the state store).

const BankA := preload("res://games/quiz_show/bank_a.gd")
const BankB := preload("res://games/quiz_show/bank_b.gd")
const BankC := preload("res://games/quiz_show/bank_c.gd")
const BankTF := preload("res://games/quiz_show/bank_tf.gd")
const Pictures := preload("res://games/quiz_show/pictures.gd")

const MIN_QUESTIONS := 400
const CATEGORIES: Array[String] = ["ANIMALS", "SPACE", "FOOD", "COLOURS & SHAPES", "NUMBERS", "GEOGRAPHY",
	"SPORTS", "MUSIC", "NATURE", "INVENTIONS", "FAIRY TALES", "VIDEO GAMES", "SILLY OR TRUE?"]
## Category colours and UiKit icon kinds (TV badges, the video wall, the category board).
const CATEGORY_STYLE := {
	"ANIMALS": [Color(0.55, 0.85, 0.35), "heart"], "SPACE": [Color(0.55, 0.5, 1.0), "star"],
	"FOOD": [Color(1.0, 0.6, 0.3), "potion"], "COLOURS & SHAPES": [Color(1.0, 0.45, 0.75), "gem"],
	"NUMBERS": [Color(0.4, 0.75, 1.0), "plus"], "GEOGRAPHY": [Color(0.3, 0.8, 0.7), "flag"],
	"SPORTS": [Color(1.0, 0.8, 0.25), "trophy"], "MUSIC": [Color(0.85, 0.5, 1.0), "music"],
	"NATURE": [Color(0.45, 0.85, 0.45), "drop"], "INVENTIONS": [Color(0.95, 0.9, 0.4), "bolt"],
	"FAIRY TALES": [Color(1.0, 0.6, 0.85), "crown"], "VIDEO GAMES": [Color(0.4, 0.95, 0.85), "play"],
	"SILLY OR TRUE?": [Color(1.0, 0.5, 0.4), "question"],
	"PICTURE": [Color(0.5, 0.9, 1.0), "eye"], "TRUE OR FALSE": [Color(1.0, 0.85, 0.3), "bolt"],
}

var mc: Array = []          ## [{id, cat, tier, text, answers: [correct, w1, w2, w3]}]
var tf: Array = []          ## [{id, tier, text, truth}]
var used := {}              ## ids asked in this show
var recent := {}            ## ids asked in recent shows (avoided while there are other questions)
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()
	for part in [BankA.DATA, BankB.DATA, BankC.DATA]:
		var d: Dictionary = part
		for cat in d:
			for row in d[cat]:
				var r: Array = row
				var answers: Array[String] = [String(r[2]), String(r[3]), String(r[4]), String(r[5])]
				mc.append({"id": id_of(String(r[1])), "cat": String(cat), "tier": int(r[0]), "text": String(r[1]), "answers": answers})
	for row in BankTF.DATA:
		var r2: Array = row
		tf.append({"id": id_of(String(r2[1])), "tier": int(r2[0]), "text": String(r2[1]), "truth": bool(r2[2])})


## Stable id for a question (its text).
static func id_of(text: String) -> int:
	return text.strip_edges().to_lower().hash()


## Colour of a category (or the picture / true-false pseudo categories).
static func category_color(cat: String) -> Color:
	var st: Array = CATEGORY_STYLE.get(cat, [Color(1.0, 0.8, 0.3), "question"])
	return st[0]


static func category_icon(cat: String) -> String:
	var st: Array = CATEGORY_STYLE.get(cat, [Color(1.0, 0.8, 0.3), "question"])
	return String(st[1])


## Forget which questions this show used (a new show), and take the recent-show ids to avoid.
func new_show(recent_ids: Array) -> void:
	used.clear()
	recent.clear()
	for i in recent_ids:
		recent[int(i)] = true


## A multiple-choice question of `cat` ("" = any category) at `tier` (falls back to neighbouring
## tiers if that pool is used up), ready to ask: {id, cat, tier, text, answers (shuffled), correct}.
func pick_mc(cat: String, tier: int, exclude_cats: Array = []) -> Dictionary:
	var tiers: Array[int] = [tier, tier - 1, tier + 1, tier - 2, tier + 2]
	for avoid_recent in [true, false]:
		for t in tiers:
			if t < 1 or t > 3:
				continue
			var cands: Array = []
			for q in mc:
				var qd: Dictionary = q
				if int(qd.tier) != t or used.has(int(qd.id)):
					continue
				if cat != "" and String(qd.cat) != cat:
					continue
				if cat == "" and exclude_cats.has(String(qd.cat)):
					continue
				if bool(avoid_recent) and recent.has(int(qd.id)):
					continue
				cands.append(qd)
			if not cands.is_empty():
				return _present(cands[rng.randi() % cands.size()])
	# everything used up (a very long session): start over within this show
	if used.is_empty():
		return _present(mc[rng.randi() % mc.size()])
	used.clear()
	return pick_mc(cat, tier, exclude_cats)


func _present(q: Dictionary) -> Dictionary:
	used[int(q.id)] = true
	var order: Array[int] = [0, 1, 2, 3]
	_shuffle(order)
	var answers: Array[String] = []
	var src: Array = q.answers
	for i in order:
		answers.append(String(src[i]))
	return {"id": int(q.id), "cat": String(q.cat), "tier": int(q.tier), "text": String(q.text),
		"answers": answers, "correct": order.find(0)}


## A true/false statement at `tier`: {id, tier, text, answers ["TRUE", "FALSE"], correct (0 = true)}.
func pick_tf(tier: int) -> Dictionary:
	var tiers: Array[int] = [tier, tier - 1, tier + 1, tier - 2, tier + 2]
	for avoid_recent in [true, false]:
		for t in tiers:
			if t < 1 or t > 3:
				continue
			var cands: Array = []
			for s in tf:
				var sd: Dictionary = s
				if int(sd.tier) == t and not used.has(int(sd.id)) and not (bool(avoid_recent) and recent.has(int(sd.id))):
					cands.append(sd)
			if not cands.is_empty():
				var pick: Dictionary = cands[rng.randi() % cands.size()]
				used[int(pick.id)] = true
				var ans: Array[String] = ["TRUE", "FALSE"]
				return {"id": int(pick.id), "cat": "TRUE OR FALSE", "tier": int(pick.tier), "text": String(pick.text),
					"answers": ans, "correct": 0 if bool(pick.truth) else 1}
	if used.is_empty():
		return {"id": 0, "cat": "TRUE OR FALSE", "tier": 1, "text": "Quiz shows are fun.", "answers": ["TRUE", "FALSE"], "correct": 0}
	used.clear()
	return pick_tf(tier)


## A picture for the PICTURE round at most `tier` hard (prefers exactly that tier):
## {id (hash), pic (item id), cat "PICTURE", tier, text, answers (shuffled), correct}.
func pick_picture(tier: int) -> Dictionary:
	for avoid_recent in [true, false]:
		for exact in [true, false]:
			var cands: Array = []
			for it in Pictures.ITEMS:
				var row: Array = it
				var pid := id_of("pic:" + String(row[0]))
				if used.has(pid) or (bool(avoid_recent) and recent.has(pid)):
					continue
				if (bool(exact) and int(row[1]) != tier) or int(row[1]) > maxi(tier, 1):
					continue
				cands.append(row)
			if not cands.is_empty():
				var pick: Array = cands[rng.randi() % cands.size()]
				var pid2 := id_of("pic:" + String(pick[0]))
				used[pid2] = true
				var wrong := Pictures.decoys(String(pick[0]), rng)
				var src: Array[String] = [String(pick[3])]
				src.append_array(wrong)
				while src.size() < 4:
					src.append("Something else %d" % src.size())
				var order: Array[int] = [0, 1, 2, 3]
				_shuffle(order)
				var answers: Array[String] = []
				for i in order:
					answers.append(src[i])
				return {"id": pid2, "pic": String(pick[0]), "cat": "PICTURE", "tier": int(pick[1]),
					"text": String(Pictures.QUESTIONS.get(String(pick[2]), "What is this?")), "answers": answers,
					"correct": order.find(0), "group": String(pick[2])}
	if used.is_empty():
		return {}
	used.clear()
	return pick_picture(tier)


## A random category (for warm-up questions and the final), avoiding `avoid` when possible.
func random_category(avoid: Array = []) -> String:
	var pool: Array[String] = []
	for c in CATEGORIES:
		if not avoid.has(c):
			pool.append(c)
	if pool.is_empty():
		return CATEGORIES[rng.randi() % CATEGORIES.size()]
	return pool[rng.randi() % pool.size()]


func _shuffle(a: Array[int]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


func _shuffle_s(a: Array[String]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


## Check the whole bank. Returns {errors: [String], mc: n, tf: n, pictures: n, per_category: {cat: [t1, t2, t3]}}.
static func validate() -> Dictionary:
	var errors: Array[String] = []
	var seen := {}
	var per := {}
	var count := 0
	for part in [BankA.DATA, BankB.DATA, BankC.DATA]:
		var d: Dictionary = part
		for cat in d:
			if not CATEGORIES.has(String(cat)):
				errors.append("unknown category %s" % cat)
			var tiers: Array[int] = [0, 0, 0]
			for row in d[cat]:
				var r: Array = row
				count += 1
				if r.size() != 6:
					errors.append("%s: entry with %d fields: %s" % [cat, r.size(), str(r)])
					continue
				var tier := int(r[0])
				var text := String(r[1]).strip_edges()
				if tier < 1 or tier > 3:
					errors.append("%s: bad tier %d for '%s'" % [cat, tier, text])
				else:
					tiers[tier - 1] += 1
				if text == "":
					errors.append("%s: empty question" % cat)
				var key := text.to_lower()
				if seen.has(key):
					errors.append("duplicate question: '%s' (%s and %s)" % [text, seen[key], cat])
				seen[key] = String(cat)
				var answers: Array[String] = []
				var low: Array[String] = []
				for k in range(2, 6):
					var a := String(r[k]).strip_edges()
					answers.append(a)
					if a == "":
						errors.append("%s: empty answer in '%s'" % [cat, text])
					if low.has(a.to_lower()):
						errors.append("%s: answers not distinct in '%s'" % [cat, text])
					low.append(a.to_lower())
				var correct_count := 0
				for a in answers:
					if a == answers[0]:
						correct_count += 1
				if correct_count != 1:
					errors.append("%s: correct answer is not unique in '%s'" % [cat, text])
				if text.length() > 70:
					errors.append("%s: question too long to read aloud (%d chars): '%s'" % [cat, text.length(), text])
				for a in answers:
					if a.length() > 36:
						errors.append("%s: answer too long for a tile: '%s'" % [cat, a])
			per[String(cat)] = tiers
	for c in CATEGORIES:
		var t: Array = per.get(c, [0, 0, 0])
		for i in 3:
			if int(t[i]) < 4:
				errors.append("%s has only %d tier-%d questions" % [c, int(t[i]), i + 1])
	if count < MIN_QUESTIONS:
		errors.append("only %d multiple-choice questions (want %d)" % [count, MIN_QUESTIONS])
	# true / false
	var tf_tiers: Array[int] = [0, 0, 0]
	var tf_seen := {}
	for row in BankTF.DATA:
		var r2: Array = row
		var s := String(r2[1]).strip_edges().to_lower()
		if tf_seen.has(s):
			errors.append("duplicate true/false statement: '%s'" % r2[1])
		tf_seen[s] = true
		if seen.has(s):
			errors.append("true/false statement repeats a question: '%s'" % r2[1])
		var tt := int(r2[0])
		if tt >= 1 and tt <= 3:
			tf_tiers[tt - 1] += 1
		else:
			errors.append("true/false bad tier: '%s'" % r2[1])
		if not (r2[2] is bool):
			errors.append("true/false answer is not a bool: '%s'" % r2[1])
	for i in 3:
		if tf_tiers[i] < 8:
			errors.append("only %d tier-%d true/false statements" % [tf_tiers[i], i + 1])
	# pictures
	var pic_seen := {}
	var pic_groups := {}
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	for it in Pictures.ITEMS:
		var row2: Array = it
		var pid := String(row2[0])
		if pic_seen.has(pid):
			errors.append("duplicate picture id %s" % pid)
		pic_seen[pid] = true
		pic_groups[String(row2[2])] = int(pic_groups.get(String(row2[2]), 0)) + 1
		if String(row2[2]) == "flag" and not Pictures.FLAGS.has(pid):
			errors.append("flag %s has no look" % pid)
		var dec := Pictures.decoys(pid, rng2)
		if dec.size() < 3 or dec.has(String(row2[3])):
			errors.append("picture %s has bad decoys %s" % [pid, str(dec)])
	for t2 in [1, 2]:
		if Pictures.pool(t2).size() < 6:
			errors.append("too few tier-%d pictures" % t2)
	return {"errors": errors, "mc": count, "tf": BankTF.DATA.size(), "pictures": Pictures.ITEMS.size(), "per_category": per}
