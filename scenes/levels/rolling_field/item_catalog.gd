class_name ItemCatalog
extends RefCounted
## Builds the things scattered around the rolling field, from primitive meshes
## and the prop models. Ask for a size and you get a fitting kind of thing:
## pebbles and coins when small, crates and benches in the middle, cars,
## houses and towers when big.

const TREE_SCENE := preload("res://assets/models/props/tree.blend")
const ROCK_SCENE := preload("res://assets/models/props/rock.blend")

const PALETTE: Array[Color] = [
	Color(0.94, 0.33, 0.36), Color(0.98, 0.62, 0.25), Color(0.99, 0.85, 0.35),
	Color(0.45, 0.8, 0.42), Color(0.3, 0.7, 0.86), Color(0.45, 0.45, 0.9),
	Color(0.78, 0.45, 0.88), Color(0.96, 0.55, 0.75), Color(0.92, 0.92, 0.9),
	Color(0.3, 0.32, 0.36),
]
const WOOD := Color(0.62, 0.43, 0.26)
const GOLD := Color(1.0, 0.8, 0.25)
const STONE := Color(0.55, 0.55, 0.58)
const LEAF := Color(0.24, 0.56, 0.28)
const TERRACOTTA := Color(0.78, 0.4, 0.26)
const ROOF := Color(0.6, 0.22, 0.2)
const GLASS := Color(0.55, 0.75, 0.9)

## Shared materials, one per color, so hundreds of items stay cheap to draw.
var _materials: Dictionary[Color, StandardMaterial3D] = {}


## A random item whose longest side is `size` meters.
func make_item(size: float) -> Collectible:
	var builders: Array[Callable]
	if size < 0.3:
		builders = [_pebble, _coin, _die, _candy, _eraser]
	elif size < 0.8:
		builders = [_mug, _book, _toy_ball, _flower_pot]
	elif size < 2.0:
		builders = [_crate, _barrel, _bench, _rock, _bush]
	elif size < 5.0:
		builders = [_tree, _car, _shed, _rock]
	else:
		builders = [_house, _tower, _silo, _tree]
	var builder: Callable = builders.pick_random()
	return builder.call(size)


# --- tiny --------------------------------------------------------------------

func _pebble(s: float) -> Collectible:
	var e := Vector3(s, s * 0.55, s * 0.8)
	return _build("Pebble", [_sphere(e, STONE)], e, 0.52)


func _coin(s: float) -> Collectible:
	var e := Vector3(s, s * 0.14, s)
	return _build("Coin", [_cylinder(s * 0.5, e.y, GOLD)], e, 0.78)


func _die(s: float) -> Collectible:
	var e := Vector3.ONE * s
	return _build("Die", [_box(e, PALETTE[8])], e, 1.0)


func _candy(s: float) -> Collectible:
	var e := Vector3.ONE * s
	return _build("Candy", [_sphere(e, _random_color())], e, 0.52)


func _eraser(s: float) -> Collectible:
	var e := Vector3(s, s * 0.35, s * 0.55)
	return _build("Eraser", [_box(e, PALETTE[7])], e, 1.0)


# --- small -------------------------------------------------------------------

func _mug(s: float) -> Collectible:
	var e := Vector3(s * 0.75, s, s * 0.6)
	var color := _random_color()
	var body := _cylinder(s * 0.3, s, color, Vector3(-s * 0.075, 0, 0))
	var handle := _box(Vector3(s * 0.15, s * 0.5, s * 0.1), color, Vector3(s * 0.3, 0, 0))
	return _build("Mug", [body, handle], e, 0.6)


func _book(s: float) -> Collectible:
	var e := Vector3(s * 0.72, s * 0.18, s)
	var cover := _box(e, _random_color())
	var pages := _box(Vector3(e.x * 0.94, e.y * 0.8, e.z * 0.96), PALETTE[8], Vector3(e.x * 0.04, 0, 0))
	return _build("Book", [cover, pages], e, 1.0)


