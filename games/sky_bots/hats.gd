extends RefCounted
## SKY BOTS costume HATS: every little bot rescued from a bot box moves to Gizmo Town, and every few rescues the little
## bots sew a new hat (AT: rescues needed). Each robot wears one (slot n gets a different one by itself; Y in Gizmo
## Town swaps to the next). Drawn on the robot's head (robot.gd show_hat), and on the hat stand in Gizmo Town.

const MeshKit := preload("res://core/mesh_kit.gd")

const LIST: Array[String] = ["none", "tophat", "crown", "flower", "pirate", "chef", "bunny", "party", "wizard"]
const AT: Array[int] = [0, 1, 3, 5, 8, 11, 14, 18, 22]  ## little bots rescued to unlock each
const PICS: Array[String] = ["skybot", "hattop", "hatcrown", "hatflower", "hatpirate", "hatchef", "hatbunny", "hatparty", "hatwizard"]


## How many hats are open after `rescued` little bots (always >= 1: "none").
static func unlocked(rescued: int) -> int:
	var n := 0
	for a in AT:
		n += 1 if rescued >= a else 0
	return n


## The hat a robot in slot `slot` wears unless its player picked one: the newest ones first, a different one each.
static func default_for(slot: int, rescued: int) -> int:
	var n := unlocked(rescued)
	if n <= 1:
		return 0
	return n - 1 - (slot % (n - 1))


## How much higher the propeller cap sits with hat h on.
static func lift(h: int) -> float:
	return [0.0, 0.42, 0.22, 0.12, 0.2, 0.36, 0.0, 0.34, 0.46][clampi(h, 0, LIST.size() - 1)]


## Hat h's mesh, sitting on the robot's head top (y 0 = the top of the head).
static func mesh(h: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match LIST[clampi(h, 0, LIST.size() - 1)]:
		"tophat":
			b.cylinder(0.3, 0.3, 0.04, MeshKit.at(Vector3(0, 0.02, 0)), Color(0.15, 0.15, 0.2), 14)
			b.cylinder(0.19, 0.19, 0.36, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.15, 0.15, 0.2), 14)
			b.cylinder(0.195, 0.195, 0.07, MeshKit.at(Vector3(0, 0.08, 0)), Color(0.9, 0.3, 0.35), 14)
		"crown":
			b.cylinder(0.2, 0.2, 0.12, MeshKit.at(Vector3(0, 0.06, 0)), Color(1.0, 0.8, 0.2), 12)
			for k in 5:
				var a := TAU * k / 5.0
				b.cone(0.06, 0.14, MeshKit.at(Vector3(cos(a) * 0.17, 0.19, sin(a) * 0.17)), Color(1.0, 0.8, 0.2), 6)
				b.sphere(0.03, MeshKit.at(Vector3(cos(a) * 0.2, 0.07, sin(a) * 0.2)), Color(0.9, 0.2, 0.4), 6, true)
		"flower":
			b.cylinder(0.02, 0.02, 0.12, MeshKit.at(Vector3(0, 0.06, 0)), Color(0.3, 0.65, 0.3), 5)
			for k in 6:
				var a := TAU * k / 6.0
				b.sphere(0.07, MeshKit.at(Vector3(cos(a) * 0.09, 0.14, sin(a) * 0.09), Vector3(1, 0.5, 1)), Color(1.0, 0.55, 0.75), 8)
			b.sphere(0.06, MeshKit.at(Vector3(0, 0.15, 0)), Color(1.0, 0.85, 0.3), 8)
		"pirate":
			b.ellipsoid(Vector3(0.36, 0.1, 0.18), MeshKit.at(Vector3(0, 0.08, 0)), Color(0.18, 0.15, 0.15), 12)
			b.wedge(Vector3(0.42, 0.14, 0.2), MeshKit.at(Vector3(0, 0.18, 0)), Color(0.18, 0.15, 0.15))
			b.sphere(0.04, MeshKit.at(Vector3(0, 0.16, 0.11)), Color(0.95, 0.95, 0.95), 6)
		"chef":
			b.cylinder(0.17, 0.17, 0.16, MeshKit.at(Vector3(0, 0.08, 0)), Color(0.97, 0.97, 0.97), 12)
			b.sphere(0.2, MeshKit.at(Vector3(0, 0.26, 0), Vector3(1, 0.6, 1)), Color(0.97, 0.97, 0.97), 12)
		"bunny":
			for s in [-1.0, 1.0]:
				b.ellipsoid(Vector3(0.06, 0.2, 0.04), MeshKit.at(Vector3(s * 0.1, 0.18, 0), Vector3.ONE, Vector3(0, 0, -s * 0.2)), Color(0.97, 0.95, 0.97), 8)
				b.ellipsoid(Vector3(0.03, 0.13, 0.02), MeshKit.at(Vector3(s * 0.1, 0.18, 0.025), Vector3.ONE, Vector3(0, 0, -s * 0.2)), Color(1.0, 0.65, 0.75), 6)
		"party":
			b.cone(0.15, 0.36, MeshKit.at(Vector3(0, 0.18, 0)), Color(0.4, 0.75, 1.0), 10)
			b.sphere(0.05, MeshKit.at(Vector3(0, 0.37, 0)), Color(1.0, 0.85, 0.3), 8)
			b.torus(0.12, 0.025, MeshKit.at(Vector3(0, 0.1, 0)), Color(1.0, 0.45, 0.6), 12, 4)
		"wizard":
			b.cylinder(0.28, 0.28, 0.03, MeshKit.at(Vector3(0, 0.015, 0)), Color(0.35, 0.3, 0.75), 14)
			b.cone(0.18, 0.5, MeshKit.at(Vector3(0, 0.27, 0), Vector3.ONE, Vector3(0, 0, 0.15)), Color(0.35, 0.3, 0.75), 10)
			b.star(5, 0.06, 0.025, 0.02, MeshKit.at(Vector3(0, 0.22, 0.13)), Color(1.0, 0.9, 0.35), true)
	return b.build()
