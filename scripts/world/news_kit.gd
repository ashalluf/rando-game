class_name NewsKit
extends RefCounted
## The TV news crews' hardware, built in code at real size (NewsCrews, NewsVan, NewsCrew): the
## stations, the van's roof gear (a roof rack, a satellite uplink dish on a turntable or a
## telescoping microwave mast with its pan-tilt head and coiled cable), the shoulder camera, the
## reporter's hand microphone with its flag, an LED panel light on a tripod, the scene tape's
## posts and the tape itself.
##
## Every mesh is built once and shared (a van is ~8 nodes of gear, a crew 3 props). Colours ride
## in the vertex colour (sRGB, decoded by the material); parts that must catch the light like
## metal are a second surface on a metallic material. Frames: metres, -Z forward (the van's nose,
## the camera's lens), +Y up.

## The stations: invented names and colours, never a real broadcaster's. `uplink` is the van's
## roof gear: "dish" a satellite uplink, "mast" a microwave mast. `number` is the channel on the
## mic flag and the roof.
const STATIONS := [
	{"name": "BASIN 7", "tag": "NEWS", "number": "7", "color": Color(0.05, 0.19, 0.55), "uplink": "dish",
		"slogan": "ON YOUR SIDE OF THE BASIN"},
	{"name": "SUNCOAST 4", "tag": "NEWS", "number": "4", "color": Color(0.78, 0.17, 0.05), "uplink": "mast",
		"slogan": "LIVE  LOCAL  FIRST"},
	{"name": "PACIFICA 9", "tag": "NEWS", "number": "9", "color": Color(0.02, 0.40, 0.38), "uplink": "mast",
		"slogan": "THE COAST'S NEWS LEADER"},
	{"name": "ONDA 34", "tag": "NOTICIAS", "number": "34", "color": Color(0.36, 0.09, 0.50), "uplink": "dish",
		"slogan": "SIEMPRE CONTIGO"},
]
## The telescoping mast: sections, each this long, overlapping this much when raised (m). Raised
## it stands ~10.5 m over the roof.
const MAST_SECTIONS := 6
const MAST_SECTION_LEN := 1.9
const MAST_OVERLAP := 0.17
const MAST_R0 := 0.085
const MAST_R_STEP := 0.008
## The uplink dish's diameter and its focal length (m).
const DISH_D := 1.2
const DISH_F := 0.5
## Caution tape: width (m) and the texture's text.
const TAPE_W := 0.075
const TAPE_TEXT := "CAUTION   DO NOT CROSS   "

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}
static var _tape_mat: ShaderMaterial


static func station(i: int) -> Dictionary:
	return STATIONS[posmod(i, STATIONS.size())]


# --- Materials ------------------------------------------------------------------------------------

## Vertex-coloured paint / plastic (`metal` false) or metal (anodised, chrome).
static func material(metal: bool) -> StandardMaterial3D:
	var key := "metal" if metal else "paint"
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.32 if metal else 0.55
	m.metallic = 0.85 if metal else 0.0
	_mats[key] = m
	return m


## The LED panel's face and the camera's top light: lit by `energy` (NewsCrew sets it by the
## hour), one shared material.
static func lamp_material() -> StandardMaterial3D:
	if _mats.has("lamp"):
		return _mats.lamp
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.86, 0.88)
	m.roughness = 0.2
	m.emission_enabled = true
	m.emission = Color(1.0, 0.93, 0.82)
	m.emission_energy_multiplier = 1.5
	_mats.lamp = m
	return m


static func tape_material() -> ShaderMaterial:
	if _tape_mat == null:
		_tape_mat = ShaderMaterial.new()
		_tape_mat.shader = load("res://shaders/news_tape.gdshader")
		_tape_mat.set_shader_parameter("print_tex", tape_texture())
	return _tape_mat