func _toy_ball(s: float) -> Collectible:
	var e := Vector3.ONE * s
	return _build("Toy ball", [_sphere(e, _random_color())], e, 0.52)


func _flower_pot(s: float) -> Collectible:
	var e := Vector3(s * 0.6, s, s * 0.6)
	var pot := _cylinder(s * 0.25, s * 0.5, TERRACOTTA, Vector3(0, -s * 0.25, 0))
	var plant := _sphere(Vector3.ONE * s * 0.55, LEAF, Vector3(0, s * 0.2, 0))
	return _build("Flower pot", [pot, plant], e, 0.5)


# --- medium ------------------------------------------------------------------

func _crate(s: float) -> Collectible:
	var e := Vector3(s, s * 0.8, s * 0.8)
	return _build("Crate", [_box(e, WOOD)], e, 1.0)


func _barrel(s: float) -> Collectible:
	var e := Vector3(s * 0.65, s, s * 0.65)
	var color := PALETTE[[0, 4, 3].pick_random()]
	return _build("Barrel", [_cylinder(e.x * 0.5, s, color)], e, 0.78)


func _bench(s: float) -> Collectible:
	var e := Vector3(s, s * 0.32, s * 0.28)
	var seat := _box(Vector3(s, s * 0.08, e.z), WOOD, Vector3(0, e.y * 0.5 - s * 0.04, 0))
	var legs: Array[MeshInstance3D] = [seat]
	for side: float in [-1.0, 1.0]:
		legs.append(_box(Vector3(s * 0.06, e.y, e.z), PALETTE[9], Vector3(side * s * 0.4, 0, 0)))
	return _build("Bench", legs, e, 0.4)


func _rock(s: float) -> Collectible:
	return _build_model("Boulder" if s >= 2.0 else "Rock", ROCK_SCENE, s, 0.55)


func _bush(s: float) -> Collectible:
	var e := Vector3(s, s * 0.7, s * 0.85)
	return _build("Bush", [_sphere(e, LEAF)], e, 0.52)


# --- large -------------------------------------------------------------------

func _tree(s: float) -> Collectible:
	return _build_model("Big tree" if s >= 5.0 else "Tree", TREE_SCENE, s, 0.3)


func _car(s: float) -> Collectible:
	var e := Vector3(s * 0.45, s * 0.34, s)
	var color := _random_color()
	var body := _box(Vector3(e.x, e.y * 0.5, e.z), color, Vector3(0, -e.y * 0.1, 0))
	var cabin := _box(Vector3(e.x * 0.9, e.y * 0.4, e.z * 0.5), GLASS, Vector3(0, e.y * 0.3, -e.z * 0.05))
	var parts: Array[MeshInstance3D] = [body, cabin]
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			var wheel := _cylinder(e.y * 0.2, e.x * 0.12, PALETTE[9], Vector3(x * e.x * 0.47, -e.y * 0.3, z * e.z * 0.32))
			wheel.rotation.z = PI * 0.5
			parts.append(wheel)
	return _build("Car", parts, e, 0.6)


func _shed(s: float) -> Collectible:
	var e := Vector3(s, s * 0.85, s * 0.8)
	var walls := _box(Vector3(e.x, e.y * 0.6, e.z), WOOD, Vector3(0, -e.y * 0.2, 0))
	var roof := _prism(Vector3(e.x * 1.04, e.y * 0.4, e.z * 1.04), ROOF, Vector3(0, e.y * 0.3, 0))
	return _build("Shed", [walls, roof], e, 0.8)


# --- huge --------------------------------------------------------------------

func _house(s: float) -> Collectible:
	var e := Vector3(s, s * 0.8, s * 0.75)
	var color := PALETTE[[1, 2, 8, 4].pick_random()]
	var walls := _box(Vector3(e.x, e.y * 0.6, e.z), color, Vector3(0, -e.y * 0.2, 0))
	var roof := _prism(Vector3(e.x * 1.05, e.y * 0.4, e.z * 1.05), ROOF, Vector3(0, e.y * 0.3, 0))
	var door := _box(Vector3(e.x * 0.14, e.y * 0.3, e.z * 0.04), WOOD, Vector3(0, -e.y * 0.35, e.z * 0.5))
	return _build("House", [walls, roof, door], e, 0.85)


