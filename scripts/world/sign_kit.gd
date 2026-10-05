class_name SignKit
extends RefCounted
## The meshes of the boulevard signs (BoulevardSigns places them): tall pole signs - a strip-mall
## tenant pylon, five Googie motel signs (a slanted board with the name, a starburst, a VACANCY box
## with neon letters, hanging plates and a bent arrow ringed with chasing bulbs), a liquor /
## check-cashing cabinet sign and a tyre shop's with a giant tyre on top - and the small pieces: a
## street plate, its post, a lamp-post banner and its brackets, a window vinyl, a banner for a sign
## band, a wayfinding sign. All built in code at real size, on ONE material
## (shaders/boulevard_sign.gdshader), cached per kind.
##
## Every vertex: COLOR.rgb the colour (sRGB) or, on fabric, (sway weight, phase, -), COLOR.a the
## part code (A_*), UV 0..1 over a printed face plus 2 x its SLOT in UV.x (see the shader's
## sg_cell()), or metres on solid parts; UV2 = (roughness, metallic).
##
## Pole sign frame: origin at the foot of the pole on the pavement, +y up, the sign's plane the XY
## plane (both faces printed, facing +-z: along the street), +x into the lot away from the street.

const A_FIXED := 0.0
const A_STEEL := 0.1
const A_FACE := 0.2
const A_NEON := 0.3
const A_NEON_NO := 0.35
const A_BULB := 0.4
const A_PRINT := 0.5
const A_VINYL := 0.6
const A_FABRIC := 0.7
const A_LAMP := 0.8

## Slots (the shader's sg_cell()): which atlas family a printed face reads and with which index.
const SLOT_TENANT_HEAD := 1
const SLOT_TENANT := 2          # 2..7: the k-th tenant panel down the stack
const SLOT_NAME := 8
const SLOT_PLATE_B := 9
const SLOT_PLATE_B1 := 10
const SLOT_VINYL := 11
const SLOT_BANNER := 12
const SLOT_LAMPB := 13
const SLOT_PLATE := 14
const SLOT_BANNER_B := 15

const BRONZE := Color(0.16, 0.13, 0.11)
const GALV := Color(0.62, 0.63, 0.62)
const DARK := Color(0.08, 0.08, 0.085)
const CREAM := Color(0.86, 0.82, 0.72)

## Tenant pylon: cabinet width and height of a tenant panel, the header, the top of the stack.
const TENANT_W := 2.9
const TENANT_PANEL := 0.72
const TENANT_HEAD := 1.05
const TENANT_PANELS := 5
const TENANT_TOP := 8.6
const TENANT_CX := 0.95
const CAB_DEPTH := 0.42

## Motel sign: the board's size and centre, the top of the pole.
const MOTEL_POLE_TOP := 12.4
const MOTEL_BOARD := Vector2(4.2, 2.1)
const MOTEL_BOARD_C := Vector2(1.25, 9.9)
## [trim, pole, starburst neon, arrow, VACANCY neon, bulbs] per motel (the art's MOTELS order).
const MOTEL_PAINT := [
	[Color(0.95, 0.83, 0.25), Color(0.08, 0.25, 0.43), Color(1.0, 0.31, 0.48), Color(1.0, 0.31, 0.48), Color(1.0, 0.18, 0.2), Color(1.0, 0.86, 0.6)],
	[Color(1.0, 0.62, 0.18), Color(0.06, 0.36, 0.29), Color(1.0, 0.95, 0.75), Color(1.0, 0.62, 0.18), Color(0.2, 0.9, 0.45), Color(1.0, 0.9, 0.65)],
	[Color(0.10, 0.56, 0.54), Color(0.95, 0.9, 0.79), Color(0.2, 0.95, 0.9), Color(0.77, 0.15, 0.18), Color(1.0, 0.22, 0.3), Color(1.0, 0.88, 0.62)],
	[Color(1.0, 0.89, 0.30), Color(0.11, 0.17, 0.33), Color(0.5, 0.83, 1.0), Color(1.0, 0.89, 0.30), Color(1.0, 0.25, 0.3), Color(0.9, 0.95, 1.0)],
	[Color(1.0, 0.84, 0.29), Color(0.71, 0.16, 0.12), Color(1.0, 0.84, 0.29), Color(1.0, 0.96, 0.88), Color(1.0, 0.2, 0.25), Color(1.0, 0.86, 0.6)],
]
const MOTELS := 5

## Box sign (liquor, check cashing, tyres): the cabinet and the pole.
const BOX_W := 3.0
const BOX_H := 1.5
const BOX_BOTTOM := 5.4
const BOX_CX := 1.0

## Plates: 12 x 18 in.
const PLATE := Vector2(0.305, 0.457)
const POST_H := 3.0
## Lamp-post banners: size, bottom, the arms' reach from the pole's axis.
const LAMPB := Vector2(0.46, 1.25)
const LAMPB_BOTTOM := 2.3
const LAMPB_ARM := 0.62

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
static var _text_cache: Dictionary = {}


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/boulevard_sign.gdshader")
		_material.set_shader_parameter("atlas", load("res://assets/textures/boulevard_signs/sign_atlas.png"))
	return _material


# --- Pole signs ----------------------------------------------------------------------------------

