class_name SandboxOrb
extends Area3D
## DEMO: glowing pickup. Emits `collected` when the player walks into it.

signal collected(orb: SandboxOrb)

const RADIUS := 0.35

var _time: float = randf() * TAU
var _mesh: MeshInstance3D


func _init() -> void:
	collision_layer = 16 # "pickups"
	collision_mask = 2 # "player"
	monitorable = false

	var shape := SphereShape3D.new()
	shape.radius = RADIUS + 0.2
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	var material := StandardMaterial3D.new()
	var color := Color.from_hsv(randf_range(0.08, 0.16), 0.8, 1.0)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.material = material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_time += delta
	_mesh.position.y = sin(_time * 3.0) * 0.15


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		collected.emit(self)
