class_name BroadwayTheatre
extends RefCounted
## One of Broadway's movie palaces (Broadway.THEATRES), built on its lot in code at real size.
##
## Its own frame: x along the street (to the right seen from the street), y up from the pavement
## top, +z out toward the street; the facade's face is z = 0 and the building runs back to -depth.
## The front building (the lobby wing, an office block over it where the real palace has one)
## fills the lot's whole Broadway frontage: shopfronts either side of the entrance, the PAVILION
## in the middle (the palace's own ornamented front, in its style: FRENCH beaux-arts with a giant
## arched window between paired columns, SPANISH churrigueresque with a carved frontispiece on a
## tall office shaft and pinnacles, DECO with fluted fins stepping up past the parapet), then the
## brick auditorium and fly tower behind, out to the lot's back.
## On the street: the recessed entrance (terrazzo sunburst floor, glass doors in brass, lit poster
## cases, a bulb-studded soffit, the ticket booth), the marquee projecting over the pavement (a
## vee, flat or drum front of changeable-letter boards between chasing bulb rows, neon along its
## top, the name on its crest) and the blade sign above it (enamel, both faces carrying the name
## in stacked bulb letters that spell out row by row, bulb borders, a neon outline, a crown).
## One mesh per palace for the masonry (a surface per material on landmark_facade, floodlit after
## dark) and ONE surface for every lit or painted thing on the street (broadway_sign.gdshader).
## LOD and the far city: boxes, the sign column and marquee lit at night (building_lod's PANEL).

const STOREY_GROUND := 6.2
const MARQUEE_Y0 := 4.25
const MARQUEE_Y1 := 7.0
const RECESS := 4.6
const SIGN_Y0 := 7.6
const BAY := 5.2

## broadway_sign.gdshader kinds (COLOR.a * 16).
const K_ENAMEL := 0
const K_BULBS := 1
const K_NEON := 2
const K_LETTERS := 3
const K_BOARD := 4
const K_SOFFIT := 5
const K_TYPE := 6
const K_IRON := 7
const K_BRASS := 8
const K_GLASS := 9
const K_POSTER := 10
const K_TERRAZZO := 11

const BRASS := Color(0.78, 0.60, 0.30)
const IRON := Color(0.10, 0.11, 0.10)
const AUDITORIUM_H := 24.0

static var _mats: Dictionary = {}


static func kc(rgb: Color, kind: int) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, float(kind) / 16.0)


## The palace's frame in the chunk (true world): [Transform3D, frontage, depth, to_kerb].
static func frame(ch: CityChunk, p: Dictionary) -> Array:
	var lot: Dictionary = p.lot
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	var side: int = p.side
	var fx := c.x + s.x * 0.5 if side < 0 else c.x - s.x * 0.5
	var out := Vector3(-float(side), 0.0, 0.0)
	var x_axis := Vector3.UP.cross(out)
	var g := ch._gy(fx, c.y)
	var xf := Transform3D(Basis(x_axis, Vector3.UP, out), Vector3(fx, g + CityChunk.SIDEWALK_TOP, c.y))
	var to_kerb := absf(Broadway.avenue_x() - fx) - Broadway.avenue_width() * 0.5
	return [xf, s.y, s.x, to_kerb]


static func pavilion_width(spec: Dictionary, frontage: float) -> float:
	if frontage < 26.0:
		return frontage
	var w := 22.0 if int(spec.style) == Broadway.Style.DECO else 26.0
	return clampf(minf(w, frontage * 0.7), 16.0, frontage)


static func build(ch: CityChunk, p: Dictionary) -> void:
	var spec: Dictionary = p.spec
	# A caller may hand its own frame (StarBoulevard's palace, set back behind its forecourt).
	var f: Array = p.frame if p.has("frame") else frame(ch, p)
	var xf: Transform3D = f[0]
	var w: float = f[1]
	var d: float = f[2]
	var to_kerb: float = f[3]
	var lot: Dictionary = p.lot
	var hc: float = spec.front_h
	var fd := 14.0 if hc > 30.0 else 10.0
	var ha := maxf(AUDITORIUM_H, minf(hc - 2.0, 30.0))
	var tower: float = spec.get("tower", 0.0)
	ch._lot_rects.append(Rect2((lot.center as Vector2) - (lot.size as Vector2) * 0.5, lot.size))
	ch.building_count += 1
	var sh: float = spec.sign_h
	if ch.level != CityChunk.Level.FULL:
		_far(ch, xf, spec, w, d, fd, hc, ha, sh, to_kerb, int(lot.seed))
		return
	var node := Node3D.new()
	node.name = "Palace_" + str(spec.id)
	node.transform = xf
	node.add_to_group("broadway_palace")
	ch.add_child(node)
	var g := LandmarkGeo.new()
	_use_mats(g, spec, hc)
	var tw := pavilion_width(spec, w)
	var marquee_l := clampf(to_kerb - 0.7, 2.5, 4.8)
	_ground_storey(g, spec, w, tw, fd, int(lot.seed))
	_front_block(g, spec, w, tw, fd, hc)
	match int(spec.style):
		Broadway.Style.FRENCH:
			_french(g, spec, tw, hc)
		Broadway.Style.SPANISH:
			_spanish(g, spec, w, tw, hc)
		_:
			_deco(g, spec, tw, hc)
	if tower > 0.0:
		_clock_tower(g, spec, hc, tower)
	if spec.get("roof_sign", false):
		_roof_sign(g, spec, w, hc)
	_auditorium(g, w, d, fd, ha)
	_entrance(g, spec, tw, marquee_l)
	_marquee(g, spec, tw, marquee_l)
	_blade_sign(g, spec, sh, minf(marquee_l - 0.9, 3.0), hc)
	g.commit(node, "Palace")
	# Collision: the front block, the auditorium, the marquee and the sign.
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	LandmarkGeo.shape_box(body, Vector3(0.0, hc * 0.5, -fd * 0.5 - 0.3), Vector3(w, hc, fd - 0.6))
	LandmarkGeo.shape_box(body, Vector3(0.0, ha * 0.5, -(fd + d) * 0.5), Vector3(w - 1.0, ha, d - fd))
	LandmarkGeo.shape_box(body, Vector3(0.0, (MARQUEE_Y0 + MARQUEE_Y1) * 0.5, marquee_l * 0.5), Vector3(minf(tw, 14.0), MARQUEE_Y1 - MARQUEE_Y0, marquee_l))
	LandmarkGeo.shape_box(body, Vector3(0.0, SIGN_Y0 + sh * 0.5, 2.0), Vector3(0.8, sh, 2.8))
	ch._occluder_boxes.append([xf, Vector3(0.0, hc * 0.5, -fd * 0.5), Vector3(w - 0.8, hc - 0.8, fd - 1.2)])
	ch._occluder_boxes.append([xf, Vector3(0.0, ha * 0.5, -(fd + d) * 0.5), Vector3(w - 1.6, ha - 0.8, d - fd - 1.2)])
	# Night: the marquee's light on the pavement and the people under it (DayNight's lamp group),
	# and coloured pools from the blade sign's neon and the marquee.
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 3.6, marquee_l * 0.55)
	light.omni_range = 13.0
	light.omni_attenuation = 1.2
	light.light_color = Color(1.0, 0.80, 0.55)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.add_to_group("lamp_light")
	node.add_child(light)
	var neon: Color = spec.neon
	var pools := [
		[Vector3(0.0, 0.1, marquee_l * 0.5 + 0.8), Vector2(minf(tw, 16.0) + 4.0, marquee_l + 5.0), Color(1.0, 0.82, 0.58), 1.0],
		[Vector3(0.0, 0.11, marquee_l + 2.2), Vector2(9.0, 7.0), neon, 0.55],
	]
	for pl: Array in pools:
		var at: Vector3 = xf * (pl[0] as Vector3)
		# The batch adds the relief itself.
		at.y -= ch._gy(at.x, at.z)
		var sz: Vector2 = pl[1]
		var pool := Transform3D(Basis(Vector3.UP, xf.basis.get_euler().y) * Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(sz.x, 1.0, sz.y)), at)
		ch._batch.add("bw_pool", PropFactory.light_pool(Color(1.0, 1.0, 1.0), 1.3, 1.6), pool, Color((pl[2] as Color).r, (pl[2] as Color).g, (pl[2] as Color).b, float(pl[3])))
	ch._batch.set_no_shadow("bw_pool")


# --- Materials ---------------------------------------------------------------------------------

static func _use_mats(g: LandmarkGeo, spec: Dictionary, hc: float) -> void:
	var style: int = spec.style
	var tint := Color(0.74, 0.67, 0.55)
	var trim_tint := Color(0.80, 0.74, 0.62)
	if style == Broadway.Style.SPANISH:
		tint = Color(0.76, 0.62, 0.48)
		trim_tint = Color(0.80, 0.68, 0.54)
	elif style == Broadway.Style.DECO:
		tint = Color(0.70, 0.69, 0.64)
		trim_tint = Color(0.62, 0.66, 0.58)
	var k := str(int(style))
	var flood := {"flood_strength": 0.5, "flood_base_y": MARQUEE_Y1 + 0.2, "flood_reach": 16.0, "flood_floor": 0.15, "flood_spacing": 4.0}
	var plain := {"tint": tint, "roughness": 0.55, "texture_contrast": 0.45, "joint_spacing": Vector2(0.9, 0.48), "joint_width": 0.012,
		"joint_dark": 0.7, "grime": 0.35, "seed": 4.0}
	plain.merge(flood)
	g.use("terra", LandmarkMats.facade("bw_terra_" + k, "plaster_white", 3.0, plain))
	var trim := {"tint": trim_tint, "roughness": 0.45, "texture_contrast": 0.4, "grime": 0.3, "seed": 9.0}
	trim.merge(flood)
	g.use("trim", LandmarkMats.facade("bw_trim_" + k, "plaster_white", 2.0, trim))
	var win := plain.duplicate()
	win.merge({"win_pitch": Vector2(1.9, 3.7), "win_size": Vector2(0.36, 0.56), "win_sill": 0.2,
		"win_band": Vector2(STOREY_GROUND + 1.2, 200.0), "lit_ratio": 0.22, "flood_strength": 0.7}, true)
	g.use("terra_win", LandmarkMats.facade("bw_terrawin_" + k, "plaster_white", 3.0, win))
	g.use("brick", LandmarkMats.facade("bw_brick", "brick_red", 2.6,
		{"tint": Color(0.86, 0.74, 0.66), "roughness": 0.85, "texture_contrast": 0.9, "grime": 0.5, "seed": 2.0}))
	# The flanking blocks of a wide palace: brick with windows (the 1920s commercial fronts either
	# side of the pavilion), so a 70 m frontage is not one long terracotta front.
	g.use("brick_win", LandmarkMats.facade("bw_brickwin", "brick_red", 2.6,
		{"tint": Color(0.80, 0.66, 0.56), "roughness": 0.85, "texture_contrast": 0.9, "grime": 0.45, "seed": 6.0,
		"win_pitch": Vector2(1.9, 3.7), "win_size": Vector2(0.36, 0.56), "win_sill": 0.2,
		"win_band": Vector2(STOREY_GROUND + 1.2, 200.0), "lit_ratio": 0.25}))
	g.use("roof", LandmarkMats.plain("bw_roof", Color(0.30, 0.30, 0.31), 0.9))
	g.use("sign", sign_material(str(spec.id)))