## The strip-mall pylon: two posts on stucco bases, the plaza's header panel under an arched
## cap, five tenant lightboxes in bronze retainers.
static func tenant_pylon() -> Mesh:
	var key := "tenant"
	if _meshes.has(key):
		return _meshes[key]
	var st := _begin()
	var cx := TENANT_CX
	var hw := TENANT_W * 0.5
	var rm_paint := Vector2(0.45, 0.6)
	var stucco := Color(0.82, 0.74, 0.62)
	var post_x := [cx - hw + 0.18, cx + hw - 0.18]
	var bottom := TENANT_TOP - TENANT_HEAD - TENANT_PANELS * (TENANT_PANEL + 0.06) - 0.12
	for px: float in post_x:
		_box(st, Vector3(px, bottom * 0.5, 0.0), Vector3(0.26, bottom, 0.26), BRONZE, A_STEEL, rm_paint)
		# Stucco base round each post.
		_box(st, Vector3(px, 0.6, 0.0), Vector3(0.62, 1.2, 0.62), stucco, A_FIXED, Vector2(0.9, 0.0))
		_box(st, Vector3(px, 1.24, 0.0), Vector3(0.7, 0.08, 0.7), CREAM, A_FIXED, Vector2(0.8, 0.0))
	# The cabinet: one bronze box behind every panel, the faces proud of it on both sides.
	var y := TENANT_TOP
	# Arched cap over the header.
	_arch(st, Vector3(cx, y, 0.0), hw + 0.1, 0.42, CAB_DEPTH + 0.04, BRONZE, rm_paint)
	var head_c := y - TENANT_HEAD * 0.5
	_box(st, Vector3(cx, head_c, 0.0), Vector3(TENANT_W + 0.12, TENANT_HEAD + 0.08, CAB_DEPTH), BRONZE, A_STEEL, rm_paint)
	_faces(st, Vector3(cx, head_c, 0.0), Vector2(TENANT_W - 0.1, TENANT_HEAD - 0.12), CAB_DEPTH * 0.5 + 0.004, SLOT_TENANT_HEAD)
	y -= TENANT_HEAD + 0.06
	for k in TENANT_PANELS:
		var c := y - TENANT_PANEL * 0.5
		_box(st, Vector3(cx, c, 0.0), Vector3(TENANT_W + 0.06, TENANT_PANEL + 0.04, CAB_DEPTH - 0.04), BRONZE, A_STEEL, rm_paint)
		_faces(st, Vector3(cx, c, 0.0), Vector2(TENANT_W - 0.08, TENANT_PANEL - 0.08), (CAB_DEPTH - 0.04) * 0.5 + 0.004, SLOT_TENANT + k)
		y -= TENANT_PANEL + 0.06
	# A skirt under the last panel and a kicker between the posts.
	_box(st, Vector3(cx, y + 0.0, 0.0), Vector3(TENANT_W + 0.12, 0.12, CAB_DEPTH + 0.02), BRONZE, A_STEEL, rm_paint)
	return _finish(st, key)