## The tape's print: black block capitals (LedScreen's 5 x 7 glyphs, each dot a rounded block)
## on safety yellow, one repeat of TAPE_TEXT across the texture, alpha the letters.
static func tape_texture() -> Texture2D:
	if _mats.has("tape_tex"):
		return _mats.tape_tex
	var cell := 6
	var gap := 1
	var cols := TAPE_TEXT.length() * (5 + gap)
	var w := cols * cell
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	var top := (h - 7 * cell) / 2
	for ci in TAPE_TEXT.length():
		var rows: Array = LedScreen.GLYPHS.get(TAPE_TEXT[ci], LedScreen.GLYPHS[" "])
		for r in 7:
			var row: String = rows[r]
			for c in 5:
				if row[c] != "#":
					continue
				var x0 := (ci * (5 + gap) + c) * cell
				var y0 := top + r * cell
				for yy in cell:
					for xx in cell:
						# Rounded where a dot has no neighbour: the corners of a stroke soften.
						var cx := xx - (cell - 1) * 0.5
						var cy := yy - (cell - 1) * 0.5
						var open_x := (c == 0 or row[c - 1] != "#") if cx < 0.0 else (c == 4 or row[c + 1] != "#")
						var open_y := (r == 0 or String(rows[r - 1])[c] != "#") if cy < 0.0 else (r == 6 or String(rows[r + 1])[c] != "#")
						if open_x and open_y and Vector2(absf(cx), absf(cy)).length() > cell * 0.62:
							continue
						img.set_pixel(x0 + xx, y0 + yy, Color(1, 1, 1))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mats.tape_tex = tex
	return tex


# --- Geometry helpers -----------------------------------------------------------------------------

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3 = Vector3.ZERO) -> void:
	var fn := (b - a).cross(c - a)
	if n == Vector3.ZERO:
		n = fn.normalized()
	elif fn.dot(n) < 0.0:
		var t := b
		b = c
		c = t
	# Godot's front faces wind clockwise seen from the front: swap to match.
	for p: Vector3 in [a, c, b]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


## A box at `c` sized `s`, turned by `basis` (defaults square), flat-shaded.
static func box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, basis: Basis = Basis()) -> void:
	var h := s * 0.5
	var axes := [basis.x, basis.y, basis.z]
	for ai in 3:
		for sgn: float in [-1.0, 1.0]:
			var n: Vector3 = axes[ai] * sgn
			var u: Vector3 = axes[(ai + 1) % 3] * h[(ai + 1) % 3]
			var v: Vector3 = axes[(ai + 2) % 3] * h[(ai + 2) % 3]
			var o: Vector3 = c + n * h[ai]
			_tri(st, o - u - v, o + u - v, o + u + v, col, n)
			_tri(st, o - u - v, o + u + v, o - u + v, col, n)


## A tube from `a` to `b`, radii `ra` / `rb`, `sides` round, smooth sides, capped ends.
static func tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides: int = 14, caps: bool = true) -> void:
	var ax := (b - a)
	if ax.length() < 1e-5:
		return
	ax = ax.normalized()
	var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
	var u := ax.cross(ref).normalized()
	var v := ax.cross(u).normalized()
	var slope := (ra - rb) / a.distance_to(b)
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var n0 := (d0 + ax * slope).normalized()
		var n1 := (d1 + ax * slope).normalized()
		var p := [a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb]
		var ns := [n0, n1, n1, n0]
		for idx: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(ns[idx])
			st.add_vertex(p[idx])
		if caps:
			_tri(st, a, a + d0 * ra, a + d1 * ra, col, -ax)
			_tri(st, b, b + d0 * rb, b + d1 * rb, col, ax)


# --- The van's roof gear --------------------------------------------------------------------------

