class_name TopDownCamera
extends Node3D
## Top-down follow camera.
##
## Follows `target`, rotates around it (Q/E or hold right mouse + drag) and
## zooms with the mouse wheel. Zooming in also flattens the angle a bit.
##
## Structure:  TopDownCamera (yaw, sits on the target)
##               └ Pivot (pitch)
##                   └ Camera (pulled back by the zoom distance)
##
## Also answers "what's under the mouse?" for aiming and clicking on things.
## The camera moves in _process (every rendered frame), so physics
## interpolation is turned off for this node in the scene.

@export var target: Node3D

@export_group("Follow")
## Higher = snappier follow. 0 = don't follow.
@export var follow_speed: float = 10.0

@export_group("Zoom")
@export var min_distance: float = 8.0
@export var max_distance: float = 28.0
@export var start_distance: float = 16.0
@export var zoom_step: float = 2.0
@export var zoom_speed: float = 10.0
## Pitch in degrees when fully zoomed in (negative looks down).
@export var pitch_near: float = -45.0
## Pitch in degrees when fully zoomed out.
@export var pitch_far: float = -65.0

@export_group("Rotation")
## Radians per second while holding Q/E.
@export var key_rotate_speed: float = 2.5
## Radians per pixel of mouse movement while right-dragging.
@export var mouse_rotate_sensitivity: float = 0.008
@export var rotate_smoothing: float = 14.0

var _yaw: float
var _target_yaw: float
var _distance: float
var _target_distance: float

@onready var _pivot: Node3D = %Pivot
@onready var camera: Camera3D = %Camera


func _ready() -> void:
	_target_yaw = rotation.y
	_yaw = _target_yaw
	_target_distance = clampf(start_distance, min_distance, max_distance)
	_distance = _target_distance
	if target:
		global_position = _get_target_position()
	_apply_transform()


func _process(delta: float) -> void:
	var rotate_input := Input.get_axis("camera_rotate_right", "camera_rotate_left")
	_target_yaw += rotate_input * key_rotate_speed * delta

	_yaw = lerpf(_yaw, _target_yaw, _smoothing(rotate_smoothing, delta))
	_distance = lerpf(_distance, _target_distance, _smoothing(zoom_speed, delta))
	if target and follow_speed > 0.0:
		global_position = global_position.lerp(_get_target_position(), _smoothing(follow_speed, delta))
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_target_distance = clampf(_target_distance - zoom_step, min_distance, max_distance)
	elif event.is_action_pressed("zoom_out"):
		_target_distance = clampf(_target_distance + zoom_step, min_distance, max_distance)
	elif event is InputEventMouseMotion and Input.is_action_pressed("camera_rotate_drag"):
		_target_yaw -= (event as InputEventMouseMotion).relative.x * mouse_rotate_sensitivity


## Rotation around the vertical axis only. Multiply an input direction by this
## to make movement camera-relative ("W" always moves up the screen).
func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


## Where the mouse cursor points on a flat horizontal plane at `height`.
## Returns a Vector3, or null if the cursor points at the sky.
func get_mouse_ground_point(height: float = 0.0) -> Variant:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, height).intersects_ray(origin, direction)


## Physics raycast from the cursor into the world. Returns the hit info
## ({position, normal, collider, ...}) or an empty Dictionary if nothing was hit.
## Use `collision_mask` to only hit certain layers (see Project Settings > Layer Names).
func get_mouse_raycast(collision_mask: int = 0xFFFFFFFF, max_ray_length: float = 500.0) -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var end := origin + camera.project_ray_normal(mouse) * max_ray_length
	var query := PhysicsRayQueryParameters3D.create(origin, end, collision_mask)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _get_target_position() -> Vector3:
	# Use the interpolated transform so following stays smooth on high refresh
	# rate monitors (physics runs at 60 Hz, rendering may run faster).
	return target.get_global_transform_interpolated().origin


func _apply_transform() -> void:
	rotation.y = _yaw
	var zoom_t := inverse_lerp(min_distance, max_distance, _distance)
	_pivot.rotation.x = deg_to_rad(lerpf(pitch_near, pitch_far, zoom_t))
	camera.position = Vector3(0.0, 0.0, _distance)


## Frame-rate independent smoothing factor for lerp().
static func _smoothing(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * delta)
