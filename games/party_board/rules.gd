extends RefCounted
## Party Board rules in one place: coins, prices, items and the event-space happenings, so the
## numbers are easy to tune. Plain data + small helpers (no state).

const START_COINS := 10
const STAR_PRICE := 20
const BLUE_COINS := 3
const RED_COINS := 3
const RED_COINS_KID := 1
const MAX_ITEMS := 3
const DUEL_STAKE := 5
## Minigame coins by finishing place (FFA), and for team wins.
const MG_PLACE_COINS := [10, 6, 3, 1, 1, 1, 1]
const MG_PLACE_COINS_KID := [10, 7, 5, 4, 4, 4, 4]
const MG_TEAM_WIN := 8
const MG_SOLO_WIN := 12
const MG_LOSE := 1
const MG_LOSE_KID := 3
## Kid mode: the player in last place gets this at the start of every round.
const CATCH_UP_COINS := 5
const TURN_CHOICES := [5, 10, 15]

const ITEMS := {
	"double": {"name": "DOUBLE DICE", "price": 5, "icon": "plus", "color": Color(0.35, 0.7, 1.0),
		"desc": "Roll TWO dice this turn!"},
	"pipe": {"name": "GOLDEN PIPE", "price": 15, "icon": "star", "color": Color(1.0, 0.82, 0.3),
		"desc": "Warp right next to the STAR!"},
	"steal": {"name": "STEAL-A-COIN", "price": 6, "icon": "coin", "color": Color(1.0, 0.55, 0.3),
		"desc": "Sneak 5 coins from a player you pick!"},
	"swap": {"name": "SWAP SHELL", "price": 8, "icon": "arrow_right", "color": Color(0.7, 0.5, 1.0),
		"desc": "Swap places with a player you pick!"},
}
const ITEM_ORDER := ["double", "steal", "swap", "pipe"]

const EVENTS := {
	"coin_rain": {"title": "COIN RAIN!", "text": "Coins fall from the sky! You get 6, everyone else gets 2."},
	"dragon": {"title": "FRIENDLY DRAGON!", "text": "A dragon gives you a ride right next to the STAR!"},
	"whirlwind": {"title": "WHIRLWIND!", "text": "Whoosh! You swap places with another player!"},
	"treasure": {"title": "TREASURE CHEST!", "text": "You open a chest full of coins!"},
	"gift": {"title": "SURPRISE GIFT!", "text": "A present with a free item inside!"},
	"star_shuffle": {"title": "STAR SHUFFLE!", "text": "The STAR flies off to a new spot!"},
	"volcano": {"title": "VOLCANO BURP!", "text": "Hot rocks! Everyone on the Volcano Trail drops 3 coins."},
	"party": {"title": "BEACH PARTY!", "text": "Everybody dances and gets 3 coins!"},
}
## Which happenings each zone favours: [event, weight].
const ZONE_EVENTS := {
	"beach": [["coin_rain", 3], ["party", 3], ["treasure", 2], ["dragon", 1], ["whirlwind", 1]],
	"candy": [["gift", 3], ["treasure", 3], ["coin_rain", 2], ["whirlwind", 1]],
	"volcano": [["volcano", 3], ["dragon", 3], ["star_shuffle", 1], ["treasure", 1]],
	"meadow": [["dragon", 2], ["gift", 2], ["party", 2], ["whirlwind", 2], ["star_shuffle", 1]],
	"lagoon": [["whirlwind", 3], ["star_shuffle", 2], ["treasure", 2], ["coin_rain", 1]],
}


static func pick_event(zone: String, rng: RandomNumberGenerator) -> String:
	var list: Array = ZONE_EVENTS.get(zone, ZONE_EVENTS["meadow"])
	var total := 0
	for e in list:
		total += int((e as Array)[1])
	var r := rng.randi_range(1, total)
	for e in list:
		var ea: Array = e
		r -= int(ea[1])
		if r <= 0:
			return String(ea[0])
	return "treasure"


static func item_name(id: String) -> String:
	return String((ITEMS.get(id, {}) as Dictionary).get("name", id.to_upper()))


static func item_price(id: String) -> int:
	return int((ITEMS.get(id, {}) as Dictionary).get("price", 99))
