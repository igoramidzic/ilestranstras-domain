extends Node
## Global game flow: starting a run, returning to the menu, pausing and quitting.
##
## Autoloaded as `Game`, so any script can call e.g. `Game.start_game()`.
## Scene paths live here so there is exactly one place to change them.

signal paused_changed(is_paused: bool)

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## The scene the "Play" button loads. Point this at your first real level
## once you delete the sandbox (see README.md).
const GAMEPLAY_SCENE := "res://scenes/levels/rolling_field/rolling_field.tscn"
## Auto-pause when the game window loses focus (alt-tab). Turn off if it gets
## in your way while debugging with the editor side by side.
const PAUSE_ON_FOCUS_LOSS := true

## True while a gameplay scene is loaded (as opposed to a menu).
## The pause menu only responds when this is true.
var is_in_gameplay: bool = false


func _ready() -> void:
	# Keep running while the tree is paused, so we can unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Route the window close button through quit() so settings get saved.
	get_tree().set_auto_accept_quit(false)
	SceneManager.scene_changed.connect(_on_scene_changed)
	print("%s v%s starting" % [
		ProjectSettings.get_setting("application/config/name"),
		ProjectSettings.get_setting("application/config/version", "0.0.0"),
	])


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if PAUSE_ON_FOCUS_LOSS and is_in_gameplay and not SceneManager.is_transitioning:
				set_paused(true)


func start_game() -> void:
	if SceneManager.is_transitioning:
		return
	is_in_gameplay = true
	SceneManager.change_scene(GAMEPLAY_SCENE)


func return_to_main_menu() -> void:
	if SceneManager.is_transitioning:
		return
	is_in_gameplay = false
	SceneManager.change_scene(MAIN_MENU_SCENE)


func is_paused() -> bool:
	return get_tree().paused


func set_paused(value: bool) -> void:
	if get_tree().paused == value:
		return
	get_tree().paused = value
	paused_changed.emit(value)


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


## Web builds can't close their own tab, so menus hide "Quit" there.
func can_quit() -> bool:
	return not OS.has_feature("web")


func quit() -> void:
	Settings.save()
	get_tree().quit()


func _on_scene_changed(_scene: Node) -> void:
	# Every freshly loaded scene starts unpaused.
	set_paused(false)
