class_name BoostTrail
extends Node3D
## The player's boost, shot the way a superhero film shoots flight: a thin vapour trail torn off
## the body that widens and thins out behind, faint streaks of air sliding past, dust ripped off
## the ground under a low pass, and a ring of vapour thrown out when the boost kicks in (and a
## bigger one when it reaches top speed). It replaced a stream of solid cyan balls.
##
## Built in code. The player calls `drive()` every physics tick; `emitting = false` stops it (the
## car, the downed card). Vapour and dust are world-space puffs on WeaponFX's smoke material, so
## they hang in the air where the player passed; the streaks are local to the player and drawn by
## shaders/boost_streak.gdshader as camera-facing lines along their velocity.

## Speed (m/s) at which the trail and streaks are at full strength.
@export var full_speed: float = 40.0
## Speed (m/s) below which nothing is drawn.
@export var min_speed: float = 9.0
## Vapour puffs a second (the trail thins out below `full_speed` rather than bunching up).
@export var vapour_rate: float = 110.0
## How long one puff of the trail lives (s); with the speed, how long the trail is.
@export var vapour_life: float = 1.1
## A puff's size at birth (m) and how many times it grows over its life.
@export var vapour_size: float = 0.45
@export var vapour_grow: float = 3.6
## The trail's opacity at its thickest.
@export var vapour_alpha: float = 0.22
## The wake: mist streaming off the body and back past the camera, moving with the player (the
## contrail is world-space and, at 45 m/s, mostly behind a chase camera within a tenth of a
## second - this is what the camera actually sees).
@export var wake_rate: float = 90.0
## How long a wake puff lives (s) and how fast it streams back off the body (m/s).
@export var wake_life: float = 0.32
@export var wake_speed: float = 15.0
## The wake's opacity at its thickest.
@export var wake_alpha: float = 0.22
## Streaks of air a second at full speed.
@export var streak_rate: float = 120.0
## How long a streak lives (s) and how fast it slides back past the player (m/s).
@export var streak_life: float = 0.22
@export var streak_speed: float = 26.0
## A streak's brightness at full speed.
@export var streak_alpha: float = 0.6
## How far round the body the streaks start (m, outer and inner radius of the ring).
@export var streak_radius: float = 1.25
@export var streak_inner: float = 0.45
## Ground this close under the player (m) gets dust ripped off it.
@export var dust_reach: float = 3.5
## Dust puffs a second at full speed right over the ground, and their opacity.
@export var dust_rate: float = 50.0
@export var dust_alpha: float = 0.3
## Puffs in the ring thrown out when the boost kicks in; the top-speed ring has half again more.
@export var burst_puffs: int = 18
## Share of `Player.boost_max_speed` that sets off the top-speed ring.
@export var boom_share: float = 0.97
## How bright the vapour is at full night (it is lit by the city, not the sun).
@export var night_brightness: float = 0.2

## Setting it false stops everything at once (getting into a car, going down); `drive()` starts
## it again the next time the player boosts.
var emitting: bool = false:
	set(value):
		emitting = value
		if not value:
			_stop()

var _vapour: CPUParticles3D
var _wake: CPUParticles3D
var _streaks: CPUParticles3D
var _dust: CPUParticles3D
var _burst: CPUParticles3D
var _was_boosting: bool = false
var _boomed: bool = false
var _day: Node
var _looked_for_day: bool = false

static var _streak_mat: ShaderMaterial