## A roof rack over the cargo roof: two side rails on feet, cross bars, a walkway of slats between
## them and a cable tray to the mast. `length` / `width` the space it covers; built round z 0.
static func rack_mesh(length: float, width: float) -> ArrayMesh:
	var key := "rack_%.2f_%.2f" % [length, width]
	if _meshes.has(key):
		return _meshes[key]
	var st := _st()
	var alu := Color(0.62, 0.63, 0.65)
	var black := Color(0.04, 0.04, 0.045)
	var half_l := length * 0.5
	var half_w := width * 0.5
	for sx: float in [-half_w, half_w]:
		tube(st, Vector3(sx, 0.07, -half_l), Vector3(sx, 0.07, half_l), 0.017, 0.017, alu, 10)
		var feet := 4
		for k in feet:
			var z := lerpf(-half_l + 0.12, half_l - 0.12, float(k) / float(feet - 1))
			box(st, Vector3(sx, 0.025, z), Vector3(0.06, 0.05, 0.09), black)
			tube(st, Vector3(sx, 0.045, z), Vector3(sx, 0.07, z), 0.012, 0.012, black, 8, false)
	var bars := 6
	for k in bars:
		var z := lerpf(-half_l + 0.05, half_l - 0.05, float(k) / float(bars - 1))
		box(st, Vector3(0.0, 0.075, z), Vector3(width, 0.022, 0.035), alu)
	# Diamond-plate walkway slats down the middle.
	var slats := int(length / 0.16)
	for k in slats:
		var z := -half_l + 0.1 + float(k) * (length - 0.2) / float(maxi(slats - 1, 1))
		box(st, Vector3(0.0, 0.092, z), Vector3(0.42, 0.01, 0.11), Color(0.55, 0.56, 0.57))
	var mesh := st.commit()
	mesh.surface_set_material(0, material(true))
	_meshes[key] = mesh
	return mesh


## The mast's base: a housing on the rack at the back corner with its compressor box, a guide
## collar and the foot of the first section. Origin at the foot.
static func mast_base_mesh() -> ArrayMesh:
	if _meshes.has("mast_base"):
		return _meshes.mast_base
	var st := _st()
	var white := Color(0.88, 0.88, 0.86)
	var black := Color(0.05, 0.05, 0.055)
	box(st, Vector3(0.0, 0.18, 0.0), Vector3(0.34, 0.36, 0.34), white)
	box(st, Vector3(0.0, 0.37, 0.0), Vector3(0.36, 0.03, 0.36), black)
	tube(st, Vector3(0.0, 0.38, 0.0), Vector3(0.0, 0.52, 0.0), MAST_R0 + 0.025, MAST_R0 + 0.02, black, 16)
	box(st, Vector3(0.0, 0.12, -0.32), Vector3(0.3, 0.24, 0.26), Color(0.30, 0.31, 0.33))
	for k in 5:
		box(st, Vector3(0.0, 0.06 + k * 0.035, -0.452), Vector3(0.24, 0.012, 0.01), black)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	_meshes.mast_base = mesh
	return mesh


## Section `i` of the mast: an aluminium tube with a black clamp collar at its top. Origin at its
## foot, up +Y.
static func mast_section_mesh(i: int) -> ArrayMesh:
	var key := "mast_%d" % i
	if _meshes.has(key):
		return _meshes[key]
	var st := _st()
	var r := MAST_R0 - MAST_R_STEP * float(i)
	tube(st, Vector3.ZERO, Vector3(0.0, MAST_SECTION_LEN, 0.0), r, r, Color(0.78, 0.79, 0.80), 18)
	tube(st, Vector3(0.0, MAST_SECTION_LEN - 0.07, 0.0), Vector3(0.0, MAST_SECTION_LEN, 0.0), r + 0.011, r + 0.011, Color(0.05, 0.05, 0.055), 18)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(true))
	_meshes[key] = mesh
	return mesh