## A Googie motel sign (variant 0..4: its name, paints and plates).
static func motel(variant: int) -> Mesh:
	var key := "motel_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var paint: Array = MOTEL_PAINT[variant % MOTELS]
	var trim: Color = paint[0]
	var pole_c: Color = paint[1]
	var star_c: Color = paint[2]
	var arrow_c: Color = paint[3]
	var vac_c: Color = paint[4]
	var bulb_c: Color = paint[5]
	var st := _begin()
	var rm_paint := Vector2(0.4, 0.3)
	# The pole: a round pipe on a base plate.
	_cyl(st, Vector3.ZERO, 0.21, 0.19, MOTEL_POLE_TOP, pole_c, A_STEEL, rm_paint, 14)
	_box(st, Vector3(0.0, 0.03, 0.0), Vector3(0.7, 0.06, 0.7), GALV, A_STEEL, Vector2(0.6, 0.8))
	# The board: a parallelogram slanted forward (Googie), edged in the trim colour.
	var bc := MOTEL_BOARD_C
	var bw := MOTEL_BOARD.x
	var bh := MOTEL_BOARD.y
	var lean := 0.45
	var d := 0.5
	var tl := Vector2(bc.x - bw * 0.5 + lean, bc.y + bh * 0.5)
	var tr := Vector2(bc.x + bw * 0.5 + lean, bc.y + bh * 0.5)
	var br := Vector2(bc.x + bw * 0.5 - lean, bc.y - bh * 0.5)
	var bl := Vector2(bc.x - bw * 0.5 - lean, bc.y - bh * 0.5)
	_slab(st, [tl, tr, br, bl], d, trim, rm_paint)
	var inset := 0.12
	var ftl := tl + Vector2(inset * 1.2, -inset)
	var ftr := tr + Vector2(-inset * 0.8, -inset)
	var fbr := br + Vector2(-inset * 1.2, inset)
	var fbl := bl + Vector2(inset * 0.8, inset)
	_face_quad(st, ftl, ftr, fbr, fbl, d * 0.5 + 0.004, SLOT_NAME)
	# Bulbs along the board's top edge.
	var idx := 0
	var n_top := 16
	for k in n_top:
		var p := tl.lerp(tr, (float(k) + 0.5) / n_top) + Vector2(0.0, 0.06)
		for side: float in [1.0, -1.0]:
			_bulb(st, Vector3(p.x, p.y, side * (d * 0.5 + 0.02)), 0.055, bulb_c, idx)
		idx += 1
	# The starburst on top of the pole: spikes of neon round a ball.
	var sc := Vector3(0.0, MOTEL_POLE_TOP + 0.55, 0.0)
	_sphere(st, sc, 0.22, trim, A_FIXED, rm_paint, 10)
	for k in 12:
		var a := TAU * float(k) / 12.0 + 0.13
		var length := 0.95 if k % 2 == 0 else 0.6
		var tip := sc + Vector3(cos(a), sin(a), 0.0) * length
		_tube(st, [sc + Vector3(cos(a), sin(a), 0.0) * 0.2, tip], 0.035, 6, star_c, A_NEON, Vector2(0.2, 0.0))
		_sphere(st, tip, 0.07, star_c, A_NEON, Vector2(0.2, 0.0), 6)
	# The VACANCY box under the board: a black cabinet with neon letters on both faces.
	var vy := 8.05
	var vx := 1.45
	var vw := 2.7
	var vh := 0.62
	_box(st, Vector3(vx, vy, 0.0), Vector3(vw, vh, 0.32), DARK, A_FIXED, Vector2(0.5, 0.1))
	for side: float in [1.0, -1.0]:
		var n := Vector3(0.0, 0.0, side)
		var face_z := side * 0.165
		var b := Basis(Vector3(side, 0.0, 0.0), Vector3.UP, n)
		_text(st, "VACANCY", 0.36, Transform3D(b, Vector3(vx + 0.35 * side, vy, face_z + side * 0.006)), vac_c, A_NEON, 1.7)
		_text(st, "NO", 0.36, Transform3D(b, Vector3(vx - 0.95 * side, vy, face_z + side * 0.006)), vac_c, A_NEON_NO, 0.6)
	# Chains and two plates hanging under the VACANCY box (slots B and B + 1).
	for k in 2:
		var px := vx - 0.6 + 1.2 * k
		for cx_off: float in [-0.12, 0.12]:
			_tube(st, [Vector3(px + cx_off, vy - vh * 0.5, 0.0), Vector3(px + cx_off, 7.3, 0.0)], 0.008, 4, GALV, A_FIXED, Vector2(0.4, 0.9))
		var pc := Vector3(px, 7.0, 0.0)
		_box(st, pc, Vector3(0.62, 0.66, 0.05), Color(0.9, 0.9, 0.9), A_FIXED, Vector2(0.4, 0.6))
		_faces(st, pc, Vector2(0.56, 0.6), 0.027, SLOT_PLATE_B + k, A_PRINT)
	# The arrow: a flat bar bent down the far side of the board to point at the drive, its edges
	# ringed with bulbs that chase toward the head.
	var path := [Vector2(4.05, 10.6), Vector2(4.35, 9.2), Vector2(4.25, 7.6), Vector2(3.75, 6.3), Vector2(3.0, 5.35), Vector2(2.2, 4.85)]
	var aw := 0.5
	var ad := 0.26
	var rmp := Vector2(0.45, 0.2)
	var spine: Array = []
	for i in path.size():
		var p: Vector2 = path[i]
		var t := ((path[mini(i + 1, path.size() - 1)] as Vector2) - (path[maxi(i - 1, 0)] as Vector2)).normalized()
		spine.append([p, Vector2(-t.y, t.x)])
	for i in path.size() - 1:
		var p0: Vector2 = spine[i][0]
		var n0: Vector2 = spine[i][1]
		var p1: Vector2 = spine[i + 1][0]
		var n1: Vector2 = spine[i + 1][1]
		_slab(st, [p0 + n0 * aw * 0.5, p1 + n1 * aw * 0.5, p1 - n1 * aw * 0.5, p0 - n0 * aw * 0.5], ad, arrow_c, rmp)
	# The head.
	var hp: Vector2 = path[path.size() - 1]
	var ht: Vector2 = (hp - (path[path.size() - 2] as Vector2)).normalized()
	var hn := Vector2(-ht.y, ht.x)
	_slab(st, [hp + hn * aw * 1.25, hp + ht * 0.95, hp - hn * aw * 1.25], ad, arrow_c, rmp)
	# Bulbs along both edges of the bar, numbered from the tail so the chase runs to the head.
	var edge_pts: Array = []
	var total := 0.0
	for i in path.size() - 1:
		total += (path[i + 1] as Vector2).distance_to(path[i])
	var count := int(total / 0.3)
	for k in count:
		var s := (float(k) + 0.5) / count * total
		var acc := 0.0
		for i in path.size() - 1:
			var seg := (path[i + 1] as Vector2).distance_to(path[i])
			if acc + seg >= s:
				var f := (s - acc) / seg
				var p := (path[i] as Vector2).lerp(path[i + 1], f)
				var nn := ((spine[i][1] as Vector2).lerp(spine[i + 1][1], f)).normalized()
				edge_pts.append([p, nn])
				break
			acc += seg
	for k in edge_pts.size():
		var p: Vector2 = edge_pts[k][0]
		var nn: Vector2 = edge_pts[k][1]
		for e: float in [1.0, -1.0]:
			var q := p + nn * e * aw * 0.32
			for side: float in [1.0, -1.0]:
				_bulb(st, Vector3(q.x, q.y, side * (ad * 0.5 + 0.02)), 0.05, bulb_c, idx + k)
	# Bulbs round the head.
	var head_pts := [hp + hn * aw * 1.0, hp + ht * 0.7, hp - hn * aw * 1.0]
	for k in 2:
		for j in 3:
			var q := (head_pts[k] as Vector2).lerp(head_pts[k + 1], (float(j) + 0.5) / 3.0)
			for side: float in [1.0, -1.0]:
				_bulb(st, Vector3(q.x, q.y, side * (ad * 0.5 + 0.02)), 0.05, bulb_c, idx + count + k * 3 + j)
	# Brackets: the arrow's tail to the board, and a strut from the pole to its elbow.
	_tube(st, [Vector3(3.6, 8.9, 0.0), Vector3(4.2, 8.9, 0.0)], 0.04, 6, pole_c, A_STEEL, rm_paint)
	_tube(st, [Vector3(0.15, 6.4, 0.0), Vector3(3.8, 6.4, 0.0)], 0.05, 6, pole_c, A_STEEL, rm_paint)
	_tube(st, [Vector3(0.15, 8.4, 0.0), Vector3(1.0, 8.4, 0.0)], 0.05, 6, pole_c, A_STEEL, rm_paint)
	return _finish(st, key)


