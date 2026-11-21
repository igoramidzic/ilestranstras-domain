extends Node
## Player-facing settings (audio, video), saved to user://settings.cfg.
##
## Autoloaded as `Settings`. To add an option: add a default to DEFAULTS,
## handle it in _apply(), and add a control to the settings menu.
## On macOS the file lives in ~/Library/Application Support/Godot/app_userdata/<project>/.

signal changed(section: String, key: String, value: Variant)

const SAVE_PATH := "user://settings.cfg"
const DEFAULTS: Dictionary = {
	"audio": {"master": 1.0, "music": 0.8, "sfx": 0.8},
	"video": {"fullscreen": false, "vsync": true},
}
## Settings key -> audio bus name (see resources/audio/default_bus_layout.tres).
const AUDIO_BUSES: Dictionary = {"master": "Master", "music": "Music", "sfx": "SFX"}

var _config := ConfigFile.new()
var _dirty := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var err := _config.load(SAVE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Settings: could not read %s (error %d), using defaults" % [SAVE_PATH, err])
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			_apply(section, key, get_value(section, key))


func get_value(section: String, key: String) -> Variant:
	return _config.get_value(section, key, DEFAULTS[section][key])


## Applies the change immediately. Call save() to write it to disk
## (the settings menu does this when it closes, and Game.quit() does too).
func set_value(section: String, key: String, value: Variant) -> void:
	if get_value(section, key) == value:
		return
	_config.set_value(section, key, value)
	_dirty = true
	_apply(section, key, value)
	changed.emit(section, key, value)


func save() -> void:
	if not _dirty:
		return
	var err := _config.save(SAVE_PATH)
	if err != OK:
		push_error("Settings: could not write %s (error %d)" % [SAVE_PATH, err])
		return
	_dirty = false


func _apply(section: String, key: String, value: Variant) -> void:
	match section:
		"audio":
			var bus := AudioServer.get_bus_index(AUDIO_BUSES[key])
			if bus == -1:
				push_warning("Settings: audio bus '%s' not found" % AUDIO_BUSES[key])
				return
			var linear := float(value)
			AudioServer.set_bus_volume_db(bus, linear_to_db(linear))
			AudioServer.set_bus_mute(bus, linear <= 0.0)
		"video":
			match key:
				"fullscreen":
					var mode := DisplayServer.window_get_mode()
					var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
							or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
					if is_fullscreen != bool(value):
						DisplayServer.window_set_mode(
								DisplayServer.WINDOW_MODE_FULLSCREEN if value
								else DisplayServer.WINDOW_MODE_WINDOWED)
				"vsync":
					DisplayServer.window_set_vsync_mode(
							DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
