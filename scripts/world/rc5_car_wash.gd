class_name RcCarWash
extends RefCounted
## The car wash from the kerb (wave 8 refcam `car_wash`, tools/refcams/cameras_w8.json;
## docs/HANDOFF.md "The car wash at 14:00"). Hooks in Roadside._car_wash(), after every roll of the
## pad, FULL chunks only:
##
## * The HAND-DRY AREA at the tunnel's exit end (`dry_rect()`): the vacuum stations it covers are
##   left out (their rolls still made), a two-bay shade canopy on steel posts, a wet concrete pad
##   (the roadside shader's concrete with UV2.y < 0: water film, puddles mirroring the sky, drips
##   under the exit), 1-2 freshly washed cars nose to the exit (real, empty Vehicles) with
##   `CarWashAttendant`s working them with towels, a towel rack hung with towels, a towel cart and
##   buckets.
## * The vacuum stalls' cars are real (empty) Vehicles (`stall_car()`): the static code car they
##   were read as a box at the kerb.
## * The tunnel floor is wet (`wet_u2()`), and the traced tunnel behind the window band shows its
##   brushes as lit cylinders of cloth in a dark, wet, misty tunnel (roadside.gdshader kind 4).
##
## Every roll is a hash of seed + lot. RC5_CAR_WASH=0 is the A/B (the pad exactly as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_CAR_WASH") != "0"

## The hand-dry area: metres along the frontage from the lot's exit end, and its depth from the
## tunnel's front wall toward the street.
const DRY_LEN := 13.0
const DRY_EDGE := 1.0
## Height of the shade canopy's sails at their low (street) and high (tunnel) edges: low at the
## street, so the tunnel's sign stands clear over it from the kerb.
const SAIL_LOW := 3.05
const SAIL_HIGH := 3.55
## How wet the pad and the tunnel floor are (the shader's UV2.y = -wet).
const WET_PAD := 0.85
const WET_TUNNEL := 0.75
## Microfibre towels: what an LA hand-dry crew uses.
const TOWELS := [Color(0.12, 0.35, 0.78), Color(0.93, 0.78, 0.12), Color(0.85, 0.2, 0.2), Color(0.95, 0.95, 0.93), Color(0.2, 0.62, 0.4), Color(0.6, 0.3, 0.75)]
## The attendants' polo colours (the crew's uniform, by the pad's hash).
const POLOS := [Color(0.08, 0.32, 0.62), Color(0.85, 0.2, 0.18), Color(0.12, 0.5, 0.45), Color(0.15, 0.15, 0.17)]

static var stats := {"pads": 0, "cars": 0, "crew": 0}


## The roadside material's car wash look (the traced tunnel's brushes), from RoadsideKit.material().
static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("wash_look", 1.0 if enabled else 0.0)


static func _h01(parts: Array) -> float:
	return float(hash(parts) & 0xffffff) / float(0x1000000)


static func _key(s: Variant) -> Array:
	var c: Vector2 = s.lot.center
	return [s.ch.plan.seed, int(c.x * 4.0), int(c.y * 4.0), "rc5_car_wash"]


## The ground's UV2 for a car wash's wet concrete: (roughness, -wetness), plain when off.
static func wet_u2(rough: float, wet: float = WET_TUNNEL) -> Vector2:
	return Vector2(rough, -wet if enabled else 0.0)


## The hand-dry area in the pad's frame (x along the street, -z toward it): the last DRY_LEN m of
## the frontage at the tunnel's exit end, from the tunnel's front wall to the planter. Empty when off.
static func dry_rect(s: Variant, tunnel: Rect2) -> Rect2:
	if not enabled:
		return Rect2()
	var hw: float = s.w * 0.5
	var hd: float = s.d * 0.5
	var x1 := hw - DRY_EDGE
	var z0 := -hd + 2.5
	var z1 := tunnel.position.y - 0.6
	if z1 - z0 < 6.0:
		return Rect2()
	return Rect2(x1 - DRY_LEN, z0, DRY_LEN, z1 - z0)