## A cabinet sign on one square pole (liquor, check cashing); `tire` puts a giant tyre on top.
static func box_sign(tire: bool) -> Mesh:
	var key := "box_tire" if tire else "box"
	if _meshes.has(key):
		return _meshes[key]
	var st := _begin()
	var rm_paint := Vector2(0.5, 0.5)
	var top := BOX_BOTTOM + BOX_H
	var pole_h := top + (0.15 if not tire else 0.4)
	_box(st, Vector3(0.0, pole_h * 0.5, 0.0), Vector3(0.3, pole_h, 0.3), DARK if not tire else Color(0.55, 0.12, 0.1), A_STEEL, rm_paint)
	_box(st, Vector3(0.0, 0.3, 0.0), Vector3(0.55, 0.6, 0.55), Color(0.62, 0.6, 0.56), A_FIXED, Vector2(0.9, 0.0))
	var c := Vector3(BOX_CX, BOX_BOTTOM + BOX_H * 0.5, 0.0)
	# A cabinet with rounded ends (two half-cylinders) and a retainer.
	_box(st, c, Vector3(BOX_W, BOX_H, CAB_DEPTH), Color(0.85, 0.85, 0.84), A_STEEL, Vector2(0.4, 0.7))
	for e: float in [-1.0, 1.0]:
		_cylz(st, c + Vector3(e * BOX_W * 0.5, 0.0, 0.0), BOX_H * 0.5, CAB_DEPTH, e, Color(0.85, 0.85, 0.84), Vector2(0.4, 0.7))
	_faces(st, c, Vector2(BOX_W - 0.06, BOX_H - 0.08), CAB_DEPTH * 0.5 + 0.004, SLOT_NAME)
	# The arm from the pole to the cabinet.
	_box(st, Vector3(BOX_CX * 0.5 - 0.3, top + 0.08, 0.0), Vector3(BOX_CX + 0.2, 0.12, 0.12), DARK, A_STEEL, rm_paint)
	if tire:
		# A giant tyre standing on edge on the pole's cap: a torus with blocks of tread.
		var tc := Vector3(0.6, top + 1.25, 0.0)
		_torus(st, tc, 0.95, 0.32, 24, 10, Color(0.05, 0.05, 0.055), Vector2(0.85, 0.0))
		for k in 24:
			var a := TAU * (float(k) + 0.5) / 24.0
			var o := tc + Vector3(cos(a), sin(a), 0.0) * 1.27
			var b := Basis(Vector3.BACK, a)
			_xbox(st, Transform3D(b, o), Vector3(0.06, 0.12, 0.5), Color(0.05, 0.05, 0.055), A_FIXED, Vector2(0.9, 0.0))
		# The rim: a disc of chrome on both sides.
		for side: float in [-1.0, 1.0]:
			_disc(st, tc + Vector3(0.0, 0.0, side * 0.18), 0.62, Vector3(0.0, 0.0, side), Color(0.75, 0.76, 0.78), Vector2(0.25, 1.0), 18)
		_box(st, Vector3(0.6, top + 0.17, 0.0), Vector3(0.5, 0.18, 0.4), DARK, A_STEEL, rm_paint)
	else:
		# Two gooseneck lamps over the cabinet, lit at night.
		for e: float in [-0.8, 0.8]:
			var base := Vector3(BOX_CX + e, top + 0.02, 0.0)
			for side: float in [1.0, -1.0]:
				_tube(st, [base, base + Vector3(0.0, 0.35, 0.0), base + Vector3(0.0, 0.45, side * 0.35)], 0.02, 5, DARK, A_STEEL, rm_paint)
				_sphere(st, base + Vector3(0.0, 0.42, side * 0.4), 0.07, Color(1.0, 0.92, 0.75), A_LAMP, Vector2(0.3, 0.0), 6)
	return _finish(st, key)


# --- Small pieces --------------------------------------------------------------------------------

