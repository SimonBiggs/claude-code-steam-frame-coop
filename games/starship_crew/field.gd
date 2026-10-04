extends RefCounted
## Starship Crew: a deterministic field of asteroids or storm clouds ahead of the ship.
## Built from (kind, seed, count, length) on every machine, so only the distance flown (snapshots) and
## which rocks were destroyed (state store) travel over the network.
## Space coordinates: x right, y up; `d` is how far along the field an object sits. With the ship having
## flown `s` metres, an object is at z = s - d - AHEAD in the ship's frame (the nose is near z = -12).

const AHEAD := 150.0
const NOSE_Z := -12.0

var kind := "asteroids"  # or "storm"
var seed_value := 1
var length := 800.0
var pos := PackedVector3Array()  # x, y, d
var size := PackedFloat32Array()
var spin := PackedVector3Array()
var crystal := PackedByteArray()  # asteroids worth bonus scrap (revealed by a science scan)


## Build the field (same result on every machine for the same arguments).
func setup(p_kind: String, p_seed: int, count: int, p_length: float) -> void:
	kind = p_kind
	seed_value = p_seed
	length = p_length
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	pos.resize(count)
	size.resize(count)
	spin.resize(count)
	crystal.resize(count)
	for i in count:
		var d := (float(i) + rng.randf_range(0.0, 0.8)) / float(count) * length
		var p := Vector3.ZERO
		if kind == "storm":
			p = Vector3(rng.randf_range(-11.0, 11.0), rng.randf_range(-5.0, 5.0), d)
			size[i] = rng.randf_range(4.5, 7.0)
		else:
			if rng.randf() < 0.45:
				p = Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-4.0, 4.0), d)  # in the ship's way
			else:
				p = Vector3(rng.randf_range(-26.0, 26.0), rng.randf_range(-12.0, 12.0), d)
			size[i] = rng.randf_range(0.9, 3.2) if rng.randf() < 0.85 else rng.randf_range(3.5, 5.5)
		pos[i] = p
		spin[i] = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.2, 1.2)
		crystal[i] = 0


func count() -> int:
	return pos.size()


## z in the ship's frame for object i after flying s metres.
func z_of(i: int, s: float) -> float:
	return s - pos[i].z - AHEAD


## Flying distance at which object i reaches the nose.
func reach_s(i: int) -> float:
	return pos[i].z + AHEAD + NOSE_Z


## Fraction of the field flown (0..1).
func progress(s: float) -> float:
	return clampf(s / (length + AHEAD), 0.0, 1.0)


## Done once the last object has passed the ship.
func finished(s: float) -> bool:
	return s > length + AHEAD + 20.0