## The palace's sign material (the shared shader, its own sequence phase).
static func sign_material(id: String) -> ShaderMaterial:
	if _mats.has(id):
		return _mats[id]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/broadway_sign.gdshader")
	m.set_shader_parameter("seed", Broadway.h01([id, "seq"]))
	_mats[id] = m
	return m


# --- Masonry ---------------------------------------------------------------------------------

## The ground storey: shopfronts in bays across the wings, piers, sign boards with the shops'
## names, the dark interior behind the glass. The pavilion's middle is left to _entrance().
static func _ground_storey(g: LandmarkGeo, spec: Dictionary, w: float, tw: float, fd: float, seed_value: int) -> void:
	var ew := entrance_width(tw)
	# Interior back wall behind the glass and the shop ceilings.
	g.box("roof", Vector3(0.0, STOREY_GROUND * 0.5, -fd + 0.5), Vector3(w, STOREY_GROUND, 1.0))
	g.box("trim", Vector3(0.0, STOREY_GROUND - 0.15, -fd * 0.5 - 0.6), Vector3(w, 0.3, fd - 1.2))
	# Bays from the entrance out to each end.
	var shop_i := 0
	for sx: float in [-1.0, 1.0]:
		var x0 := ew * 0.5 + 0.8
		var x1 := w * 0.5
		var run := x1 - x0
		if run < 2.0:
			# Only the entrance's flanking pier.
			g.box("trim", Vector3(sx * (x0 + x1) * 0.5, STOREY_GROUND * 0.5, 0.05), Vector3(maxf(run, 0.8), STOREY_GROUND, 0.5))
			continue
		var n := maxi(1, int(round(run / BAY)))
		var bw := run / float(n)
		for i in n + 1:
			var px := sx * (x0 + float(i) * bw)
			g.box("trim", Vector3(px, STOREY_GROUND * 0.5, 0.08), Vector3(0.7, STOREY_GROUND, 0.55), Color.WHITE, Basis(), 0.04)
			g.box("trim", Vector3(px, 0.3, 0.14), Vector3(0.86, 0.6, 0.66))
		for i in n:
			var cx := sx * (x0 + (float(i) + 0.5) * bw)
			var inner := bw - 0.7
			# Bulkhead, display glass, transom, sign board.
			g.box("sign", Vector3(cx, 0.32, -0.25), Vector3(inner, 0.64, 0.3), kc(IRON, K_IRON))
			# The display's light after dark rides in the glass's red (broadway_sign.gdshader):
			# about half the shops are shut for the night (a trace of light from the back).
			var lit := Broadway.h01([seed_value, "shop_lit", shop_i])
			var glass := Color(0.06 if lit < 0.45 else 0.55 + 0.45 * lit, 0.0, 0.0)
			g.box("sign", Vector3(cx, 2.35, -0.32), Vector3(inner, 3.4, 0.06), kc(glass, K_GLASS))
			g.box("sign", Vector3(cx, 4.12, -0.3), Vector3(inner, 0.08, 0.14), kc(BRASS, K_BRASS))
			g.box("sign", Vector3(cx, 4.55, -0.32), Vector3(inner, 0.8, 0.06), kc(glass, K_GLASS))
			# Mullions in the display glass.
			for mu: float in [-0.33, 0.33]:
				g.box("sign", Vector3(cx + mu * inner, 2.35, -0.27), Vector3(0.06, 3.4, 0.08), kc(BRASS, K_BRASS))
			# The shop's sign board over the transom, a name painted on it.
			var hue := Broadway.h01([seed_value, "shop_hue", shop_i])
			var board := Color.from_hsv(hue, 0.65, 0.55)
			if Broadway.h01([seed_value, "shop_board", shop_i]) < 0.35:
				board = Color(0.93, 0.90, 0.80)
			g.box("sign", Vector3(cx, 5.45, 0.18), Vector3(inner - 0.1, 0.85, 0.12), kc(board, K_ENAMEL))
			var names: Array = spec.get("shops", Broadway.BROADWAY_SHOPS)
			var name: String = names[(int(Broadway.h01([seed_value, "shop_name"]) * 997.0) + shop_i * 7) % names.size()]
			var ink := Color(1.0, 0.9, 0.2) if board.v < 0.7 else Color(0.6, 0.06, 0.06)
			text(g, name, Transform3D(Basis(), Vector3(cx, 5.45, 0.25)), 0.5, inner - 0.6, kc(ink, K_ENAMEL), Vector3.BACK)
			# A striped shop awning on some, over the display glass.
			if Broadway.h01([seed_value, "awning", shop_i]) < 0.45:
				_awning(g, Vector3(cx, 4.95, 0.0), inner, Color.from_hsv(Broadway.h01([seed_value, "aw", shop_i]), 0.7, 0.55))
			shop_i += 1


static func entrance_width(tw: float) -> float:
	return clampf(tw - 6.0, 6.0, 11.0)


## A sloped canvas awning: a lip of `width` at y over z 0, falling out 1.4 m, stripes in COLOR.
static func _awning(g: LandmarkGeo, at: Vector3, width: float, col: Color) -> void:
	var stripes := maxi(3, int(width / 0.6))
	var sw := width / float(stripes)
	for i in stripes:
		var x0 := at.x - width * 0.5 + float(i) * sw
		var c := col if i % 2 == 0 else Color(0.92, 0.90, 0.84)
		var a := Vector3(x0, at.y, 0.1)
		var b := Vector3(x0 + sw, at.y, 0.1)
		var e := Vector3(x0 + sw, at.y - 0.75, 1.5)
		var f := Vector3(x0, at.y - 0.75, 1.5)
		g.quad("sign", a, b, e, f, Vector3(0.0, 0.88, 0.47), Vector2(0, 0), Vector2(sw, 0), Vector2(sw, 1), Vector2(0, 1), kc(c, K_ENAMEL))
		g.quad("sign", a, b, e, f, Vector3(0.0, -0.88, -0.47), Vector2(0, 0), Vector2(sw, 0), Vector2(sw, 1), Vector2(0, 1), kc(c * 0.7, K_ENAMEL))
		# The valance.
		g.quad("sign", f, e, e + Vector3(0, -0.28, 0), f + Vector3(0, -0.28, 0), Vector3.BACK, Vector2(0, 0), Vector2(sw, 0), Vector2(sw, 1), Vector2(0, 1), kc(c, K_ENAMEL))
		g.quad("sign", f, e, e + Vector3(0, -0.28, 0), f + Vector3(0, -0.28, 0), Vector3.FORWARD, Vector2(0, 0), Vector2(sw, 0), Vector2(sw, 1), Vector2(0, 1), kc(c * 0.7, K_ENAMEL))


## The front building over the ground storey: the wings (windowed terracotta), their cornice,
## the parapet; the pavilion's own wall comes from the style.
static func _front_block(g: LandmarkGeo, spec: Dictionary, w: float, tw: float, fd: float, hc: float) -> void:
	var hw := hc if hc > 30.0 else hc - 3.0
	var office := hc > 30.0
	var wing_w := (w - tw) * 0.5
	for sx: float in [-1.0, 1.0]:
		if wing_w > 0.5:
			var cx := sx * (tw * 0.5 + wing_w * 0.5)
			g.box("brick_win" if wing_w > 9.0 else "terra_win", Vector3(cx, (STOREY_GROUND + hw) * 0.5, -fd * 0.5), Vector3(wing_w, hw - STOREY_GROUND, fd), Color.WHITE, Basis(), 0.0, false, 1.9)
			_cornice(g, Vector3(cx, hw, 0.0), wing_w, fd, 1.0)
			# A belt course over the shops and one at the second floor.
			g.box("trim", Vector3(cx, STOREY_GROUND + 0.2, 0.15), Vector3(wing_w, 0.4, 0.5), Color.WHITE, Basis(), 0.05)
			g.box("trim", Vector3(cx, STOREY_GROUND + 3.9, 0.08), Vector3(wing_w, 0.22, 0.25))
			# Corner quoins up the outer edge.
			var qx := sx * (w * 0.5 - 0.4)
			var y := STOREY_GROUND + 0.6
			var q := 0
			while y < hw - 1.5:
				g.box("trim", Vector3(qx - sx * (0.15 if q % 2 == 0 else 0.0), y + 0.3, 0.06), Vector3(0.8 if q % 2 == 0 else 0.5, 0.56, 0.2))
				y += 0.62
				q += 1
	if office:
		# The office shaft over the pavilion (its middle is the style's frontispiece) and its roof.
		g.box("terra_win", Vector3(0.0, (STOREY_GROUND + hc) * 0.5, -fd * 0.5 - 0.3), Vector3(tw, hc - STOREY_GROUND, fd - 0.6), Color.WHITE, Basis(), 0.0, false, 1.9)
	else:
		# The pavilion's body behind its face (the style builds the face), roofed.
		g.box("terra", Vector3(0.0, (STOREY_GROUND + hc) * 0.5, -fd * 0.5 - 0.2), Vector3(tw, hc - STOREY_GROUND, fd - 0.4))
	# Membrane roofs over the wings and the pavilion (the facade material's own top faces would
	# read as white terracotta slabs from the air).
	if wing_w > 0.5:
		for sx: float in [-1.0, 1.0]:
			g.box("roof", Vector3(sx * (tw * 0.5 + wing_w * 0.5), hw + 0.03, -fd * 0.5), Vector3(wing_w - 0.5, 0.06, fd - 0.5))
	g.box("roof", Vector3(0.0, hc + 0.03, -fd * 0.5 - 0.2), Vector3(tw - 0.5, 0.06, fd - 0.8))


