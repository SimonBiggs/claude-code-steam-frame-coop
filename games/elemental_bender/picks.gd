extends "res://core/pick_flow.gd"
## ELEMENTAL BENDER MODE PICK on the shared pick flow, EVERYONE VOTES (core/pick_flow.gd vote mode): after practice
## the team picks GENTLE / BRAVE / HARD on Kiko's altar stones (altar.gd: the same stones, spinning pictures and
## names as the masters and gifts). Walk onto a stone or bend at it (main.gd projectile_hit -> choose): that is your
## vote, a little orb in your colour circles it on every machine. Everyone has voted (or the time is up): the most
## votes win and a tie stays GENTLER; nobody voted: the family's last mode (the middle stone).
## The altar's masters and gifts are each player's OWN pick (main.gd _altar_pick), not a team vote: they stay there.
## Every machine builds the stones from the host's net state "pick" (main.gd _open_pick), so this flow publishes
## nothing itself.

const Boons := preload("res://games/elemental_bender/boons.gd")


func _init() -> void:
	vote = true
	tie_rule = "gentler"
	after = 0.6


## The altar (main.gd builds it before this): the mode stones share it with the masters and gifts.
func make_orbs() -> PickOrbs:
	return main.altar


## Host / local: the mode stones go up (main.gd _open_pick shares them as net state "pick").
func begin(ids: Array, done: Callable) -> void:
	start("mode", ids, done)
	main._open_pick("mode", ids)


func publish(_payload: Array) -> void:
	pass  # (net state "pick" is the altar's sync)


func closed() -> void:
	main._close_pick()


func vote_row() -> bool:
	return orbs.stage == "mode"


func wait_for() -> float:
	return Boons.WAIT_FAST if main.fast else Boons.WAIT


## Walking onto a stone (every bender and the VR master; bending at one comes through choose()).
func takers() -> Dictionary:
	var out := {}
	for f in main.fighters(true):
		out["f%d" % int(f.get("slot"))] = [(f as Node3D).global_position, int(f.get("slot")), "foot"]
	return out


## Everyone in the game votes (bending reaches the stones from anywhere).
func voters(_points: Dictionary) -> Array:
	var out: Array = []
	for f in main.fighters(false):
		out.append(int(f.get("slot")))
	return out


func slot_color(slot: int) -> Color:
	return main._slot_colors().get(slot, Color.WHITE)


func vote_fx(i: int, slot: int) -> void:
	var id := String(options[i])
	var fm: Node3D = main.fighter_of(slot)
	if fm == null:
		return
	main.fx.burst(fm.global_position + Vector3.UP, PickOrbs.mode_color(id), 16, 3.0, 0.3, 0.6)
	main.sound_all("power_up", fm.global_position, -4.0, 1.2)
	main._note(slot, "%s!" % PickOrbs.mode_name(id))


## The winning stone pops here; every machine sees the votes and Kiko's mode card.
func send_take(i: int, slot: int) -> void:
	take_fx(i, slot)