## A street plate on its own: 12 x 18 in of sheeting on an aluminium blank, two bolts, its slot
## PLATE A. Origin at the plate's centre, facing +z, back to -z (the post's side).
static func plate() -> Mesh:
	if _meshes.has("plate"):
		return _meshes["plate"]
	var st := _begin()
	_box(st, Vector3(0.0, 0.0, -0.002), Vector3(PLATE.x, PLATE.y, 0.004), Color(0.7, 0.71, 0.72), A_FIXED, Vector2(0.4, 0.9))
	_face(st, Vector3(0.0, 0.0, 0.0005), Vector2(PLATE.x - 0.004, PLATE.y - 0.004), 1.0, SLOT_PLATE, A_PRINT)
	for y: float in [-PLATE.y * 0.42, PLATE.y * 0.42]:
		_cylz(st, Vector3(0.0, y, 0.004), 0.012, 0.008, 0.0, GALV, Vector2(0.4, 0.9))
	return _finish(st, "plate")


## A sign post: a 2 in square galvanised tube with a cap, origin at its foot.
static func post() -> Mesh:
	if _meshes.has("post"):
		return _meshes["post"]
	var st := _begin()
	_box(st, Vector3(0.0, POST_H * 0.5, 0.0), Vector3(0.05, POST_H, 0.05), GALV, A_STEEL, Vector2(0.45, 0.8))
	_box(st, Vector3(0.0, POST_H + 0.01, 0.0), Vector3(0.06, 0.02, 0.06), GALV, A_STEEL, Vector2(0.45, 0.8))
	return _finish(st, "post")


## A lamp-post banner: fabric hung between two arms, its pole edge at x 0, the free edge at
## +x, facing +-z, both faces printed (LAMPB A). Origin at the bottom of the pole edge.
static func lamp_banner() -> Mesh:
	if _meshes.has("lampb"):
		return _meshes["lampb"]
	var st := _begin()
	var cols := 3
	var rows := 6
	for side: float in [1.0, -1.0]:
		var n := Vector3(0.0, 0.0, side)
		for i in cols:
			for j in rows:
				var u0 := float(i) / cols
				var u1 := float(i + 1) / cols
				var v0 := float(j) / rows
				var v1 := float(j + 1) / rows
				var pts: Array = []
				for uv: Vector2 in [Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]:
					# The sway weight: nothing at the pole edge or the arms, most mid-way out and down.
					var w := uv.x * (0.35 + 0.65 * sin(uv.y * PI))
					var pos := Vector3(uv.x * LAMPB.x, uv.y * LAMPB.y, side * 0.002)
					# Printed so it reads from either side: the back's u runs the other way.
					var tex := Vector2((uv.x if side > 0.0 else 1.0 - uv.x) + 2.0 * SLOT_LAMPB, 1.0 - uv.y)
					pts.append([pos, tex, Color(w, 0.5 + side * 0.1, 0.0, A_FABRIC)])
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					var a: Array = pts[tri[0]]
					var b: Array = pts[tri[1]]
					var c: Array = pts[tri[2]]
					var order := [a, b, c]
					if ((c[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3)).dot(n) < 0.0:
						order = [a, c, b]
					for v: Array in order:
						_vtx(st, v[0], n, v[1], v[2], Vector2(0.8, 0.0))
	return _finish(st, "lampb")


## The brackets of a pair of lamp-post banners: a clamp ring and two arms each side, the arms
## along +-x, origin on the pole's axis at the bottom arm. `r` the pole's radius there.
static func lamp_banner_arms() -> Mesh:
	if _meshes.has("lampb_arms"):
		return _meshes["lampb_arms"]
	var st := _begin()
	var c := Color(0.12, 0.12, 0.13)
	var rm := Vector2(0.45, 0.7)
	for y: float in [0.0, LAMPB.y]:
		_cyl(st, Vector3(0.0, y - 0.04, 0.0), 0.075, 0.075, 0.08, c, A_FIXED, rm, 10)
		for side: float in [-1.0, 1.0]:
			_tube(st, [Vector3(side * 0.07, y, 0.0), Vector3(side * LAMPB_ARM, y, 0.0)], 0.014, 6, c, A_FIXED, rm)
			_sphere(st, Vector3(side * LAMPB_ARM, y, 0.0), 0.025, c, A_FIXED, rm, 6)
	return _finish(st, "lampb_arms")


## Window vinyl: a unit square on the glass (scale it), facing +z, VINYL A, cut out by the atlas.
static func vinyl() -> Mesh:
	if _meshes.has("vinyl"):
		return _meshes["vinyl"]
	var st := _begin()
	_face(st, Vector3.ZERO, Vector2.ONE, 1.0, SLOT_VINYL, A_VINYL)
	return _finish(st, "vinyl")


## A vinyl banner over a sign band: 4 : 1, sagging a little between its corner ties, facing +z
## (BANNER A). Unit height (scale it uniformly), origin at its centre.
static func band_banner() -> Mesh:
	if _meshes.has("banner"):
		return _meshes["banner"]
	var st := _begin()
	var cols := 8
	var rows := 2
	var w := 4.0
	var n := Vector3(0.0, 0.0, 1.0)
	for i in cols:
		for j in rows:
			var pts: Array = []
			for uv: Vector2 in [Vector2(float(i) / cols, float(j + 1) / rows), Vector2(float(i + 1) / cols, float(j + 1) / rows),
					Vector2(float(i + 1) / cols, float(j) / rows), Vector2(float(i) / cols, float(j) / rows)]:
				var bow := sin(uv.x * PI) * 0.05
				var pos := Vector3((uv.x - 0.5) * w, (uv.y - 0.5), bow - sin(uv.y * PI) * 0.02)
				var wgt := sin(uv.x * PI) * 0.25 * (1.0 - uv.y * 0.5)
				pts.append([pos, Vector2(uv.x + 2.0 * SLOT_BANNER, 1.0 - uv.y), Color(wgt, 0.2, 0.0, A_FABRIC)])
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				var a: Array = pts[tri[0]]
				var b: Array = pts[tri[1]]
				var c: Array = pts[tri[2]]
				var order := [a, b, c]
				if ((c[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3)).dot(n) < 0.0:
					order = [a, c, b]
				for v: Array in order:
					_vtx(st, v[0], n, v[1], v[2], Vector2(0.75, 0.0))
	# Ties at the corners, back to the wall.
	for x: float in [-w * 0.5 + 0.05, w * 0.5 - 0.05]:
		for y: float in [-0.4, 0.4]:
			_tube(st, [Vector3(x, y, -0.005), Vector3(x + signf(x) * 0.08, y, -0.12)], 0.006, 4, CREAM, A_FIXED, Vector2(0.9, 0.0))
	return _finish(st, "banner")


## A wayfinding sign: a round post and a 4 : 1 panel printed both faces (BANNER B), at 2.6 m.
static func wayfinding() -> Mesh:
	if _meshes.has("wayfind"):
		return _meshes["wayfind"]
	var st := _begin()
	var c := Color(0.15, 0.17, 0.16)
	var rm := Vector2(0.45, 0.6)
	_cyl(st, Vector3.ZERO, 0.055, 0.05, 3.55, c, A_STEEL, rm, 10)
	_sphere(st, Vector3(0.0, 3.57, 0.0), 0.06, c, A_FIXED, rm, 8)
	var pc := Vector3(0.0, 3.05, 0.0)
	_box(st, pc, Vector3(1.86, 0.5, 0.05), c, A_STEEL, rm)
	_faces(st, pc, Vector2(1.8, 0.45), 0.026, SLOT_BANNER_B, A_PRINT)
	return _finish(st, "wayfind")


# --- Geometry helpers ----------------------------------------------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


static func _vtx(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color, rm: Vector2) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(uv)
	st.set_uv2(rm)
	st.add_vertex(p)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3, col: Color, rm: Vector2) -> void:
	var cr := (c - a).cross(b - a)
	if cr.length_squared() < 1e-14:
		return
	if cr.dot(want) < 0.0:
		var t := b
		b = c
		c = t
		cr = -cr
	var n := cr.normalized()
	for p: Vector3 in [a, b, c]:
		_vtx(st, p, n, StreetClutter._proj(p, n), col, rm)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color, rm: Vector2) -> void:
	_tri(st, a, b, c, want, col, rm)
	_tri(st, a, c, d, want, col, rm)