## A cornice of `width` along the face at `at` (its top centre on the facade line), `depth` back:
## fascia, dentils, the corona on modillions, a cyma; a parapet with coping over it.
static func _cornice(g: LandmarkGeo, at: Vector3, width: float, depth: float, scale: float) -> void:
	var s := scale
	var y := at.y - 1.4 * s
	g.box("trim", Vector3(at.x, y, 0.1 * s), Vector3(width, 0.4 * s, 0.3 * s))
	g.box("trim", Vector3(at.x, y + 0.42 * s, 0.22 * s), Vector3(width, 0.24 * s, 0.5 * s))
	var n := maxi(2, int(width / (0.34 * s)))
	for i in n:
		var x := at.x - width * 0.5 + (float(i) + 0.5) * width / float(n)
		g.box("trim", Vector3(x, y + 0.66 * s, 0.4 * s), Vector3(0.16 * s, 0.22 * s, 0.24 * s))
	var m := maxi(2, int(width / (1.0 * s)))
	for i in m:
		var x := at.x - width * 0.5 + (float(i) + 0.5) * width / float(m)
		g.box("trim", Vector3(x, y + 0.9 * s, 0.55 * s), Vector3(0.24 * s, 0.26 * s, 0.7 * s), Color.WHITE, Basis(), 0.03)
	g.box("trim", Vector3(at.x, y + 1.13 * s, 0.6 * s), Vector3(width + 0.3 * s, 0.22 * s, 1.0 * s), Color.WHITE, Basis(), 0.04)
	g.box("trim", Vector3(at.x, y + 1.3 * s, 0.5 * s), Vector3(width + 0.2 * s, 0.14 * s, 0.85 * s), Color.WHITE, Basis(), 0.03)
	# Parapet with coping.
	g.box("terra", Vector3(at.x, at.y + 0.5 * s, -depth * 0.5 + 0.1), Vector3(width, 1.0 * s, 0.3))
	g.box("terra", Vector3(at.x, at.y + 0.5 * s, -0.05), Vector3(width, 1.0 * s, 0.3))
	g.box("trim", Vector3(at.x, at.y + 1.06 * s, -0.05), Vector3(width + 0.1, 0.14 * s, 0.42))


## A recessed opening's surround: jambs, sill and head as mouldings standing proud.
static func _surround(g: LandmarkGeo, c: Vector3, size: Vector2, z: float, key: String = "trim") -> void:
	var t := 0.22
	for sx: float in [-1.0, 1.0]:
		g.box(key, Vector3(c.x + sx * (size.x * 0.5 + t * 0.5), c.y, z), Vector3(t, size.y + t * 2.0, 0.18))
	g.box(key, Vector3(c.x, c.y - size.y * 0.5 - 0.12, z + 0.05), Vector3(size.x + 0.7, 0.16, 0.34))
	g.box(key, Vector3(c.x, c.y + size.y * 0.5 + 0.2, z + 0.04), Vector3(size.x + 0.6, 0.3, 0.3))
	# Glass and its frame, set back.
	g.box("sign", Vector3(c.x, c.y, z - 0.25), Vector3(size.x, size.y, 0.05), kc(Color.BLACK, K_GLASS))
	g.box("sign", Vector3(c.x, c.y, z - 0.2), Vector3(0.05, size.y, 0.06), kc(IRON, K_IRON))
	# Reveals.
	for sx: float in [-1.0, 1.0]:
		g.box(key, Vector3(c.x + sx * (size.x * 0.5 - 0.05), c.y, z - 0.12), Vector3(0.1, size.y, 0.26))


## An arched opening in the face plane z = zf, from y0 up to the spring line ys and a half round
## over it, `width` wide, its glass `depth` back - and the face round it out to the rectangle
## [x0, x1] x [y0, y1], so the caller gets a wall with a real hole in it.
static func _arched_wall(g: LandmarkGeo, key: String, zf: float, x0: float, x1: float, y0: float, y1: float,
		cx: float, width: float, sill: float, ys: float, depth: float) -> void:
	var r := width * 0.5
	var segs := 16
	var out := Vector3.BACK
	# Below the sill, left and right piers.
	g.quad(key, Vector3(x0, y0, zf), Vector3(x1, y0, zf), Vector3(x1, sill, zf), Vector3(x0, sill, zf), out,
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, sill), Vector2(x0, sill))
	g.quad(key, Vector3(x0, sill, zf), Vector3(cx - r, sill, zf), Vector3(cx - r, y1, zf), Vector3(x0, y1, zf), out,
		Vector2(x0, sill), Vector2(cx - r, sill), Vector2(cx - r, y1), Vector2(x0, y1))
	g.quad(key, Vector3(cx + r, sill, zf), Vector3(x1, sill, zf), Vector3(x1, y1, zf), Vector3(cx + r, y1, zf), out,
		Vector2(cx + r, sill), Vector2(x1, sill), Vector2(x1, y1), Vector2(cx + r, y1))
	# Spandrels over the arch, strip by strip.
	for i in segs:
		var a0 := PI - PI * float(i) / float(segs)
		var a1 := PI - PI * float(i + 1) / float(segs)
		var p0 := Vector2(cx + cos(a0) * r, ys + sin(a0) * r)
		var p1 := Vector2(cx + cos(a1) * r, ys + sin(a1) * r)
		g.quad(key, Vector3(p0.x, p0.y, zf), Vector3(p1.x, p1.y, zf), Vector3(p1.x, y1, zf), Vector3(p0.x, y1, zf), out,
			p0, p1, Vector2(p1.x, y1), Vector2(p0.x, y1))
		# The reveal round the arch.
		var n := Vector3(-cos((a0 + a1) * 0.5), -sin((a0 + a1) * 0.5), 0.0)
		g.quad(key, Vector3(p0.x, p0.y, zf), Vector3(p1.x, p1.y, zf), Vector3(p1.x, p1.y, zf - depth), Vector3(p0.x, p0.y, zf - depth), n,
			Vector2(0.0, p0.y), Vector2(depth, p1.y), Vector2(depth, p1.y), Vector2(0.0, p0.y))
		# Glass in the arch.
		g.tri("sign", Vector3(cx, ys, zf - depth), Vector3(p0.x, p0.y, zf - depth), Vector3(p1.x, p1.y, zf - depth), out,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, kc(Color.BLACK, K_GLASS))
		# The archivolt: a moulded band of voussoirs round it.
		var mid := (a0 + a1) * 0.5
		var vc := Vector3(cx + cos(mid) * (r + 0.32), ys + sin(mid) * (r + 0.32), zf + 0.12)
		var key_stone := i == segs / 2 or i == segs / 2 - 1
		var vs := Vector3(0.6 if not key_stone else 0.95, PI * r / float(segs) * 0.96, 0.26 if not key_stone else 0.42)
		g.box("trim", vc, vs, Color.WHITE, Basis(Vector3.BACK, mid))
	# Jamb reveals and the glass of the straight part, with mullions and transoms.
	for sx: float in [-1.0, 1.0]:
		g.quad(key, Vector3(cx + sx * r, sill, zf), Vector3(cx + sx * r, ys, zf), Vector3(cx + sx * r, ys, zf - depth), Vector3(cx + sx * r, sill, zf - depth),
			Vector3(-sx, 0.0, 0.0), Vector2(0.0, sill), Vector2(0.0, ys), Vector2(depth, ys), Vector2(depth, sill))
	g.quad(key, Vector3(cx - r, sill, zf), Vector3(cx + r, sill, zf), Vector3(cx + r, sill, zf - depth), Vector3(cx - r, sill, zf - depth), Vector3.UP,
		Vector2(cx - r, 0.0), Vector2(cx + r, 0.0), Vector2(cx + r, depth), Vector2(cx - r, depth))
	g.box("sign", Vector3(cx, (sill + ys) * 0.5, zf - depth), Vector3(width, ys - sill, 0.04), kc(Color.BLACK, K_GLASS))
	var cols := maxi(2, int(width / 1.2))
	for i in range(1, cols):
		var x := cx - r + width * float(i) / float(cols)
		var top := ys + sqrt(maxf(r * r - (x - cx) * (x - cx), 0.0))
		g.box("sign", Vector3(x, (sill + top) * 0.5, zf - depth + 0.05), Vector3(0.08, top - sill, 0.08), kc(IRON, K_IRON))
	var y := sill + 1.6
	while y < ys:
		g.box("sign", Vector3(cx, y, zf - depth + 0.05), Vector3(width, 0.08, 0.08), kc(IRON, K_IRON))
		y += 1.6
	# Sill moulding and the keystone's carved bracket.
	g.box("trim", Vector3(cx, sill - 0.1, zf + 0.15), Vector3(width + 1.0, 0.24, 0.42), Color.WHITE, Basis(), 0.04)


## Carved ornament: a cluster of small blocks round `c` in the face (a cartouche, a garland),
## seeded so each one differs.
static func _carving(g: LandmarkGeo, c: Vector3, size: Vector2, seed_value: int, key: String = "trim") -> void:
	var n := int(clampf(size.x * size.y * 4.0, 5.0, 26.0))
	for i in n:
		var hx := Broadway.h01([seed_value, "cv", i, 0]) - 0.5
		var hy := Broadway.h01([seed_value, "cv", i, 1]) - 0.5
		var s := 0.08 + 0.2 * Broadway.h01([seed_value, "cv", i, 2])
		# Mirror about the centre line: ornament is symmetric.
		for m: float in [-1.0, 1.0]:
			var p := Vector3(c.x + m * absf(hx) * size.x, c.y + hy * size.y, c.z + 0.05 + s * 0.4)
			g.box(key, p, Vector3(s * 1.3, s, s * 0.8), Color.WHITE, Basis(Vector3.BACK, hx * 2.0 * m))


