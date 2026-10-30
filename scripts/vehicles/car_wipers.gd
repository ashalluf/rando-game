class_name CarWipers
extends RefCounted
## A car's windscreen wipers (wet-world): two arms with their rubber blades, code-built once per body
## type from the windscreen CarCabin measured, and turned in the vertex stage
## (shaders/car_wiper.gdshader, car_wipers.gdshaderinc) from TIME while it rains on a car somebody
## drives - the same angle the glass (car_glass_wet.gdshaderinc) clears its beads by, so the arcs
## the blades sweep are the arcs left clear.
##
## The blades are ONE MeshInstance3D under the car's first glass mesh with no transform of its own,
## so its space is the body mesh's (the glass shader's). Materials are shared: per body type one
## parked and PHASES running copies (a queue of cars does not wipe in step); the car's own glass
## copy takes the same phase (`sync()`, from Vehicle._apply_occupant()). Nothing per car runs on
## the CPU. Off with WetWorld (WET_WORLD=0).

const SHADER := preload("res://shaders/car_wiper.gdshader")
## Running phase buckets (fractions of a cycle).
const PHASES := 4
## How far up from parked the blades sweep (radians).
const SWEEP := 1.72
## Pivots across the screen (fractions of its width from its middle, + toward the car's right), the
## arm's reach and the blade's length (fractions of the width).
const PIVOT_A := -0.03
const PIVOT_B := 0.42
const ARM := 0.27
const BLADE := 0.4
## The rubber's clearance over the glass (m) and the blades' draw distance (m).
const CLEARANCE := 0.012
const DRAW_DISTANCE := 45.0

## Body key -> {"mesh", "mats" (parked + PHASES), "params"}.
static var _bodies: Dictionary = {}


## Builds (or reuses) the body's wipers and hangs them under `glass_mi` (the car's first glass mesh)
## and puts the screen's frame on the body's shared glass material `glass_mat`. `data` is
## CarCabin.measure()'s, `ctx` its context(). No windscreen, no wipers.
static func attach(car: Vehicle, glass_mi: MeshInstance3D, glass_mat: ShaderMaterial, data: Dictionary, ctx: Dictionary) -> void:
	if not WetWorld.enabled or car.has_meta("wipers"):
		return
	var spec: Dictionary = _spec(car.body_type, glass_mi.mesh, data, ctx)
	if spec.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Wipers"
	mi.mesh = spec.mesh
	mi.material_override = spec.mats[0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = minf(DRAW_DISTANCE, car.body_far_distance) if car.body_far_distance > 0.0 else DRAW_DISTANCE
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	glass_mi.add_child(mi)
	car.set_meta("wipers", mi)
	if glass_mat != null:
		_frame_on(glass_mat, spec.params)


## Puts the running (or parked) blades on `car` for `seats` (CarCabin's: anybody at the wheel runs
## them) and the same phase on `glass_mat` (the glass the car wears, or null).
static func sync(car: Vehicle, seats: int, glass_mat: ShaderMaterial) -> void:
	if not car.has_meta("wipers"):
		return
	var mi := car.get_meta("wipers") as MeshInstance3D
	if not is_instance_valid(mi) or not _bodies.has(car.body_type):
		return
	var spec: Dictionary = _bodies[car.body_type]
	var idx := phase_index(car, seats)
	if mi.material_override != spec.mats[idx]:
		mi.material_override = spec.mats[idx]
	if glass_mat != null:
		if glass_mat.get_shader_parameter("wiper_reach") == null or (glass_mat.get_shader_parameter("wiper_reach") as Vector2).y <= 0.0:
			_frame_on(glass_mat, spec.params)
		glass_mat.set_shader_parameter("wipers_on", 1.0 if idx > 0 else 0.0)
		glass_mat.set_shader_parameter("wiper_phase", phase_of(idx))


## 0 parked (nobody at the wheel), else 1..PHASES from the car's occupant seed.
static func phase_index(car: Vehicle, seats: int) -> int:
	if seats & 1 == 0:
		return 0
	return 1 + absi(hash([car._occupant_seed, 77])) % PHASES


static func phase_of(idx: int) -> float:
	return 0.0 if idx <= 0 else float(idx - 1) / float(PHASES)


## The body's wipers, built once: {} when it has no windscreen.
static func _spec(key: Variant, mesh: Mesh, data: Dictionary, ctx: Dictionary) -> Dictionary:
	if _bodies.has(key):
		return _bodies[key]
	var screen: Array = []
	for p: Array in data.get("panes", []):
		if int(p[3]) == CarCabin.KIND_SCREEN and (screen.is_empty() or _vol(p) > _vol(screen)):
			screen = p
	if screen.is_empty():
		_bodies[key] = {}
		return {}
	var spec := build(screen, mesh, ctx)
	_bodies[key] = spec
	return spec


static func _vol(p: Array) -> float:
	var s: Vector3 = (p[1] as Vector3) - (p[0] as Vector3)
	return s.x * s.y + s.y * s.z + s.x * s.z


## The geometry and the uniforms for windscreen pane `screen` ([lo, hi, normal, ...] in mesh space)
## of `mesh` (whose glass vertices, where it has mesh data, say how far the screen bulges out).
static func build(screen: Array, mesh: Mesh, ctx: Dictionary) -> Dictionary:
	var to_mesh: Transform3D = ctx.to_mesh
	var to_car := to_mesh.affine_inverse()
	var lo: Vector3 = screen[0]
	var hi: Vector3 = screen[1]
	# The screen's frame in the car's space: across (+x), out of it (up and forward), up it.
	var u := Vector3.RIGHT
	var n := (to_car.basis * (screen[2] as Vector3))
	n.x = 0.0
	if n.length() < 1e-4:
		n = Vector3(0.0, 0.5, -0.87)
	n = n.normalized()
	if n.y < 0.0 and n.z > 0.0:
		n = -n
	var v := u.cross(n).normalized()
	var c := to_car * ((lo + hi) * 0.5)
	var umin := INF
	var umax := -INF
	var vmin := INF
	var vmax := -INF
	for i in 8:
		var corner := Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z)
		var d := to_car * corner - c
		umin = minf(umin, d.dot(u))
		umax = maxf(umax, d.dot(u))
		vmin = minf(vmin, d.dot(v))
		vmax = maxf(vmax, d.dot(v))
	var w := (umax - umin) * 0.92
	var h := (vmax - vmin) * 0.85
	# How far the glass stands out of the plane through the box's middle (the screen's bulge).
	var out := _bulge(mesh, lo, hi, to_car, c, n)
	var foot := c + u * ((umin + umax) * 0.5) - v * (h * 0.5 - 0.03) + n * (out + CLEARANCE)
	var pa := foot + u * (PIVOT_A * w)
	var pb := foot + u * (PIVOT_B * w)
	var arm := ARM * w
	var blade := BLADE * w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var pv := pa if k == 0 else pb
		var col_k := float(k)
		var d := -u
		# The pivot's cap, the arm running out to the blade's middle, and the blade.
		_box(st, to_mesh, pv + n * 0.012, d, v, n, Vector3(0.035, 0.035, 0.024), Color(col_k, 0.0, 1.0))
		_box(st, to_mesh, pv + d * (arm * 0.5) + n * 0.014, d, v, n, Vector3(arm, 0.012, 0.009), Color(col_k, 0.0, 0.6))
		_box(st, to_mesh, pv + d * arm + n * 0.004, d, v, n, Vector3(blade, 0.016, 0.012), Color(col_k, 0.0, 0.3))
		_box(st, to_mesh, pv + d * arm - n * 0.004, d, v, n, Vector3(blade * 0.98, 0.006, 0.006), Color(col_k, 1.0, 0.0))
	var m := st.commit()
	var sc := float(ctx.scale)
	var params := {
		"wiper_u": (to_mesh.basis * u).normalized(),
		"wiper_v": (to_mesh.basis * v).normalized(),
		"wiper_n": (to_mesh.basis * n).normalized(),
		"wiper_pivot_a": to_mesh * pa,
		"wiper_pivot_b": to_mesh * pb,
		"wiper_reach": Vector2(maxf(arm - blade * 0.5, 0.0), arm + blade * 0.5) / sc,
		"wiper_sweep": SWEEP,
	}
	var mats: Array[ShaderMaterial] = []
	for i in PHASES + 1:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		_frame_on(mat, params)
		mat.set_shader_parameter("wipers_on", 1.0 if i > 0 else 0.0)
		mat.set_shader_parameter("wiper_phase", phase_of(i))
		mats.append(mat)
	return {"mesh": m, "mats": mats, "params": params, "width": w, "foot": foot}


