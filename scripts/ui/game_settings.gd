class_name GameSettings
extends RefCounted
## The player's settings (the pause menu's SETTINGS screen, scripts/ui/pause_menu.gd): mouse
## sensitivity and invert, the camera's field of view on foot and in a car, the Master / World /
## Ambience bus volumes, graphics toggles over Quality's and CameraPost's knobs (motion blur,
## depth of field, film grain, vignette, render scale) and the HUD's scale. Kept in a ConfigFile
## at `path` (user://settings.cfg), loaded and applied once the city scene is up (PauseMenu's
## _ready), applied again on every change in the menu and saved when the screen is left.
##
## Every default is what the game did before settings existed, so an empty or missing file changes
## nothing. Values are multipliers on each knob's own number where the knob has one (sensitivity,
## render scale, HUD scale), so a tuned export stays the base. `SETTINGS_MENU=0` in the environment
## is the A/B: no screen, nothing loaded or applied. The smoke test never reads the player's own
## file (`path` is a test path there and a SmokeTest root skips the load).

## Where the settings live.
static var path: String = "user://settings.cfg"
## The values in force (keys of DEFAULTS).
static var values: Dictionary = {}
## Multiplier on every HUD piece's window scale (MinimapFrame.hud_scale(), WeaponHud, WantedHud).
static var hud_scale: float = 1.0
static var _loaded: bool = false

const SECTION := "settings"
## Key, default. Defaults are the game as it was.
const DEFAULTS := {
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"fov": 75.0,
	"car_fov": 75.0,
	"volume_master": 1.0,
	"volume_world": 1.0,
	"volume_ambience": 1.0,
	"motion_blur": true,
	"depth_of_field": true,
	"film_grain": true,
	"vignette": true,
	"render_scale": 1.0,
	"hud_scale": 1.0,
}
## Number ranges: min, max, step.
const RANGES := {
	"mouse_sensitivity": [0.2, 3.0, 0.05],
	"fov": [55.0, 100.0, 1.0],
	"car_fov": [55.0, 110.0, 1.0],
	"volume_master": [0.0, 1.0, 0.01],
	"volume_world": [0.0, 1.0, 0.01],
	"volume_ambience": [0.0, 1.0, 0.01],
	"render_scale": [0.5, 1.0, 0.05],
	"hud_scale": [0.75, 1.5, 0.05],
}
## Bus per volume key (Sfx._install_buses() makes them).
const BUSES := {"volume_master": &"Master", "volume_world": &"World", "volume_ambience": &"Ambience"}


static func enabled() -> bool:
	return OS.get_environment("SETTINGS_MENU") != "0"


## The value of `key` (its default until loaded or set).
static func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


## Sets `key` to `v`, clamped to its range and snapped to its step; returns what was stored.
static func set_value(key: String, v: Variant) -> Variant:
	if not DEFAULTS.has(key):
		return null
	values[key] = sanitize(key, v)
	return values[key]


## `v` as `key` takes it: a bool for a toggle, a number clamped and snapped for a slider.
static func sanitize(key: String, v: Variant) -> Variant:
	var d: Variant = DEFAULTS[key]
	if d is bool:
		return bool(v)
	var f := float(v) if (v is float or v is int) else float(d)
	if is_nan(f) or is_inf(f):
		f = float(d)
	var r: Array = RANGES.get(key, [])
	if r.size() == 3:
		f = clampf(snappedf(f, r[2]), r[0], r[1])
	return f


static func reset() -> void:
	# hud_scale itself follows in apply(), which also lays the HUD out again.
	values = DEFAULTS.duplicate()


## Reads `path`; missing keys (or no file) take their defaults, bad values are sanitized.
static func load_file() -> void:
	reset()
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: String in DEFAULTS:
		if cfg.has_section_key(SECTION, key):
			values[key] = sanitize(key, cfg.get_value(SECTION, key))


static func save_file() -> int:
	var cfg := ConfigFile.new()
	for key: String in DEFAULTS:
		cfg.set_value(SECTION, key, get_value(key))
	return cfg.save(path)


## Loads once a session (the menu's _ready on every city load re-applies what is in memory).
static func ensure_loaded() -> void:
	if not _loaded:
		load_file()


## Pushes every value onto the running game. `scene` is the city scene root (the pause menu's
## parent); the camera is the player's.
static func apply(scene: Node) -> void:
	if scene == null or not scene.is_inside_tree():
		return
	var tree := scene.get_tree()
	_apply_camera(tree)
	_apply_audio()
	_apply_post(tree)
	_apply_vignette(scene)
	var quality := scene.get_node_or_null("Quality")
	if quality and quality.has_method("set_user_scale"):
		quality.call("set_user_scale", float(get_value("render_scale")))
	var hs := float(get_value("hud_scale"))
	if absf(hs - hud_scale) > 0.0001:
		hud_scale = hs
		# Every HUD piece lays itself out again on a size change.
		var vp := scene.get_viewport()
		if vp:
			vp.size_changed.emit()


static func _apply_camera(tree: SceneTree) -> void:
	var player := tree.get_first_node_in_group("player")
	var rig := player.get_node_or_null("CameraRig") if player else null
	if rig == null:
		return
	# The rig's own exports are the base the multiplier scales (kept once, as meta).
	if not rig.has_meta("gs_mouse"):
		rig.set_meta("gs_mouse", float(rig.get("mouse_sensitivity")))
		rig.set_meta("gs_pad", float(rig.get("gamepad_look_speed")))
	var k := float(get_value("mouse_sensitivity"))
	rig.set("mouse_sensitivity", float(rig.get_meta("gs_mouse")) * k)
	rig.set("gamepad_look_speed", float(rig.get_meta("gs_pad")) * k)
	rig.set("invert_y", bool(get_value("invert_y")))
	rig.set("camera_fov", float(get_value("fov")))
	rig.set("car_fov", float(get_value("car_fov")))


static func _apply_audio() -> void:
	for key: String in BUSES:
		var idx := AudioServer.get_bus_index(BUSES[key])
		if idx < 0:
			continue
		var v := float(get_value(key))
		AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.0005 else -80.0)
		AudioServer.set_bus_mute(idx, v <= 0.0005)


static func _apply_post(tree: SceneTree) -> void:
	for post in tree.get_nodes_in_group("camera_post"):
		post.set("motion_blur_enabled", bool(get_value("motion_blur")))
		post.set("user_dof", bool(get_value("depth_of_field")))


## The lens layer CityStreamer builds (`Vignette`): strength and grain at the city's own numbers,
## or none.
static func _apply_vignette(scene: Node) -> void:
	var layer := scene.get_node_or_null("Vignette")
	if layer == null or layer.get_child_count() == 0:
		return
	var rect := layer.get_child(0) as CanvasItem
	var mat := rect.material as ShaderMaterial if rect else null
	if mat == null:
		return
	var base_v := float(scene.get("vignette_strength")) if "vignette_strength" in scene else 0.24
	var base_g := float(scene.get("film_grain")) if "film_grain" in scene else 0.028
	mat.set_shader_parameter("strength", base_v if bool(get_value("vignette")) else 0.0)
	mat.set_shader_parameter("grain", base_g if bool(get_value("film_grain")) else 0.0)