## The mast head: a pan-tilt unit and the microwave transmitter with its white radome, aimed -Z.
## Origin at the top of the last section.
static func mast_head_mesh() -> ArrayMesh:
	if _meshes.has("mast_head"):
		return _meshes.mast_head
	var st := _st()
	var white := Color(0.90, 0.90, 0.88)
	var grey := Color(0.32, 0.33, 0.35)
	var black := Color(0.05, 0.05, 0.055)
	tube(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.16, 0.0), 0.075, 0.075, grey, 18)
	# The yoke.
	box(st, Vector3(0.0, 0.18, 0.0), Vector3(0.44, 0.04, 0.12), grey)
	for sx: float in [-0.2, 0.2]:
		box(st, Vector3(sx, 0.33, 0.0), Vector3(0.035, 0.28, 0.1), grey)
	# Transmitter box, radome drum at its front, a feed cable at the back.
	box(st, Vector3(0.0, 0.40, 0.08), Vector3(0.3, 0.26, 0.24), white)
	tube(st, Vector3(0.0, 0.40, -0.04), Vector3(0.0, 0.40, -0.18), 0.30, 0.31, white, 28)
	tube(st, Vector3(0.0, 0.40, -0.18), Vector3(0.0, 0.40, -0.20), 0.31, 0.29, Color(0.84, 0.84, 0.82), 28)
	tube(st, Vector3(0.0, 0.40, -0.035), Vector3(0.0, 0.40, -0.05), 0.315, 0.315, black, 28)
	tube(st, Vector3(0.0, 0.32, 0.2), Vector3(0.0, 0.18, 0.12), 0.012, 0.012, black, 8, false)
	# Red obstruction light on top.
	tube(st, Vector3(0.0, 0.53, 0.08), Vector3(0.0, 0.6, 0.08), 0.03, 0.025, Color(0.75, 0.05, 0.03), 10)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	_meshes.mast_head = mesh
	return mesh


## The coiled cable that runs up beside the mast: a helix of `turns` round a 0.13 m radius over
## 1 m (NewsVan scales it to the mast's height).
static func coil_mesh(turns: int = 22) -> ArrayMesh:
	if _meshes.has("coil"):
		return _meshes.coil
	var pts: Array[Vector3] = []
	var steps := turns * 10
	for k in steps + 1:
		var t := float(k) / float(steps)
		var a := t * TAU * float(turns)
		pts.append(Vector3(0.13 * cos(a), t, 0.13 * sin(a)))
	var mesh := EmergencyCrew.tube_mesh(pts, 0.009, 5)
	mesh.surface_set_material(0, PropFactory.material(Color(0.03, 0.03, 0.035), 0.6))
	_meshes.coil = mesh
	return mesh


## The uplink's turntable: a drum on the rack with the elevation hinge's brackets on top. Origin
## at its foot; the hinge axis is X at HINGE_Y.
const HINGE_Y := 0.30
static func dish_base_mesh() -> ArrayMesh:
	if _meshes.has("dish_base"):
		return _meshes.dish_base
	var st := _st()
	var white := Color(0.88, 0.88, 0.86)
	var grey := Color(0.3, 0.31, 0.33)
	tube(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.14, 0.0), 0.26, 0.24, white, 28)
	tube(st, Vector3(0.0, 0.14, 0.0), Vector3(0.0, 0.18, 0.0), 0.2, 0.2, grey, 24)
	for sx: float in [-0.22, 0.22]:
		box(st, Vector3(sx, 0.25, 0.0), Vector3(0.04, 0.16, 0.16), grey)
	tube(st, Vector3(-0.26, HINGE_Y, 0.0), Vector3(0.26, HINGE_Y, 0.0), 0.03, 0.03, grey, 12)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	_meshes.dish_base = mesh
	return mesh


