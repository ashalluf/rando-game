class_name HouseNights
extends RefCounted
## The suburbs and the beach town at night (21:00-23:30, from the street, a car and the air): each
## house's night is ONE integer, its key (`key()`: the house seed mod 997, which the far box already
## carries in INSTANCE_CUSTOM.b - MidCity.house_custom()), and every roll below is an integer hash
## of it (`shaders/house_nights.gdshaderinc` is the same maths, bit for bit), so the house the street
## sees is the house the hills see:
## - nobody home (`DARK` per mille): every window dark, the porch light on a timer in some;
## - a lamp TONE per house (warm incandescent, soft white, neutral, a cool LED), the share of rooms
##   lit, a bedtime after which one lamp in four stays on (the city's clock);
## - a TV in one room of a third of them, flickering blue (house_glass.gdshader);
## - the porch light, the garage's carriage lamps, a lit house number, and on the nicer houses
##   (`NICE`) path lights down the front walk and landscape uplights grazing the facade;
## - pool lights glowing turquoise in the back yards (`pool_on()`, keyed by the pool's own place,
##   the key MidCity.pool() gives the far box).
## Fixtures are geometry in the chunk's house mesh ("h_lamp", shaders/house_lamp.gdshader); their
## light is additive quads in four batches a chunk (shaders/house_glow.gdshader): pools on the
## ground, scallops and uplight cones on the walls, halos. Real OmniLights only on the few porches
## nearest the camera, Forward+ desktop (`HouseNightLights`, `HouseNightLights.budget`).
## `HOUSE_NIGHTS=0` in the environment is the A/B: no UV2 on the glass (its old look), no
## fixtures, no glow, the far boxes and pools as before.

static var enabled: bool = OS.get_environment("HOUSE_NIGHTS") != "0"

# The numbers house_nights.gdshaderinc holds too (checked by tests/house_nights_checks.gd).
const DARK := 110
const TV := 340
const SHARE_LO := 0.32
const SHARE_SPAN := 0.42
const BED_LO := 22.4
const BED_SPAN := 2.4
const BED_KEEP := 0.28
const POOL := 650
## Per mille of lived-in houses with the porch light on, and of dark ones (a timer).
const PORCH := 820
const PORCH_DARK := 350
## Per mille of houses with a porch light whose garage carriage lamps burn, and whose number is lit.
const CARRIAGE := 760
const NUMBER := 620
## Per mille of lived-in houses with landscape lighting (path lights and uplights).
const NICE := 300

## The lamp tones, LINEAR (hn_tone()).
const TONES := [Color(1.0, 0.56, 0.24), Color(1.0, 0.70, 0.40), Color(1.0, 0.82, 0.62), Color(0.84, 0.88, 1.0)]
## The outdoor lamps' tint in DISPLAY numbers (the glow quads add in display numbers).
const PORCH_GLOW := Color(1.0, 0.78, 0.48)
const LED_GLOW := Color(0.92, 0.94, 1.0)
## A fixture's housing in the fixtures mesh (house_lamp.gdshader kind 3: dark bronze, never lit).
const HOUSING := Color(0.05, 0.045, 0.04, 0.75)
const UPLIGHT_GLOW := Color(1.0, 0.86, 0.62)
const POOL_GLOW := Color(0.25, 0.85, 0.95)
## How far the glow batches draw (m): the halos further, so the street reads from the air.
const GLOW_DISTANCE := 260.0
const HALO_DISTANCE := 900.0


static func ihash(x: int) -> int:
	x = x & 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 0x7feb352d) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 0x846ca68b) & 0xFFFFFFFF
	x ^= x >> 16
	return x


## A house's key from its seed (MidCity.house_custom() puts the same number in the far box).
static func key(seed_v: int) -> int:
	return absi(seed_v) % 997


## 0..999 for a key and a salt (hn_pct()).
static func pct(k: int, salt: int) -> int:
	return ihash((k * 7919 + salt) & 0xFFFFFFFF) % 1000


static func dark(k: int) -> bool:
	return pct(k, 1) < DARK


static func tone_index(k: int) -> int:
	return ihash((k * 7919 + 2) & 0xFFFFFFFF) % 4


static func tone(k: int) -> Color:
	return TONES[tone_index(k)]


static func tv(k: int) -> bool:
	return pct(k, 4) < TV


## The share of the house's rooms lit at `hour` (hn_share()).
static func share(k: int, hour: float) -> float:
	if dark(k):
		return 0.0
	var s := SHARE_LO + SHARE_SPAN * float(pct(k, 3)) / 1000.0
	var h := hour + 24.0 if hour < 6.0 else hour
	var bed := BED_LO + BED_SPAN * float(pct(k, 9)) / 1000.0
	return s * BED_KEEP if h > bed else s


