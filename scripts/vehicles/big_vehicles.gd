class_name BigVehicles
extends RefCounted
## The big vehicles in traffic: the 40 ft city bus, the box truck and the semi (tractor and 53 ft
## trailer). Their bodies are Blender-built by tools/make_big_vehicles.py on the cars' pipeline
## and they ARE Vehicles (BodyType BUS, BOX_TRUCK, SEMI): kinematic in traffic, go_physical() when
## hit, CarDamage, CarCabin glass with a driver, CarLights, PhysicsBudget, the traffic pools. What
## is theirs lives here:
##   * the look: make() picks the livery (the bus's transit colours, the box truck's and the
##     trailer's fleet, the tractor's paint) - every company and agency name is INVENTED;
##   * their generated wheels: truck wheels (steel discs with hand holes, aluminium on a tractor),
##     duals on the driven and trailer axles, one mesh per dual pair (wheel_mesh());
##   * the bus's fittings (BusFittings): plug doors that swing open at a stop, the kerb-side kneel,
##     the LED destination signs (shaders/bus_sign.gdshader, sign_material());
##   * the semi's trailer (Hitch): a pivot at the kingpin that follows the tractor as a real
##     trailer does - its axle is dragged toward the kingpin (a tractrix), so a snapped turn at a
##     junction swings it round behind instead of jumping;
##   * the bus routes and their stops, worked out, never placed: route_of() says whether a road
##     carries a line, block_stop() where on a block a stop is, so the traffic (where a bus pulls
##     in) and the chunks (where the shelter and the clear kerb are) agree with no shared state.

const BUS := Vehicle.BodyType.BUS
const BOX_TRUCK := Vehicle.BodyType.BOX_TRUCK
const SEMI := Vehicle.BodyType.SEMI

## Mass relative to a car (1200 kg): engine, brakes and suspension are scaled with it so the
## handling numbers keep their meaning. A laden bus is ~13 t, a box truck 8 t, a rig 15-30 t.
const MASS_SCALE := {BUS: 8.0, BOX_TRUCK: 5.5, SEMI: 11.0, Vehicle.BodyType.FIRE_ENGINE: 12.0,
		Vehicle.BodyType.AMBULANCE: 4.5, Vehicle.BodyType.SCHOOL_BUS: 7.0}

## The transit agency (invented): its name on the skirt, its colours.
const AGENCY := "BASIN TRANSIT"
const BUS_PAINT := Color(0.93, 0.93, 0.91)
const BUS_TRIM := Color(0.04, 0.33, 0.36)
## Invented destinations a line's sign can show after its street name.
const DESTINATIONS := ["DOWNTOWN", "HARBOR", "AIRPORT", "BEACH", "VALLEY", "UNION STA", "CIVIC CTR",
	"COLLEGE", "MEDICAL CTR", "PIER"]

## Box-truck fleets: name, box paint, band. Invented businesses, none real.
const BOX_FLEETS := [
	["ARROYO BAKERY", Color(0.93, 0.92, 0.88), Color(0.70, 0.22, 0.10)],
	["HARBOR FRESH PRODUCE", Color(0.92, 0.93, 0.92), Color(0.10, 0.45, 0.20)],
	["TUMBLEWEED MOVERS", Color(0.95, 0.62, 0.10), Color(0.08, 0.08, 0.09)],
	["QUILLAN APPLIANCE", Color(0.92, 0.92, 0.93), Color(0.08, 0.20, 0.52)],
	["CORVO LINEN SUPPLY", Color(0.18, 0.30, 0.52), Color(0.93, 0.93, 0.90)],
	["MARIGOLD FLORAL", Color(0.92, 0.92, 0.90), Color(0.85, 0.45, 0.05)],
	["RANDO RENTALS", Color(0.82, 0.10, 0.10), Color(0.95, 0.95, 0.93)],
	["", Color(0.92, 0.92, 0.91), Color(0.92, 0.92, 0.91)],
]
## Semi fleets: name on the trailer, tractor paint.
const SEMI_FLEETS := [
	["WESTWIND FREIGHT", Color(0.55, 0.06, 0.07)],
	["DUSTBOWL CARRIERS", Color(0.92, 0.92, 0.90)],
	["PELICAN LOGISTICS", Color(0.07, 0.18, 0.42)],
	["CINDERCONE TRANSPORT", Color(0.06, 0.06, 0.07)],
	["OXBOW LINES", Color(0.10, 0.32, 0.18)],
	["", Color(0.60, 0.60, 0.62)],
	["", Color(0.92, 0.92, 0.90)],
]

