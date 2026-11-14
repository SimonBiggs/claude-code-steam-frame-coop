extends "res://core/pick_flow.gd"
## SNOWBALL BLITZ MODE PICK on the shared pick flow, EVERYONE VOTES (core/pick_flow.gd vote mode): after the practice
## on the first game of a visit the team picks GENTLE / BRAVE / HARD on the glowing orbs in front of the fort. Throw a
## snowball at one (main.gd on_orb_hit -> choose) or walk into it: that is your vote, a dot in your colour circles it
## on every machine. Everyone has voted (or the time is up): the most votes win and a tie stays GENTLER; nobody
## voted: the family's last mode (the middle orb).
## BOBO'S GIFTS after every wave are each player's OWN pick on the same orbs (main.gd on_orb_hit): not a team vote.
## Sync: the sticky "orbs" event [stage, entries] and "take" [i, slot] (main.gd draws them on every machine).

const Gifts := preload("res://games/snowball_blitz/gifts.gd")


func _init() -> void:
	vote = true
	tie_rule = "gentler"
	after = 0.6


## The fort's pick orbs (main.gd): the gift picks share them.
func make_orbs() -> PickOrbs:
	return main.orbs


## Host / local: the mode orbs go up.
func begin(ids: Array, done: Callable) -> void:
	start("mode", ids, done)
	var entries: Array = main._orb_entries("mode", ids)
	show_row(entries)
	publish(["mode", entries])


## Every machine: the row in front of the fort.
func show_row(entries: Array) -> void:
	orbs.show_orbs("mode", entries, main.ORB_ROW, main.ORB_GAP, main.ORB_Y)


func vote_row() -> bool:
	return orbs.stage == "mode"


func wait_for() -> float:
	return float(Gifts.WAIT["mode"])


## Walking into an orb (throws come through choose()).
func takers() -> Dictionary:
	var out := {}
	for p in main.players:
		if p.active and not p.is_down and not p.ghost and p.is_inside_tree():
			out["p%d" % p.index] = [p.global_position, int(p.index), "foot"]
	return out


## Everyone playing votes (a throw reaches the orbs from anywhere).
func voters(_points: Dictionary) -> Array:
	var out: Array = []
	for p in main._pick_players():
		out.append(int(p.index))
	return out


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot % main.PLAYER_COLORS.size()]


func vote_fx(i: int, _slot: int) -> void:
	main.sound("pickup", 0.0, 1.0 + 0.1 * i)


func fx(i: int, _slot: int, at: Vector3, _col: Color) -> void:
	if at != Vector3.INF:
		main.puff(at, orbs.color_of(i), 16, 0.09)
