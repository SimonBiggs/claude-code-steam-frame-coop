extends "res://core/pick_flow.gd"
## DUO ARENA TEAM PICKS on the shared pick flow, EVERYONE VOTES (core/pick_flow.gd vote mode): the MODE (GENTLE /
## BRAVE / HARD, the first game of a visit) and NOVA'S GIFTS (after a boss) on the glowing orbs in front of the start
## (zone.gd draws them, picks.gd says what they are). Shoot an orb (main.gd on_orb_hit -> choose) or walk into it:
## that is your vote, a dot in your colour circles it on every machine. Everyone has voted (or the time is up): the
## most votes win; a tie stays GENTLER on the mode, the middle orb for a gift; nobody voted: the middle orb.
## HERO and PERK are each player's OWN pick on the same orbs (main.gd on_orb_hit): not a team vote.
## Sync: the sticky "orbs" event [stage, ids] and "take" [i, slot] (main.gd draws them on every machine).

const Picks := preload("res://games/duo_arena/picks.gd")


func _init() -> void:
	vote = true
	tie_rule = "gentler"
	after = 0.6


## The orbs in front of the start (zone.gd): the hero and perk picks share them.
func make_orbs() -> PickOrbs:
	return main.zone.picker


## Host / local: a team pick's orbs go up.
func begin(new_stage: String, ids: Array, done: Callable) -> void:
	start(new_stage, ids, done)
	main.zone.show_orbs(new_stage, ids)
	publish([new_stage, ids])


func vote_row() -> bool:
	return Picks.TEAM_STAGES.has(orbs.stage)


func wait_for() -> float:
	return float(Picks.WAIT[stage]) * (1.6 if main.game_mode == "gentle" and stage != "mode" else 1.0)


## Walking into an orb (shots come through choose()).
func takers() -> Dictionary:
	var out := {}
	for p in main.players:
		if p.active and not p.is_down and p.is_inside_tree():
			out["p%d" % p.index] = [p.global_position, int(p.index), "foot"]
	return out


## Everyone playing votes (a shot reaches the orbs from anywhere).
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
		main.burst(at, orbs.color_of(i), 14, 0.12)
