extends "res://games/party_board/minigames/mg_base.gd"
## PAINT SPLASH (free for all; from the arcade's Paint and Guess): the plaza is a grid of white tiles. Walk on a
## tile to paint it your colour - anyone can paint over it again. Most tiles at the end wins. Just the stick:
## wherever a little one wanders, they paint, so everyone scores. The GIANT paints with a glove pressed on the
## tiles (a 3x3 dab). Tiles are synced as one byte each (paint + 1).

const META := {
	"name": "PAINT SPLASH",
	"goal": "Walk on the tiles to paint them your colour! Most tiles wins.",
	"format": "ffa", "time": 22.0, "music": "party", "cam": [15.0, 12.0],
	"tv": [["L-STICK", "Walk to paint"]],
	"vr": [["GLOVE", "Press on the tiles to paint"]],
	"vr_line": "PAINT the tiles with your glove!",
	"cue": "catch",
}
const N := 11  ## tiles per side
const STEP := 1.05
const TILE := 0.95

var paint: PackedByteArray  ## tile -> paint pid + 1 (0 = white)
var mm: MultiMesh
var _shown: PackedByteArray
var _cpu_tile := {}  # pid -> tile index


func build() -> void:
	arena_r = N * STEP * 0.5 - 0.3
	walk_speed = 5.0
	build_island(arena_r + 1.6, Color(0.5, 0.75, 0.42))
	paint = PackedByteArray()
	paint.resize(N * N)
	_shown = PackedByteArray()
	_shown.resize(N * N)
	var tile := ResCache.get_or_make("pb_paint_tile", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(TILE, 0.1, TILE), 0.04, MeshKit.at(Vector3(0, 0.05, 0)), Color(1, 1, 1))
		return b.build())
	var xfs: Array = []
	var cols := PackedColorArray()
	for i in N * N:
		xfs.append(Transform3D(Basis(), tile_pos(i)))
		cols.append(Color(0.96, 0.96, 0.98))
	var mmi := MeshKit.scatter(tile, xfs, cols, PackedColorArray(), false)
	mm = mmi.multimesh
	add_child(mmi)


func tile_pos(i: int) -> Vector3:
	return Vector3((float(i % N) - (N - 1) * 0.5) * STEP, 0.0, (float(i / N) - (N - 1) * 0.5) * STEP)


func tile_at(p: Vector3) -> int:
	var x := roundi(p.x / STEP + (N - 1) * 0.5)
	var z := roundi(p.z / STEP + (N - 1) * 0.5)
	if x < 0 or z < 0 or x >= N or z >= N:
		return -1
	return z * N + x


func start_pos(i: int, n: int) -> Vector3:
	var a := TAU * float(i) / float(maxi(1, n)) + PI * 0.25
	return Vector3(cos(a), 0, sin(a)) * 3.6


func on_begin() -> void:
	paint.fill(0)
	_recount()


func _paint(i: int, pid: int) -> void:
	if i < 0 or i >= paint.size() or int(paint[i]) == pid + 1:
		return
	paint[i] = pid + 1
	if not practice:
		_recount()


func _recount() -> void:
	for p in pids:
		score[p] = 0.0
	for i in paint.size():
		var o := int(paint[i]) - 1
		if o >= 0 and score.has(o):
			score[o] = float(score[o]) + 1.0


func play_tick(delta: float) -> void:
	for p in walkers():
		walk(p, delta, -1.0, arena_r + 0.3)
		_paint(tile_at(pos[p]), p)
	separate()
	if giant:
		var hs := giant_hands()
		for h in hs.size():
			if hs[h].y < 1.2 and hs[h].y > -0.6:
				var c := tile_at(hs[h])
				if c >= 0:
					for dz in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							var x := c % N + int(dx)
							var z := c / N + int(dz)
							if x >= 0 and z >= 0 and x < N and z < N:
								_paint(z * N + x, 0)
	if practice:
		_refresh()


func snap_extra() -> Array:
	return [paint]


func unsnap_extra(a: Array) -> void:
	if not a.is_empty():
		paint = a[0]


func _process(delta: float) -> void:
	super(delta)
	_refresh()


## Every machine: tiles whose paint changed take the new colour (with a little squash).
func _refresh() -> void:
	if mm == null or paint.size() != _shown.size():
		return
	for i in paint.size():
		if paint[i] != _shown[i]:
			_shown[i] = paint[i]
			var o := int(paint[i]) - 1
			mm.set_instance_color(i, color_of(o).lightened(0.15) if o >= 0 else Color(0.96, 0.96, 0.98))


func cpu_move(pid: int) -> Vector3:
	var me := where(pid)
	var cur := int(_cpu_tile.get(pid, -1))
	if cur >= 0 and int(paint[cur]) != pid + 1:
		return tile_pos(cur)
	var best := -1
	var bd := INF
	for k in 12:
		var i := rng.randi() % (N * N)
		if int(paint[i]) == pid + 1:
			continue
		var d := tile_pos(i).distance_to(me) + rng.randf() * 2.0
		if d < bd:
			bd = d
			best = i
	_cpu_tile[pid] = best
	return tile_pos(best) if best >= 0 else me


func bot_vr_goal() -> Vector3:
	var t := Time.get_ticks_msec() / 1000.0
	return Vector3(sin(t * 0.9) * 3.5, 0.3, cos(t * 0.7) * 3.0)


func touch_goal() -> Vector3:
	return Vector3(0, 1.0, 2.0)
