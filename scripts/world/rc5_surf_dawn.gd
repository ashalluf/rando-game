class_name RcSurfDawn
extends RefCounted
## The surf at dawn from the water (wave 8, refcam5 `surf_dawn`, docs/HANDOFF.md "The surf at dawn
## from the water"): BeachActivity's hooks for a surfer riding the drawn wave (SurfRide), and the
## view's other fixes. RC5_SURF_DAWN=0 (SurfRide.enabled) is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## How fast (m/s) the rider runs down the line along the shore while the wave carries him in.
const TRIM_SPEED := 2.4
## Most the board and the rider are tipped to the face (radians).
const MAX_TILT := 0.6
## How far over the drawn surface the node rides: the board hangs 5 cm under it, so its bottom planes
## 11 cm over SeaSurface.height() (on a 27-degree face the water a few cm off the rider stands higher).
const RIDE_LIFT := 0.16
## A rider's spray runs only within this (m) of the camera: the fan thrown off the board's rail and
## the mist the offshore breeze tears off the lip behind him, both backlit by a low sun.
const SPRAY_REACH := 160.0
## How far behind the rider (m along the shore) the lip's mist is centred, and its half length.
const LIP_BEHIND := 6.0
const LIP_HALF := 8.0
## Dawn patrol: surfers more than the hour's beach density gives, out from first light to mid
## morning (a clear morning's lineup is its busiest; the sand is still empty). At most this many a
## stretch, scaled by `dawn()`.
const DAWN_SURFERS := 4
## ocean_closeup's glint_keep: the share of glitter cells that may flash.
const GLINT_KEEP := 0.3


## The ocean material's rc5 settings (Weather's hook): the de-latticed ripple (ocean.gdshader
## ripple_rot) and the crest's glow carried over its top (crest_carry) and sparse glitter facets (glint_keep), the capillaries de-latticed
## (capillary_rot) unless RC5_SURF_DAWN=0.
static func apply_ocean(mat: ShaderMaterial) -> void:
	if mat:
		mat.set_shader_parameter("ripple_rot", 1.0 if SurfRide.enabled else 0.0)
		mat.set_shader_parameter("crest_carry", 1.0 if SurfRide.enabled else 0.0)
		mat.set_shader_parameter("glint_keep", GLINT_KEEP if SurfRide.enabled else 1.0)
		mat.set_shader_parameter("capillary_rot", 1.0 if SurfRide.enabled else 0.0)


## 1 from 06:30 to 08:30, easing out by 10:00, 0 otherwise.
static func dawn(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 6.5 or h > 10.0:
		return 0.0
	return 1.0 - smoothstep(8.5, 10.0, h)


## The extra surfers BeachActivity seats at dawn (after its own, so their hashes are new indices).
static func dawn_surfers(hour: float, roll: float) -> int:
	if not SurfRide.enabled:
		return 0
	return roundi(float(DAWN_SURFERS) * dawn(hour) * (0.6 + 0.4 * roll))


static func _state(act: BeachActivity) -> Array:
	if act.sea_state.is_empty():
		act.sea_state = SeaSurface.state(act.get_tree())
	return act.sea_state


## A staged ride (BEACH_STAGE): the place along the shore and the set wave SurfRide.stage_pick() finds.
static func stage_ride(act: BeachActivity, w: Dictionary) -> void:
	var m := act.plan_ref.macro
	var st := _state(act)
	var pick := SurfRide.stage_pick(m, st, float(w.z), SurfRide.now())
	w.staged = true
	w.stage_z = float(w.z)
	w.stage_shape = st[2]
	w.z = pick.x
	w.z_home = pick.x
	w.wave = pick.y
	# The lineup sits past THIS sea's break (BeachActivity seats it past a clear day's 38 m).
	var brk := (st[2] as Vector4).w
	for o: Dictionary in act._water:
		if String(o.kind) == "surf" and String(o.get("state", "")) == "sit":
			if not o.has("lineup0"):
				o.lineup0 = float(o.lineup) - Surf.BREAK
			o.lineup = brk + float(o.lineup0)
			o.s = o.lineup
	# Down the line toward -z (the refcam's lens waits there), side-on as BeachActivity rides.
	w.dir_z = -1.0
	w.yaw = atan2(0.7, 0.85)
	var rp := SurfRide.ride_point(m, st, pick.x, pick.y, SurfRide.now())
	w.s = rp.x
	if OS.get_environment("SURF_DEBUG") == "1":
		var sc := SurfRide.crest_s(m, st[2], pick.x, pick.y, SurfRide.now())
		print("SURF stage z=%.1f wave=%d crest_s=%.1f rider_s=%.1f x=%.2f y=%.2f slope=%.2f gain=%.2f brk=%.1f" % [
			pick.x, int(pick.y), sc, rp.x, m.coast_x(pick.x) - rp.x, rp.y, rp.z,
			SurfRide.gain(m, st[2], pick.x, pick.y), (st[2] as Vector4).w])


## Paddling in to the break: catch the wave whose crest is coming up behind.
static func catch(act: BeachActivity, w: Dictionary) -> void:
	var m := act.plan_ref.macro
	var st := _state(act)
	w.wave = SurfRide.wave_at(m, st[2], float(w.z), float(w.s), SurfRide.now())


## Riding: carried in by wave n, trimming down the line.
static func ride_tick(act: BeachActivity, w: Dictionary, dt: float) -> void:
	var m := act.plan_ref.macro
	var st := _state(act)
	w.z = float(w.z) + float(w.dir_z) * TRIM_SPEED * dt
	var rp := SurfRide.ride_point(m, st, float(w.z), float(w.wave), SurfRide.now())
	w.s = rp.x


## The rider on the face: on the drawn surface, tipped to its slope, side-on.
static func place_ride(act: BeachActivity, w: Dictionary, _x: float) -> void:
	var m := act.plan_ref.macro
	if w.get("staged", false):
		# A staged still follows the sea it is shot in (a refcam row's surf_gain is set after the
		# chunk was built): a new sea state, a new pick.
		act.sea_state = SeaSurface.state(act.get_tree())
		if act.sea_state[2] != w.stage_shape:
			w.z = float(w.stage_z)
			stage_ride(act, w)
	var st := _state(act)
	var z := float(w.z)
	var rp := SurfRide.ride_point(m, st, z, float(w.wave), SurfRide.now())
	var p := SurfRide.point(m, z, rp.x)
	# The face rises seaward (-x in the world here: the sea is west); its normal leans landward.
	var n := Vector3(clampf(rp.z, -1.2, 1.2), 1.0, 0.0).normalized()
	var ang := minf(acos(clampf(n.y, -1.0, 1.0)), MAX_TILT)
	var axis := Vector3.UP.cross(n)
	var tilt := Basis(axis.normalized(), ang) if axis.length() > 0.0001 else Basis.IDENTITY
	var node: Node3D = w.node
	node.transform = Transform3D(tilt * Basis(Vector3.UP, float(w.yaw)), Vector3(p.x, rp.y + RIDE_LIFT, z))
	var board: Node3D = w.board
	board.transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, -0.05, 0.0))
	var sc := SurfRide.crest_s(m, st[2], z, float(w.wave), SurfRide.now())
	var cp := SurfRide.point(m, z, sc)
	spray(act, w, Vector3(p.x, rp.y, z), Vector3(cp.x, SeaSurface.height(m, cp, SurfRide.now(), st), z))
	if OS.get_environment("SURF_DEBUG") == "1" and Engine.get_physics_frames() % 30 == 0:
		var cam := act.get_viewport().get_camera_3d()
		print("SURF rider at %s world %s, camera %s" % [node.position, node.global_position, cam.global_position if cam else Vector3.ZERO])