## A column standing at `base` (shaft, base and capital), `h` tall.
static func _column(g: LandmarkGeo, base: Vector3, h: float, r: float) -> void:
	g.box("trim", base + Vector3(0.0, 0.25, 0.0), Vector3(r * 2.6, 0.5, r * 2.6), Color.WHITE, Basis(), 0.04)
	g.cylinder("trim", base + Vector3(0.0, 0.5, 0.0), r * 1.15, 0.25, 14)
	g.cylinder("trim", base + Vector3(0.0, 0.75, 0.0), r, h - 1.75, 14, Color.WHITE, r * 0.88, false, false)
	g.cylinder("trim", base + Vector3(0.0, h - 1.0, 0.0), r * 0.9, 0.2, 14, Color.WHITE, r * 1.2)
	g.box("trim", base + Vector3(0.0, h - 0.55, 0.0), Vector3(r * 2.4, 0.5, r * 2.4), Color.WHITE, Basis(Vector3.UP, PI * 0.25), 0.06)
	g.box("trim", base + Vector3(0.0, h - 0.15, 0.0), Vector3(r * 2.8, 0.3, r * 2.8), Color.WHITE, Basis(), 0.03)


## FRENCH: the pavilion's wall with a giant arched window between paired columns, side bays of
## windows with balconettes, the entablature, an attic, a balustrade with urns and a cartouche.
static func _french(g: LandmarkGeo, spec: Dictionary, tw: float, hc: float) -> void:
	var zf := 0.45
	var x0 := -tw * 0.5
	var x1 := tw * 0.5
	var y0 := STOREY_GROUND
	var ent := hc - 4.4
	var aw := clampf(tw * 0.36, 5.0, 9.0)
	var sill := MARQUEE_Y1 + 1.2
	var seed_value := hash(spec.id)
	var ys := maxf(ent - 1.0 - aw * 0.5, sill + 1.5)
	if ys + aw * 0.5 > ent - 0.5:
		aw = maxf(2.0 * (ent - 0.5 - ys), 2.0)
	_arched_wall(g, "terra", zf, x0, x1, y0, ent, 0.0, aw, sill, ys, 0.7)
	# The pavilion's returns and its body behind the face.
	for sx: float in [-1.0, 1.0]:
		g.box("terra", Vector3(sx * (tw * 0.5 - 0.3), (y0 + ent) * 0.5, -0.05), Vector3(0.6, ent - y0, 1.0))
	# Paired columns either side of the arch on a ledge.
	var cr := clampf(tw * 0.02, 0.32, 0.5)
	g.box("trim", Vector3(0.0, y0 + 0.35, zf + 0.35), Vector3(tw, 0.7, 0.9), Color.WHITE, Basis(), 0.05)
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var x := sx * (aw * 0.5 + 0.9 + float(k) * (cr * 2.0 + 0.6) + cr)
			_column(g, Vector3(x, y0 + 0.7, zf + cr + 0.15), ent - y0 - 0.7, cr)
		# Side bay windows, stacked, with surrounds and iron balconettes.
		var bx := sx * (aw * 0.5 + 0.9 + 2.0 * (cr * 2.0 + 0.6) + (tw * 0.5 - aw * 0.5 - 0.9 - 2.0 * (cr * 2.0 + 0.6)) * 0.5)
		var room := tw * 0.5 - (aw * 0.5 + 0.9 + 2.0 * (cr * 2.0 + 0.6))
		if room > 1.6:
			var y := sill + 0.4
			while y + 2.4 < ent - 0.6:
				_surround(g, Vector3(bx, y + 1.1, zf + 0.05), Vector2(minf(room - 0.8, 1.4), 2.0), zf + 0.05)
				g.box("sign", Vector3(bx, y - 0.05, zf + 0.35), Vector3(minf(room - 0.4, 1.8), 0.06, 0.5), kc(IRON, K_IRON))
				for b in 6:
					g.box("sign", Vector3(bx - 0.7 + float(b) * 0.28, y + 0.35, zf + 0.58), Vector3(0.03, 0.7, 0.03), kc(IRON, K_IRON))
				g.box("sign", Vector3(bx, y + 0.72, zf + 0.58), Vector3(minf(room - 0.4, 1.8), 0.05, 0.05), kc(IRON, K_IRON))
				y += 3.4
	# A cartouche over the arch's keystone.
	_carving(g, Vector3(0.0, ys + aw * 0.5 + 0.9, zf), Vector2(2.4, 1.2), seed_value)
	# Entablature: architrave, frieze (carved garlands), cornice.
	g.box("trim", Vector3(0.0, ent + 0.25, zf + 0.25), Vector3(tw + 0.2, 0.5, 0.6), Color.WHITE, Basis(), 0.04)
	g.box("terra", Vector3(0.0, ent + 1.0, zf + 0.12), Vector3(tw, 1.0, 0.4))
	for i in int(tw / 3.0):
		_carving(g, Vector3(x0 + 1.5 + float(i) * 3.0, ent + 1.0, zf + 0.3), Vector2(1.6, 0.6), seed_value + i)
	_cornice(g, Vector3(0.0, ent + 3.0, zf), tw + 0.4, 10.0, 1.15)
	# Attic: low wall with small square windows, a balustrade with urns, the crest.
	var at := ent + 3.0
	g.box("terra", Vector3(0.0, at + 0.6, -0.2), Vector3(tw - 0.6, 1.2, 0.5))
	var nb := int(tw / 0.42)
	for i in nb:
		var x := x0 + 0.5 + float(i) * (tw - 1.0) / float(nb - 1)
		g.cylinder("trim", Vector3(x, at + 1.2, 0.05), 0.11, 0.75, 6, Color.WHITE, 0.07)
	g.box("trim", Vector3(0.0, at + 2.05, 0.05), Vector3(tw - 0.4, 0.18, 0.4))
	for sx: float in [-1.0, 1.0]:
		g.box("trim", Vector3(sx * (tw * 0.5 - 0.5), at + 1.6, 0.05), Vector3(0.6, 1.0, 0.6))
		g.cylinder("trim", Vector3(sx * (tw * 0.5 - 0.5), at + 2.1, 0.05), 0.18, 0.2, 10, Color.WHITE, 0.32)
		g.cylinder("trim", Vector3(sx * (tw * 0.5 - 0.5), at + 2.3, 0.05), 0.32, 0.45, 10, Color.WHITE, 0.12)
	# The crest: a raised panel with a carved shell.
	g.box("terra", Vector3(0.0, at + 2.6, 0.0), Vector3(minf(tw * 0.4, 7.0), 2.0, 0.5))
	_carving(g, Vector3(0.0, at + 2.8, 0.25), Vector2(minf(tw * 0.35, 6.0), 1.4), seed_value + 99)
	g.box("trim", Vector3(0.0, at + 3.65, 0.05), Vector3(minf(tw * 0.42, 7.4), 0.2, 0.7))


## SPANISH: the churrigueresque frontispiece on the office shaft - estipite pilasters, nested
## carved frames round a central arched window, a crest of scrolls and finials - with Gothic
## piers up the shaft ending in pinnacles past the parapet.
static func _spanish(g: LandmarkGeo, spec: Dictionary, w: float, tw: float, hc: float) -> void:
	var zf := 0.0
	var seed_value := hash(spec.id)
	var fw := clampf(tw * 0.55, 8.0, 14.0)
	var top := minf(hc - 6.0, 26.0)
	var y0 := MARQUEE_Y1 + 0.6
	var aw := minf(fw * 0.42, 5.2)
	var ys := top - 3.6 - aw * 0.5
	var hx := aw * 0.5 + 0.6
	var hy0 := y0 + 1.0
	var hy1 := ys + aw * 0.5 + 0.6
	# The frontispiece's field, standing proud of the shaft, round the arched window's wall.
	for sx: float in [-1.0, 1.0]:
		g.box("terra", Vector3(sx * (hx + fw * 0.5) * 0.5, (STOREY_GROUND + top) * 0.5, 0.25), Vector3(fw * 0.5 - hx, top - STOREY_GROUND, 0.5))
	g.box("terra", Vector3(0.0, (STOREY_GROUND + hy0) * 0.5, 0.25), Vector3(hx * 2.0, hy0 - STOREY_GROUND, 0.5))
	g.box("terra", Vector3(0.0, (hy1 + top) * 0.5, 0.25), Vector3(hx * 2.0, top - hy1, 0.5))
	# Three nested frames, each further out.
	for k in 3:
		var fx := fw * 0.5 - 0.6 - float(k) * 0.7
		var fz := 0.55 + float(k) * 0.12
		for sx: float in [-1.0, 1.0]:
			g.box("trim", Vector3(sx * fx, (y0 + top - 1.0) * 0.5, fz), Vector3(0.28, top - 1.0 - y0, 0.24), Color.WHITE, Basis(), 0.04)
		g.box("trim", Vector3(0.0, top - 1.0 - float(k) * 0.5, fz), Vector3(fx * 2.0 + 0.28, 0.3, 0.24), Color.WHITE, Basis(), 0.04)
	# Estipites: stacked base, inverted taper, cube, capital, up each side.
	for sx: float in [-1.0, 1.0]:
		var x := sx * (fw * 0.5 + 0.55)
		var y := y0
		while y + 3.6 < top:
			g.box("trim", Vector3(x, y + 0.3, 0.6), Vector3(0.9, 0.6, 0.9), Color.WHITE, Basis(), 0.06)
			g.cylinder("trim", Vector3(x, y + 0.6, 0.6), 0.22, 1.6, 4, Color.WHITE, 0.48)
			g.box("trim", Vector3(x, y + 2.5, 0.6), Vector3(0.8, 0.6, 0.8), Color.WHITE, Basis(Vector3.UP, PI * 0.25), 0.08)
			g.box("trim", Vector3(x, y + 3.0, 0.6), Vector3(1.0, 0.3, 1.0), Color.WHITE, Basis(), 0.04)
			y += 3.6
	# The central arched window and the carving that crowds round it.
	_arched_wall(g, "terra", 0.5, -hx, hx, hy0, hy1, 0.0, aw, y0 + 1.6, ys, 0.55)
	_carving(g, Vector3(0.0, ys + aw * 0.5 + 1.4, 0.6), Vector2(fw * 0.7, 1.6), seed_value)
	_carving(g, Vector3(0.0, y0 + 0.8, 0.6), Vector2(fw * 0.6, 1.0), seed_value + 7)
	for sx: float in [-1.0, 1.0]:
		_carving(g, Vector3(sx * (aw * 0.5 + 1.4), (y0 + top) * 0.5, 0.6), Vector2(0.9, top - y0 - 4.0), seed_value + 13 + int(sx))
	# Crest: scrolls in an arc and three finials.
	for i in 9:
		var a := PI * float(i) / 8.0
		var p := Vector3(cos(a) * fw * 0.36, top + sin(a) * 1.8, 0.4)
		g.box("trim", p, Vector3(0.7, 0.5, 0.5), Color.WHITE, Basis(Vector3.BACK, a), 0.12)
	for x: float in [-fw * 0.36, 0.0, fw * 0.36]:
		g.cylinder("trim", Vector3(x, top + (2.0 if x == 0.0 else 0.3), 0.4), 0.3, 1.2, 8, Color.WHITE, 0.05)
	# Gothic piers up the whole shaft, each ending in a pinnacle past the parapet.
	var npier := maxi(2, int(w / 5.6))
	for i in npier + 1:
		var x := -w * 0.5 + 0.4 + float(i) * (w - 0.8) / float(npier)
		if absf(x) < fw * 0.5 + 1.4:
			continue
		g.box("trim", Vector3(x, (STOREY_GROUND + hc) * 0.5, 0.18), Vector3(0.55, hc - STOREY_GROUND, 0.36))
		g.box("trim", Vector3(x, hc + 0.8, 0.1), Vector3(0.7, 1.6, 0.7))
		g.cylinder("trim", Vector3(x, hc + 1.6, 0.1), 0.38, 2.6, 4, Color.WHITE, 0.02)
	# A clay-tiled eave along the top, Spanish fashion.
	g.box("trim", Vector3(0.0, hc - 0.3, 0.45), Vector3(w + 0.6, 0.35, 1.1), Color(0.75, 0.42, 0.30), Basis(), 0.05)
	g.box("terra", Vector3(0.0, hc + 0.5, -0.1), Vector3(w, 1.0, 0.3))