## A box (flat-shaded, 12 triangles) of colour `col` and part code `code`.
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, code: float, rm: Vector2) -> void:
	_xbox(st, Transform3D(Basis(), c), size, col, code, rm)


static func _xbox(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color, code: float, rm: Vector2) -> void:
	var h := size * 0.5
	var cc := Color(col.r, col.g, col.b, code)
	for k in 3:
		var j := (k + 1) % 3
		var l := (k + 2) % 3
		for sg: float in [-1.0, 1.0]:
			var pts: Array = []
			for pair: Array in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				var v := Vector3.ZERO
				v[k] = sg * h[k]
				v[j] = float(pair[0]) * h[j]
				v[l] = float(pair[1]) * h[l]
				pts.append(xf * v)
			var nrm := Vector3.ZERO
			nrm[k] = sg
			_quad(st, pts[0], pts[1], pts[2], pts[3], (xf.basis * nrm).normalized(), cc, rm)


## A printed face, centred at `c` in the XY plane at z = `z` (facing +z when z > 0, -z when < 0),
## UV 0..1 over it plus its slot. `code` A_FACE (lit) or A_PRINT / A_VINYL.
static func _face(st: SurfaceTool, c: Vector3, size: Vector2, facing: float, slot: int, code: float) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var n := Vector3(0.0, 0.0, signf(facing))
	var col := Color(1.0, 1.0, 1.0, code)
	var x0 := -hx if facing > 0.0 else hx
	var x1 := hx if facing > 0.0 else -hx
	var tl := c + Vector3(x0, hy, 0.0)
	var tr := c + Vector3(x1, hy, 0.0)
	var br := c + Vector3(x1, -hy, 0.0)
	var bl := c + Vector3(x0, -hy, 0.0)
	var off := 2.0 * slot
	var pts := [[tl, Vector2(off, 0.0)], [tr, Vector2(off + 1.0, 0.0)], [br, Vector2(off + 1.0, 1.0)], [bl, Vector2(off, 1.0)]]
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var a: Array = pts[tri[0]]
		var b: Array = pts[tri[1]]
		var d: Array = pts[tri[2]]
		var order := [a, b, d]
		if ((d[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3)).dot(n) < 0.0:
			order = [a, d, b]
		for v: Array in order:
			_vtx(st, v[0], n, v[1], col, Vector2(0.3, 0.0))


## Both faces of a cabinet: printed at z = +-half, each reading the right way round.
static func _faces(st: SurfaceTool, c: Vector3, size: Vector2, half: float, slot: int, code: float = A_FACE) -> void:
	_face(st, c + Vector3(0.0, 0.0, half), size, 1.0, slot, code)
	_face(st, c + Vector3(0.0, 0.0, -half), size, -1.0, slot, code)


## A printed quad with given corners (x, y; top-left, top-right, bottom-right, bottom-left as seen
## from +z) on both faces at z = +-half.
static func _face_quad(st: SurfaceTool, tl: Vector2, tr: Vector2, br: Vector2, bl: Vector2, half: float, slot: int) -> void:
	var off := 2.0 * slot
	var col := Color(1.0, 1.0, 1.0, A_FACE)
	for side: float in [1.0, -1.0]:
		var n := Vector3(0.0, 0.0, side)
		var z := side * half
		var corners := [tl, tr, br, bl] if side > 0.0 else [tr, tl, bl, br]
		var pts: Array = []
		var uvs := [Vector2(off, 0.0), Vector2(off + 1.0, 0.0), Vector2(off + 1.0, 1.0), Vector2(off, 1.0)]
		for k in 4:
			var q: Vector2 = corners[k]
			pts.append([Vector3(q.x, q.y, z), uvs[k]])
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			var a: Array = pts[tri[0]]
			var b: Array = pts[tri[1]]
			var d: Array = pts[tri[2]]
			var order := [a, b, d]
			if ((d[0] as Vector3) - (a[0] as Vector3)).cross((b[0] as Vector3) - (a[0] as Vector3)).dot(n) < 0.0:
				order = [a, d, b]
			for v: Array in order:
				_vtx(st, v[0], n, v[1], col, Vector2(0.3, 0.0))


## An extruded convex polygon in the XY plane (corners in order), `depth` thick about z 0.
static func _slab(st: SurfaceTool, poly: Array, depth: float, col: Color, rm: Vector2) -> void:
	var cc := Color(col.r, col.g, col.b, A_FIXED)
	var hz := depth * 0.5
	var n := poly.size()
	var mid := Vector2.ZERO
	for p: Vector2 in poly:
		mid += p
	mid /= float(n)
	for side: float in [1.0, -1.0]:
		for k in range(1, n - 1):
			var a: Vector2 = poly[0]
			var b: Vector2 = poly[k]
			var c: Vector2 = poly[k + 1]
			_tri(st, Vector3(a.x, a.y, side * hz), Vector3(b.x, b.y, side * hz), Vector3(c.x, c.y, side * hz), Vector3(0.0, 0.0, side), cc, rm)
	for k in n:
		var a: Vector2 = poly[k]
		var b: Vector2 = poly[(k + 1) % n]
		var e := b - a
		var out := Vector2(e.y, -e.x).normalized()
		if out.dot((a + b) * 0.5 - mid) < 0.0:
			out = -out
		_quad(st, Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz), Vector3(b.x, b.y, -hz), Vector3(a.x, a.y, -hz), Vector3(out.x, out.y, 0.0), cc, rm)


