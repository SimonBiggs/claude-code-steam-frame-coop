extends Node3D
## PARTY BOARD: MANGO'S GIFTS on show (deep.gd GIFTS; who holds one comes in the "players" state: gift). Every machine
## floats the gift's picture (a story card picture on a little gold disc) over the holder's token, beside its item, so
## everyone sees who has a LUCKY DIE, SHORTCUT, UMBRELLA or DOUBLE STAR; it bounces when the gift is used. What the
## gifts DO is in turn_flow.gd (_add_die, _start_move, _land_simple, _star_grab, _surprises_fall). Under main.stage.
##   sync(roster), bounce(pid)

const StoryCard := preload("res://core/story_card.gd")
const Deep := preload("res://games/party_board/deep.gd")

const PX := 96
const SIZE := 1.15  # board units
const OVER := Vector3(0.9, 3.0, 0.0)  # over the token, beside its held item

var main
var tags := {}  # pid -> [gift id, Sprite3D]
var pop := {}  # pid -> 0..1


func _ready() -> void:
	name = "Gifts"


## Every machine: the gifts held now (the "players" state records).
func sync(roster: Array) -> void:
	var want := {}
	for p in roster:
		var pd: Dictionary = p
		var g := String(pd.get("gift", ""))
		if g != "" and not Deep.gift(g).is_empty():
			want[int(pd["pid"])] = g
	for pid in tags.keys():
		if not want.has(pid) or String(tags[pid][0]) != String(want[pid]):
			if is_instance_valid(tags[pid][1]):
				(tags[pid][1] as Node).queue_free()
			tags.erase(pid)
	for pid in want:
		if not tags.has(pid):
			tags[pid] = [want[pid], _tag(String(want[pid]))]
			pop[pid] = 1.0


func _tag(id: String) -> Sprite3D:
	var gd := Deep.gift(id)
	var s := StoryCard.sprite(String(gd.pic), PX, gd.color)
	s.name = "Gift_" + id
	s.pixel_size = SIZE / PX
	add_child(s)
	return s


## Every machine: pid's gift was just used.
func bounce(pid: int) -> void:
	pop[pid] = 1.0


func _process(delta: float) -> void:
	for pid in tags:
		var s: Sprite3D = tags[pid][1]
		if not is_instance_valid(s) or not main.tokens.has(pid):
			continue
		var tk: Node3D = main.tokens[pid]
		s.visible = tk.visible
		var p := float(pop.get(pid, 0.0))
		pop[pid] = maxf(0.0, p - delta * 1.6)
		s.position = tk.position + OVER + Vector3(0, 0.12 * sin(Time.get_ticks_msec() / 400.0 + pid), 0)
		s.scale = Vector3.ONE * (1.0 + 0.35 * sin(p * PI))