## DECO: fluted fins up the pavilion stepping above the parapet, chevron spandrels between them,
## speed lines across, a stepped central pylon.
static func _deco(g: LandmarkGeo, spec: Dictionary, tw: float, hc: float) -> void:
	var zf := 0.3
	var y0 := STOREY_GROUND
	g.box("terra", Vector3(0.0, (y0 + hc) * 0.5, -0.1), Vector3(tw, hc - y0, 0.8))
	var nf := maxi(5, int(tw / 2.2) | 1)
	for i in nf:
		var t := float(i) / float(nf - 1)
		var x := lerpf(-tw * 0.5 + 0.4, tw * 0.5 - 0.4, t)
		var mid := 1.0 - absf(t - 0.5) * 2.0
		var fh := hc + 1.0 + mid * mid * 6.0
		g.box("trim", Vector3(x, (y0 + fh) * 0.5, zf + 0.25), Vector3(0.5, fh - y0, 0.5), Color.WHITE, Basis(), 0.08)
		# Flutes: a darker groove down the fin's face.
		g.box("sign", Vector3(x, (y0 + fh) * 0.5, zf + 0.505), Vector3(0.08, fh - y0 - 1.0, 0.01), kc(Color(0.52, 0.48, 0.34), K_ENAMEL))
		if i < nf - 1:
			var x2 := lerpf(-tw * 0.5 + 0.4, tw * 0.5 - 0.4, float(i + 1) / float(nf - 1))
			var cx := (x + x2) * 0.5
			var bw := x2 - x - 0.5
			# Chevron spandrels between the windows, one per storey.
			var y := MARQUEE_Y1 + 1.0
			while y + 3.0 < hc - 1.0:
				g.box("sign", Vector3(cx, y + 1.3, zf - 0.05), Vector3(bw - 0.2, 2.2, 0.04), kc(Color.BLACK, K_GLASS))
				for c in 3:
					var cy := y + 2.7 + float(c) * 0.18
					for sx: float in [-1.0, 1.0]:
						g.box("trim", Vector3(cx + sx * bw * 0.22, cy, zf + 0.05), Vector3(bw * 0.5, 0.08, 0.1), Color(0.72, 0.62, 0.38), Basis(Vector3.BACK, sx * 0.45))
				y += 3.4
	# Speed lines across the base and a band over the top.
	for k in 3:
		g.box("trim", Vector3(0.0, y0 + 0.3 + float(k) * 0.3, zf + 0.2), Vector3(tw, 0.08, 0.2))
	g.box("trim", Vector3(0.0, hc - 0.3, zf + 0.15), Vector3(tw + 0.2, 0.6, 0.5), Color(0.72, 0.62, 0.38), Basis(), 0.05)
	# The central pylon, stepped.
	for k in 3:
		g.box("trim", Vector3(0.0, hc + 2.0 + float(k) * 2.4, 0.2 - float(k) * 0.3), Vector3(3.6 - float(k) * 1.0, 2.4, 1.4 - float(k) * 0.3), Color.WHITE, Basis(), 0.06)


## A clock tower over the pavilion: a square shaft, a clock face each side, a dome and spire.
static func _clock_tower(g: LandmarkGeo, spec: Dictionary, hc: float, h: float) -> void:
	var s := 5.0
	var y0 := hc - 0.5
	var c := Vector3(0.0, 0.0, -s * 0.5 - 0.5)
	g.box("terra", Vector3(c.x, y0 + h * 0.5, c.z), Vector3(s, h, s))
	g.box("trim", Vector3(c.x, y0 + h - 0.4, c.z), Vector3(s + 0.6, 0.6, s + 0.6), Color.WHITE, Basis(), 0.05)
	g.box("trim", Vector3(c.x, y0 + 0.3, c.z), Vector3(s + 0.4, 0.6, s + 0.4))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.box("trim", Vector3(c.x + sx * (s * 0.5 - 0.2), y0 + h * 0.5, c.z + sz * (s * 0.5 - 0.2)), Vector3(0.6, h, 0.6))
	# Clock faces (BroadwayStreet's face material, its hands following the hour).
	var faces := [[Vector3(0, 0, 1), 0.0], [Vector3(1, 0, 0), PI * 0.5], [Vector3(0, 0, -1), PI], [Vector3(-1, 0, 0), -PI * 0.5]]
	if not g.has("clock"):
		g.use("clock", BroadwayStreet.clock_material())
	for fc: Array in faces:
		var n: Vector3 = fc[0]
		var b := Basis(Vector3.UP, float(fc[1]))
		var at := c + Vector3(0.0, y0 + h * 0.62, 0.0) + n * (s * 0.5 + 0.06)
		_disc(g, "clock", at, b, 1.6)
		_ring(g, at + n * 0.05, b, 1.6, 1.85, Color.WHITE, "trim")
	g.dome("terra", Vector2(c.x, c.z), Vector2(s * 0.52, s * 0.52), y0 + h, 2.4, 16, 4)
	g.cylinder("sign", Vector3(c.x, y0 + h + 2.2, c.z), 0.25, 3.5, 8, kc(BRASS, K_BRASS), 0.02)


## A clock face disc of radius r at `at` facing basis z (UV 0..1 across the dial).
static func _disc(g: LandmarkGeo, key: String, at: Vector3, b: Basis, r: float) -> void:
	var segs := 24
	var n := b.z
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector2(cos(a0), sin(a0))
		var p1 := Vector2(cos(a1), sin(a1))
		g.tri(key, at, at + b * Vector3(p0.x * r, p0.y * r, 0.0), at + b * Vector3(p1.x * r, p1.y * r, 0.0), n,
			Vector2(0.5, 0.5), Vector2(0.5 + p0.x * 0.5, 0.5 - p0.y * 0.5), Vector2(0.5 + p1.x * 0.5, 0.5 - p1.y * 0.5))


static func _ring(g: LandmarkGeo, at: Vector3, b: Basis, r0: float, r1: float, col: Color, key: String) -> void:
	var segs := 24
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var q := [Vector3(cos(a0) * r0, sin(a0) * r0, 0), Vector3(cos(a0) * r1, sin(a0) * r1, 0), Vector3(cos(a1) * r1, sin(a1) * r1, 0), Vector3(cos(a1) * r0, sin(a1) * r0, 0)]
		g.quad(key, at + b * (q[0] as Vector3), at + b * (q[1] as Vector3), at + b * (q[2] as Vector3), at + b * (q[3] as Vector3), b.z,
			Vector2(a0, 0), Vector2(a0, 1), Vector2(a1, 1), Vector2(a1, 0), col)
		# Its rim.
		g.quad(key, at + b * (q[1] as Vector3), at + b * (q[2] as Vector3), at + b * ((q[2] as Vector3) - Vector3(0, 0, 0.12)), at + b * ((q[1] as Vector3) - Vector3(0, 0, 0.12)),
			b * Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0.0), Vector2(a0, 0), Vector2(a1, 0), Vector2(a1, 1), Vector2(a0, 1), col)


## A rooftop sign: the name in big lit letters on an iron lattice along the roof edge.
static func _roof_sign(g: LandmarkGeo, spec: Dictionary, w: float, hc: float) -> void:
	var name: String = spec.name
	var lh := 3.2
	var y := hc + 1.4
	var width := minf(w - 2.0, float(name.length()) * lh * 0.72)
	for i in 5:
		var x := -width * 0.5 + width * float(i) / 4.0
		g.box("sign", Vector3(x, y + lh * 0.5 + 0.3, -1.2), Vector3(0.14, lh + 1.6, 0.14), kc(IRON, K_IRON))
		g.box("sign", Vector3(x, y + lh * 0.5, -2.4), Vector3(0.1, lh + 1.0, 2.4), kc(IRON, K_IRON), Basis(Vector3.RIGHT, 0.5))
	for yy: float in [y, y + lh + 0.2]:
		g.box("sign", Vector3(0.0, yy, -1.2), Vector3(width, 0.12, 0.12), kc(IRON, K_IRON))
	text(g, name, Transform3D(Basis(), Vector3(0.0, y + lh * 0.5 + 0.1, -1.05)), lh * 1.25, width, kc(spec.letters, K_LETTERS), Vector3.BACK, true)


