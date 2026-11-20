extends SceneTree
## FIRST GOAL: every arcade game has games/<id>/first_goal.gd (core/first_goal.gd): what the player is, the one thing
## to do first for TV and VR ([button, short text]), a small-win condition, and expressions that parse. The FirstGoal
## service is in core/services.gd (so every game shows it without code of its own).
## Runtime: every game bot runs the service too, and a data expression that fails on the real game is an engine ERROR
## from res:// (bots fail on it).
##   godot-test --headless --path . -s res://tests/first_goal_test.gd     Prints FIRST GOAL: PASS / FAIL.

const FirstGoal := preload("res://core/first_goal.gd")

var fails := 0


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FIRST GOAL: FAIL ", what)


func _initialize() -> void:
	var games: Array = load("res://arcade/arcade.gd").GAMES
	var n := 0
	for g in games:
		var id := String(g.id)
		n += 1
		for p in FirstGoal.problems_of(id):
			_expect(false, p)
	# every game folder with a main scene that the arcade lists is covered above; a game folder the arcade doesn't
	# list yet (being built) still needs data before it lands
	for id in FirstGoal.game_ids():
		var listed := false
		for g in games:
			listed = listed or String(g.id) == id
		if not listed:
			for p in FirstGoal.problems_of(id):
				_expect(false, p)
	var services: Array = load("res://core/services.gd").SERVICES
	var has := false
	for e in services:
		has = has or String(e.path) == "res://core/first_goal.gd"
	_expect(has, "core/first_goal.gd is not a service in core/services.gd")
	# the helper's own pieces: remembered per profile, sums nested scores
	var fg: Node = FirstGoal.new()
	_expect(is_equal_approx(fg.sum({"a": 2, "b": [1, 3.5]}), 6.5), "sum() of nested scores")
	_expect(FirstGoal.profile() != "", "a profile name")
	_expect(FirstGoal.game_of(null) == "", "game_of(null)")
	fg.free()
	print("FIRST GOAL: %d games checked, %d problems" % [n, fails])
	print("FIRST GOAL: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