static func _frame_on(mat: ShaderMaterial, params: Dictionary) -> void:
	for k: String in params:
		mat.set_shader_parameter(k, params[k])


## The most the screen's glass stands out along `n` from `c` (car space), from the mesh's glass
## vertices inside the pane's box; 0 without mesh data (the headless dummy keeps none).
static func _bulge(mesh: Mesh, lo: Vector3, hi: Vector3, to_car: Transform3D, c: Vector3, n: Vector3) -> float:
	if mesh == null:
		return 0.0
	var box := AABB(lo, hi - lo).grow(0.005)
	var best := -INF
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si)
		if src == null or String(src.resource_name) != "glass":
			continue
		var arr := mesh.surface_get_arrays(si)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		for p: Vector3 in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if box.has_point(p):
				best = maxf(best, (to_car * p - c).dot(n))
	return 0.0 if best == -INF else clampf(best, 0.0, 0.25)


## A box `size` (along `d`, `v`, `n`) at `at` (car space) into `st`, written in mesh space.
static func _box(st: SurfaceTool, to_mesh: Transform3D, at: Vector3, d: Vector3, v: Vector3, n: Vector3, size: Vector3, col: Color) -> void:
	var ax := [d * size.x * 0.5, v * size.y * 0.5, n * size.z * 0.5]
	for f in 6:
		var a := f >> 1
		var sgn := 1.0 if f & 1 == 0 else -1.0
		var nn: Vector3 = (ax[a] as Vector3).normalized() * sgn
		var c0: Vector3 = at + (ax[a] as Vector3) * sgn
		var e1: Vector3 = ax[(a + 1) % 3]
		var e2: Vector3 = ax[(a + 2) % 3]
		var q := [c0 - e1 - e2, c0 + e1 - e2, c0 + e1 + e2, c0 - e1 + e2]
		var nm := (to_mesh.basis * nn).normalized()
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(nm)
			st.add_vertex(to_mesh * (q[i] as Vector3))


# --- Mirrors of shaders/car_wipers.gdshaderinc (the checks hold the two together) -----------------

## One sweep's time (s): WIPER_STROKE.
const STROKE := 0.48


## wiper_period(): the cycle at rain `rain` (fast in a downpour, intermittent in a drizzle).
static func period(rain: float) -> float:
	return lerpf(3.6, 1.12, smoothstep(0.25, 0.7, rain))


## wiper_angle(): the blades' angle up from parked at time `t` for phase `phase`, rain `rain`.
static func angle_at(t: float, phase: float, rain: float, on: bool = true) -> float:
	if not on or rain < 0.02:
		return 0.0
	var p := period(rain)
	var c := fposmod(t + phase * p, p)
	return SWEEP * (smoothstep(0.0, STROKE, c) - smoothstep(STROKE, 2.0 * STROKE, c))
