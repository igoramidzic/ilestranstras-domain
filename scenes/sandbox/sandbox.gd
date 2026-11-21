extends Node3D
## DEMO SANDBOX: a throwaway playground so there's something to poke at.
## Delete the whole scenes/sandbox/ folder when you start the real game
## (see README.md > "Removing the sandbox").
##
## Collect the glowing orbs, hold left mouse to shoot, knock the crates around.
## Press R to drop more crates.

const TREE_SCENE := preload("res://assets/models/props/tree.blend")
const ROCK_SCENE := preload("res://assets/models/props/rock.blend")

const ARENA_HALF_SIZE := 20.0
const WALL_HEIGHT := 1.5
const TREE_COUNT := 14
const ROCK_COUNT := 12
const CRATE_COUNT := 24
const ORB_COUNT := 6
const FIRE_COOLDOWN := 0.12
const PROJECTILE_SPEED := 28.0
## Keep spawns this far from the player's start so you don't begin inside a tree.
const SAFE_RADIUS := 4.0

var _score: int = 0
var _fire_cooldown: float = 0.0

@onready var _player: Player = %Player
@onready var _camera: TopDownCamera = %CameraRig
@onready var _props: Node3D = %Props
@onready var _crates: Node3D = %Crates
@onready var _orbs: Node3D = %Orbs
@onready var _projectiles: Node3D = %Projectiles
@onready var _aim_marker: MeshInstance3D = %AimMarker
@onready var _score_label: Label = %ScoreLabel
@onready var _blip_player: AudioStreamPlayer = %BlipPlayer
@onready var _pop_player: AudioStreamPlayer = %PopPlayer


func _ready() -> void:
	_blip_player.stream = _make_tone(880.0, 0.09)
	_pop_player.stream = _make_tone(240.0, 0.05)

	_build_walls()
	for i: int in TREE_COUNT:
		_spawn_prop(TREE_SCENE, randf_range(0.8, 1.4))
	for i: int in ROCK_COUNT:
		_spawn_prop(ROCK_SCENE, randf_range(0.6, 1.8))
	for i: int in CRATE_COUNT:
		_spawn_crate()
	for i: int in ORB_COUNT:
		_spawn_orb()
	_update_hud()


func _process(_delta: float) -> void:
	var point: Variant = _camera.get_mouse_ground_point(0.03)
	_aim_marker.visible = point != null
	if point != null:
		_aim_marker.global_position = point


func _physics_process(delta: float) -> void:
	_fire_cooldown -= delta
	if _player.is_primary_action_held and _fire_cooldown <= 0.0:
		_fire_cooldown = FIRE_COOLDOWN
		_fire()

	for crate: Node3D in _crates.get_children():
		if crate.global_position.y < -20.0: # Knocked out of the arena.
			crate.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Sandbox-only shortcut, so it isn't in the project's input map.
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_R:
		for i: int in 10:
			_spawn_crate()


func _fire() -> void:
	var projectile := SandboxProjectile.new()
	_projectiles.add_child(projectile)
	projectile.global_position = _player.aim_origin.global_position
	projectile.linear_velocity = _player.get_aim_direction() * PROJECTILE_SPEED
	projectile.reset_physics_interpolation()
	_pop_player.pitch_scale = randf_range(0.9, 1.1)
	_pop_player.play()


func _on_orb_collected(orb: SandboxOrb) -> void:
	_score += 1
	_update_hud()
	_blip_player.pitch_scale = 1.0 + minf(_score, 24) * 0.03
	_blip_player.play()
	# Move it somewhere else instead of freeing it. Deferred because we're in
	# the middle of a physics callback.
	_respawn_orb.call_deferred(orb)


func _respawn_orb(orb: SandboxOrb) -> void:
	orb.global_position = _random_point(2.0) + Vector3.UP * 0.8
	orb.reset_physics_interpolation()


func _update_hud() -> void:
	_score_label.text = "Orbs: %d" % _score


# --- world building ----------------------------------------------------------

func _random_point(margin: float) -> Vector3:
	var limit := ARENA_HALF_SIZE - margin
	for attempt: int in 20:
		var point := Vector3(randf_range(-limit, limit), 0.0, randf_range(-limit, limit))
		if point.distance_to(_player.global_position) > SAFE_RADIUS:
			return point
	return Vector3(limit, 0.0, limit)


func _spawn_prop(scene: PackedScene, scale_factor: float) -> void:
	var prop := scene.instantiate() as Node3D
	_props.add_child(prop)
	prop.global_position = _random_point(2.0)
	prop.rotation.y = randf() * TAU
	prop.scale = Vector3.ONE * scale_factor


func _spawn_crate() -> void:
	var size := randf_range(0.6, 1.5)
	var crate := RigidBody3D.new()
	crate.collision_layer = 4 # "props"
	crate.collision_mask = 1 | 2 | 4 | 8 # world, player, props, projectiles
	crate.mass = size * size * size * 1.5

	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	crate.add_child(collision)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(randf(), 0.5, 0.9)
	material.roughness = 0.7
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	box.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	crate.add_child(mesh)

	_crates.add_child(crate)
	# Drop them in from above for a bit of fun.
	crate.global_position = _random_point(2.0) + Vector3.UP * randf_range(3.0, 10.0)
	crate.rotation = Vector3(randf(), randf(), randf()) * TAU
	crate.reset_physics_interpolation()


func _spawn_orb() -> void:
	var orb := SandboxOrb.new()
	orb.collected.connect(_on_orb_collected)
	_orbs.add_child(orb)
	orb.global_position = _random_point(2.0) + Vector3.UP * 0.8


func _build_walls() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.11, 0.14)
	var length := ARENA_HALF_SIZE * 2.0 + 1.0
	var walls := {
		Vector3(0, 0, -ARENA_HALF_SIZE - 0.5): Vector3(length, WALL_HEIGHT, 1.0),
		Vector3(0, 0, ARENA_HALF_SIZE + 0.5): Vector3(length, WALL_HEIGHT, 1.0),
		Vector3(-ARENA_HALF_SIZE - 0.5, 0, 0): Vector3(1.0, WALL_HEIGHT, length),
		Vector3(ARENA_HALF_SIZE + 0.5, 0, 0): Vector3(1.0, WALL_HEIGHT, length),
	}
	for center: Vector3 in walls:
		var size: Vector3 = walls[center]
		var wall := StaticBody3D.new()
		wall.collision_layer = 1 # "world"
		wall.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		wall.add_child(collision)
		var box := BoxMesh.new()
		box.size = size
		box.material = material
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		wall.add_child(mesh)
		add_child(wall)
		wall.position = center + Vector3.UP * (WALL_HEIGHT * 0.5)


# --- audio -------------------------------------------------------------------

## Generates a short beep so the demo has sound without any audio files.
## Real sounds go in assets/audio/ and play through the "SFX" bus.
static func _make_tone(frequency: float, duration: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i: int in sample_count:
		var t := float(i) / mix_rate
		var envelope := 1.0 - float(i) / sample_count
		var sample := sin(TAU * frequency * t) * envelope * 0.35
		data.encode_s16(i * 2, int(sample * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav
