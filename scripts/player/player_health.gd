class_name PlayerHealth
extends Node
## The player's health (the player had none before the police). Generous on purpose - this is a
## power fantasy - and quick to come back once you are out of the fire. Damage comes from police
## rounds and cruisers, and from your own blasts only if `self_blast_damage` is on (rocket jumps
## are part of how the game moves, so it is off).
##
## At zero: the world drops to slow motion while the hero crumples (a ragdoll of the same rig,
## still in the tracksuit), the screen greys under an original "OUT COLD" card, and after a beat
## the player stands up again on the nearest open street corner with full health and the stars
## gone. The slow motion and the card run on the real clock, so they are the same length however
## far time has been slowed.

signal health_changed(health: float, max_health: float)
signal downed_changed(downed: bool)

@export_group("Health")
## Full health.
@export var max_health: float = 250.0
## Seconds after the last hit before health starts to come back, and how fast it does (hp/s).
@export var regen_delay: float = 3.5
@export var regen_rate: float = 45.0
## Share of the damage that still reaches you through the car you are sitting in.
@export var in_car_factor: float = 0.45
## Your own explosions hurt you too. Off: rocket jumps are how the game moves.
@export var self_blast_damage: bool = false
## Damage of a blast at its centre, when self_blast_damage is on (scaled by the falloff).
@export var blast_damage: float = 120.0

@export_group("Down")
## Real seconds of slow motion while the hero goes down, and the time scale during it.
@export var collapse_seconds: float = 2.2
@export var collapse_time_scale: float = 0.3
## Real seconds from going down to standing up again.
@export var downed_seconds: float = 4.2
## How far from where you went down the respawn corner may be (m): the nearest intersection
## at least this far off, so you do not stand up in the middle of the fight.
@export var respawn_clearance: float = 60.0

var health: float = 250.0
var downed: bool = false
## Real time (ms) of the last hit, for the HUD's hurt flash.
var last_hit_ms: int = -100000

var _player: Player
var _since_hit: float = 100.0
var _down_ms: int = 0
var _slowed: bool = false
var _doll: Ragdoll
var _screen: CanvasLayer
var _screen_mat: ShaderMaterial
var _card: Control
var _hit_from: Vector3 = Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as Player
	health = max_health


func is_full() -> bool:
	return health >= max_health - 0.01


func fraction() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


## Takes `amount` of damage from `from` (scene position). `kind`: "bullet", "ram" or "blast".
func take_damage(amount: float, from: Vector3 = Vector3.INF, kind: String = "bullet") -> void:
	if downed or amount <= 0.0 or _player == null:
		return
	if _player.is_driving():
		amount *= in_car_factor
	health = maxf(health - amount, 0.0)
	_since_hit = 0.0
	last_hit_ms = Time.get_ticks_msec()
	if from != Vector3.INF:
		_hit_from = from
	health_changed.emit(health, max_health)
	if _player.camera_rig and _player.camera_rig.has_method("shake"):
		_player.camera_rig.shake(0.12 if kind == "bullet" else 0.4)
	if health <= 0.0:
		_go_down()


## A blast of your own (Explosion.blast): hurts only with self_blast_damage on.
func on_blast(falloff: float, at: Vector3) -> void:
	if self_blast_damage:
		take_damage(blast_damage * falloff, at, "blast")


func _process(delta: float) -> void:
	if downed:
		_update_down()
		return
	_since_hit += delta
	if _since_hit > regen_delay and health < max_health:
		health = minf(health + regen_rate * delta, max_health)
		health_changed.emit(health, max_health)


# --- Going down --------------------------------------------------------------------------------