static func porch_on(k: int) -> bool:
	return pct(k, 5) < (PORCH_DARK if dark(k) else PORCH)


static func carriage_on(k: int) -> bool:
	return porch_on(k) and pct(k, 6) < CARRIAGE


static func number_lit(k: int) -> bool:
	return porch_on(k) and pct(k, 8) < NUMBER


static func nice(k: int) -> bool:
	return not dark(k) and pct(k, 7) < NICE


## The house number on the plaque by the door (three digits, 101..998).
static func house_number(k: int) -> int:
	return 101 + ihash(k * 7919 + 11) % 898


## A pool's key: its centre's place, as MidCity.pool() keys the far box.
static func pool_key(r: Rect2) -> int:
	var c := r.get_center()
	return absi(hash([c.x, c.y])) % 997


static func pool_on(pk: int) -> bool:
	return pct(pk, 10) < POOL


## The yard ground's variant for a pool (lot_yard.gdshader): 0 the old pool, 0.25 its light off,
## 0.75 on.
static func pool_variant(r: Rect2) -> float:
	if not enabled:
		return 0.0
	return 0.75 if pool_on(pool_key(r)) else 0.25


# =================================================================================================
# Building (FULL chunks): fixtures into the house mesh, light into the glow batches
# =================================================================================================

static var _glow_meshes := {}


## The unit glow quad for a shape (house_glow.gdshader: 0 pool, 1 uplight, 2 scallop, 3 halo).
static func glow_mesh(shape: int) -> Mesh:
	if _glow_meshes.has(shape):
		return _glow_meshes[shape]
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/house_glow.gdshader")
	mat.set_shader_parameter("shape", shape)
	mesh.material = mat
	if shape == 3:
		mesh.custom_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_glow_meshes[shape] = mesh
	return mesh


const GLOW_KEYS := ["hn_pool", "hn_uplight", "hn_scallop", "hn_halo"]


static var _lamp_mat: ShaderMaterial


static func lamp_material() -> ShaderMaterial:
	if _lamp_mat == null:
		_lamp_mat = ShaderMaterial.new()
		_lamp_mat.shader = load("res://shaders/house_lamp.gdshader")
	return _lamp_mat


## A glow quad: `shape` (GLOW_KEYS' order) at chunk-space `at`, its plane spanned by `ax` (width)
## and `ay` (height) - for a pool lying flat, for a wall wash up the wall - tint in display numbers,
## strength in alpha. The batch lifts every instance by the relief, so that is taken off here.
static func _glow(ch: CityChunk, shape: int, at: Vector3, ax: Vector3, ay: Vector3, tint: Color, strength: float) -> void:
	var n := ax.cross(ay)
	if n.length_squared() < 1e-8:
		return
	var o := at
	o.y -= ch._gy(at.x, at.z)
	var c := tint
	c.a = strength
	ch._batch.add(GLOW_KEYS[shape], glow_mesh(shape), Transform3D(Basis(ax, ay, n.normalized() * 0.01), o), c)


static func _pool_at(ch: CityChunk, at: Vector3, radius: float, tint: Color, strength: float) -> void:
	_glow(ch, 0, at, Vector3(radius * 2.0, 0, 0), Vector3(0, 0, -radius * 2.0), tint, strength)


static func _halo(ch: CityChunk, at: Vector3, size: float, tint: Color, strength: float) -> void:
	var o := at
	o.y -= ch._gy(at.x, at.z)
	var c := tint
	c.a = strength
	ch._batch.add("hn_halo", glow_mesh(3), Transform3D(Basis().scaled(Vector3.ONE * size), o), c)


