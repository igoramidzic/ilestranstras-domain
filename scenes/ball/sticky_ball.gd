class_name StickyBall
extends CharacterBody3D
## A sticky ball that the character pushes around, with a third-person camera
## behind the character.
##
## - W / S (up / down) roll the ball forward / back, the way the character faces.
## - A / D (left / right), Q / E, or right-mouse drag turn: the character walks
##   around the ball and the camera swings with them.
## - Touch a Collectible whose longest side is at most `radius * pickup_ratio`
##   (so about half the ball's diameter or less) and it sticks to the ball.
##   The ball grows by the item's volume. Anything bigger is a solid obstacle.
## - Everything picked up stays visible: when the ball grows, stuck items are
##   pushed back out to the new surface.
## - The bigger the ball, the faster it rolls and the further the camera pulls back,
##   so the world seems to shrink around you.
##
## The body's origin sits on the ground under the ball (like the player's feet).
## The body never rotates. The spinning happens on the Roller node, and stuck items
## are children of Roller so they roll along with the ball.

signal item_collected(item: Collectible)
signal radius_changed(radius: float)
## Rolled into something too big to pick up. `strength` is 0..1.
signal bumped(strength: float)

const PROPS_LAYER := 4
## How long a picked-up item takes to snap onto the ball.
const SETTLE_TIME := 0.15

## Third-person camera. It's turned to face where the character faces, and its
## zoom follows the ball's size.
@export var camera: TopDownCamera
@export var start_radius: float = 0.4

@export_group("Pickup")
## Items whose longest side is up to radius * pickup_ratio stick. 1.0 = half the diameter.
@export var pickup_ratio: float = 1.0
## How much of an item's volume is added to the ball. Above 1 makes growing quicker.
@export var growth: float = 2.5
## How far stuck items poke out: 0 = centered on the surface, 0.5 = sitting on top of it.
@export var stick_out: float = 0.1

@export_group("Movement")
## Top speed (m/s) at the starting size.
@export var base_speed: float = 4.5
## Top speed grows with (radius / start_radius) ^ this.
@export var speed_exponent: float = 0.75
## How quickly it reaches top speed (per second, relative to top speed).
@export var acceleration: float = 3.0
@export var deceleration: float = 2.5
## How fast you turn (radians per second).
@export var turn_speed: float = 2.2
## Radians per pixel when turning with right-mouse drag.
@export var mouse_turn_sensitivity: float = 0.006

@export_group("Pusher")
## Character size at the starting ball size (1 = the model's own 1.8 m).
@export var pusher_base_scale: float = 0.55
## The character grows with (radius / start_radius) ^ this, a bit slower than the
## ball, so the ball ends up towering over them.
@export var pusher_scale_exponent: float = 0.6

var radius: float
var items_collected: int = 0
## Which way the character (and camera) faces. Not wrapped to -PI..PI, so the
## camera can smooth it without jumping.
var heading_yaw: float = 0.0

var _volume: float
var _walk_time: float = 0.0
var _bump_cooldown: float = 0.0
var _mouse_turn: float = 0.0
var _query := PhysicsShapeQueryParameters3D.new()
var _query_shape := SphereShape3D.new()
## Everything stuck to the ball.
var _stuck: Array[StuckItem] = []

@onready var _collision: CollisionShape3D = %Collision
@onready var _roller: Node3D = %Roller
@onready var _core: MeshInstance3D = %Core
@onready var _pusher: Node3D = %Pusher
@onready var _pusher_model: Node3D = %PusherModel


class StuckItem:
	var visual: Node3D
	var direction: Vector3
	var size: float
	## Where it was (Roller space) when picked up, and how far into snapping on it is (0..1).
	var start: Vector3
	var settle: float = 0.0


func _ready() -> void:
	_query.shape = _query_shape
	_query.collision_mask = PROPS_LAYER
	_query.exclude = [get_rid()]
	_collision.shape = _collision.shape.duplicate() # We resize it, so don't share it.
	_volume = _sphere_volume(start_radius)
	heading_yaw = rotation.y
	rotation.y = 0.0 # The body never rotates; the scene's rotation just sets the starting heading.
	if camera:
		camera.manual_rotation = false
		camera.snap_yaw(heading_yaw)
	_set_radius(start_radius)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and Input.is_action_pressed("camera_rotate_drag"):
		_mouse_turn -= motion.relative.x * mouse_turn_sensitivity


func _physics_process(delta: float) -> void:
	_bump_cooldown -= delta
	if not is_on_floor():
		velocity += get_gravity() * delta

	var turn := Input.get_axis("move_right", "move_left") \
		+ Input.get_axis("camera_rotate_right", "camera_rotate_left")
	heading_yaw += clampf(turn, -1.0, 1.0) * turn_speed * delta + _mouse_turn
	_mouse_turn = 0.0
	if camera:
		camera.set_yaw(heading_yaw)

	var throttle := Input.get_axis("move_back", "move_forward")
	var direction := get_forward() * throttle

	var top_speed := get_top_speed()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := (acceleration if throttle != 0.0 else deceleration) * top_speed
	horizontal = horizontal.move_toward(direction * top_speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var speed_before := horizontal.length()
	var before := global_position
	move_and_slide()
	var moved := global_position - before
	moved.y = 0.0

	_roll(moved)
	_handle_collisions(speed_before / top_speed)
	_absorb_touching()
	_settle_items(delta)
	_update_pusher(moved.length() / maxf(delta, 0.0001), absf(turn), delta)


## Flat direction the character is facing (and pushing toward).
func get_forward() -> Vector3:
	return Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))