func _go_down() -> void:
	downed = true
	_down_ms = Time.get_ticks_msec()
	if _player.is_driving():
		_player.exit_vehicle()
	# Nothing the player does counts while they are down: no input, no guns, no aim.
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	if _player.weapon_manager:
		_player.weapon_manager.set_physics_process(false)
		_player.weapon_manager.visible = false
	if _player.lock_on:
		_player.lock_on.set_process(false)
	var wheel := get_tree().get_first_node_in_group("weapon_wheel")
	if wheel and wheel.has_method("_close"):
		wheel.call("_close", false)
	_player.visual.visible = false
	_player._boost_fx.emitting = false
	if _player._boost_sound:
		_player._boost_sound.stop()
	_spawn_doll()
	Engine.time_scale = collapse_time_scale
	AudioServer.playback_speed_scale = 0.7
	_slowed = true
	_show_screen()
	Sfx.play("yelp", _player.global_position + Vector3.UP * 1.4, 0.0, 0.85)
	downed_changed.emit(true)


## The hero as a ragdoll, falling away from whatever put them down.
func _spawn_doll() -> void:
	var doll := Ragdoll.new()
	var host := get_tree().current_scene if get_tree().current_scene else _player.get_parent()
	host.add_child(doll)
	doll.global_position = _player.global_position
	doll.rotation.y = _player.visual.rotation.y
	if not doll.build_from_rig(_player.avatar_model, _player.avatar_look):
		doll.build(Color(0.2, 0.04, 0.05), Color(0.2, 0.04, 0.05), Color(0.8, 0.6, 0.5))
	else:
		_dress_doll(doll)
	var away := _player.global_position - _hit_from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else -_player.visual.global_basis.z
	doll.fling(away * 5.0 + Vector3.UP * 2.0)
	PhysicsBudget.register_debris(doll)
	_doll = doll


## The same clothes the hero wore (the avatar's own materials, tracksuit and all).
func _dress_doll(doll: Ragdoll) -> void:
	if _player.avatar == null or doll._rig == null:
		return
	var src: Array = _player.avatar.find_children("*", "MeshInstance3D", true, false)
	var dst: Array = doll._rig.find_children("*", "MeshInstance3D", true, false)
	if _player.avatar_tracksuit.a > 0.0:
		Pedestrian.add_piping(doll._rig)
		dst = doll._rig.find_children("*", "MeshInstance3D", true, false)
	for i in mini(src.size(), dst.size()):
		var m := (src[i] as MeshInstance3D).material_override
		if m:
			(dst[i] as MeshInstance3D).material_override = m


func _update_down() -> void:
	var real := float(Time.get_ticks_msec() - _down_ms) / 1000.0
	if _slowed and real >= collapse_seconds:
		_slowed = false
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
	elif _slowed:
		# Held here rather than set once: the weapon wheel eases time back on its own clock.
		Engine.time_scale = collapse_time_scale
	if _screen_mat:
		_screen_mat.set_shader_parameter("amount", clampf(real / 0.6, 0.0, 1.0))
	if _card:
		_card.set("fade", clampf((real - 0.35) / 0.5, 0.0, 1.0))
	if real >= downed_seconds:
		_get_up()


func _get_up() -> void:
	downed = false
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_slowed = false
	health = max_health
	_since_hit = 100.0
	var police := Police.find(get_tree())
	if police:
		police.clear()
	_respawn_on_street()
	_player.visual.visible = true
	_player.set_physics_process(true)
	if _player.weapon_manager:
		_player.weapon_manager.set_physics_process(true)
		_player.weapon_manager.visible = true
	if _player.lock_on:
		_player.lock_on.set_process(true)
	if is_instance_valid(_doll):
		_doll.queue_free()
	_doll = null
	_hide_screen()
	health_changed.emit(health, max_health)
	downed_changed.emit(false)


