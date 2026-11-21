extends Node3D
## Rolling field: push the sticky ball around, pick things up, grow.
##
## Items are scattered in rings: small things near the start, bigger things
## further out, so the level opens up as the ball grows.

const ARENA_HALF_SIZE := 90.0
const WALL_VISIBLE_HEIGHT := 3.0
## Walls are much taller than they look, so a huge ball can't roll over them.
const WALL_COLLISION_HEIGHT := 200.0
## Ball diameter (m) that counts as winning. You can keep rolling afterwards.
const GOAL_DIAMETER := 10.0
## Keep spawns this far from the start so the ball doesn't begin inside something.
const SAFE_RADIUS := 2.5

## [count, min size, max size, spawn ring inner radius, outer radius]
## Sizes are the longest side in meters, picked log-uniformly.
const TIERS: Array[Array] = [
	[320, 0.06, 0.32, 0.0, 20.0],
	[240, 0.25, 0.8, 4.0, 38.0],
	[180, 0.6, 2.0, 12.0, 60.0],
	[90, 1.8, 5.0, 25.0, 85.0],
	[30, 5.0, 14.0, 45.0, 85.0],
	# Some small stuff everywhere, so there's always something to grab.
	[160, 0.08, 0.5, 20.0, 88.0],
	[120, 0.4, 1.6, 35.0, 88.0],
]

var _catalog := ItemCatalog.new()
## Big things already placed, as [position, radius], so they don't overlap.
var _occupied: Array[Vector4] = []
var _goal_reached: bool = false

@onready var _ball: StickyBall = %Ball
@onready var _camera: TopDownCamera = %CameraRig
@onready var _sun: DirectionalLight3D = %Sun
@onready var _items: Node3D = %Items
@onready var _size_label: Label = %SizeLabel
@onready var _count_label: Label = %CountLabel
@onready var _toast_label: Label = %ToastLabel
@onready var _goal_label: Label = %GoalLabel
@onready var _blip_player: AudioStreamPlayer = %BlipPlayer
@onready var _bonk_player: AudioStreamPlayer = %BonkPlayer


func _ready() -> void:
	_blip_player.stream = _make_tone(660.0, 0.08)
	_bonk_player.stream = _make_tone(110.0, 0.12)
	_build_walls()
	for tier: Array in TIERS:
		_spawn_tier(tier[0], tier[1], tier[2], tier[3], tier[4])

	_ball.item_collected.connect(_on_item_collected)
	_ball.radius_changed.connect(_on_radius_changed)
	_ball.bumped.connect(_on_bumped)
	_toast_label.modulate.a = 0.0
	_goal_label.visible = false
	_on_radius_changed(_ball.radius)


func _process(_delta: float) -> void:
	# Keep shadows visible however far the camera has pulled back.
	_sun.directional_shadow_max_distance = maxf(40.0, _camera.get_view_distance() * 3.0)


func _on_item_collected(item: Collectible) -> void:
	_count_label.text = "Things: %d" % _ball.items_collected
	_toast_label.text = item.display_name
	_toast_label.modulate.a = 1.0
	var tween := _toast_label.create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)
	# Small things relative to the ball make high blips, big ones low.
	_blip_player.pitch_scale = clampf(1.8 - item.size / _ball.radius, 0.7, 1.8)
	_blip_player.play()


func _on_radius_changed(radius: float) -> void:
	var diameter := radius * 2.0
	_size_label.text = _format_length(diameter)
	_count_label.text = "Things: %d" % _ball.items_collected
	if not _goal_reached and diameter >= GOAL_DIAMETER:
		_goal_reached = true
		_goal_label.text = "%s! Goal reached. Keep rolling." % _format_length(GOAL_DIAMETER)
		_goal_label.visible = true
		var tween := _goal_label.create_tween()
		tween.tween_interval(4.0)
		tween.tween_property(_goal_label, "modulate:a", 0.0, 1.0)


func _on_bumped(strength: float) -> void:
	_bonk_player.volume_db = linear_to_db(0.4 + 0.6 * strength)
	_bonk_player.pitch_scale = randf_range(0.9, 1.1)
	_bonk_player.play()


## "45 cm", "1 m 20 cm", "12 m".
static func _format_length(meters: float) -> String:
	if meters < 1.0:
		return "%d cm" % int(meters * 100.0)
	if meters < 10.0:
		return "%d m %d cm" % [int(meters), int(fmod(meters, 1.0) * 100.0)]
	return "%d m" % int(meters)


# --- world building ----------------------------------------------------------

func _spawn_tier(count: int, min_size: float, max_size: float, inner: float, outer: float) -> void:
	for i: int in count:
		var size := exp(randf_range(log(min_size), log(max_size)))
		var item := _catalog.make_item(size)
		var footprint := Vector2(item.extents.x, item.extents.z).length() * 0.5
		var point: Variant = _find_spot(footprint, inner, outer)
		if point == null:
			item.free()
			continue
		_items.add_child(item)
		var spot: Vector3 = point
		item.position = spot + Vector3.UP * (item.extents.y * 0.5)
		item.rotation.y = randf() * TAU
		# Only bother keeping big things apart; small ones can sit wherever.
		if size >= 0.6:
			_occupied.append(Vector4(spot.x, spot.z, footprint, 0.0))


## A random free point on the ground in the ring between `inner` and `outer`,
## or null if nothing was found.
func _find_spot(footprint: float, inner: float, outer: float) -> Variant:
	var limit := ARENA_HALF_SIZE - footprint - 1.0
	for attempt: int in 30:
		var distance := sqrt(randf_range(inner * inner, outer * outer))
		var angle := randf() * TAU
		var point := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		point.x = clampf(point.x, -limit, limit)
		point.z = clampf(point.z, -limit, limit)
		if Vector2(point.x, point.z).length() < SAFE_RADIUS + footprint:
			continue
		if _is_free(point, footprint):
			return point
	return null


func _is_free(point: Vector3, footprint: float) -> bool:
	for other: Vector4 in _occupied:
		if Vector2(point.x - other.x, point.z - other.y).length() < footprint + other.z + 0.3:
			return false
	return true


func _build_walls() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.3, 0.36)
	var length := ARENA_HALF_SIZE * 2.0 + 2.0
	var sides := {
		Vector3(0, 0, -ARENA_HALF_SIZE - 1.0): Vector2(length, 2.0),
		Vector3(0, 0, ARENA_HALF_SIZE + 1.0): Vector2(length, 2.0),
		Vector3(-ARENA_HALF_SIZE - 1.0, 0, 0): Vector2(2.0, length),
		Vector3(ARENA_HALF_SIZE + 1.0, 0, 0): Vector2(2.0, length),
	}
	for center: Vector3 in sides:
		var footprint: Vector2 = sides[center]
		var wall := StaticBody3D.new()
		wall.collision_layer = 1 # "world"
		wall.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(footprint.x, WALL_COLLISION_HEIGHT, footprint.y)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = WALL_COLLISION_HEIGHT * 0.5
		wall.add_child(collision)
		var box := BoxMesh.new()
		box.size = Vector3(footprint.x, WALL_VISIBLE_HEIGHT, footprint.y)
		box.material = material
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.position.y = WALL_VISIBLE_HEIGHT * 0.5
		wall.add_child(mesh)
		add_child(wall)
		wall.position = center


# --- audio -------------------------------------------------------------------

## A short beep, so there's sound without any audio files.
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
