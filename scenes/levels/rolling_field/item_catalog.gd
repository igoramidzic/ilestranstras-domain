class_name ItemCatalog
extends RefCounted
## Builds the things scattered around the rolling field from the models in
## assets/models/items/items.blend (made by tools/blender/build_item_models.py).
##
## Ask for a size and you get a fitting kind of thing: pebbles and coins when
## small, crates and benches in the middle, cars, houses and towers when big.
##
## Every object in items.blend is named "<Kind>_<variant>" (e.g. "Mug_Red").
## A random variant of the chosen kind is used, so adding a variant in Blender
## needs no code change. Models are scaled so their longest side matches the
## requested size.

const ITEMS_SCENE := preload("res://assets/models/items/items.blend")

## [largest size in meters, kinds that can appear up to that size]
const KINDS_BY_SIZE: Array[Array] = [
	[0.3, ["Pebble", "Coin", "Die", "Candy", "Eraser"]],
	[0.8, ["Mug", "Book", "ToyBall", "FlowerPot"]],
	[2.0, ["Crate", "Barrel", "Bench", "Rock", "Bush"]],
	[5.0, ["Tree", "Pine", "Car", "Shed", "Rock"]],
	[INF, ["House", "Tower", "Silo", "Tree", "Pine"]],
]
## HUD names, where the kind name alone isn't right.
const DISPLAY_NAMES: Dictionary[String, String] = {
	"ToyBall": "Beach ball", "FlowerPot": "Flower pot", "Pine": "Pine tree",
}
## Roughly how much of its bounding box each kind fills. Decides how much the ball grows.
const FILL: Dictionary[String, float] = {
	"Pebble": 0.5, "Coin": 0.78, "Die": 0.95, "Candy": 0.4, "Eraser": 0.95,
	"Mug": 0.55, "Book": 0.95, "ToyBall": 0.52, "FlowerPot": 0.35,
	"Crate": 0.6, "Barrel": 0.75, "Bench": 0.25, "Rock": 0.55, "Bush": 0.45,
	"Tree": 0.2, "Pine": 0.25, "Car": 0.6, "Shed": 0.8,
	"House": 0.8, "Tower": 0.65, "Silo": 0.75,
}
## Kinds with an airy outline get a narrower collision box than their bounds,
## so the ball can roll in under the leaves.
const LOOSE: Array[String] = ["Tree", "Pine", "Bush", "FlowerPot"]

## Kind -> the meshes of all its variants.
var _variants: Dictionary[String, Array] = {}


func _init() -> void:
	var root := ITEMS_SCENE.instantiate()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var kind := String(mesh_instance.name).get_slice("_", 0)
		_variants.get_or_add(kind, []).append(mesh_instance.mesh)
	root.free()


## A random item whose longest side is `size` meters.
func make_item(size: float) -> Collectible:
	var kinds: Array = KINDS_BY_SIZE[-1][1]
	for band: Array in KINDS_BY_SIZE:
		if size < band[0]:
			kinds = band[1]
			break
	var kind: String = kinds.pick_random()
	var meshes: Array = _variants.get(kind, [])
	if meshes.is_empty():
		push_error("items.blend has no objects named %s_*" % kind)
		return null
	return _build(kind, meshes.pick_random(), size)


func _build(kind: String, mesh: Mesh, size: float) -> Collectible:
	var bounds := mesh.get_aabb()
	var k := size / maxf(bounds.get_longest_axis_size(), 0.0001)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.scale = Vector3.ONE * k
	instance.position = -bounds.get_center() * k
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.add_child(instance)

	var extents := bounds.size * k
	var shape := BoxShape3D.new()
	shape.size = extents * (Vector3(0.6, 1.0, 0.6) if kind in LOOSE else Vector3(0.95, 1.0, 0.95))
	var item := Collectible.new()
	item.setup(_display_name(kind, size), visual, shape, extents, FILL.get(kind, 0.6))
	return item


func _display_name(kind: String, size: float) -> String:
	if kind == "Rock" and size >= 2.0:
		return "Boulder"
	if kind == "Tree" and size >= 5.0:
		return "Big tree"
	return DISPLAY_NAMES.get(kind, kind)