## The night dress of one house (HouseKit.build(), after its house and LaTrees' planting): fixtures,
## their light, and the porch for the real lights. `cyp0`: where this house's cypresses start in the
## chunk's "la_cypress_at" (they get uplights on the nicer houses).
static func dress(b: HouseBuild, cyp0: int = -1) -> void:
	if not enabled:
		return
	var h := b.h
	var ch := b.ch
	var k := key(b.seed)
	var porch := porch_on(k)
	var lamp_tint := tone(k)
	var glow_tint := PORCH_GLOW if tone_index(k) < 3 else LED_GLOW
	var ground := CityChunk.SIDEWALK_TOP + YardFill.LIFT + 0.03
	var door: Dictionary = h.get("door", {})
	if not door.is_empty() and int(door.wing) < (h.wings as Array).size():
		var wr: Rect2 = h.wings[door.wing].r
		var du: float = door.u
		var wv := wr.position.y
		var side := 1.0 if du + 1.1 < wr.end.x else -1.0
		# The porch lantern beside the door, its scallop on the wall, its pool on the step.
		var lu := du + side * 0.95
		_lantern(b, Vector2(lu, wv), 1.95, porch, lamp_tint, 0)
		var lp := b.W(lu, 1.95, wv - 0.2)
		if porch:
			_glow(ch, 2, b.W(lu, 1.35, wv - 0.04), b.N(Vector2(1, 0)) * 2.6, Vector3(0, 3.0, 0), glow_tint, 0.85)
			_pool_at(ch, Vector3(lp.x, b.g - HouseKit.FLOOR_LIFT + 0.04, lp.z) + b.N(Vector2(0, -1)) * 0.9, 2.6, glow_tint, 0.6)
			_halo(ch, lp + b.N(Vector2(0, -1)) * 0.12, 0.5, glow_tint, 1.0)
			HouseNightLights.add_spot(ch, lp + b.N(Vector2(0, -1)) * 0.5, glow_tint)
		# The house number on the other side of the door.
		_plaque(b, Vector2(du - side * 0.9, wv), 1.55, number_lit(k), lamp_tint, house_number(k))
	var gar: Dictionary = h.get("garage", {})
	if not gar.is_empty() and String(gar.get("kind", "")) != "carport" and int(gar.wing) < (h.wings as Array).size():
		var gv: float = (h.wings[gar.wing].r as Rect2).position.y
		var on := carriage_on(k)
		for gu: float in [float(gar.u0) - 0.32, float(gar.u1) + 0.32]:
			_lantern(b, Vector2(gu, gv), 2.25, on, lamp_tint, 0)
			if on:
				var gp := b.W(gu, 2.25, gv - 0.2)
				_glow(ch, 2, b.W(gu, 1.6, gv - 0.04), b.N(Vector2(1, 0)) * 2.0, Vector3(0, 2.8, 0), glow_tint, 0.7)
				_halo(ch, gp, 0.36, glow_tint, 0.8)
		if on:
			# The drive in front of the doors.
			var mid := b.W((float(gar.u0) + float(gar.u1)) * 0.5, 0.0, gv - 2.2)
			_pool_at(ch, Vector3(mid.x, ch._gy(mid.x, mid.z) + ground, mid.z), maxf(2.6, (float(gar.u1) - float(gar.u0)) * 0.6), glow_tint, 0.3)
	if nice(k):
		_landscape(b, k, ground)
		# Uplights at the foot of its cypresses: two crossed cones up each tree.
		var at: Array = ch.get_meta("la_cypress_at", [])
		if cyp0 >= 0:
			for i in range(cyp0, at.size()):
				var p: Vector3 = at[i]
				var gy := ch._gy(p.x, p.z) + p.y
				for ax: Vector3 in [Vector3(1.6, 0, 0), Vector3(0, 0, 1.6)]:
					_glow(ch, 1, Vector3(p.x, gy + 3.2, p.z), ax, Vector3(0, 6.4, 0), UPLIGHT_GLOW, 0.5)
				_halo(ch, Vector3(p.x, gy + 0.15, p.z), 0.12, UPLIGHT_GLOW, 0.6)


## A small wall lantern: a box of frosted lens under a dark cap, on the wall at frame point `p`
## (the wall's foot line), `y` over the floor.
static func _lantern(b: HouseBuild, p: Vector2, y: float, on: bool, tint: Color, kind: int) -> void:
	var cl := Color(tint.r, tint.g, tint.b, float(kind) * 0.25 + (0.125 if on else 0.0))
	var c := p + Vector2(0, -0.13)
	b._box("h_lamp", c, y + 0.17, y + 0.23, Vector2(1, 0), Vector2(0, 1), Vector2(0.11, 0.11), HOUSING)
	b._box("h_lamp", c, y - 0.22, y - 0.17, Vector2(1, 0), Vector2(0, 1), Vector2(0.09, 0.09), HOUSING)
	_lens_box(b, c, y - 0.17, y + 0.17, Vector2(0.08, 0.08), cl)


## A lens: the four sides and the top of a box, UV 0..1 on each face.
static func _lens_box(b: HouseBuild, c: Vector2, y0: float, y1: float, hs: Vector2, cl: Color) -> void:
	var t := Vector2(1, 0)
	var n := Vector2(0, 1)
	var ht := t * hs.x
	var hn := n * hs.y
	var q := [c - ht - hn, c + ht - hn, c + ht + hn, c - ht + hn]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in 4:
		var a2: Vector2 = q[i]
		var b2: Vector2 = q[(i + 1) % 4]
		var out := ((a2 + b2) * 0.5 - c).normalized()
		b._quad("h_lamp", b.L(a2, y0), b.L(b2, y0), b.L(b2, y1), b.L(a2, y1), b.N(out), cl, uv)