## The auditorium behind the front building and the fly tower over its stage end.
static func _auditorium(g: LandmarkGeo, w: float, d: float, fd: float, ha: float) -> void:
	var depth := d - fd
	if depth < 4.0:
		return
	var aw := w - 1.0
	g.box("brick", Vector3(0.0, ha * 0.5, -fd - depth * 0.5), Vector3(aw, ha, depth))
	var fly := minf(14.0, depth * 0.4)
	g.box("brick", Vector3(0.0, (ha + 9.0) * 0.5, -d + fly * 0.5 + 0.5), Vector3(aw * 0.72, ha + 9.0, fly))
	g.box("roof", Vector3(0.0, ha + 0.05, -fd - depth * 0.5), Vector3(aw - 0.4, 0.1, depth - 0.4))
	g.box("roof", Vector3(0.0, ha + 9.05, -d + fly * 0.5 + 0.5), Vector3(aw * 0.72 - 0.4, 0.1, fly - 0.4))
	# Coping and a few vents on the roof.
	g.box("trim", Vector3(0.0, ha + 0.3, -fd - depth * 0.5), Vector3(aw + 0.2, 0.2, 0.4))
	for i in 3:
		g.box("roof", Vector3(-aw * 0.3 + float(i) * aw * 0.3, ha + 0.8, -fd - depth * 0.35), Vector3(1.6, 1.4, 1.6))


# --- The street front ------------------------------------------------------------------------

## The entrance: a recess under the marquee with terrazzo, glass doors in brass, lit poster
## cases on its walls, a bulb soffit, the ticket booth in its mouth; terrazzo out to the kerb
## side of the marquee.
static func _entrance(g: LandmarkGeo, spec: Dictionary, tw: float, marquee_l: float) -> void:
	var ew := entrance_width(tw)
	var r := RECESS
	var h := MARQUEE_Y0 - 0.1
	var tz: Array = spec.terrazzo
	var tcol: Color = tz[0]
	# Side walls of the recess (terracotta), their poster cases, the ceiling.
	for sx: float in [-1.0, 1.0]:
		g.box("trim", Vector3(sx * (ew * 0.5 + 0.4), STOREY_GROUND * 0.5, -r * 0.5), Vector3(0.8, STOREY_GROUND, r + 0.4))
		for k in 2:
			var z := -r * 0.25 - float(k) * r * 0.45
			g.box("sign", Vector3(sx * (ew * 0.5 - 0.02), 2.0, z), Vector3(0.06, 2.0, 1.4), kc(BRASS, K_BRASS))
			g.quad("sign", Vector3(sx * (ew * 0.5 - 0.06), 1.1, z - 0.6), Vector3(sx * (ew * 0.5 - 0.06), 1.1, z + 0.6),
				Vector3(sx * (ew * 0.5 - 0.06), 2.9, z + 0.6), Vector3(sx * (ew * 0.5 - 0.06), 2.9, z - 0.6), Vector3(-sx, 0, 0),
				Vector2(float(k) * 1.3, 0.0), Vector2(float(k) * 1.3 + 1.2, 0.0), Vector2(float(k) * 1.3 + 1.2, 1.8), Vector2(float(k) * 1.3, 1.8), kc(Color.WHITE, K_POSTER))
		# A pier on the facade line either side of the opening, with a poster case on its face.
		g.box("trim", Vector3(sx * (ew * 0.5 + 0.9), STOREY_GROUND * 0.5, 0.1), Vector3(1.8, STOREY_GROUND, 0.6), Color.WHITE, Basis(), 0.05)
		g.box("sign", Vector3(sx * (ew * 0.5 + 0.9), 2.1, 0.42), Vector3(1.4, 2.1, 0.06), kc(BRASS, K_BRASS))
		g.quad("sign", Vector3(sx * (ew * 0.5 + 0.9) - 0.6, 1.15, 0.46), Vector3(sx * (ew * 0.5 + 0.9) + 0.6, 1.15, 0.46),
			Vector3(sx * (ew * 0.5 + 0.9) + 0.6, 3.05, 0.46), Vector3(sx * (ew * 0.5 + 0.9) - 0.6, 3.05, 0.46), Vector3.BACK,
			Vector2(2.6 + sx, 0.0), Vector2(3.8 + sx, 0.0), Vector2(3.8 + sx, 1.9), Vector2(2.6 + sx, 1.9), kc(Color.WHITE, K_POSTER))
	g.quad("sign", Vector3(-ew * 0.5, h, -r), Vector3(ew * 0.5, h, -r), Vector3(ew * 0.5, h, 0.0), Vector3(-ew * 0.5, h, 0.0), Vector3.DOWN,
		Vector2(-ew * 0.5, -r), Vector2(ew * 0.5, -r), Vector2(ew * 0.5, 0.0), Vector2(-ew * 0.5, 0.0), kc(Color(0.82, 0.70, 0.42), K_SOFFIT))
	# The doors at the back: a row of glazed leaves in brass frames, transoms over them.
	var nd := maxi(4, int(ew / 1.2))
	var dw := ew / float(nd)
	g.box("trim", Vector3(0.0, (h + 2.7) * 0.5 + 0.6, -r - 0.1), Vector3(ew, h - 2.7, 0.3))
	for i in nd:
		var x := -ew * 0.5 + (float(i) + 0.5) * dw
		g.box("sign", Vector3(x, 1.25, -r), Vector3(dw - 0.12, 2.5, 0.05), kc(Color.BLACK, K_GLASS))
		g.box("sign", Vector3(x, 2.85, -r), Vector3(dw - 0.12, 0.5, 0.05), kc(Color.BLACK, K_GLASS))
		g.box("sign", Vector3(x - dw * 0.5 + 0.03, 1.6, -r + 0.03), Vector3(0.08, 3.2, 0.09), kc(BRASS, K_BRASS))
		g.box("sign", Vector3(x, 0.1, -r + 0.03), Vector3(dw - 0.1, 0.2, 0.09), kc(BRASS, K_BRASS))
		g.box("sign", Vector3(x, 2.55, -r + 0.03), Vector3(dw - 0.1, 0.1, 0.09), kc(BRASS, K_BRASS))
		g.box("sign", Vector3(x + dw * 0.32 * (1.0 if i % 2 == 0 else -1.0), 1.15, -r + 0.12), Vector3(0.05, 0.6, 0.05), kc(BRASS, K_BRASS))
	# Terrazzo from the doors out past the marquee's edge.
	var tw2 := ew + 3.6
	g.quad("sign", Vector3(-ew * 0.5, 0.012, -r), Vector3(ew * 0.5, 0.012, -r), Vector3(ew * 0.5, 0.012, 0.0), Vector3(-ew * 0.5, 0.012, 0.0), Vector3.UP,
		Vector2(-ew * 0.5, -r), Vector2(ew * 0.5, -r), Vector2(ew * 0.5, 0.0), Vector2(-ew * 0.5, 0.0), kc(tcol, K_TERRAZZO))
	g.quad("sign", Vector3(-tw2 * 0.5, 0.012, 0.0), Vector3(tw2 * 0.5, 0.012, 0.0), Vector3(tw2 * 0.5, 0.012, marquee_l), Vector3(-tw2 * 0.5, 0.012, marquee_l), Vector3.UP,
		Vector2(-tw2 * 0.5, 0.0), Vector2(tw2 * 0.5, 0.0), Vector2(tw2 * 0.5, marquee_l), Vector2(-tw2 * 0.5, marquee_l), kc(tcol, K_TERRAZZO))
	# The palace's name inlaid in brass at the threshold.
	text(g, spec.name, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.016, marquee_l - 0.7)), 0.45, ew, kc(BRASS, K_BRASS), Vector3.UP)
	_booth(g, Vector3(0.0, 0.0, 0.4))


## The ticket booth: a polygonal glazed kiosk on a base, brass trim, a domed cap with bulbs.
static func _booth(g: LandmarkGeo, at: Vector3) -> void:
	var r := 0.85
	var c := Vector2(at.x, at.z)
	g.band("sign", c, Vector2(r, r), Vector2(r, r), 0.0, 1.0, 0.0, TAU, 8, kc(Color(0.45, 0.10, 0.08), K_ENAMEL))
	g.band("sign", c, Vector2(r + 0.04, r + 0.04), Vector2(r + 0.04, r + 0.04), 1.0, 1.1, 0.0, TAU, 8, kc(BRASS, K_BRASS))
	g.band("sign", c, Vector2(r - 0.05, r - 0.05), Vector2(r - 0.05, r - 0.05), 1.1, 2.25, 0.0, TAU, 8, kc(Color.BLACK, K_GLASS))
	for i in 8:
		var a := TAU * float(i) / 8.0
		g.box("sign", Vector3(at.x + cos(a) * (r - 0.03), 1.67, at.z + sin(a) * (r - 0.03)), Vector3(0.05, 1.15, 0.05), kc(BRASS, K_BRASS))
	g.band("sign", c, Vector2(r + 0.12, r + 0.12), Vector2(r + 0.12, r + 0.12), 2.25, 2.45, 0.0, TAU, 8, kc(Color(0.45, 0.10, 0.08), K_ENAMEL))
	g.ring_flat("sign", c, Vector2(0.0, 0.0), Vector2(r + 0.12, r + 0.12), 2.25, 0.0, TAU, 8, kc(BRASS, K_BRASS), false, true)
	g.dome("sign", c, Vector2(r + 0.12, r + 0.12), 2.45, 0.55, 8, 3, kc(Color(0.75, 0.58, 0.28), K_BRASS))
	g.cylinder("sign", Vector3(at.x, 3.0, at.z), 0.05, 0.35, 6, kc(BRASS, K_BRASS), 0.01)
	# A band of bulbs round the cap.
	var u := 0.0
	for i in 8:
		var a0 := TAU * float(i) / 8.0
		var a1 := TAU * float(i + 1) / 8.0
		var p0 := Vector3(at.x + cos(a0) * (r + 0.13), 0.0, at.z + sin(a0) * (r + 0.13))
		var p1 := Vector3(at.x + cos(a1) * (r + 0.13), 0.0, at.z + sin(a1) * (r + 0.13))
		var n := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		var l := p0.distance_to(p1)
		g.quad("sign", p0 + Vector3(0, 2.27, 0), p1 + Vector3(0, 2.27, 0), p1 + Vector3(0, 2.43, 0), p0 + Vector3(0, 2.43, 0), n,
			Vector2(u, 0), Vector2(u + l, 0), Vector2(u + l, 1), Vector2(u, 1), kc(Color(0.45, 0.10, 0.08), K_BULBS))
		u += l
	# The speaking grille and the slot.
	g.box("sign", Vector3(at.x, 1.35, at.z + r - 0.02), Vector3(0.36, 0.06, 0.08), kc(BRASS, K_BRASS))