## The rider's spray (see SPRAY_REACH): made on first need, placed each tick, off past the reach.
static func spray(act: BeachActivity, w: Dictionary, at: Vector3, crest: Vector3) -> void:
	var cam := act.get_viewport().get_camera_3d() if act.is_inside_tree() else null
	var on := cam != null and cam.global_position.distance_to(act.to_global(at)) < SPRAY_REACH
	if not w.has("fx"):
		if not on:
			return
		w.fx = [_emitter(act, 110, 0.9, Color(1.55, 1.52, 1.48, 0.62), 0.12, 0.7, 9.8),
			_emitter(act, 240, 1.1, Color(1.6, 1.58, 1.55, 0.3), 0.2, 1.0, 3.0)]
	var travel := Vector3(0.0, 0.0, float(w.dir_z))
	var rail: CPUParticles3D = w.fx[0]
	rail.position = at + Vector3(0.0, 0.1, 0.0) - travel * 0.6
	# Thrown off the tail up the face and back over the lip: up, seaward (-x), behind.
	rail.direction = Vector3(-0.55, 1.0, 0.0) - travel * 0.55
	var lip: CPUParticles3D = w.fx[1]
	lip.position = Vector3(crest.x, crest.y + 0.15, crest.z - float(w.dir_z) * LIP_BEHIND)
	lip.emission_box_extents = Vector3(0.35, 0.12, LIP_HALF)
	# The offshore breeze of a clear morning blows the feathering lip back out to sea.
	lip.direction = Vector3(-1.0, 0.3, 0.0)
	for p: CPUParticles3D in w.fx:
		if p.emitting != on:
			p.emitting = on


static func stop_spray(w: Dictionary) -> void:
	if w.has("fx"):
		for p: CPUParticles3D in w.fx:
			if is_instance_valid(p):
				p.emitting = false


static func _emitter(act: BeachActivity, n: int, life: float, col: Color, s0: float, s1: float, grav: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "SurfSpray"
	p.amount = n if not OS.has_feature("web") else n / 3
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.25, 0.1, 0.4)
	p.gravity = Vector3(0.0, -grav, 0.0)
	p.spread = 22.0
	p.initial_velocity_min = 2.0 if grav > 5.0 else 1.2
	p.initial_velocity_max = 5.5 if grav > 5.0 else 3.2
	p.damping_min = 0.6
	p.damping_max = 1.6
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_curve = SwimFX._grow(s0, s1)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.12, col)
	g.set_color(g.get_point_count() - 1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	p.mesh = SwimFX._quad(1.0, BoatWake.spray_material())
	p.custom_aabb = AABB(Vector3(-40, -6, -40), Vector3(80, 20, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	act.add_child(p)
	return p