## The uplink dish in its hinge's frame: a prime-focus paraboloid of DISH_D, boresight +Z, its
## rim's lowest point at the hinge (origin) and the dish up +Y; feed struts to the horn at the
## focus, a back frame and the actuator lug. NewsVan turns the hinge about X.
static func dish_mesh() -> ArrayMesh:
	if _meshes.has("dish"):
		return _meshes.dish
	var st := _st()
	var face := Color(0.86, 0.86, 0.84)
	var back := Color(0.72, 0.73, 0.74)
	var grey := Color(0.3, 0.31, 0.33)
	var r := DISH_D * 0.5
	var centre := Vector3(0.0, r + 0.04, 0.0)
	var rings := 7
	var segs := 32
	var depth := r * r / (4.0 * DISH_F)
	var pt := func(ring: int, seg: int) -> Vector3:
		var rr := r * float(ring) / float(rings)
		var a := TAU * float(seg) / float(segs)
		return centre + Vector3(rr * cos(a), rr * sin(a), rr * rr / (4.0 * DISH_F) - depth)
	var nrm := func(ring: int, seg: int) -> Vector3:
		var rr := r * float(ring) / float(rings)
		var a := TAU * float(seg) / float(segs)
		# Paraboloid z = rr^2 / 4f: the inside faces +Z (toward the focus).
		var dz := rr / (2.0 * DISH_F)
		return Vector3(-dz * cos(a), -dz * sin(a), 1.0).normalized()
	for ring in rings:
		for seg in segs:
			var q := [pt.call(ring, seg), pt.call(ring + 1, seg), pt.call(ring + 1, seg + 1), pt.call(ring, seg + 1)]
			var qn := [nrm.call(ring, seg), nrm.call(ring + 1, seg), nrm.call(ring + 1, seg + 1), nrm.call(ring, seg + 1)]
			# Front (toward +Z) and back, 1 cm apart.
			for idx: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(face)
				st.set_normal(qn[idx])
				st.add_vertex(q[idx])
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(back)
				st.set_normal(-(qn[idx] as Vector3))
				st.add_vertex((q[idx] as Vector3) - (qn[idx] as Vector3) * 0.012)
	# The rolled rim.
	var rim_c := centre + Vector3(0.0, 0.0, 0.0)
	for seg in segs:
		var a0 := TAU * float(seg) / float(segs)
		var a1 := TAU * float(seg + 1) / float(segs)
		tube(st, rim_c + Vector3(r * cos(a0), r * sin(a0), 0.0), rim_c + Vector3(r * cos(a1), r * sin(a1), 0.0), 0.014, 0.014, back, 6, false)
	# Feed struts to the horn and the LNB at the focus.
	var focus := centre + Vector3(0.0, 0.0, DISH_F - depth)
	for k in 3:
		var a := TAU * float(k) / 3.0 + PI * 0.5
		tube(st, centre + Vector3(r * 0.92 * cos(a), r * 0.92 * sin(a), 0.0), focus - Vector3(0.0, 0.0, 0.05), 0.011, 0.009, grey, 8, false)
	tube(st, focus - Vector3(0.0, 0.0, 0.16), focus + Vector3(0.0, 0.0, 0.02), 0.045, 0.06, Color(0.15, 0.15, 0.16), 14)
	box(st, focus - Vector3(0.0, 0.0, 0.2), Vector3(0.1, 0.1, 0.1), Color(0.86, 0.86, 0.84))
	# Back frame: a spine down to the hinge and a cross brace.
	var back_c := centre - Vector3(0.0, 0.0, depth * 0.2 + 0.08)
	tube(st, back_c, Vector3(0.0, 0.03, -0.02), 0.025, 0.025, grey, 10)
	tube(st, back_c + Vector3(-r * 0.7, 0.0, 0.03), back_c + Vector3(r * 0.7, 0.0, 0.03), 0.02, 0.02, grey, 10)
	tube(st, Vector3(-0.2, 0.0, 0.0), Vector3(0.2, 0.0, 0.0), 0.035, 0.035, grey, 12)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	_meshes.dish = mesh
	return mesh


# --- The crew's kit -------------------------------------------------------------------------------

