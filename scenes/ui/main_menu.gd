extends Control
## Title screen: Play / Settings / Quit.

@onready var _menu: Control = %Menu
@onready var _title: Label = %Title
@onready var _version_label: Label = %VersionLabel
@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name")).capitalize()
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	_quit_button.visible = Game.can_quit()

	_play_button.pressed.connect(Game.start_game)
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(Game.quit)
	_settings_menu.closed.connect(_on_settings_closed)

	_settings_menu.hide()
	_play_button.grab_focus() # Lets keyboard users navigate with arrows + Enter.


func _open_settings() -> void:
	_menu.hide()
	_settings_menu.open()


func _on_settings_closed() -> void:
	_menu.show()
	_settings_button.grab_focus()
