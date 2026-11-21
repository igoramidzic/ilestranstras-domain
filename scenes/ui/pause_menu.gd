extends CanvasLayer
## Pause overlay. Autoloaded as `PauseMenu` (it's a scene autoload), so every
## gameplay scene gets pausing for free. It only reacts while
## Game.is_in_gameplay is true, so menus never pause.
##
## process_mode is ALWAYS (set in the .tscn) so this keeps working while the
## rest of the tree is paused.

@onready var _root: Control = %Root
@onready var _panel: Control = %Panel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	_root.hide()
	_settings_menu.hide()
	_quit_button.visible = Game.can_quit()

	_resume_button.pressed.connect(Game.set_paused.bind(false))
	_settings_button.pressed.connect(_open_settings)
	_main_menu_button.pressed.connect(Game.return_to_main_menu)
	_quit_button.pressed.connect(Game.quit)
	_settings_menu.closed.connect(_on_settings_closed)
	Game.paused_changed.connect(_on_paused_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if not Game.is_in_gameplay or SceneManager.is_transitioning:
		return
	get_viewport().set_input_as_handled()
	Game.toggle_pause()


func _on_paused_changed(is_paused: bool) -> void:
	_root.visible = is_paused
	if is_paused:
		_settings_menu.hide()
		_panel.show()
		_resume_button.grab_focus()


func _open_settings() -> void:
	_panel.hide()
	_settings_menu.open()


func _on_settings_closed() -> void:
	_panel.show()
	_settings_button.grab_focus()
