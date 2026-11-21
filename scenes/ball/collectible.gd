class_name Collectible
extends StaticBody3D
## Something the StickyBall can pick up once the ball is big enough.
##
## The body's origin is the item's center. All meshes live under `visual`.
## When the ball picks the item up, the visual moves onto the ball and this
## body is freed. Until then it's solid, so things that are too big block the
## ball like any other obstacle.

## Shown on the HUD when picked up.
var display_name: String = "Thing"
## Bounding box size in meters (before the body is rotated).
var extents: Vector3 = Vector3.ONE
## Longest side in meters. This is what the ball compares against.
var size: float = 1.0
## Roughly how much space the item fills (m^3). Decides how much the ball grows.
var volume: float = 1.0
var visual: Node3D


## `fill` is how much of the bounding box the item fills (1.0 for a box,
## about 0.5 for a sphere).
func setup(item_name: String, item_visual: Node3D, shape: Shape3D, item_extents: Vector3, fill: float) -> void:
	name = item_name
	display_name = item_name
	extents = item_extents
	size = maxf(extents.x, maxf(extents.y, extents.z))
	volume = extents.x * extents.y * extents.z * fill
	collision_layer = 4 # "props"
	collision_mask = 0

	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	visual = item_visual
	add_child(visual)


## Moves the visual under `new_parent` (keeping where it is in the world),
## frees this body and returns the visual.
func detach_visual(new_parent: Node3D) -> Node3D:
	collision_layer = 0 # Stop blocking / being found right away, not at the end of the frame.
	visual.reparent(new_parent)
	visual.reset_physics_interpolation()
	queue_free()
	return visual
