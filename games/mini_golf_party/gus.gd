extends Node3D
## GUS the gopher, in the world: he lives in a molehill beside the flag board of every hole. He pops up when a
## hole starts, bobs and looks at the balls, and hops and spins when someone sinks one. The VR golfer can
## boop his nose (props.gd "gus" touch). Every machine builds and animates him itself (pop / cheer / boop come from
## main.gd's hole build and the "sink" / "prop" events). One merged mesh for the hill, one for Gus.

const MeshKit := preload("res://core/mesh_kit.gd")

const FUR := Color(0.72, 0.5, 0.3)
const BELLY := Color(0.95, 0.82, 0.62)

var body: Node3D
var up := 0.0  ## 0 = hidden in the hill, 1 = all the way up
var hop := 0.0
var spin := 0.0
var _t := 0.0


func _ready() -> void:
	var hb := MeshKit.Builder.new()
	hb.dome(0.24, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.5, 1.0)), Color(0.55, 0.38, 0.22), 12)
	hb.disc(0.13, MeshKit.at(Vector3(0.0, 0.122, 0.0)), Color(0.15, 0.1, 0.06), 12)
	add_child(MeshKit.instance(hb.build(), false))
	body = Node3D.new()
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(0.075, 0.1, 0.07), MeshKit.at(Vector3(0.0, 0.1, 0.0)), FUR, 12)
	b.ellipsoid(Vector3(0.05, 0.07, 0.03), MeshKit.at(Vector3(0.0, 0.09, 0.05)), BELLY, 10)
	b.sphere(0.07, MeshKit.at(Vector3(0.0, 0.22, 0.0)), FUR, 12)
	b.sphere(0.04, MeshKit.at(Vector3(0.0, 0.205, 0.055)), BELLY, 10)
	b.sphere(0.014, MeshKit.at(Vector3(0.0, 0.225, 0.092)), Color(0.95, 0.5, 0.55), 6)
	for sx in [-1.0, 1.0]:
		b.sphere(0.013, MeshKit.at(Vector3(sx * 0.028, 0.245, 0.06)), Color(0.08, 0.06, 0.05), 6)
		b.sphere(0.022, MeshKit.at(Vector3(sx * 0.055, 0.28, -0.005)), FUR.darkened(0.15), 6)
		b.ellipsoid(Vector3(0.018, 0.035, 0.018), MeshKit.at(Vector3(sx * 0.07, 0.13, 0.04)), FUR.darkened(0.08), 6)
	b.box(Vector3(0.024, 0.02, 0.006), MeshKit.at(Vector3(0.0, 0.18, 0.085)), Color.WHITE)
	# His little green golf cap.
	b.dome(0.06, MeshKit.at(Vector3(0.0, 0.265, 0.0)), Color(0.25, 0.7, 0.4), 10)
	b.box(Vector3(0.07, 0.008, 0.05), MeshKit.at(Vector3(0.0, 0.27, 0.06)), Color(0.2, 0.6, 0.35))
	body.add_child(MeshKit.instance(b.build(), false))
	body.scale = Vector3.ONE * 2.2  # big enough to spot on a Deck
	add_child(body)
	_place()


## A new hole: down into the hill, then pop up.
func pop() -> void:
	up = -0.6
	hop = 0.0


## Someone sank a ball: a happy hop and a spin.
func cheer() -> void:
	hop = 0.7
	spin = TAU


## Booped by the VR golfer: a little surprised hop.
func boop() -> void:
	hop = maxf(hop, 0.4)


func _process(delta: float) -> void:
	_t += delta
	up = minf(1.0, up + delta * 2.0)
	hop = maxf(0.0, hop - delta)
	spin = maxf(0.0, spin - delta * TAU * 1.6)
	_place()


func _place() -> void:
	if body == null:
		return
	var u := clampf(up, 0.0, 1.0)
	var h := sin(hop / 0.7 * PI) * 0.18 if hop > 0.0 else 0.0
	body.position.y = -0.72 + u * 0.72 + h + sin(_t * 2.2) * 0.006
	body.rotation.y = spin + sin(_t * 0.7) * 0.35
	body.visible = u > 0.05