## A shoulder camera (an ENG camcorder), lens toward -Z, origin at the shoulder pad's middle: the
## body, the lens and its hood, the zoom grip on the right (+X), the viewfinder out to the left (-X) at
## the operator's right eye, the top handle with a shotgun mic, the battery at the back, a small LED
## light on the handle (a separate surface on the lamp material) and the red tally lamp.
static func camera_mesh() -> ArrayMesh:
	if _meshes.has("camera"):
		return _meshes.camera
	var st := _st()
	var body := Color(0.10, 0.10, 0.11)
	var dark := Color(0.035, 0.035, 0.04)
	var grey := Color(0.32, 0.33, 0.35)
	box(st, Vector3(0.0, 0.0, 0.02), Vector3(0.07, 0.03, 0.2), dark)
	box(st, Vector3(0.0, 0.1, -0.02), Vector3(0.12, 0.17, 0.3), body)
	box(st, Vector3(0.0, 0.17, -0.02), Vector3(0.11, 0.03, 0.28), Color(0.16, 0.16, 0.17))
	# Lens: barrel, zoom ring, hood.
	tube(st, Vector3(0.0, 0.1, -0.17), Vector3(0.0, 0.1, -0.36), 0.048, 0.044, dark, 18)
	tube(st, Vector3(0.0, 0.1, -0.23), Vector3(0.0, 0.1, -0.29), 0.053, 0.053, grey, 18)
	tube(st, Vector3(0.0, 0.1, -0.36), Vector3(0.0, 0.1, -0.42), 0.06, 0.075, dark, 18)
	tube(st, Vector3(0.0, 0.1, -0.415), Vector3(0.0, 0.1, -0.418), 0.05, 0.05, Color(0.10, 0.13, 0.18), 18)
	# Zoom grip on the lens's right side (+X) with its rocker.
	box(st, Vector3(0.07, 0.085, -0.27), Vector3(0.04, 0.09, 0.12), body)
	box(st, Vector3(0.091, 0.115, -0.25), Vector3(0.006, 0.02, 0.04), grey)
	# Viewfinder: arm out to the left at the front, the eyecup back toward the operator.
	box(st, Vector3(-0.09, 0.2, -0.12), Vector3(0.1, 0.02, 0.03), dark)
	box(st, Vector3(-0.14, 0.2, -0.08), Vector3(0.05, 0.06, 0.13), body)
	tube(st, Vector3(-0.14, 0.2, -0.02), Vector3(-0.14, 0.2, 0.04), 0.024, 0.03, dark, 12)
	# Top handle and the shotgun mic in its holder.
	box(st, Vector3(0.0, 0.23, -0.18), Vector3(0.025, 0.06, 0.025), dark)
	box(st, Vector3(0.0, 0.23, 0.06), Vector3(0.025, 0.06, 0.025), dark)
	box(st, Vector3(0.0, 0.265, -0.06), Vector3(0.03, 0.02, 0.27), dark)
	tube(st, Vector3(-0.045, 0.24, -0.08), Vector3(-0.045, 0.24, -0.33), 0.012, 0.012, Color(0.18, 0.18, 0.19), 10)
	tube(st, Vector3(-0.045, 0.24, -0.33), Vector3(-0.045, 0.24, -0.35), 0.012, 0.008, grey, 10)
	# Battery at the back, its plate and the red tally on the front.
	box(st, Vector3(0.0, 0.1, 0.16), Vector3(0.1, 0.13, 0.05), Color(0.06, 0.06, 0.065))
	box(st, Vector3(0.0, 0.1, 0.135), Vector3(0.11, 0.15, 0.01), grey)
	box(st, Vector3(0.04, 0.16, -0.172), Vector3(0.014, 0.01, 0.006), Color(0.9, 0.05, 0.03))
	# The LED light's housing at the handle's front.
	box(st, Vector3(0.0, 0.31, -0.15), Vector3(0.07, 0.04, 0.03), dark)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	var lamp := _st()
	box(lamp, Vector3(0.0, 0.31, -0.1655), Vector3(0.06, 0.03, 0.002), Color(1, 1, 1))
	lamp.commit(mesh)
	mesh.surface_set_material(1, lamp_material())
	_meshes.camera = mesh
	return mesh


