class_name SettingsMenu
extends Control
## Settings screen. Reused by the main menu and the pause menu:
## call open(), listen for `closed`.

signal closed

@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _vsync_check: CheckButton = %VsyncCheck
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_master_slider.value_changed.connect(
			func(value: float) -> void: Settings.set_value("audio", "master", value))
	_music_slider.value_changed.connect(
			func(value: float) -> void: Settings.set_value("audio", "music", value))
	_sfx_slider.value_changed.connect(
			func(value: float) -> void: Settings.set_value("audio", "sfx", value))
	_fullscreen_check.toggled.connect(
			func(on: bool) -> void: Settings.set_value("video", "fullscreen", on))
	_vsync_check.toggled.connect(
			func(on: bool) -> void: Settings.set_value("video", "vsync", on))
	_back_button.pressed.connect(close)


func open() -> void:
	_sync_from_settings()
	show()
	_master_slider.grab_focus()


func close() -> void:
	Settings.save()
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _sync_from_settings() -> void:
	_master_slider.set_value_no_signal(Settings.get_value("audio", "master"))
	_music_slider.set_value_no_signal(Settings.get_value("audio", "music"))
	_sfx_slider.set_value_no_signal(Settings.get_value("audio", "sfx"))
	_fullscreen_check.set_pressed_no_signal(Settings.get_value("video", "fullscreen"))
	_vsync_check.set_pressed_no_signal(Settings.get_value("video", "vsync"))