## Share of street traffic that is a box truck or a semi (per spawn), and of freeway traffic.
const STREET_BOX_SHARE := 0.06
const STREET_SEMI_SHARE := 0.02
const FREEWAY_BOX_SHARE := 0.08
const FREEWAY_SEMI_SHARE := 0.16
## Share of the avenues that carry a bus line, and of a line's spawns that are a bus.
const ROUTE_SHARE := 0.5
const BUS_SHARE_ON_ROUTE := 0.3
## A route's stop on one block of one carriageway, every other block or so.
const STOP_SHARE := 0.55
## Metres from the kerb line of the crossing road back to where a far-side stop puts the bus's
## nose (a crosswalk, then a whole bus at the kerb).
const STOP_FROM_CORNER := 19.0
## How long the bus stands at a stop with its doors open (s), and the zone at the kerb kept clear
## of parked cars behind the nose (m).
const DWELL := Vector2(7.0, 13.0)
const STOP_ZONE := 16.0
## ...and ahead of it, where the bus pulls out again (m).
const STOP_CLEAR_AHEAD := 9.0
## How far a bus pulls over toward the kerb at a stop (m): out of its lane into the cleared kerb.
const STOP_SHIFT := 1.4
## Lettering draws to here (m): a TextMesh is glyph outlines, a few hundred triangles a letter.
const LETTER_DISTANCE := 55.0

static var _wheel_cache: Dictionary = {}
static var _sign_tex: Dictionary = {}
static var _sign_mats: Dictionary = {}
static var _text_meshes: Dictionary = {}
static var _letter_mat: Dictionary = {}


static func is_big(type: int) -> bool:
	return type == BUS or type == BOX_TRUCK or type == SEMI or type == Vehicle.BodyType.FIRE_ENGINE \
			or type == Vehicle.BodyType.AMBULANCE or type == Vehicle.BodyType.SCHOOL_BUS


# --- Making one ----------------------------------------------------------------------------------

## A big vehicle of `type` with its livery rolled from `look` (any int). Not in the tree yet.
static func make(type: int, look: int) -> Vehicle:
	var car := Vehicle.new()
	var paint := Color.WHITE
	var trim := Color.WHITE
	var livery := Vehicle.Livery.NONE
	var fleet := ""
	match type:
		BUS:
			paint = BUS_PAINT
			trim = BUS_TRIM
			livery = Vehicle.Livery.TWO_TONE
			fleet = AGENCY
		BOX_TRUCK:
			var f: Array = BOX_FLEETS[absi(hash([look, 1])) % BOX_FLEETS.size()]
			fleet = f[0]
			paint = f[1]
			trim = f[2]
			livery = Vehicle.Livery.DELIVERY if trim != paint else Vehicle.Livery.NONE
		SEMI:
			var f: Array = SEMI_FLEETS[absi(hash([look, 2])) % SEMI_FLEETS.size()]
			fleet = f[0]
			paint = f[1]
			trim = Vehicle._contrast_trim(paint)
		Vehicle.BodyType.SCHOOL_BUS:
			# National school bus yellow; the district's name is in the model (Schools).
			paint = Schools.BUS_YELLOW
			trim = paint
	car.setup(type, paint, Vehicle.Addon.NONE)
	car.setup_look(Vehicle.Finish.GLOSS, livery, trim)
	car.wheel_style = 0
	car.wheel_kit = 0 if type == SEMI else 1
	car.set_meta("fleet", fleet)
	car.set_meta("fleet_no", 100 + absi(hash([look, 3])) % 8900)
	return car


## Scales a big vehicle's physics by its mass (from Vehicle._ready, before _build()).
static func tune(car: Vehicle) -> void:
	var k: float = MASS_SCALE.get(car.body_type, 1.0)
	car.mass = 1200.0 * k
	car.engine_power *= k * 0.8
	car.reverse_power *= k
	car.brake_force *= k
	car.handbrake_force *= k
	car.parking_brake *= k
	car.suspension_max_force *= k
	car.top_speed = 30.0
	car.enter_radius = 6.0
	car.crash_min_dv = 6.0
	# A bus's windscreen is two metres of glass with the cabin behind it: its far twin (no glass
	# slot) drew it as a black slab from the 30 m a car's hands over at.
	if car.body_type == BUS or car.body_type == Vehicle.BodyType.SCHOOL_BUS:
		car.body_far_distance = 60.0


## After the body model is placed (Vehicle._add_body_model): the trailer onto its pivot, the bus's
## doors and signs, the lettering. `trailer` and `doors` are the model's MeshInstance3Ds by name.
static func fit(car: Vehicle, holder: Node3D, trailer: Array, doors: Array) -> void:
	_tune_paint(car, trailer)
	if not trailer.is_empty():
		var hitch := Hitch.new()
		hitch.name = "Hitch"
		car.add_child(hitch)
		hitch.setup(car, holder, trailer)
	if car.body_type == BUS:
		var fit_node := BusFittings.new()
		fit_node.name = "BusFittings"
		car.add_child(fit_node)
		fit_node.setup(car, holder, doors)
	_add_lettering(car)