## The house number: a backlit plaque on the wall, three seven-segment digits.
static func _plaque(b: HouseBuild, p: Vector2, y: float, on: bool, tint: Color, num: int) -> void:
	var cl := Color(tint.r, tint.g, tint.b, 0.25 + (0.125 if on else 0.0))
	var a := p + Vector2(-0.2, -0.035)
	var e := p + Vector2(0.2, -0.035)
	var n0 := float(num)
	b._quad("h_lamp", b.L(a, y - 0.09), b.L(e, y - 0.09), b.L(e, y + 0.09), b.L(a, y + 0.09), b.N(Vector2(0, -1)), cl,
		[Vector2(n0, 1), Vector2(n0 + 0.999, 1), Vector2(n0 + 0.999, 0), Vector2(n0, 0)])
	b._box("h_lamp", p + Vector2(0, -0.015), y - 0.11, y + 0.11, Vector2(1, 0), Vector2(0, 1), Vector2(0.22, 0.015), HOUSING)


## Path lights down the front walk and uplights grazing the house front (the nicer houses).
static func _landscape(b: HouseBuild, k: int, ground: float) -> void:
	var h := b.h
	var ch := b.ch
	var tint := tone(k)
	var du: float = h.door_u
	var dv: float = h.door_v
	var drive: Vector2 = h.drive
	var walk_clear := drive.y <= drive.x or du < drive.x - 2.0 or du > drive.y + 2.0
	if walk_clear and dv > 3.0:
		var n := clampi(int((dv - 1.2) / 2.4), 1, 5)
		for i in n:
			var v := lerpf(1.0, dv - 0.9, (float(i) + 0.5) / float(n))
			var u := du + (0.95 if i % 2 == 0 else -0.95)
			var gy := ch._gy(b.P(u, v).x, b.P(u, v).y) + ground
			var floor_y := gy - b.g
			# A short dark post with a lens under its cap.
			b._box("h_lamp", Vector2(u, v), floor_y, floor_y + 0.38, Vector2(1, 0), Vector2(0, 1), Vector2(0.03, 0.03), HOUSING)
			b._box("h_lamp", Vector2(u, v), floor_y + 0.5, floor_y + 0.54, Vector2(1, 0), Vector2(0, 1), Vector2(0.09, 0.09), HOUSING)
			_lens_box(b, Vector2(u, v), floor_y + 0.38, floor_y + 0.5, Vector2(0.05, 0.05), Color(tint.r, tint.g, tint.b, 0.5 + 0.125))
			var wp := b.W(u, floor_y, v)
			_pool_at(ch, Vector3(wp.x, gy, wp.z), 1.2, UPLIGHT_GLOW, 0.5)
			_halo(ch, wp + Vector3(0, 0.45, 0), 0.16, UPLIGHT_GLOW, 0.7)
	# Uplights along the main wing's front, between its windows' bays.
	var mw: Dictionary = {}
	for w: Dictionary in h.wings:
		if String(w.role) == "main":
			mw = w
			break
	if mw.is_empty():
		return
	var r: Rect2 = mw.r
	var count := clampi(int(r.size.x / 4.0), 2, 4)
	var top := float(mw.storeys) * HouseKit.STOREY
	for i in count:
		var u := lerpf(r.position.x + 0.6, r.end.x - 0.6, float(i) / float(count - 1))
		if absf(u - du) < 1.2:
			continue
		var foot := b.W(u, 0.0, r.position.y - 0.05)
		var gy := ch._gy(foot.x, foot.z) + ground
		var hgt := minf(top + 0.6, 5.5)
		_glow(ch, 1, Vector3(foot.x, gy + hgt * 0.5, foot.z), b.N(Vector2(1, 0)) * 2.2, Vector3(0, hgt, 0), UPLIGHT_GLOW, 0.6)
		_halo(ch, Vector3(foot.x, gy + 0.12, foot.z) + b.N(Vector2(0, -1)) * 0.35, 0.12, UPLIGHT_GLOW, 0.6)


## The glow batches' draw distances and shadows (the chunk's finish).
static func finish(ch: CityChunk) -> void:
	if not enabled:
		return
	for key_s: String in GLOW_KEYS:
		ch._batch.set_no_shadow(key_s)
		ch._batch.set_draw_distance(key_s, HALO_DISTANCE if key_s == "hn_halo" else GLOW_DISTANCE)


## A pool's light: the turquoise glow over its water and coping (YardFill, FULL chunks).
static func pool_glow(ch: CityChunk, r: Rect2) -> void:
	if not enabled or not pool_on(pool_key(r)):
		return
	var c := r.get_center()
	var y := ch._gy(c.x, c.y) + CityChunk.SIDEWALK_TOP + YardFill.LIFT + 0.06
	_glow(ch, 0, Vector3(c.x, y, c.y), Vector3(r.size.x + 2.6, 0, 0), Vector3(0, 0, -(r.size.y + 2.6)), POOL_GLOW, 0.55)
	_halo(ch, Vector3(c.x, y + 0.05, c.y), maxf(r.size.x, r.size.y) * 0.5, POOL_GLOW, 0.3)
