extends Control
## Boot splash: the first scene that runs (Project Settings > Application > Run > Main Scene).
##
## By the time this runs, the autoloads (Settings, SceneManager, Game, PauseMenu)
## are already loaded, so settings like volume and fullscreen are applied.
## Any key or click skips ahead to the main menu.

@export var hold_time: float = 1.2

var _leaving: bool = false

@onready var _content: Control = %Content
@onready var _title: Label = %Title


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name")).capitalize()
	_content.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_content, "modulate:a", 1.0, 0.6)
	tween.tween_interval(hold_time)
	tween.finished.connect(_go_to_main_menu)


func _unhandled_input(event: InputEvent) -> void:
	var is_skip := event is InputEventKey or event is InputEventMouseButton
	if is_skip and event.is_pressed() and not event.is_echo():
		get_viewport().set_input_as_handled()
		_go_to_main_menu()


func _go_to_main_menu() -> void:
	if _leaving:
		return
	_leaving = true
	SceneManager.change_scene(Game.MAIN_MENU_SCENE)