## Where the livery's band sits on each body (fractions of the model's height), and the semi's
## trailer in its own white paint (the tractor keeps the car's).
const BAND := {BUS: [0.365, 0.006], BOX_TRUCK: [0.57, 0.03]}
const TRAILER_PAINT := Color(0.90, 0.90, 0.89)


static func _tune_paint(car: Vehicle, trailer: Array) -> void:
	var paint: ShaderMaterial = null
	for m in car._body_meshes:
		if not is_instance_valid(m) or m.mesh == null or trailer.has(m):
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src != null and String(src.resource_name).begins_with("paint"):
				paint = m.get_surface_override_material(si) as ShaderMaterial
				break
		if paint != null:
			break
	if paint == null:
		return
	if BAND.has(car.body_type):
		var b: Array = BAND[car.body_type]
		paint.set_shader_parameter("stripe_height", b[0])
		paint.set_shader_parameter("stripe_width", b[1])
	if trailer.is_empty():
		return
	var tp := paint.duplicate() as ShaderMaterial
	tp.set_shader_parameter("paint", TRAILER_PAINT)
	tp.set_shader_parameter("stripe_mode", 0)
	tp.set_shader_parameter("flake_strength", 0.0)
	for m: MeshInstance3D in trailer:
		for si in m.mesh.get_surface_count():
			if m.get_surface_override_material(si) == paint:
				m.set_surface_override_material(si, tp)


## The fleet's name on both sides (box truck: the box; semi: the trailer; bus: the skirt).
static func _add_lettering(car: Vehicle) -> void:
	var fleet: String = car.get_meta("fleet", "")
	if fleet.is_empty() or OS.has_feature("web"):
		return
	var d := car._dims()
	var at: Vector3 = d.get("letter_at", Vector3.ZERO)
	var size: float = float(d.get("letter_size", 0.4))
	var parent: Node3D = car
	if car.body_type == SEMI and car.get_node_or_null("Hitch") != null:
		parent = (car.get_node("Hitch") as Hitch).pivot
	var color := car.trim_color if car.body_type != SEMI else Color(0.12, 0.13, 0.15)
	if car.body_type == BUS:
		color = BUS_TRIM
	var mesh := text_mesh(fleet, size, color)
	for side: float in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "Lettering"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = LETTER_DISTANCE
		mi.basis = Basis(Vector3.UP, PI * 0.5 * side)
		mi.position = Vector3(side * at.x, at.y, at.z)
		parent.add_child(mi)


## One TextMesh per (text, size, colour), shared by every vehicle that wears it.
static func text_mesh(text: String, size: float, color: Color) -> TextMesh:
	var key := "%s|%.2f|%s" % [text, size, color.to_html()]
	if _text_meshes.has(key):
		return _text_meshes[key]
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 64
	tm.pixel_size = size / 64.0
	tm.depth = 0.0
	tm.curve_step = 1.5
	var ck := color.to_html()
	if not _letter_mat.has(ck):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.45
		_letter_mat[ck] = m
	tm.material = _letter_mat[ck]
	_text_meshes[key] = tm
	return tm


# --- Truck wheels ---------------------------------------------------------------------------------

## A truck wheel (tyre, steel or alloy disc with ten hand holes, hub and lug nuts), outboard face
## toward +X like PropFactory.car_wheel(), on PropFactory's wheel material classes. `dual` makes it
## a pair side by side `gap` apart (the mesh centred between them, the outer disc deep-dished),
## one mesh and one draw for both. `near` false: the far LOD (16 segments, no nuts).
static func wheel_mesh(radius: float, width: float, dual: bool, gap: float, near: bool) -> Mesh:
	var key := "tw_%d_%d_%d_%d_%d" % [roundi(radius * 500.0), roundi(width * 500.0), int(dual), roundi(gap * 500.0), int(near)]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var seg := 40 if near else 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if dual:
		_one_wheel(st, radius, width, gap * 0.5, -0.62, seg, near, true)
		_one_wheel(st, radius, width, -gap * 0.5, 0.0, seg, false, false)
	else:
		_one_wheel(st, radius, width, 0.0, 0.18, seg, near, true)
	st.index()
	var mesh := st.commit()
	_wheel_cache[key] = mesh
	return mesh