## The reporter's hand microphone in the GRIP frame (CrowdLife.prop_mesh's: x along the thumb, y
## along the fingers, z out of the palm): the handle up the fist along x, the grille over the
## thumb, and the station's flag (a box in its colour with the number's white panel) on the shaft.
static func mic_mesh(station_i: int) -> ArrayMesh:
	var key := "mic_%d" % posmod(station_i, STATIONS.size())
	if _meshes.has(key):
		return _meshes[key]
	var s := station(station_i)
	var col: Color = s.color
	var st := _st()
	var black := Color(0.03, 0.03, 0.035)
	var c := Vector3(0.0, 0.045, 0.03)
	tube(st, c + Vector3(-0.09, 0.0, 0.0), c + Vector3(0.1, 0.0, 0.0), 0.014, 0.018, black, 14)
	tube(st, c + Vector3(0.1, 0.0, 0.0), c + Vector3(0.115, 0.0, 0.0), 0.02, 0.022, Color(0.55, 0.56, 0.58), 14)
	# The ball grille.
	var g := c + Vector3(0.145, 0.0, 0.0)
	tube(st, g - Vector3(0.03, 0.0, 0.0), g + Vector3(0.0, 0.0, 0.0), 0.022, 0.031, Color(0.62, 0.63, 0.65), 16, false)
	tube(st, g, g + Vector3(0.028, 0.0, 0.0), 0.031, 0.012, Color(0.62, 0.63, 0.65), 16)
	# The flag: a square-section collar round the shaft.
	var fc := c + Vector3(0.06, 0.0, 0.0)
	box(st, fc, Vector3(0.055, 0.075, 0.075), col)
	for face_n: Vector3 in [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		box(st, fc + face_n * 0.0385, Vector3(0.035, 0.05, 0.05) * (Vector3.ONE - face_n.abs()) + face_n.abs() * 0.002, Color(0.95, 0.95, 0.94))
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	_meshes[key] = mesh
	return mesh


## An LED panel on a lighting stand: three splayed legs, the centre column up to `height`, the
## yoke and the panel facing -Z (its face a second surface on the lamp material). Origin at the
## floor under the column.
static func light_stand_mesh(height: float = 2.05) -> ArrayMesh:
	var key := "stand_%.2f" % height
	if _meshes.has(key):
		return _meshes[key]
	var st := _st()
	var black := Color(0.04, 0.04, 0.045)
	var alu := Color(0.55, 0.56, 0.58)
	var hub := Vector3(0.0, 0.62, 0.0)
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.4
		var foot := Vector3(cos(a) * 0.62, 0.0, sin(a) * 0.62)
		tube(st, hub, foot, 0.014, 0.012, black, 8)
		tube(st, hub.lerp(foot, 0.45), Vector3(0.0, 0.42, 0.0), 0.007, 0.007, black, 6, false)
		box(st, foot + Vector3(0.0, 0.01, 0.0), Vector3(0.04, 0.02, 0.04), Color(0.1, 0.1, 0.1))
	tube(st, Vector3(0.0, 0.42, 0.0), hub + Vector3(0.0, 0.06, 0.0), 0.022, 0.022, black, 12)
	tube(st, hub, Vector3(0.0, height - 0.25, 0.0), 0.018, 0.018, alu, 12)
	tube(st, Vector3(0.0, height - 0.25, 0.0), Vector3(0.0, height - 0.12, 0.0), 0.013, 0.013, alu, 10)
	# Yoke and panel.
	box(st, Vector3(0.0, height - 0.11, 0.0), Vector3(0.36, 0.02, 0.03), black)
	for sx: float in [-0.17, 0.17]:
		box(st, Vector3(sx, height + 0.02, 0.0), Vector3(0.015, 0.26, 0.03), black)
	box(st, Vector3(0.0, height + 0.05, 0.0), Vector3(0.32, 0.32, 0.045), Color(0.12, 0.12, 0.13))
	# Barn doors open round the face.
	box(st, Vector3(0.0, height + 0.235, -0.07), Vector3(0.32, 0.005, 0.12), black, Basis(Vector3.RIGHT, -0.5))
	box(st, Vector3(0.0, height - 0.135, -0.07), Vector3(0.32, 0.005, 0.12), black, Basis(Vector3.RIGHT, 0.5))
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	var lamp := _st()
	box(lamp, Vector3(0.0, height + 0.05, -0.024), Vector3(0.28, 0.28, 0.002), Color(1, 1, 1))
	lamp.commit(mesh)
	mesh.surface_set_material(1, lamp_material())
	_meshes[key] = mesh
	return mesh


## A tape post: a weighted rubber base and an orange post with a reflective collar and a slot at
## the top where the tape runs. Origin at the base's foot; the tape at TAPE_Y.
const TAPE_Y := 0.98
static func post_mesh() -> ArrayMesh:
	if _meshes.has("post"):
		return _meshes.post
	var st := _st()
	tube(st, Vector3.ZERO, Vector3(0.0, 0.04, 0.0), 0.2, 0.18, Color(0.05, 0.05, 0.055), 18)
	tube(st, Vector3(0.0, 0.04, 0.0), Vector3(0.0, 0.07, 0.0), 0.07, 0.05, Color(0.05, 0.05, 0.055), 12)
	tube(st, Vector3(0.0, 0.07, 0.0), Vector3(0.0, 1.0, 0.0), 0.028, 0.025, Color(0.95, 0.38, 0.04), 12)
	tube(st, Vector3(0.0, 0.84, 0.0), Vector3(0.0, 0.92, 0.0), 0.029, 0.029, Color(0.92, 0.92, 0.90), 12)
	tube(st, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.03, 0.0), 0.03, 0.02, Color(0.05, 0.05, 0.055), 12)
	var mesh := st.commit()
	mesh.surface_set_material(0, material(false))
	_meshes.post = mesh
	return mesh