## A real, empty parked Vehicle at frame XZ facing `yaw` (a vacuum stall's or the dry area's car):
## built in a step of its own (a car is ~35 ms). False when off or not FULL (the caller lays the
## static car then).
static func stall_car(s: Variant, p: Vector2, yaw: float, tag: String = "stall") -> bool:
	if not enabled or not s.full or not Roadside.live_queue:
		return false
	var ch: CityChunk = s.ch
	var w: Vector3 = s.at(Vector3(p.x, 0.0, p.y))
	var seed := hash(_key(s) + [tag, int(w.x * 4.0), int(w.z * 4.0)])
	var world_yaw: float = s.yaw + yaw
	ch._run_or_defer(func() -> bool:
		if not is_instance_valid(ch) or not PhysicsBudget.can_spawn():
			return true
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var car := Vehicle.random_car(rng)
		car.set_meta("roadside", true)
		car.set_meta("car_wash", tag)
		var holder: Node = ch.get_parent() if ch.get_parent() else ch
		var spot := Vector3(w.x, Roadside.TOP + ch._gy(w.x, w.z) + Roadside.GROUND_LIFT + 0.4, w.z)
		car.position = WorldState.to_local(spot) if holder != ch else spot
		car.rotation.y = world_yaw
		holder.add_child(car)
		car.visible = ch.visible
		ch._cars.append(car)
		stats.cars += 1
		return true)
	return true