## One tyre and rim centred `x0` along the axle; `dish` is where the disc sits across the rim in
## half-widths (+ outboard); `face` false leaves the disc off (the hidden inner tyre of a dual).
static func _one_wheel(st: SurfaceTool, r: float, w: float, x0: float, dish: float, seg: int, nuts: bool, face: bool) -> void:
	var hw := w * 0.5
	var rim_r := r * 0.56
	var S := PropFactory.WheelSlot
	# Profile: (radius, axial, slot, shade), outboard (+) to inboard round the tyre, then the rim.
	var tyre := [
		[rim_r + 0.012, hw * 0.86], [r * 0.80, hw * 1.0], [r * 0.95, hw * 0.96], [r, hw * 0.72],
		[r, -hw * 0.72], [r * 0.95, -hw * 0.96], [r * 0.80, -hw * 1.0], [rim_r + 0.012, -hw * 0.86],
	]
	for i in tyre.size() - 1:
		var a: Array = tyre[i]
		var b: Array = tyre[i + 1]
		var slot: int = S.LETTER if (i == 1 or i == 5) else S.RUBBER
		_lathe(st, float(a[0]), x0 + float(a[1]), float(b[0]), x0 + float(b[1]), seg, slot, 0.9 if i >= 2 and i <= 4 else 0.75)
	# The rim's barrel and flanges.
	_lathe(st, rim_r + 0.012, x0 - hw * 0.86, rim_r - 0.005, x0 - hw * 0.80, seg, S.BARREL, 0.6)
	_lathe(st, rim_r - 0.005, x0 + hw * 0.80, rim_r + 0.012, x0 + hw * 0.86, seg, S.FACE, 0.95)
	_lathe(st, rim_r - 0.012, x0 + hw * 0.80, rim_r - 0.012, x0 - hw * 0.80, seg, S.BARREL, 0.45)
	if not face:
		return
	var dx := x0 + hw * dish
	# The flange down into the dish, the disc with its hand holes, the hub, the cap.
	_lathe(st, rim_r - 0.012, x0 + hw * 0.80, rim_r * 0.92, dx, seg, S.FACE, 0.8)
	var holes := 10
	for k in seg:
		var a0 := TAU * float(k) / float(seg)
		var a1 := TAU * float(k + 1) / float(seg)
		var mid := fposmod((a0 + a1) * 0.5 * float(holes) / TAU, 1.0)
		var hole := mid > 0.25 and mid < 0.75
		_ring_quad(st, rim_r * 0.92, rim_r * 0.80, dx, dx, a0, a1, S.FACE, 0.9)
		_ring_quad(st, rim_r * 0.80, rim_r * 0.62, dx, dx - (0.02 if hole else 0.0), a0, a1, S.DARK if hole else S.FACE, 0.35 if hole else 0.85)
		_ring_quad(st, rim_r * 0.62, rim_r * 0.50, dx, dx, a0, a1, S.FACE, 0.9)
	_lathe(st, rim_r * 0.50, dx, rim_r * 0.44, dx + 0.025, seg, S.FACE, 1.0)
	_lathe(st, rim_r * 0.44, dx + 0.025, rim_r * 0.30, dx + 0.03, seg, S.CAP, 1.0)
	_lathe(st, rim_r * 0.30, dx + 0.03, rim_r * 0.22, dx + 0.075, seg, S.CAP, 1.0)
	_lathe(st, rim_r * 0.22, dx + 0.075, 0.001, dx + 0.085, seg, S.CAP, 1.0)
	if nuts:
		for k in 10:
			var a := TAU * (float(k) + 0.5) / 10.0
			var c := Vector3(dx + 0.025, cos(a) * rim_r * 0.38, sin(a) * rim_r * 0.38)
			_nut(st, c, 0.016, 0.03)


## A band of quads revolved round the axle (X) from (r0, x0) to (r1, x1), normals off the profile.
static func _lathe(st: SurfaceTool, r0: float, x0: float, r1: float, x1: float, seg: int, slot: int, shade: float) -> void:
	var dr := r1 - r0
	var dx := x1 - x0
	# The profile's outward normal in (axial, radial): turned from its tangent, toward +radius
	# for a band like the tread and toward +axial for a face looking outboard.
	var n2 := Vector2(-dr, dx).normalized()
	if n2 == Vector2.ZERO:
		n2 = Vector2(1.0, 0.0)
	for k in seg:
		var a0 := TAU * float(k) / float(seg)
		var a1 := TAU * float(k + 1) / float(seg)
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var pa := Vector3(x0, c0.x * r0, c0.y * r0)
		var pb := Vector3(x0, c1.x * r0, c1.y * r0)
		var pc := Vector3(x1, c1.x * r1, c1.y * r1)
		var pd := Vector3(x1, c0.x * r1, c0.y * r1)
		var na := Vector3(n2.x, c0.x * n2.y, c0.y * n2.y)
		var nb := Vector3(n2.x, c1.x * n2.y, c1.y * n2.y)
		PropFactory._wq(st, pa, pb, pc, pd, na, nb, nb, na, shade, slot)


