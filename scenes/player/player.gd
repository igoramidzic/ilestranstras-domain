class_name Player
extends CharacterBody3D
## Top-down character controller.
##
## - WASD / arrows move relative to the camera (W = up the screen).
## - The body turns to face the mouse cursor.
## - Left mouse fires `primary_action_started`; `is_primary_action_held` tells
##   you if it's still held. The player doesn't decide what the action does:
##   the level (or a weapon/ability node later) listens and reacts.
##
## Godot's forward is -Z. The imported model faces +Z, so the Model node in
## player.tscn is rotated 180 degrees.

signal primary_action_started

## The camera used for camera-relative movement and mouse aiming.
@export var camera: TopDownCamera

@export_group("Movement")
@export var move_speed: float = 7.0
@export var acceleration: float = 50.0
@export var deceleration: float = 60.0
## How fast the body turns toward the cursor. Higher = snappier.
@export var turn_speed: float = 18.0

## The point on the ground the player is aiming at (world space).
var aim_point: Vector3
var is_primary_action_held: bool = false

@onready var aim_origin: Marker3D = %AimOrigin


func _ready() -> void:
	aim_point = global_position - global_basis.z


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_update_movement(delta)
	_update_aim(delta)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("primary_action"):
		is_primary_action_held = true
		primary_action_started.emit()


func _input(event: InputEvent) -> void:
	# Releases are caught in _input (not _unhandled_input) so they're never
	# missed, e.g. when the button is released over a UI element.
	if event.is_action_released("primary_action"):
		is_primary_action_held = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		# We won't see the release while paused, so don't get stuck "held".
		is_primary_action_held = false


## Flat (horizontal) direction from the aim origin toward the cursor.
func get_aim_direction() -> Vector3:
	var to_aim := aim_point - aim_origin.global_position
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.25:
		var forward := -global_basis.z
		forward.y = 0.0
		return forward.normalized()
	return to_aim.normalized()


func _update_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input.x, 0.0, input.y)
	if camera:
		direction = camera.get_yaw_basis() * direction

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if direction != Vector3.ZERO else deceleration
	horizontal = horizontal.move_toward(direction * move_speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_aim(delta: float) -> void:
	if camera == null:
		return
	var hit: Variant = camera.get_mouse_ground_point(global_position.y)
	if hit == null:
		return
	aim_point = hit

	var to_aim := aim_point - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.01:
		return
	var target_yaw := atan2(-to_aim.x, -to_aim.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