## An arched cap: a half-ellipse slab over (c.x +- hw), `rise` tall, `depth` thick.
static func _arch(st: SurfaceTool, c: Vector3, hw: float, rise: float, depth: float, col: Color, rm: Vector2) -> void:
	var poly: Array = []
	var segs := 10
	for k in segs + 1:
		var a := PI * float(k) / segs
		poly.append(Vector2(c.x + cos(a) * hw, c.y + sin(a) * rise))
	_slab(st, poly, depth, col, rm)


## A vertical cylinder from `c` up `h`, radii r0 at the foot and r1 at the top.
static func _cyl(st: SurfaceTool, c: Vector3, r0: float, r1: float, h: float, col: Color, code: float, rm: Vector2, sides: int) -> void:
	StreetClutter._cyl(st, Transform3D(Basis(), c), r0, r1, h, Color(col.r, col.g, col.b, code), rm, sides)


## A cylinder along z centred at `c`, `depth` long; `half` -1 / 1 keeps only the half toward -x /
## +x (a cabinet's rounded end), 0 the whole round.
static func _cylz(st: SurfaceTool, c: Vector3, r: float, depth: float, half: float, col: Color, rm: Vector2) -> void:
	var cc := Color(col.r, col.g, col.b, A_FIXED)
	var sides := 12
	var a0 := -PI * 0.5 if half > 0.0 else (PI * 0.5 if half < 0.0 else 0.0)
	var span := PI if half != 0.0 else TAU
	var hz := depth * 0.5
	for k in sides:
		var t0 := a0 + span * float(k) / sides
		var t1 := a0 + span * float(k + 1) / sides
		var d0 := Vector3(cos(t0), sin(t0), 0.0)
		var d1 := Vector3(cos(t1), sin(t1), 0.0)
		StreetClutter._smooth_quad(st, c + d0 * r + Vector3(0, 0, hz), c + d1 * r + Vector3(0, 0, hz), c + d1 * r - Vector3(0, 0, hz), c + d0 * r - Vector3(0, 0, hz), d0, d1, d1, d0, cc, rm)
		for side: float in [1.0, -1.0]:
			_tri(st, c + Vector3(0, 0, side * hz), c + d0 * r + Vector3(0, 0, side * hz), c + d1 * r + Vector3(0, 0, side * hz), Vector3(0, 0, side), cc, rm)