static func _ring_quad(st: SurfaceTool, r0: float, r1: float, x0: float, x1: float, a0: float, a1: float, slot: int, shade: float) -> void:
	var c0 := Vector2(cos(a0), sin(a0))
	var c1 := Vector2(cos(a1), sin(a1))
	var n := Vector3(1.0, 0.0, 0.0)
	PropFactory._wq(st, Vector3(x0, c0.x * r0, c0.y * r0), Vector3(x0, c1.x * r0, c1.y * r0),
			Vector3(x1, c1.x * r1, c1.y * r1), Vector3(x1, c0.x * r1, c0.y * r1), n, n, n, n, shade, slot)


## A lug nut: a hexagonal prism `h` long pointing outboard from `c`.
static func _nut(st: SurfaceTool, c: Vector3, r: float, h: float) -> void:
	var slot: int = PropFactory.WheelSlot.CAP
	for k in 6:
		var a0 := TAU * float(k) / 6.0
		var a1 := TAU * float(k + 1) / 6.0
		var p0 := c + Vector3(0.0, cos(a0) * r, sin(a0) * r)
		var p1 := c + Vector3(0.0, cos(a1) * r, sin(a1) * r)
		var n := Vector3(0.0, cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5))
		PropFactory._wq(st, p0, p1, p1 + Vector3(h, 0, 0), p0 + Vector3(h, 0, 0), n, n, n, n, 1.0, slot)
		var e := c + Vector3(h, 0, 0)
		PropFactory._wq(st, p0 + Vector3(h, 0, 0), p1 + Vector3(h, 0, 0), e, e, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, 1.0, slot)


## The wheel finish: white-painted steel (the bus, the box truck) or polished aluminium (a semi).
static func wheel_material(type: int) -> Material:
	var key := "truck_wheel_%d" % type
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var base := PropFactory.wheel_material(0)
	var mat := base.duplicate() as ShaderMaterial
	# Polished discs on the semi and the fire engine; painted steel on the rest.
	if type != SEMI and type != Vehicle.BodyType.FIRE_ENGINE:
		mat.set_shader_parameter("c_face", Vector3(0.78, 0.78, 0.76))
		mat.set_shader_parameter("m_face", Vector2(0.0, 0.42))
		mat.set_shader_parameter("c_barrel", Vector3(0.55, 0.55, 0.54))
		mat.set_shader_parameter("m_barrel", Vector2(0.0, 0.5))
		mat.set_shader_parameter("c_cap", Vector3(0.62, 0.62, 0.63))
		mat.set_shader_parameter("m_cap", Vector2(0.2, 0.4))
	_wheel_cache[key] = mat
	return mat


## Every axle's wheels for a big vehicle (Vehicle._add_generated_wheels hands over here): one rig
## a wheel or dual pair, the first axle steering, a trailer's axles on its pivot. Fills the car's
## own rig list, so its _update_wheels() rolls and steers them like a car's.
static func add_wheels(car: Vehicle, pose: Dictionary) -> void:
	var r := float(pose.r)
	var w := float(pose.w)
	var gap := float(pose.get("dual_gap", 0.33))
	var mat := wheel_material(car.body_type)
	car._wheel_radius = r
	car._wheel_far_end = car.wheel_draw_distance
	car._wheel_meshes = []
	var axles: Array = pose.axles
	var hitch := car.get_node_or_null("Hitch") as Hitch
	for t_axle: Array in pose.get("trailer_axles", []):
		axles = axles + [[float(t_axle[0]), true, true]]
	for k in axles.size():
		var ax: Array = axles[k]
		var z := float(ax[0])
		var dual := bool(ax[1])
		var on_trailer: bool = ax.size() > 2 and bool(ax[2])
		var parent: Node3D = car
		var y := float(pose.y)
		if on_trailer:
			if hitch == null:
				continue
			parent = hitch.pivot
			y -= hitch.pivot.position.y
		var near := wheel_mesh(r, w, dual, gap, true)
		var far := wheel_mesh(r, w, dual, gap, false)
		for side: float in [-1.0, 1.0]:
			var steer := Node3D.new()
			steer.name = "Wheel%d%s" % [k, "L" if side < 0.0 else "R"]
			var x := float(pose.get("dual_x", pose.x)) if dual else float(pose.x)
			steer.position = Vector3(side * x, y, z)
			parent.add_child(steer)
			var flip := Basis(Vector3.UP, 0.0 if side > 0.0 else PI)
			var mi := MeshInstance3D.new()
			mi.mesh = near
			mi.material_override = mat
			mi.basis = flip
			mi.visibility_range_end = car._wheel_far_end
			steer.add_child(mi)
			# No caliper on a truck wheel (the hub covers it); an empty node keeps the rig's shape.
			var cal := MeshInstance3D.new()
			cal.visible = false
			steer.add_child(cal)
			car._wheel_rigs.append([steer, mi, cal, flip, k == 0, y, near, far])
		car._wheel_meshes.append([near, far, null])
	car._susp_rest = PackedFloat32Array()
	car._susp_rest.resize(car._wheel_rigs.size())
	car._susp_rest.fill(NAN)
	car._last_yaw = car.rotation.y