## The nearest street corner to where you went down, at least `respawn_clearance` away, on the
## pavement; the start point when you went down anywhere but the city grid.
func _respawn_on_street() -> void:
	var city := get_tree().get_first_node_in_group("city")
	var plan: CityPlan = city.get("plan") if city else null
	if plan == null:
		_player.respawn()
		return
	var wp := WorldState.to_world(_player.global_position)
	var here := Vector2(wp.x, wp.z)
	var zone := plan.zone_at(here)
	if zone != MacroMap.Zone.CITY and zone != MacroMap.Zone.BEACH:
		_player.respawn()
		return
	var idx := plan.block_index_at(here)
	var best := Vector2.INF
	for ix in range(idx.x - 1, idx.x + 3):
		for iz in range(idx.y - 1, idx.y + 3):
			var corner := Vector2(plan.road_pos(CityPlan.AXIS_X, ix), plan.road_pos(CityPlan.AXIS_Z, iz))
			# Onto the pavement at the corner, not the middle of the crossing.
			var off := Vector2(plan.road_width(CityPlan.AXIS_X, ix) * 0.5 + 2.0, plan.road_width(CityPlan.AXIS_Z, iz) * 0.5 + 2.0)
			corner += Vector2(off.x * signf(here.x - corner.x + 0.01), off.y * signf(here.y - corner.y + 0.01))
			if plan.zone_at(corner) != MacroMap.Zone.CITY:
				continue
			var d := corner.distance_to(here)
			if d < respawn_clearance:
				continue
			if best == Vector2.INF or d < best.distance_to(here):
				best = corner
	if best == Vector2.INF:
		_player.respawn()
		return
	var local := WorldState.to_local(Vector3(best.x, 0.0, best.y))
	var y: float = city.surface_height_at(local) if city.has_method("surface_height_at") else 1.0
	_player.global_position = Vector3(local.x, y + 0.3, local.z)
	_player.velocity = Vector3.ZERO


# --- The card -----------------------------------------------------------------------------------

func _show_screen() -> void:
	if _screen == null:
		_screen = CanvasLayer.new()
		_screen.name = "DownedScreen"
		_screen.layer = 5
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen_mat = ShaderMaterial.new()
		_screen_mat.shader = load("res://shaders/downed.gdshader")
		rect.material = _screen_mat
		_screen.add_child(rect)
		_card = DownedCard.new()
		_card.set_anchors_preset(Control.PRESET_FULL_RECT)
		_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen.add_child(_card)
		add_child(_screen)
	_screen_mat.set_shader_parameter("amount", 0.0)
	_card.set("fade", 0.0)
	_screen.visible = true


func _hide_screen() -> void:
	if _screen:
		_screen.visible = false


## The words on the grey: an original card, not anybody else's.
class DownedCard extends Control:
	var fade: float = 0.0:
		set(v):
			fade = v
			queue_redraw()
	var _font: Font
	const TITLE := "OUT COLD"
	const LINE := "walk it off"

	func _ready() -> void:
		var path := "res://assets/fonts/Inter-SemiBold.woff2"
		_font = load(path) as Font if ResourceLoader.exists(path) else ThemeDB.fallback_font

	func _draw() -> void:
		if fade <= 0.0:
			return
		var h := size.y
		var px := int(clampf(h * 0.085, 28.0, 140.0))
		var sub_px := int(clampf(h * 0.022, 12.0, 34.0))
		var spacing := px * 0.18
		var width := 0.0
		for ch in TITLE:
			width += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + spacing
		width -= spacing
		var y := h * 0.5 + (_font.get_ascent(px) - _font.get_descent(px)) * 0.5 - px * 0.08
		var x := (size.x - width) * 0.5
		var ink := Color(1.0, 1.0, 1.0, 0.94 * fade)
		# Letter-spaced, with a hairline rule above and below that grows out from the middle.
		for ch in TITLE:
			draw_string(_font, Vector2(x, y + px * 0.04), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.35 * fade))
			draw_string(_font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
			x += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + spacing
		var rule := width * 0.55 * fade
		var cx := size.x * 0.5
		var top := h * 0.5 - px * 0.78
		var bottom := h * 0.5 + px * 0.62
		draw_line(Vector2(cx - rule, top), Vector2(cx + rule, top), Color(1, 1, 1, 0.5 * fade), maxf(1.0, h / 900.0))
		draw_line(Vector2(cx - rule, bottom), Vector2(cx + rule, bottom), Color(1, 1, 1, 0.5 * fade), maxf(1.0, h / 900.0))
		var sw := _font.get_string_size(LINE, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_px).x
		draw_string(_font, Vector2(cx - sw * 0.5, bottom + sub_px * 1.6), LINE, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_px, Color(1, 1, 1, 0.7 * fade))