## The hand-dry area (Roadside._car_wash's last line).
static func dress(s: Variant, tunnel: Rect2, th: float, accent: Color) -> void:
	if not enabled or not s.full:
		return
	var r := dry_rect(s, tunnel)
	if r.size.x <= 0.0:
		return
	stats.pads += 1
	var K := RoadsideKit
	var pen: RoadsideKit.Pen = s.pen
	var key := _key(s)
	# The wet pad: concrete laid over the forecourt, and a run of water from the tunnel's exit.
	Roadside._ground(s, r, K.c(Color(0.52, 0.52, 0.5), K.K_CONCRETE), Roadside.GROUND_LIFT + 0.004, Vector2.ZERO, Vector2(0.7, -WET_PAD))
	var ex: float = tunnel.end.x
	var wet_run := Rect2(minf(ex - 6.0, r.end.x - 7.0), r.end.y, 6.0, tunnel.position.y - r.end.y + 0.6)
	Roadside._ground(s, wet_run, K.c(Color(0.52, 0.52, 0.5), K.K_CONCRETE), Roadside.GROUND_LIFT + 0.004, Vector2.ZERO, Vector2(0.7, -WET_PAD))
	# The shade canopy: two bays of tensioned sails on steel posts with a beam front and back.
	var sail: Color = accent.lerp(Color(0.92, 0.92, 0.9), 0.35)
	var steel := K.c(Color(0.72, 0.73, 0.75), K.K_STEEL)
	var zb := r.end.y - 0.4
	var zf := r.position.y + 0.6
	var xs := [r.position.x + 0.4, r.get_center().x, r.end.x - 0.4]
	for x: float in xs:
		for z: float in [zb, zf]:
			var top := SAIL_HIGH if z == zb else SAIL_LOW
			var y0: float = s.dy(x, z)
			pen.cyl(Vector3(x, y0 - 0.2, z), 0.09, 0.09, top - y0 + 0.25, steel, K.RM_STEEL, 10)
			pen.box(Vector3(x, y0 + 0.01, z), Vector3(0.36, 0.03, 0.36), steel, K.RM_STEEL)
			s.ch._add_shape(Vector3(0.2, top, 0.2), s.at(Vector3(x, top * 0.5, z)), s.yaw)
	for z: float in [zb, zf]:
		var top := SAIL_HIGH if z == zb else SAIL_LOW
		pen.box(Vector3(r.get_center().x, top + 0.06, z), Vector3(r.size.x - 0.4, 0.14, 0.14), steel, K.RM_STEEL, 0.02)
	for b in 2:
		var x0: float = xs[b] + 0.15
		var x1: float = xs[b + 1] - 0.15
		_sail(pen, x0, x1, zf, zb, SAIL_LOW + 0.13, SAIL_HIGH + 0.13, K.c(sail, K.K_FIXED))
	# The towel rack along the tunnel wall: a rail on two posts, towels folded over it.
	var rz := tunnel.position.y - 0.35
	var rx0 := r.position.x + 1.2
	var rx1 := minf(rx0 + 4.6, r.end.x - 1.0)
	var ry: float = s.dy((rx0 + rx1) * 0.5, rz)
	for x: float in [rx0, rx1]:
		pen.cyl(Vector3(x, ry, rz), 0.025, 0.025, 1.35, steel, K.RM_STEEL, 6)
	pen.cyl(Vector3(rx0, ry + 1.35, rz), 0.022, 0.022, rx1 - rx0, steel, K.RM_STEEL, 6, Basis(Vector3.BACK, -PI * 0.5))
	var nt := int((rx1 - rx0) / 0.4)
	for k in nt:
		var tx := rx0 + 0.25 + k * (rx1 - rx0 - 0.5) / maxf(nt - 1, 1)
		var tc: Color = TOWELS[absi(hash(key + ["rack", k])) % TOWELS.size()]
		_draped(pen, Vector3(tx, ry + 1.37, rz), 0.3, 0.62 + 0.16 * _h01(key + ["len", k]), K.c(tc, K.K_FIXED))
	# The towel cart and buckets by the rack.
	var cx := minf(rx1 + 1.3, r.end.x - 0.8)
	var cy: float = s.dy(cx, rz)
	pen.box(Vector3(cx, cy + 0.5, rz - 0.15), Vector3(0.95, 0.62, 0.6), K.c(Color(0.35, 0.37, 0.4), K.K_FIXED), K.RM_PLASTIC, 0.04)
	for wx: float in [-0.38, 0.38]:
		for wz: float in [-0.22, 0.22]:
			pen.cyl(Vector3(cx + wx, cy, rz - 0.15 + wz), 0.09, 0.09, 0.08, K.c(Color(0.05, 0.05, 0.05), K.K_RUBBER), K.RM_RUBBER, 8, Basis(Vector3.RIGHT, PI * 0.5))
	for k in 6:
		var tc: Color = TOWELS[absi(hash(key + ["stack", k])) % TOWELS.size()]
		var sx := -0.24 + (k % 2) * 0.48
		pen.box(Vector3(cx + sx, cy + 0.84 + int(k / 2) * 0.07, rz - 0.15), Vector3(0.4, 0.065, 0.3), K.c(tc, K.K_FIXED), Vector2(0.95, 0.0), 0.02)
	s.ch._add_shape(Vector3(0.95, 1.0, 0.6), s.at(Vector3(cx, cy + 0.5, rz - 0.15)), s.yaw)
	for k in 2:
		var bx := cx - 1.0 - k * 0.45
		var bc: Color = [Color(0.92, 0.42, 0.08), Color(0.9, 0.9, 0.88)][k]
		pen.cyl(Vector3(bx, s.dy(bx, rz - 0.55), rz - 0.55), 0.14, 0.17, 0.36, K.c(bc, K.K_FIXED), K.RM_PLASTIC, 12)
	# The washed cars, nose to the exit drive, and the crew on them.
	var ncar := 1 + (1 if _h01(key + ["cars"]) < 0.8 else 0)
	var cz := r.get_center().y - 0.4
	var lot_rect := Rect2(s.lot.center - Vector2(s.w, s.d) * 0.5, Vector2(s.w, s.d)).grow(4.0)
	var polo: int = absi(hash(key + ["polo"])) % POLOS.size()
	for i in ncar:
		var px: float = r.position.x + r.size.x * (0.27 if i == 0 else 0.73)
		if not stall_car(s, Vector2(px, cz), 0.0, "dry"):
			continue
		# Two on the car's sides leaning over its roof with a towel, one at its tail.
		var crew := [[Vector2(px - 1.45, cz - 0.3), -PI * 0.5, "rail"], [Vector2(px + 1.45, cz + 0.5), PI * 0.5, "rail"], [Vector2(px + 0.5, cz + 3.05), PI, "idle"]]
		for j in crew.size():
			if j == 2 and _h01(key + ["tail", i]) < 0.4:
				continue
			_attendant(s, crew[j][0], crew[j][1], crew[j][2], absi(hash(key + ["crew", i, j])), polo, lot_rect)
	# One at the cart.
	_attendant(s, Vector2(cx - 0.3, rz - 1.1), PI, "idle", absi(hash(key + ["cart"])), polo, lot_rect)