## Caution tape strung post to post through `tops` (scene space), sagging between them: a ribbon
## TAPE_W wide with a slight twist, UV.x metres along it (the print repeats), UV.y across, and in
## UV2.x how far into its span (0..1) a point is, which the shader's flutter reads.
static func tape_mesh(tops: Array[Vector3]) -> ArrayMesh:
	var st := _st()
	var run := 0.0
	for i in tops.size() - 1:
		var a := tops[i]
		var b := tops[i + 1]
		var span := a.distance_to(b)
		var sag := 0.035 * span
		var along := (b - a).normalized()
		var side := along.cross(Vector3.UP).normalized()
		var steps := maxi(int(span / 0.35), 4)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_u := 0.0
		for k in steps + 1:
			var t := float(k) / float(steps)
			var p := a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
			# The tape hangs across its width, twisting a little in the middle of a span.
			var twist := sin(t * PI) * 0.6 * (0.5 + 0.5 * sin(float(i) * 2.1))
			var across := (Vector3.UP * cos(twist) + side * sin(twist)) * (TAPE_W * 0.5)
			var l := p + across
			var r := p - across
			var u := run + span * t
			if k > 0:
				var n := (l - prev_l).cross(prev_r - prev_l).normalized()
				var verts := [[prev_l, prev_u, 0.0], [l, u, 0.0], [r, u, 1.0], [prev_l, prev_u, 0.0], [r, u, 1.0], [prev_r, prev_u, 1.0]]
				for v: Array in verts:
					st.set_normal(n)
					st.set_uv(Vector2(float(v[1]), float(v[2])))
					var tt := (float(v[1]) - run) / span
					st.set_uv2(Vector2(tt, float(i)))
					st.add_vertex(v[0])
			prev_l = l
			prev_r = r
			prev_u = u
		run += span
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, tape_material())
	return mesh