## The marquee's plan: a polyline from the facade round the front and back, in (x, z).
static func marquee_plan(kind: String, mw: float, l: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var z0 := 0.35
	match kind:
		"v":
			pts.append(Vector2(-mw * 0.5, z0))
			pts.append(Vector2(-mw * 0.5, l - 1.6))
			pts.append(Vector2(0.0, l))
			pts.append(Vector2(mw * 0.5, l - 1.6))
			pts.append(Vector2(mw * 0.5, z0))
		"round":
			pts.append(Vector2(-mw * 0.5, z0))
			var rz := l - z0
			for i in 9:
				var a := PI - PI * float(i) / 8.0
				pts.append(Vector2(cos(a) * mw * 0.5, z0 + sin(a) * rz))
			pts.append(Vector2(mw * 0.5, z0))
		_:
			pts.append(Vector2(-mw * 0.5, z0))
			pts.append(Vector2(-mw * 0.5, l))
			pts.append(Vector2(mw * 0.5, l))
			pts.append(Vector2(mw * 0.5, z0))
	return pts


## The marquee: board faces round its plan between bulb rows, a fascia and neon on top, the
## soffit of bulbs under it, the crest with the name, tie rods to the facade.
static func _marquee(g: LandmarkGeo, spec: Dictionary, tw: float, l: float) -> void:
	var mw := minf(tw - 1.0, entrance_width(tw) + 6.0)
	var pts := marquee_plan(str(spec.marquee), mw, l)
	var enamel: Color = spec.enamel
	var neon: Color = spec.neon
	var y0 := MARQUEE_Y0
	var y1 := MARQUEE_Y1
	var titles: Array = spec.titles
	var u := 0.0
	var nseg := pts.size() - 1
	# Which segments face the street most (the front lines go there).
	var front := []
	for i in nseg:
		var d := pts[i + 1] - pts[i]
		var n := Vector2(d.y, -d.x).normalized()
		if n.y < 0.0:
			n = -n
		front.append(n.y > 0.7)
	for i in nseg:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var len := d.length()
		var n2 := Vector2(d.y, -d.x).normalized()
		# Outward is away from the plan's centroid.
		var mid := (a + b) * 0.5
		var cen := Vector2(0.0, l * 0.45)
		if (mid - cen).dot(n2) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, 0.0, n2.y)
		var A := Vector3(a.x, 0.0, a.y)
		var B := Vector3(b.x, 0.0, b.y)
		var o := n * 0.01
		# Body (enamel, the full height) and its back face.
		g.quad("sign", A + Vector3(0, y0, 0), B + Vector3(0, y0, 0), B + Vector3(0, y1, 0), A + Vector3(0, y1, 0), n,
			Vector2(u, y0), Vector2(u + len, y0), Vector2(u + len, y1), Vector2(u, y1), kc(enamel, K_ENAMEL))
		# Bulb rows above and below the board, the board between.
		for band: Array in [[y0 + 0.1, y0 + 0.3, K_BULBS], [y0 + 0.4, y1 - 0.75, K_BOARD], [y1 - 0.65, y1 - 0.45, K_BULBS]]:
			var b0: float = band[0]
			var b1: float = band[1]
			var kind: int = band[2]
			var ua := Vector2(u, 0.0) if kind == K_BULBS else Vector2(u, b0)
			var ub := Vector2(u + len, 0.0) if kind == K_BULBS else Vector2(u + len, b0)
			var uc := Vector2(u + len, 1.0) if kind == K_BULBS else Vector2(u + len, b1)
			var ud := Vector2(u, 1.0) if kind == K_BULBS else Vector2(u, b1)
			var ins := 0.06 if len > 0.5 else 0.0
			var da := d.normalized() * ins
			var A2 := A + Vector3(da.x, 0, da.y)
			var B2 := B - Vector3(da.x, 0, da.y)
			g.quad("sign", A2 + Vector3(0, b0, 0) + o, B2 + Vector3(0, b0, 0) + o, B2 + Vector3(0, b1, 0) + o, A2 + Vector3(0, b1, 0) + o, n,
				ua, ub, uc, ud, kc(enamel.darkened(0.3), kind))
		# The fascia over it, neon along its top edge.
		g.quad("sign", A + Vector3(0, y1 - 0.4, 0) + o, B + Vector3(0, y1 - 0.4, 0) + o, B + Vector3(0, y1 - 0.06, 0) + o, A + Vector3(0, y1 - 0.06, 0) + o, n,
			Vector2(u, 0), Vector2(u + len, 0), Vector2(u + len, 1), Vector2(u, 1), kc(enamel.lightened(0.15), K_ENAMEL))
		var mid3 := (A + B) * 0.5 + Vector3(0.0, y1 + 0.06, 0.0) + n * 0.05
		g.box("sign", mid3, Vector3(len, 0.07, 0.07), kc(neon, K_NEON), Basis(Vector3.UP, atan2(-d.y, d.x)))
		g.box("sign", (A + B) * 0.5 + Vector3(0.0, y0 + 0.02, 0.0) + n * 0.05, Vector3(len, 0.06, 0.06), kc(neon, K_NEON), Basis(Vector3.UP, atan2(-d.y, d.x)))
		# Letters on the board: three lines on a front segment, two on a side.
		if len > 1.5:
			var lines: Array = []
			if front[i]:
				lines = [titles[0], titles[1], titles[2]]
			else:
				lines = [spec.name, titles[3]]
			var row_h := ((y1 - 0.75) - (y0 + 0.4)) / float(lines.size())
			for li in lines.size():
				var yy := y1 - 0.75 - row_h * (float(li) + 0.5)
				var basis := Basis(Vector3.UP, atan2(n.x, n.z))
				text(g, lines[li], Transform3D(basis, (A + B) * 0.5 + Vector3(0.0, yy, 0.0) + n * 0.03), row_h * 1.05, len - 0.6, kc(Color.BLACK, K_TYPE), n)
		u += len
	# Soffit and roof.
	var poly := PackedVector2Array(pts)
	poly.append(Vector2(pts[pts.size() - 1].x, 0.0))
	poly.append(Vector2(pts[0].x, 0.0))
	var p := LandmarkGeo.ccw(poly)
	var idx := Geometry2D.triangulate_polygon(p)
	for t in range(0, idx.size(), 3):
		var a := p[idx[t]]
		var b := p[idx[t + 1]]
		var c := p[idx[t + 2]]
		g.tri("sign", Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y), Vector3.DOWN, a, b, c, kc(Color(0.85, 0.72, 0.42), K_SOFFIT))
		g.tri("sign", Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(c.x, y1, c.y), Vector3.UP, a, b, c, kc(Color(0.2, 0.2, 0.2), K_IRON))
	# The crest: a raised panel with the name in lit letters, over the front.
	var crest_w := minf(mw * 0.8, float(str(spec.name).length()) * 0.75 + 1.4)
	var cz := l - (1.6 if str(spec.marquee) == "v" else 0.0) - 0.3
	if str(spec.marquee) == "v":
		cz = l - 1.9
	g.box("sign", Vector3(0.0, y1 + 0.75, cz), Vector3(crest_w, 1.3, 0.25), kc(enamel, K_ENAMEL), Basis(), 0.04)
	g.quad("sign", Vector3(-crest_w * 0.5 + 0.05, y1 + 0.12, cz + 0.13), Vector3(crest_w * 0.5 - 0.05, y1 + 0.12, cz + 0.13),
		Vector3(crest_w * 0.5 - 0.05, y1 + 0.28, cz + 0.13), Vector3(-crest_w * 0.5 + 0.05, y1 + 0.28, cz + 0.13), Vector3.BACK,
		Vector2(0, 0), Vector2(crest_w, 0), Vector2(crest_w, 1), Vector2(0, 1), kc(enamel.darkened(0.3), K_BULBS))
	text(g, spec.name, Transform3D(Basis(), Vector3(0.0, y1 + 0.85, cz + 0.14)), 0.85, crest_w - 0.5, kc(spec.letters, K_LETTERS), Vector3.BACK, true)
	for sx: float in [-1.0, 1.0]:
		g.box("sign", Vector3(sx * crest_w * 0.5, y1 + 0.75, cz + 0.05), Vector3(0.08, 1.3, 0.08), kc(neon, K_NEON))
	# Tie rods from the front corners up to the facade.
	for sx: float in [-1.0, 1.0]:
		var a := Vector3(sx * mw * 0.42, y1, l * 0.8)
		var b := Vector3(sx * mw * 0.42, y1 + 4.5, 0.2)
		_rod(g, a, b, 0.06)


static func _rod(g: LandmarkGeo, a: Vector3, b: Vector3, t: float) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	g.box("sign", (a + b) * 0.5, Vector3(t, d.length(), t), kc(IRON, K_IRON), Basis(x, y, z))