# --- Bus destination signs -----------------------------------------------------------------------

## The L8 texture of `text` in the 5 x 7 LED face (one texel a LED, a row of blank LEDs round it),
## at least `cells` LEDs wide, the text centred.
static func sign_texture(text: String, cells: int) -> ImageTexture:
	var key := "%s|%d" % [text, cells]
	if _sign_tex.has(key):
		return _sign_tex[key]
	var w := maxi(cells, LedScreen.text_width(text) + 4)
	var img := Image.create(w, 9, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	var x := (w - LedScreen.text_width(text)) / 2
	for ch in text:
		var rows: Array = LedScreen.GLYPHS.get(ch, LedScreen.GLYPHS[" "])
		for r in 7:
			var row: String = rows[r]
			for c in 5:
				if row[c] == "#":
					img.set_pixel(x + c, 1 + r, Color.WHITE)
		x += 6
	var tex := ImageTexture.create_from_image(img)
	_sign_tex[key] = tex
	return tex


## The signs of a bus on line `number` heading for `dest` ("" leaves them dark: not in service).
## One material per (line, destination), shared by every bus showing it.
static func sign_material(number: int, dest: String) -> ShaderMaterial:
	var key := "%d|%s" % [number, dest]
	if _sign_mats.has(key):
		return _sign_mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bus_sign.gdshader")
	var front := "" if number <= 0 else "%d %s" % [number, dest]
	var ft := sign_texture(front, 96)
	var rt := sign_texture("" if number <= 0 else str(number), 24)
	mat.set_shader_parameter("front_text", ft)
	mat.set_shader_parameter("rear_text", rt)
	mat.set_shader_parameter("front_cells", Vector2(ft.get_width(), ft.get_height()))
	mat.set_shader_parameter("rear_cells", Vector2(rt.get_width(), rt.get_height()))
	mat.set_shader_parameter("lit", 1.0 if number > 0 else 0.0)
	_sign_mats[key] = mat
	return mat


# --- Routes and stops ----------------------------------------------------------------------------

## The line number road (axis, index) carries, or 0. Avenues only (two lanes each way), a hash of
## the seed and the road, so every system asks the same question and gets the same answer.
static func route_of(plan: CityPlan, axis: int, index: int) -> int:
	if plan.road_width(axis, index) <= plan.street_width + 1.0:
		return 0
	var h := absi(hash([plan.seed, axis, index, "bus_line"]))
	if float(h % 1000) / 1000.0 >= ROUTE_SHARE:
		return 0
	return 2 + (h / 1000) % 240


## The destination a line's bus shows heading `dir` along its road.
static func destination(plan: CityPlan, axis: int, index: int, dir: int) -> String:
	var h := absi(hash([plan.seed, axis, index, dir, "bus_dest"]))
	return DESTINATIONS[h % DESTINATIONS.size()]


## Where, along road (axis, index), a bus heading `dir` stops on the block between crossing roads
## `k` and `k + 1` (the true-world coordinate its NOSE stops at), or NAN: no stop on this block.
## Far side of the corner it has just crossed, the way most of LA's are.
static func block_stop(plan: CityPlan, axis: int, index: int, k: int, dir: int) -> float:
	if route_of(plan, axis, index) == 0:
		return NAN
	if float(absi(hash([plan.seed, axis, index, k, dir, "bus_stop"])) % 1000) / 1000.0 >= STOP_SHARE:
		return NAN
	var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
	var lo := plan.road_pos(cross, k) + plan.road_width(cross, k) * 0.5
	var hi := plan.road_pos(cross, k + 1) - plan.road_width(cross, k + 1) * 0.5
	if hi - lo < STOP_FROM_CORNER + 22.0:
		return NAN
	return lo + STOP_FROM_CORNER if dir > 0 else hi - STOP_FROM_CORNER


## True when true-world point `p` (on a carriageway) is in a stop's kerb zone, where nothing may
## park: the parked cars ask it (CityChunk._park_car).
static func in_stop_zone(plan: CityPlan, p: Vector2) -> bool:
	for axis: int in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var across := p.x if axis == CityPlan.AXIS_X else p.y
		var along := p.y if axis == CityPlan.AXIS_X else p.x
		var index := plan._index_at(axis, across)
		for i: int in [index, index + 1]:
			var road := plan.road_pos(axis, i)
			if absf(across - road) > plan.road_width(axis, i) * 0.5:
				continue
			var s := signf(across - road)
			var dir := int(-s) if axis == CityPlan.AXIS_X else int(s)
			var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
			var k := plan._index_at(cross, along)
			var stop := block_stop(plan, axis, i, k, dir)
			if is_nan(stop):
				continue
			var back := (stop - along) * float(dir)
			if back > -STOP_CLEAR_AHEAD and back < STOP_ZONE:
				return true
	return false


## The shelters of a block's stops (CityChunk, after its pavement furniture): for each pavement
## edge of the block on a bus line, the stop of the traffic beside it, its shelter on the
## pavement by the bus's front door. Rolls nothing from the chunk's rng.
static func build_bus_stops(chunk: CityChunk, rect: Rect2, edges: Array) -> void:
	var plan: CityPlan = chunk.plan
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		# An edge along z is beside an AXIS_X road; its traffic's side is the pavement's side.
		var along_z := absf(a.x - b.x) < 0.01
		var axis := CityPlan.AXIS_X if along_z else CityPlan.AXIS_Z
		var across := a.x if along_z else a.y
		var index := plan._index_at(axis, across - inward.x - inward.y)
		var best := index
		for i: int in [index - 1, index, index + 1]:
			if absf(plan.road_pos(axis, i) - across) < absf(plan.road_pos(axis, best) - across):
				best = i
		var road := plan.road_pos(axis, best)
		var s := signf(across - road)
		var dir := int(-s) if axis == CityPlan.AXIS_X else int(s)
		var cross := CityPlan.AXIS_Z if axis == CityPlan.AXIS_X else CityPlan.AXIS_X
		var mid := (a.y + b.y) * 0.5 if along_z else (a.x + b.x) * 0.5
		var k := plan._index_at(cross, mid)
		var stop := block_stop(plan, axis, best, k, dir)
		if is_nan(stop) or not plan.road_open(axis, best, stop):
			continue
		# The shelter stands by the front door, a few metres behind the nose.
		var at_along := stop - float(dir) * 3.5
		var p := Vector2(across, at_along) if along_z else Vector2(at_along, across)
		p += inward * 2.0
		var d2 := (b - a).normalized()
		if plan.macro and Landmarks.covers(plan, p, 3.0):
			continue
		StreetDetail._bus_shelter(chunk, p, inward, d2)


# --- The bus's doors, kneel and signs ------------------------------------------------------------

class BusFittings extends Node:
	## Seconds a door takes to open or close, and how far a leaf swings (radians).
	const DOOR_TIME := 1.1
	const DOOR_SWING := 1.45
	## The kneel at a stop: how far the body drops on the kerb side (m) and rolls (radians).
	const KNEEL_DROP := 0.055
	const KNEEL_ROLL := 0.022

	var car: Vehicle
	var holder: Node3D
	## [node, rest basis, sign (+1 or -1)] per leaf.
	var leaves: Array = []
	var _rest_pos: Vector3
	var _rest_basis: Basis
	var open: float = 0.0
	var want_open: bool = false
	var kneel: float = 0.0
	var want_kneel: bool = false
	var line: int = 0
	var dest: String = ""
	var _sign_slots: Array = []

	func setup(c: Vehicle, h: Node3D, doors: Array) -> void:
		car = c
		holder = h
		_rest_pos = h.position
		_rest_basis = h.basis
		for d: MeshInstance3D in doors:
			# Leaf "a" of a pair hangs from its front edge and runs back, "b" the other way.
			var sgn := 1.0 if String(d.name).ends_with("a") else -1.0
			leaves.append([d, d.basis, sgn])
		for m in car._body_meshes:
			if not is_instance_valid(m) or m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(si)
				if src != null and String(src.resource_name) == "sign":
					_sign_slots.append([m, si])
		set_process(false)
		show_line(0, "")

	## Puts line `number` heading for `dest` on the signs (0: dark).
	func show_line(number: int, d: String) -> void:
		line = number
		dest = d
		var mat := BigVehicles.sign_material(number, d)
		for s: Array in _sign_slots:
			(s[0] as MeshInstance3D).set_surface_override_material(s[1], mat)

	func set_doors(on: bool) -> void:
		want_open = on
		want_kneel = on
		set_process(true)

	func _process(delta: float) -> void:
		var step := delta / DOOR_TIME
		open = move_toward(open, 1.0 if want_open else 0.0, step)
		kneel = move_toward(kneel, 1.0 if want_kneel else 0.0, step * 0.8)
		var e := open * open * (3.0 - 2.0 * open)
		for l: Array in leaves:
			var n := l[0] as Node3D
			if is_instance_valid(n):
				n.basis = Basis(Vector3.UP, float(l[2]) * DOOR_SWING * e) * (l[1] as Basis)
		var k := kneel * kneel * (3.0 - 2.0 * kneel)
		holder.basis = Basis(Vector3.BACK, -KNEEL_ROLL * k) * _rest_basis
		holder.position = _rest_pos + Vector3(0.0, -KNEEL_DROP * k, 0.0)
		if open == (1.0 if want_open else 0.0) and kneel == (1.0 if want_kneel else 0.0):
			set_process(false)

	func doors_open() -> float:
		return open


# --- The semi's trailer --------------------------------------------------------------------------

class Hitch extends Node:
	## Most the trailer may swing off the tractor's line (radians).
	const MAX_ANGLE := 1.35
	## A tractor that moved further than this in one tick was placed, not driven: the trailer is
	## put straight behind it again.
	const JUMP := 6.0

	var car: Vehicle
	## The pivot on the kingpin (body space), the trailer's meshes and wheels under it.
	var pivot: Node3D
	## Kingpin to the trailer's axle centre (m), and that point in true world space.
	var axle_dist: float = 13.4
	var _axle_w: Vector3 = Vector3.INF
	var _kp_last: Vector3 = Vector3.INF
	var angle: float = 0.0
	var _shape: CollisionShape3D
	var _shape_center: Vector3
	var _shape_angle: float = INF

	func setup(c: Vehicle, holder: Node3D, meshes: Array) -> void:
		car = c
		var d := car._dims()
		pivot = Node3D.new()
		pivot.name = "Trailer"
		pivot.position = d.get("kingpin", Vector3(0.0, 0.92, 2.9))
		car.add_child(pivot)
		axle_dist = float(d.get("trailer_axle", 13.4))
		var box := AABB()
		var first := true
		for m: MeshInstance3D in meshes:
			var xf := CarCabin.chain(m, car)
			var local := pivot.transform.affine_inverse() * xf
			m.get_parent().remove_child(m)
			m.transform = local
			pivot.add_child(m)
			if not String(m.name).ends_with("_far"):
				var bb := local * m.mesh.get_aabb()
				box = bb if first else box.merge(bb)
				first = false
		# The trailer's collision: one box on the car, moved with the pivot.
		_shape = CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var floor_y := float(d.get("trailer_floor", -0.1))
		var lo := Vector3(box.position.x, floor_y, box.position.z)
		var hi := box.end
		bs.size = hi - lo
		_shape.shape = bs
		_shape_center = (lo + hi) * 0.5
		car.add_child(_shape)
		_place_shape()
		set_physics_process(true)

	func _physics_process(_delta: float) -> void:
		if not is_instance_valid(car) or not car.is_inside_tree():
			return
		var kp := WorldState.to_world(car.global_transform * pivot.position)
		var back := WorldState.to_world(car.global_transform * (pivot.position + Vector3(0.0, 0.0, axle_dist))) - WorldState.to_world(car.global_transform * pivot.position)
		if not car.is_traffic():
			# Physical (hit, or driven): the rig is rigid, straightening out.
			angle = move_toward(angle, 0.0, _delta * 0.6)
			_axle_w = Vector3.INF
		else:
			if _axle_w == Vector3.INF or _kp_last == Vector3.INF or kp.distance_to(_kp_last) > JUMP:
				_axle_w = kp + back
			# The tractrix: the axle is dragged toward the kingpin, keeping its distance.
			var to := _axle_w - kp
			to.y = 0.0
			if to.length() < 0.01:
				to = back
			_axle_w = kp + to.normalized() * axle_dist
			var fwd := car.global_basis.z
			var a := atan2(fwd.x, fwd.z)
			var t := atan2(to.x, to.z)
			angle = clampf(wrapf(t - a, -PI, PI), -MAX_ANGLE, MAX_ANGLE)
		_kp_last = kp
		pivot.basis = Basis(Vector3.UP, angle)
		_place_shape()

	func _place_shape() -> void:
		if absf(angle - _shape_angle) < 0.004:
			return
		_shape_angle = angle
		var xf := pivot.transform
		_shape.transform = Transform3D(xf.basis, xf * _shape_center)

	## Straight behind the tractor again (a placement, a test).
	func straighten() -> void:
		angle = 0.0
		_axle_w = Vector3.INF
		pivot.basis = Basis()
		_place_shape()