func _ready() -> void:
	var web := OS.has_feature("web")
	var k := 0.5 if web else 1.0
	_vapour = _puffs(maxi(8, int(vapour_rate * vapour_life * k)), vapour_life, vapour_size, vapour_grow,
		_ramp(Color(1.45, 1.47, 1.5), vapour_alpha))
	_vapour.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_vapour.emission_sphere_radius = 0.28
	_vapour.direction = Vector3.BACK
	_vapour.spread = 180.0
	_vapour.initial_velocity_min = 0.5
	_vapour.initial_velocity_max = 2.5
	_vapour.damping_min = 1.0
	_vapour.damping_max = 2.0
	add_child(_vapour)

	_wake = _puffs(maxi(6, int(wake_rate * wake_life * k)), wake_life, 0.35, 3.2,
		_ramp(Color(1.45, 1.47, 1.5), wake_alpha, 0.04))
	_wake.local_coords = true
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_wake.emission_sphere_radius = 0.35
	# Local +Y runs back along the direction of travel (the node's basis is set every tick).
	_wake.direction = Vector3.UP
	_wake.spread = 14.0
	_wake.initial_velocity_min = wake_speed * 0.7
	_wake.initial_velocity_max = wake_speed * 1.2
	_wake.damping_min = 4.0
	_wake.damping_max = 8.0
	_wake.custom_aabb = AABB(Vector3(-4.0, -2.0, -4.0), Vector3(8.0, 12.0, 8.0))
	add_child(_wake)

	_dust = _puffs(maxi(6, int(dust_rate * 1.2 * k)), 1.2, 0.8, 3.0, _ramp(Color(0.95, 0.87, 0.76), dust_alpha))
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = 0.7
	_dust.direction = Vector3.UP
	_dust.spread = 70.0
	_dust.initial_velocity_min = 2.0
	_dust.initial_velocity_max = 6.0
	_dust.damping_min = 2.0
	_dust.damping_max = 4.0
	_dust.gravity = Vector3(0.0, -1.5, 0.0)
	add_child(_dust)

	_burst = _puffs(maxi(6, int(burst_puffs * 1.5)), 0.8, 0.6, 3.2, _ramp(Color(1.45, 1.47, 1.5), 0.26))
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	# Aimed along local Z with full flatness the cone collapses into a ring in the local XZ plane
	# (see WeaponFX._puff_layer); the node's basis puts local Y on the direction of travel.
	_burst.direction = Vector3.BACK
	_burst.spread = 180.0
	_burst.flatness = 1.0
	_burst.initial_velocity_min = 9.0
	_burst.initial_velocity_max = 14.0
	_burst.damping_min = 10.0
	_burst.damping_max = 16.0
	add_child(_burst)

	_streaks = CPUParticles3D.new()
	_streaks.name = "Streaks"
	_streaks.emitting = false
	_streaks.amount = maxi(4, int(streak_rate * streak_life * k))
	_streaks.lifetime = streak_life
	_streaks.lifetime_randomness = 0.3
	_streaks.local_coords = true
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_streaks.emission_ring_axis = Vector3.UP
	_streaks.emission_ring_radius = streak_radius
	_streaks.emission_ring_inner_radius = streak_inner
	_streaks.emission_ring_height = 0.0
	_streaks.direction = Vector3.UP
	_streaks.spread = 2.0
	_streaks.initial_velocity_min = streak_speed * 0.8
	_streaks.initial_velocity_max = streak_speed * 1.2
	_streaks.gravity = Vector3.ZERO
	_streaks.particle_flag_align_y = true
	_streaks.scale_amount_min = 0.6
	_streaks.scale_amount_max = 1.1
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.7, Color(1.0, 1.0, 1.0, 0.6))
	_streaks.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = streak_material()
	_streaks.mesh = quad
	_streaks.custom_aabb = AABB(Vector3(-4.0, -8.0, -4.0), Vector3(8.0, 16.0, 8.0))
	add_child(_streaks)


## The streak material, shared (and warmed on the loading screen).
static func streak_material() -> ShaderMaterial:
	if _streak_mat == null:
		_streak_mat = ShaderMaterial.new()
		_streak_mat.shader = preload("res://shaders/boost_streak.gdshader")
	return _streak_mat


## True while the trail is being laid (boosting, over `min_speed`).
func is_trailing() -> bool:
	return _vapour != null and _vapour.emitting