## The blade sign: an enamel slab standing out from the facade over the marquee, the name in
## stacked bulb letters on both faces, bulb borders, a neon outline, a pointed foot, a crown,
## brackets to the wall.
static func _blade_sign(g: LandmarkGeo, spec: Dictionary, sh: float, reach: float, hc: float) -> void:
	var bw := clampf(reach, 2.0, 3.0)
	var t := 0.62
	var z0 := 0.55
	var z1 := z0 + bw
	var y0 := SIGN_Y0
	var y1 := y0 + sh
	var enamel: Color = spec.enamel
	var neon: Color = spec.neon
	var zc := (z0 + z1) * 0.5
	g.box("sign", Vector3(0.0, (y0 + y1) * 0.5, zc), Vector3(t, sh, bw), kc(enamel, K_ENAMEL), Basis(), 0.03)
	# The foot: a wedge to a point under the slab.
	g.tri("sign", Vector3(t * 0.5, y0, z0), Vector3(t * 0.5, y0, z1), Vector3(t * 0.5, y0 - 1.2, z1 - 0.2), Vector3.RIGHT, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, kc(enamel, K_ENAMEL))
	g.tri("sign", Vector3(-t * 0.5, y0, z0), Vector3(-t * 0.5, y0, z1), Vector3(-t * 0.5, y0 - 1.2, z1 - 0.2), Vector3.LEFT, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, kc(enamel, K_ENAMEL))
	g.quad("sign", Vector3(-t * 0.5, y0, z1), Vector3(t * 0.5, y0, z1), Vector3(t * 0.5, y0 - 1.2, z1 - 0.2), Vector3(-t * 0.5, y0 - 1.2, z1 - 0.2), Vector3(0, -0.15, 1),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, kc(enamel, K_ENAMEL))
	g.quad("sign", Vector3(-t * 0.5, y0, z0), Vector3(t * 0.5, y0, z0), Vector3(t * 0.5, y0 - 1.2, z1 - 0.2), Vector3(-t * 0.5, y0 - 1.2, z1 - 0.2), Vector3(0, -0.8, -0.6),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, kc(enamel, K_ENAMEL))
	# The front edge's column of bulbs, both faces' bulb borders and neon outlines.
	g.quad("sign", Vector3(-0.08, y0 + 0.2, z1 + 0.035), Vector3(0.08, y0 + 0.2, z1 + 0.035), Vector3(0.08, y1 - 0.2, z1 + 0.035), Vector3(-0.08, y1 - 0.2, z1 + 0.035), Vector3.BACK,
		Vector2(0, 1), Vector2(0, 0), Vector2(sh - 0.4, 0), Vector2(sh - 0.4, 1), kc(enamel.darkened(0.3), K_BULBS))
	for sx: float in [-1.0, 1.0]:
		var x := sx * (t * 0.5 + 0.035)
		var n := Vector3(sx, 0.0, 0.0)
		var e := 0.12
		var corners := [Vector2(z0 + e, y0 + e), Vector2(z1 - e, y0 + e), Vector2(z1 - e, y1 - e), Vector2(z0 + e, y1 - e)]
		var u := 0.0
		for k in 4:
			var p0: Vector2 = corners[k]
			var p1: Vector2 = corners[(k + 1) % 4]
			var dd := (p1 - p0)
			var len := dd.length()
			var across := Vector2(-dd.y, dd.x).normalized() * 0.16
			# Toward the inside of the slab.
			if (Vector2(zc, (y0 + y1) * 0.5) - p0).dot(across) < 0.0:
				across = -across
			g.quad("sign", Vector3(x, p0.y, p0.x), Vector3(x, p1.y, p1.x), Vector3(x, p1.y + across.y, p1.x + across.x), Vector3(x, p0.y + across.y, p0.x + across.x), n,
				Vector2(u, 0), Vector2(u + len, 0), Vector2(u + len, 1), Vector2(u, 1), kc(enamel.darkened(0.3), K_BULBS))
			u += len
			# Neon inset a little further in.
			var q0 := p0 + across * 2.4
			var q1 := p1 + across * 2.4
			var qm := (q0 + q1) * 0.5
			var ql := q0.distance_to(q1)
			var horiz := absf(dd.x) > absf(dd.y)
			g.box("sign", Vector3(x + sx * 0.03, qm.y, qm.x), Vector3(0.06, 0.07 if horiz else ql - 0.6, ql - 0.6 if horiz else 0.07), kc(neon, K_NEON))
		# The name, stacked, letter by letter top to bottom.
		var name := str(spec.name).replace("THE ", "").replace(" ", "")
		var rows := name.length()
		var room := sh - 1.2
		var step := room / float(rows)
		var cap := minf(step * 0.9, bw * 0.8)
		var basis := Basis(Vector3.UP, sx * PI * 0.5)
		for i in rows:
			var yy := y1 - 0.6 - step * (float(i) + 0.5)
			letter(g, name[i], Transform3D(basis, Vector3(x + sx * 0.02, yy, zc)), cap, kc(spec.letters, K_LETTERS), n, i)
	# The crown: a stepped cap, a ball and a neon ring.
	g.box("sign", Vector3(0.0, y1 + 0.2, zc), Vector3(t + 0.2, 0.4, bw + 0.2), kc(enamel.lightened(0.2), K_ENAMEL), Basis(), 0.04)
	g.box("sign", Vector3(0.0, y1 + 0.6, zc), Vector3(t, 0.4, bw * 0.6), kc(enamel, K_ENAMEL), Basis(), 0.04)
	g.cylinder("sign", Vector3(0.0, y1 + 0.8, zc), 0.12, 0.6, 8, kc(BRASS, K_BRASS))
	g.dome("sign", Vector2(0.0, zc), Vector2(0.45, 0.45), y1 + 1.4, 0.45, 10, 3, kc(BRASS, K_BRASS))
	g.cylinder("sign", Vector3(0.0, y1 + 1.0, zc), 0.12, 0.4, 8, kc(BRASS, K_BRASS), 0.45)
	g.band("sign", Vector2(0.0, zc), Vector2(0.55, 0.55), Vector2(0.55, 0.55), y1 + 1.36, y1 + 1.44, 0.0, TAU, 12, kc(neon, K_NEON))
	# Brackets to the wall.
	for yy: float in [y0 + 0.5, y1 - 0.5, (y0 + y1) * 0.5]:
		g.box("sign", Vector3(0.0, yy, z0 * 0.5), Vector3(0.18, 0.18, z0 + 0.1), kc(IRON, K_IRON))
	_rod(g, Vector3(0.0, y1, z1 - 0.3), Vector3(0.0, minf(y1 + 3.5, hc + 1.0), 0.2), 0.05)


# --- Lettering -----------------------------------------------------------------------------

## A line of text in the plane of `xf` (letters' x along xf.x, up xf.y), facing `want`, at most
## `fit` metres wide, `height` its em. `seq` makes each letter its own row of the lit sequence
## (K_LETTERS).
static func text(g: LandmarkGeo, s: String, xf: Transform3D, height: float, fit: float, col: Color, want: Vector3, seq: bool = false) -> void:
	if s == "":
		return
	var geo := ShopfrontKit._text_geo(s, height)
	var vs: PackedVector3Array = geo[0]
	if vs.is_empty():
		return
	var lo := INF
	var hi := -INF
	for v in vs:
		lo = minf(lo, v.x)
		hi = maxf(hi, v.x)
	var sc := minf(1.0, fit / maxf(hi - lo, 0.01))
	var t := xf * Transform3D(Basis.from_scale(Vector3(sc, sc, 1.0)), Vector3.ZERO)
	_add_geo(g, geo, t, col, want, 0 if seq else -1, sc)


## One letter (a row of the lit sequence when `col` is K_LETTERS).
static func letter(g: LandmarkGeo, ch: String, xf: Transform3D, height: float, col: Color, want: Vector3, row: int) -> void:
	_add_geo(g, ShopfrontKit._text_geo(ch, height * 1.3), xf, col, want, row, 1.0)


static func _add_geo(g: LandmarkGeo, geo: Array, xf: Transform3D, col: Color, want: Vector3, row: int, sc: float) -> void:
	var vs: PackedVector3Array = geo[0]
	var idx = geo[2]
	var ids: PackedInt32Array = idx if idx != null else PackedInt32Array()
	if ids.is_empty():
		for k in vs.size():
			ids.append(k)
	var lift := 100.0 * float(maxi(row, 0))
	for k in range(0, ids.size() - 2, 3):
		var a := vs[ids[k]]
		var b := vs[ids[k + 1]]
		var c := vs[ids[k + 2]]
		# Only the front face (TextMesh at depth 0 still gives both).
		g.tri("sign", xf * a, xf * b, xf * c, want,
			Vector2(a.x * sc, a.y * sc + lift), Vector2(b.x * sc, b.y * sc + lift), Vector2(c.x * sc, c.y * sc + lift), col)


# --- Far ---------------------------------------------------------------------------------------

## LOD chunks and the far city: the front block and auditorium as boxes, the blade sign and the
## marquee as lit panels (building_lod's PANEL plant: lit after dark in their own colour).
static func _far(ch: CityChunk, xf: Transform3D, spec: Dictionary, w: float, d: float, fd: float, hc: float, ha: float,
		sh: float, to_kerb: float, seed_value: int) -> void:
	var b := xf.basis
	var boxes := [
		[Vector3(0.0, hc * 0.5, -fd * 0.5), Vector3(w, hc, fd), Color(0.80, 0.72, 0.60), Color(0.25, 0.3, float(seed_value % 997) / 997.0, 0.0)],
		[Vector3(0.0, ha * 0.5, -(fd + d) * 0.5), Vector3(w - 1.0, ha, d - fd), Color(0.50, 0.30, 0.24), Color(0.0, 0.0, 0.0, 1.0)],
	]
	for bx: Array in boxes:
		var c: Vector3 = xf * (bx[0] as Vector3)
		var s: Vector3 = bx[1]
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b * Basis.from_scale(s), c - Vector3(0.0, ch._gy(c.x, c.z), 0.0)), bx[2], bx[3])
		ch._add_lod_shape(Vector3(s.z, s.y, s.x), c)
	var l := clampf(to_kerb - 0.7, 2.5, 4.8)
	var panels := [
		[Vector3(0.0, SIGN_Y0 + sh * 0.5, 1.8), Vector3(0.7, sh, 2.6), spec.letters],
		[Vector3(0.0, (MARQUEE_Y0 + MARQUEE_Y1) * 0.5, l * 0.5), Vector3(minf(pavilion_width(spec, w) - 1.0, 14.0), MARQUEE_Y1 - MARQUEE_Y0, l), Color(1.0, 0.85, 0.6)],
	]
	for pn: Array in panels:
		var c: Vector3 = xf * (pn[0] as Vector3)
		var s: Vector3 = pn[1]
		var col: Color = pn[2]
		c.y -= ch._gy(c.x, c.z)
		ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(b * Basis.from_scale(s), c), col,
			Color(float(FarBuilding.Plant.PANEL), 1.0, 1.0, FarBuilding.PLANT_FLAG))