func _tower(s: float) -> Collectible:
	var e := Vector3(s * 0.26, s, s * 0.26)
	var body := _cylinder(e.x * 0.5, s * 0.8, STONE, Vector3(0, -s * 0.1, 0))
	var cap := _cone(e.x * 0.6, s * 0.2, ROOF, Vector3(0, s * 0.4, 0))
	return _build("Tower", [body, cap], e, 0.65)


func _silo(s: float) -> Collectible:
	var e := Vector3(s * 0.4, s, s * 0.4)
	var body := _cylinder(e.x * 0.5, s * 0.8, PALETTE[8], Vector3(0, -s * 0.1, 0))
	var dome := _sphere(Vector3(e.x, s * 0.4, e.x), PALETTE[4], Vector3(0, s * 0.3, 0))
	return _build("Silo", [body, dome], e, 0.7)


# --- helpers -----------------------------------------------------------------

func _build(item_name: String, parts: Array[MeshInstance3D], e: Vector3, fill: float) -> Collectible:
	var visual := Node3D.new()
	visual.name = "Visual"
	for part: MeshInstance3D in parts:
		visual.add_child(part)
	var shape := BoxShape3D.new()
	shape.size = e
	var item := Collectible.new()
	item.setup(item_name, visual, shape, e, fill)
	return item


## Wraps an imported model, scaled so its longest side is `s` and centered on
## the origin. The model's own imported colliders are removed: the Collectible
## gets a plain box instead.
func _build_model(item_name: String, scene: PackedScene, s: float, fill: float) -> Collectible:
	var model := scene.instantiate() as Node3D
	_strip_physics(model)
	var bounds := _mesh_bounds(model, Transform3D.IDENTITY)
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var k := s / maxf(longest, 0.001)
	model.scale = Vector3.ONE * k
	model.position = -bounds.get_center() * k
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.add_child(model)
	var e := bounds.size * k
	var shape := BoxShape3D.new()
	shape.size = e * Vector3(0.8, 1.0, 0.8)
	var item := Collectible.new()
	item.setup(item_name, visual, shape, e, fill)
	return item


func _strip_physics(root: Node) -> void:
	var doomed: Array[Node] = []
	for node: Node in root.find_children("*", "CollisionObject3D", true, false):
		doomed.append(node)
	for node: Node in doomed:
		node.get_parent().remove_child(node)
		node.free()


func _mesh_bounds(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	for child: Node in node.get_children():
		var child_3d := child as Node3D
		if child_3d == null:
			continue
		var child_xform := xform * child_3d.transform
		var mesh := child_3d as MeshInstance3D
		if mesh:
			var box := child_xform * mesh.get_aabb()
			result = box if not found else result.merge(box)
			found = true
		var inner := _mesh_bounds(child_3d, child_xform)
		if inner.has_volume():
			result = inner if not found else result.merge(inner)
			found = true
	return result


func _box(e: Vector3, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = e
	return _instance(mesh, color, offset)


func _sphere(e: Vector3, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var instance := _instance(mesh, color, offset)
	instance.scale = e
	return instance


func _cylinder(radius: float, height: float, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return _instance(mesh, color, offset)


func _cone(radius: float, height: float, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var instance := _cylinder(radius, height, color, offset)
	(instance.mesh as CylinderMesh).top_radius = 0.0
	return instance


func _prism(e: Vector3, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = e
	return _instance(mesh, color, offset)


func _instance(mesh: PrimitiveMesh, color: Color, offset: Vector3) -> MeshInstance3D:
	mesh.material = _material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	return instance


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.75
		_materials[color] = material
	return _materials[color]


func _random_color() -> Color:
	return PALETTE[randi() % 8]