## The ball can pick up `item` at its current size.
func can_absorb(item: Collectible) -> bool:
	return item.size <= radius * pickup_ratio


func get_top_speed() -> float:
	return base_speed * pow(radius / start_radius, speed_exponent)


## Turns the Roller as if the ball rolled `moved` along the ground.
func _roll(moved: Vector3) -> void:
	var distance := moved.length()
	if distance < 0.0001:
		return
	var axis := Vector3.UP.cross(moved / distance)
	_roller.basis = (Basis(axis, distance / radius) * _roller.basis).orthonormalized()


func _handle_collisions(speed_ratio: float) -> void:
	for i: int in get_slide_collision_count():
		var item := get_slide_collision(i).get_collider() as Collectible
		if item == null:
			continue
		if can_absorb(item):
			_absorb(item)
		elif _bump_cooldown <= 0.0 and speed_ratio > 0.4:
			_bump_cooldown = 0.35
			bumped.emit(clampf(speed_ratio, 0.0, 1.0))


## Picks up everything small enough that's touching the ball (or very nearly).
func _absorb_touching() -> void:
	_query_shape.radius = radius * 1.08 + 0.03
	_query.transform = Transform3D(Basis.IDENTITY, _roller.global_position)
	var hits := get_world_3d().direct_space_state.intersect_shape(_query, 32)
	for hit: Dictionary in hits:
		var item := hit.collider as Collectible
		if item and item.collision_layer != 0 and can_absorb(item):
			_absorb(item)


func _absorb(item: Collectible) -> void:
	if item.collision_layer == 0:
		return # Already picked up this frame.
	var center := item.global_position
	var stuck := StuckItem.new()
	stuck.visual = item.detach_visual(_roller)
	stuck.size = item.size
	stuck.start = stuck.visual.position
	var local := _roller.to_local(center)
	stuck.direction = local.normalized() if local.length() > 0.001 else Vector3.UP
	_stuck.append(stuck)

	items_collected += 1
	_volume += item.volume * growth
	_set_radius(pow(_volume * 3.0 / (4.0 * PI), 1.0 / 3.0))
	item_collected.emit(item)


## Where a stuck item sits at the current size: on the surface, poking out a bit.
func _surface_position(stuck: StuckItem) -> Vector3:
	return stuck.direction * (radius + stuck.size * stick_out)


## Eases newly picked-up items onto the surface.
func _settle_items(delta: float) -> void:
	for stuck: StuckItem in _stuck:
		if stuck.settle >= 1.0:
			continue
		stuck.settle = minf(stuck.settle + delta / SETTLE_TIME, 1.0)
		var t := 1.0 - pow(1.0 - stuck.settle, 2.0) # Ease out.
		stuck.visual.position = stuck.start.lerp(_surface_position(stuck), t)


## Pushes every settled item back out to the surface, so nothing gets buried.
func _layout_items() -> void:
	for stuck: StuckItem in _stuck:
		if stuck.settle >= 1.0:
			stuck.visual.position = _surface_position(stuck)


func _set_radius(new_radius: float) -> void:
	radius = new_radius
	var sphere := _collision.shape as SphereShape3D
	sphere.radius = radius
	_collision.position.y = radius
	_roller.position.y = radius
	_core.scale = Vector3.ONE * radius
	floor_snap_length = maxf(0.1, radius * 0.25)
	_layout_items()
	if camera:
		camera.distance_scale = radius / start_radius
		camera.focus_height = radius * 1.35
	radius_changed.emit(radius)


## Keeps the character behind the ball, hands on it, facing the heading.
func _update_pusher(speed: float, turning: float, delta: float) -> void:
	var pusher_scale := pusher_base_scale * pow(radius / start_radius, pusher_scale_exponent)
	# Stand so the hands (about chest height) touch the ball's surface.
	var hand_height := minf(0.9 * pusher_scale, radius)
	var reach := sqrt(maxf(radius * radius - pow(radius - hand_height, 2.0), 0.0))
	_pusher.position = -get_forward() * (reach + 0.4 * pusher_scale)
	_pusher.rotation.y = heading_yaw
	_pusher.scale = Vector3.ONE * pusher_scale

	# A little bounce and lean while walking (turning in place counts as walking).
	var walk := clampf(maxf(speed / get_top_speed(), turning * 0.6), 0.0, 1.0)
	_walk_time += delta * (4.0 + 8.0 * walk) * walk
	_pusher_model.position.y = absf(sin(_walk_time * PI)) * 0.08 * walk
	_pusher_model.rotation.x = -0.25 * walk


static func _sphere_volume(r: float) -> float:
	return 4.0 / 3.0 * PI * r * r * r
