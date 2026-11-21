class_name SandboxProjectile
extends RigidBody3D
## DEMO: a glowing ball that knocks crates around, then disappears.

const RADIUS := 0.15
const LIFETIME := 2.5


func _init() -> void:
	collision_layer = 8 # "projectiles"
	collision_mask = 1 | 4 # "world" + "props"
	mass = 0.6
	gravity_scale = 0.3
	continuous_cd = true # Fast bodies can tunnel through thin objects without this.

	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.9, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.4, 0.85, 1.0)
	material.emission_energy_multiplier = 4.0
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.material = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _ready() -> void:
	# process_always = false, so the timer stops while the game is paused.
	get_tree().create_timer(LIFETIME, false).timeout.connect(queue_free)
