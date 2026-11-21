extends CanvasLayer
## Scene transitions with a fade to black and background (threaded) loading.
##
## Autoloaded as `SceneManager`. Always change scenes through
## `SceneManager.change_scene(path)` instead of calling
## `get_tree().change_scene_to_file()` directly, so every transition looks the
## same and big levels load without freezing the window.

signal transition_started
## Emitted once the new scene is in the tree (screen is still black).
signal scene_changed(scene: Node)
signal transition_finished

@export var fade_duration: float = 0.3

var is_transitioning: bool = false

var _fade: ColorRect


func _ready() -> void:
	layer = 128 # Above everything, including the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func change_scene(path: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	transition_started.emit()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP # Swallow clicks mid-transition.

	# Start loading in the background while we fade out.
	var request_error := ResourceLoader.load_threaded_request(path)
	if request_error != OK:
		push_error("SceneManager: could not start loading '%s' (error %d)" % [path, request_error])
		_finish_transition()
		return

	await _fade_to(1.0)
	var packed := await _wait_for_load(path)
	if packed == null:
		push_error("SceneManager: failed to load '%s'" % path)
		await _fade_to(0.0)
		_finish_transition()
		return

	get_tree().change_scene_to_packed(packed)
	await get_tree().scene_changed
	scene_changed.emit(get_tree().current_scene)

	await _fade_to(0.0)
	_finish_transition()


func _wait_for_load(path: String) -> PackedScene:
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	return ResourceLoader.load_threaded_get(path) as PackedScene


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, fade_duration)
	await tween.finished


func _finish_transition() -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	transition_finished.emit()