static func _disc(st: SurfaceTool, c: Vector3, r: float, n: Vector3, col: Color, rm: Vector2, sides: int) -> void:
	var cc := Color(col.r, col.g, col.b, A_FIXED)
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	for k in sides:
		var t0 := TAU * float(k) / sides
		var t1 := TAU * float(k + 1) / sides
		_tri(st, c, c + (u * cos(t0) + v * sin(t0)) * r, c + (u * cos(t1) + v * sin(t1)) * r, n, cc, rm)


static func _torus(st: SurfaceTool, c: Vector3, big: float, small: float, seg: int, ring: int, col: Color, rm: Vector2) -> void:
	var cc := Color(col.r, col.g, col.b, A_FIXED)
	for i in seg:
		for j in ring:
			var pts: Array = []
			var ns: Array = []
			for ij: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
				var a := TAU * float(ij.x) / seg
				var b := TAU * float(ij.y) / ring
				var d := Vector3(cos(a), sin(a), 0.0)
				var nn := d * cos(b) + Vector3(0.0, 0.0, sin(b))
				pts.append(c + d * big + nn * small)
				ns.append(nn)
			StreetClutter._smooth_quad(st, pts[0], pts[1], pts[2], pts[3], ns[0], ns[1], ns[2], ns[3], cc, rm)


static func _tube(st: SurfaceTool, path: Array, r: float, sides: int, col: Color, code: float, rm: Vector2) -> void:
	StreetClutter._tube(st, path, r, sides, Color(col.r, col.g, col.b, code), rm)


static func _sphere(st: SurfaceTool, c: Vector3, r: float, col: Color, code: float, rm: Vector2, seg: int) -> void:
	StreetVendors._sphere(st, c, r, Color(col.r, col.g, col.b, code), rm, seg)


## A bulb in the chase: a small sphere whose UV.x is its place along the chase.
static func _bulb(st: SurfaceTool, c: Vector3, r: float, col: Color, index: int) -> void:
	var cc := Color(col.r, col.g, col.b, A_BULB)
	var seg := 6
	var rings := 3
	for i in rings:
		for j in seg:
			var corners: Array = []
			for ij: Vector2i in [Vector2i(i, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1), Vector2i(i + 1, j)]:
				var v := PI * float(ij.x) / rings
				var u := TAU * float(ij.y) / seg
				corners.append(Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u)))
			var want: Vector3 = (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
			var verts := [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]
			if ((corners[2] - corners[0]) as Vector3).cross(corners[1] - corners[0]).dot(want) < 0.0:
				verts = [corners[0], corners[2], corners[1], corners[0], corners[3], corners[2]]
			for d: Vector3 in verts:
				_vtx(st, c + d * r, d, Vector2(float(index), 0.0), cc, Vector2(0.2, 0.0))


## Lettering (TextMesh outlines) into the mesh at `xf` (centred, facing its +z), `height` tall,
## at most `max_w` wide, in colour `col` with part code `code`.
static func _text(st: SurfaceTool, txt: String, height: float, xf: Transform3D, col: Color, code: float, max_w: float) -> void:
	var key := "%s|%.3f" % [txt, height]
	var geo: Array
	if _text_cache.has(key):
		geo = _text_cache[key]
	else:
		var tm := TextMesh.new()
		tm.text = txt
		tm.font_size = 40
		tm.pixel_size = height / 40.0 * 1.4
		tm.depth = 0.0
		tm.curve_step = 3.0
		tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var arr := tm.get_mesh_arrays()
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
			verts = arr[Mesh.ARRAY_VERTEX]
			var ids = arr[Mesh.ARRAY_INDEX]
			if ids == null or (ids as PackedInt32Array).is_empty():
				for k in verts.size():
					idx.append(k)
			else:
				idx = ids
		var lo := INF
		var hi := -INF
		for v in verts:
			lo = minf(lo, v.x)
			hi = maxf(hi, v.x)
		geo = [verts, idx, maxf(hi - lo, 0.0)]
		_text_cache[key] = geo
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	var squeeze := minf(1.0, max_w / maxf(float(geo[2]), 0.001))
	var n := xf.basis.z.normalized()
	var cc := Color(col.r, col.g, col.b, code)
	for k in range(0, idx.size() - 2, 3):
		var a := xf * (verts[idx[k]] * Vector3(squeeze, 1.0, 0.0))
		var b := xf * (verts[idx[k + 1]] * Vector3(squeeze, 1.0, 0.0))
		var c := xf * (verts[idx[k + 2]] * Vector3(squeeze, 1.0, 0.0))
		_tri(st, a, b, c, n, cc, Vector2(0.15, 0.0))


## Builds every mesh once (the loading screen).
static func warm() -> void:
	tenant_pylon()
	for v in MOTELS:
		motel(v)
	box_sign(false)
	box_sign(true)
	plate()
	post()
	lamp_banner()
	lamp_banner_arms()
	vinyl()
	band_banner()
	wayfinding()