## One tick. `boosting` is the button, `velocity` the player's, `max_speed` the boost's cap.
func drive(boosting: bool, velocity: Vector3, max_speed: float) -> void:
	var speed := velocity.length()
	emitting = boosting
	var on := boosting and speed > min_speed
	var dir := velocity / speed if speed > 0.01 else Vector3.FORWARD
	var k := clampf((speed - min_speed) / maxf(full_speed - min_speed, 0.01), 0.0, 1.0)
	var night := _night()
	var bright := lerpf(1.0, night_brightness, night)

	# Kick-off ring: the moment the button goes down, whatever the speed; the boom at top speed.
	if boosting and not _was_boosting:
		_ring(dir, 1.0, bright)
		_boomed = false
	if boosting and not _boomed and speed > max_speed * boom_share:
		_ring(dir, 1.5, bright)
		_boomed = true
	_was_boosting = boosting

	_vapour.emitting = on
	_wake.emitting = on
	_streaks.emitting = on
	if not on:
		_dust.emitting = false
		return
	# The trail comes off the back of the body and thins out as the speed drops, so a slow boost
	# does not stack its puffs into a cloud.
	_vapour.global_position = global_position - dir * 0.35
	_vapour.color = Color(bright, bright, bright, k)
	_wake.global_basis = _basis_along(-dir)
	_wake.global_position = global_position - dir * 0.2
	_wake.color = Color(bright, bright, bright, k)
	# The streaks' ring is square to the direction of travel, a metre and a half ahead of the
	# body, and its particles run backward (local +Y) past the player and the camera.
	_streaks.global_basis = _basis_along(-dir)
	_streaks.global_position = global_position + dir * 1.6
	_streaks.color = Color(bright, bright, bright, streak_alpha * k * k)
	_kick_dust(k, bright)


func _kick_dust(k: float, bright: float) -> void:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		_dust.emitting = false
		return
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (dust_reach + 1.0), 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_dust.emitting = false
		return
	var height := from.y - (hit.position as Vector3).y
	var near := clampf(1.0 - (height - 1.0) / dust_reach, 0.0, 1.0)
	_dust.emitting = near > 0.02
	_dust.global_position = hit.position + Vector3.UP * 0.2
	_dust.color = Color(bright, bright, bright, near * k)


func _ring(dir: Vector3, scale_by: float, bright: float) -> void:
	_burst.global_basis = _basis_along(dir)
	_burst.global_position = global_position
	_burst.scale_amount_min = 0.6 * scale_by * 0.7
	_burst.scale_amount_max = 0.6 * scale_by
	_burst.initial_velocity_min = 9.0 * scale_by
	_burst.initial_velocity_max = 14.0 * scale_by
	_burst.color = Color(bright, bright, bright, 1.0)
	_burst.restart()
	_burst.emitting = true


func _stop() -> void:
	if _vapour == null:
		return
	_vapour.emitting = false
	_wake.emitting = false
	_streaks.emitting = false
	_dust.emitting = false
	_was_boosting = false


## A basis whose Y axis is `up_dir`.
static func _basis_along(up_dir: Vector3) -> Basis:
	var y := up_dir.normalized()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


func _night() -> float:
	if not _looked_for_day:
		_looked_for_day = true
		var scene := get_tree().current_scene if is_inside_tree() else null
		_day = scene.get_node_or_null("DayNight") if scene else null
	if _day == null or not is_instance_valid(_day):
		return 0.0
	return float(_day.get("night_factor"))


## World-space soft puffs on the explosion's smoke material (unshaded, soft-edged, drawn before
## the fire), growing `grow` times over their life.
func _puffs(count: int, life: float, size: float, grow: float, ramp: Gradient) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = count
	p.lifetime = life
	p.lifetime_randomness = 0.25
	p.local_coords = false
	p.gravity = Vector3.ZERO
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size
	# Curve values are clamped to max_value (1.0 by default): raise it or the puffs never grow.
	var curve := Curve.new()
	curve.max_value = maxf(1.0, grow)
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = curve
	p.color_ramp = ramp
	p.angle_min = -180.0
	p.angle_max = 180.0
	var quad := QuadMesh.new()
	quad.material = WeaponFX.smoke_material()
	p.mesh = quad
	# Automatic bounds start empty; the trail is left behind in world space, so give it room.
	p.custom_aabb = AABB(Vector3(-40.0, -20.0, -40.0), Vector3(80.0, 40.0, 80.0))
	return p


static func _ramp(color: Color, alpha: float, peak: float = 0.05) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, 0.0))
	g.set_color(1, Color(color.r * 0.95, color.g * 0.95, color.b * 0.96, 0.0))
	g.add_point(peak, Color(color.r, color.g, color.b, alpha))
	g.add_point(0.45, Color(color.r, color.g, color.b, alpha * 0.55))
	return g