static func _attendant(s: Variant, p: Vector2, yaw: float, clip: String, pseed: int, polo: int, lot_rect: Rect2) -> void:
	var ch: CityChunk = s.ch
	var w: Vector3 = s.at(Vector3(p.x, 0.0, p.y))
	var face: Vector3 = s.xf.basis * Vector3(-sin(yaw), 0.0, -cos(yaw))
	var face_yaw := atan2(-face.x, -face.z)
	var towel := pseed % TOWELS.size()
	ch._run_or_defer(func() -> bool:
		if not is_instance_valid(ch) or not ch._take_crowd_room():
			return true
		var at := Vector2(w.x, w.z)
		var floor_y := Roadside.TOP + ch._gy(at.x, at.y) + Roadside.GROUND_LIFT
		var ped := CarWashAttendant.new()
		ped.polo = POLOS[polo]
		ped.towel = towel
		ped.pose_clip = CrowdLife.RAIL if clip == "rail" else CrowdLife.IDLE
		ped.setup_vendor(lot_rect, pseed, at, face_yaw, false, floor_y - ch.ground_y(at.x, at.y))
		ped.position = Vector3(at.x, floor_y + 0.05, at.y)
		ped.add_to_group("car_wash_crew")
		ch.add_child(ped)
		stats.crew += 1
		return true)


## A shade sail between x0..x1, its street edge at zf (height yf) and back edge at zb (yb), sagging
## a little in the middle; both faces.
static func _sail(pen: RoadsideKit.Pen, x0: float, x1: float, zf: float, zb: float, yf: float, yb: float, col: Color) -> void:
	var n := 4
	var pts := []
	for j in n + 1:
		var row := []
		for i in n + 1:
			var u := float(i) / n
			var v := float(j) / n
			var sag := 0.16 * sin(u * PI) * sin(v * PI)
			row.append(Vector3(lerpf(x0, x1, u), lerpf(yf, yb, v) - sag, lerpf(zf, zb, v)))
		pts.append(row)
	for j in n:
		for i in n:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			pen.quad(a, b, c, d, Vector3.UP, col, Vector2(0.9, 0.0))
			pen.quad(a, b, c, d, Vector3.DOWN, col, Vector2(0.9, 0.0))


## A towel folded over a rail at `top`: two hanging panels, the front a little longer, both faces.
static func _draped(pen: RoadsideKit.Pen, top: Vector3, w: float, length: float, col: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var l := length * (1.0 if side < 0.0 else 0.8)
		var off := 0.03 * side
		var a := top + Vector3(-w * 0.5, 0.0, off)
		var b := top + Vector3(w * 0.5, 0.0, off)
		var c := top + Vector3(w * 0.5, -l, off * 2.2)
		var d := top + Vector3(-w * 0.5, -l, off * 2.2)
		pen.quad(a, b, c, d, Vector3(0, 0, side), col, Vector2(0.95, 0.0))
		pen.quad(a, b, c, d, Vector3(0, 0, -side), col, Vector2(0.95, 0.0))


static var _towel_meshes: Dictionary = {}


## The hand towel an attendant holds (its top at the origin, hanging down -y), on the roadside
## material, in one of TOWELS.
static func towel_mesh(which: int) -> Mesh:
	which = absi(which) % TOWELS.size()
	if _towel_meshes.has(which):
		return _towel_meshes[which]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pen := RoadsideKit.Pen.new(st, Transform3D())
	var col := RoadsideKit.c(TOWELS[which], RoadsideKit.K_FIXED)
	# Gathered in the fist, spreading to 0.32 m, 0.45 m long, a slight bend.
	var rows := [[0.0, 0.05, 0.0], [-0.12, 0.2, 0.02], [-0.3, 0.3, 0.035], [-0.45, 0.32, 0.03]]
	for k in rows.size() - 1:
		var r0: Array = rows[k]
		var r1: Array = rows[k + 1]
		var a := Vector3(-r0[1] * 0.5, r0[0], r0[2])
		var b := Vector3(r0[1] * 0.5, r0[0], r0[2])
		var c := Vector3(r1[1] * 0.5, r1[0], r1[2])
		var d := Vector3(-r1[1] * 0.5, r1[0], r1[2])
		pen.quad(a, b, c, d, Vector3.BACK, col, Vector2(0.95, 0.0))
		pen.quad(a, b, c, d, Vector3.FORWARD, col, Vector2(0.95, 0.0))
	var mesh := st.commit()
	mesh.surface_set_material(0, RoadsideKit.material())
	_towel_meshes[which] = mesh
	return mesh
