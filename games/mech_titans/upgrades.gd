extends RefCounted
## MECH TITANS mech upgrades: between made rounds three glowing UPGRADE PODS land in front of the Titan
## (picks.gd). Walk the Titan into one (or punch it, or fly / drive a support vehicle through it) and the
## Titan keeps that power for the rest of the session. New upgrades unlock for good as the Kaiju Sanctuary
## grows (sanctuary.gd hearts). Effects live in main.gd / combat.gd / mech.gd (has_upg(id)).
##   SUPER PUNCH   punches hit half again as hard
##   MEGA BEAM     the chest beam is much stronger
##   TURBO LEGS    the Titan walks faster
##   ROCKET FISTS  a punch that misses flies on as a rocket fist to the kaiju ahead
##   REPAIR BOTS   armour mends by itself; a knock-down is over twice as fast
##   STUN STOMP    the Titan's footsteps make nearby kaiju dizzy
##   MAGNET HAND   kaiju nearby get pulled in towards the Titan's fists
##   SHIELD DOME   a bubble round the Titan pops instead of the next hit (comes back after a while)
##   JUMP JETS     the dash is a big jump that lands with a shockwave
##   BUDDY DRONE   a little drone flies round the Titan and zaps the kaiju
## Pure data so tests/mech_titans_rounds_test.gd can prove every offer is fair (check_offer).

## id, name (2 words at most: the pod's label and the story card), icon (UiKit icon for the pod's picture),
## color, hearts: Kaiju Sanctuary hearts to unlock it.
const LIST: Array[Dictionary] = [
	{"id": "power", "name": "SUPER PUNCH", "icon": "star", "color": Color(1.0, 0.55, 0.25), "hearts": 0},
	{"id": "beam", "name": "MEGA BEAM", "icon": "bolt", "color": Color(0.4, 0.9, 1.0), "hearts": 0},
	{"id": "legs", "name": "TURBO LEGS", "icon": "stamina", "color": Color(0.45, 1.0, 0.5), "hearts": 0},
	{"id": "rocket", "name": "ROCKET FISTS", "icon": "fire", "color": Color(1.0, 0.35, 0.3), "hearts": 0},
	{"id": "repair", "name": "REPAIR BOTS", "icon": "plus", "color": Color(0.5, 1.0, 0.7), "hearts": 0},
	{"id": "stomp", "name": "STUN STOMP", "icon": "dot", "color": Color(0.85, 0.7, 1.0), "hearts": 4},
	{"id": "magnet", "name": "MAGNET HAND", "icon": "coin", "color": Color(1.0, 0.3, 0.45), "hearts": 9},
	{"id": "dome", "name": "SHIELD DOME", "icon": "shield", "color": Color(0.5, 0.75, 1.0), "hearts": 15},
	{"id": "jets", "name": "JUMP JETS", "icon": "arrow_up", "color": Color(1.0, 0.8, 0.3), "hearts": 22},
	{"id": "buddy", "name": "BUDDY DRONE", "icon": "heart", "color": Color(0.6, 1.0, 0.95), "hearts": 32},
]
const OFFER := 3  ## pods on the ground
const MIN_OFFER := 2  ## at least this many when that many are left to take
## Numbers the effects use (main.gd / combat.gd).
const PUNCH_MULT := 1.5
const BEAM_MULT := 1.6
const LEGS_MULT := 1.35
const ROCKET_RANGE := 70.0
const ROCKET_DMG := 26.0
const REPAIR_PER_S := 7.0
const STOMP_R := 11.0
const STOMP_STUN := 14.0
const MAGNET_R := 40.0
const MAGNET_SPEED := 2.2
const DOME_COOLDOWN := 12.0
const JETS_R := 11.0
const JETS_DMG := 32.0
const BUDDY_R := 45.0
const BUDDY_EVERY := 1.1
const BUDDY_DMG := 8.0


static func count() -> int:
	return LIST.size()


static func index_of(id: String) -> int:
	for i in LIST.size():
		if String(LIST[i]["id"]) == id:
			return i
	return -1


static func info(id: String) -> Dictionary:
	var i := index_of(id)
	return LIST[i] if i >= 0 else {}


## Upgrades the family has unlocked with this many sanctuary hearts.
static func unlocked(hearts: int) -> Array:
	var out: Array = []
	for u in LIST:
		if hearts >= int(u["hearts"]):
			out.append(String(u["id"]))
	return out


## The next upgrade still to unlock ({} when every one is out).
static func next_unlock(hearts: int) -> Dictionary:
	for u in LIST:
		if hearts < int(u["hearts"]):
			return u
	return {}


## The pods after round `round_i` of session `run_seed`: up to OFFER different unlocked upgrades the Titan
## hasn't got yet. Seeded: every machine, every retry, the same pods.
static func offer(run_seed: int, round_i: int, unlocked_ids: Array, have: Array) -> Array:
	var pool: Array = []
	for u in LIST:
		var id := String(u["id"])
		if unlocked_ids.has(id) and not have.has(id):
			pool.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, round_i, "titan_upgrades"])
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, mini(OFFER, pool.size()))


## "" when the offer is fair, else what's wrong (every seed, every unlock level, every set already taken).
static func check_offer(o: Array, unlocked_ids: Array, have: Array) -> String:
	var takeable := 0
	for u in LIST:
		if unlocked_ids.has(String(u["id"])) and not have.has(String(u["id"])):
			takeable += 1
	if o.size() > OFFER:
		return "%d pods" % o.size()
	if o.size() < mini(MIN_OFFER, takeable):
		return "only %d pods while %d could be taken" % [o.size(), takeable]
	var seen := {}
	for id in o:
		if seen.has(id):
			return "%s twice" % id
		seen[id] = true
		if index_of(String(id)) < 0:
			return "unknown upgrade %s" % id
		if not unlocked_ids.has(id):
			return "%s isn't unlocked yet" % id
		if have.has(id):
			return "%s is already the Titan's" % id
	return ""
