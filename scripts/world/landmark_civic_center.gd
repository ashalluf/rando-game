class_name LandmarkCivicCenter
extends RefCounted
## The civic centre north-east of the downtown core (owner, 2026-09-24: "downtown must match
## real downtown LA"): the real buildings' FORMS in their real arrangement, every NAME invented.
##
## - `ziggurat_hall`, CITY HALL: the tall white tower with its stepped pyramid top over a
##   colonnaded belvedere, rising out of a broad base with two long wings, a colonnaded portico
##   and wide steps facing the park. Stone with vertical piers between narrow windows, and
##   FLOODLIT after dark (landmark_facade's flood term), with a beacon on its mast.
## - `civic_park`, CIVIC PARK: running north from city hall's steps - a raised terrace with a
##   long fountain pool and its row of jets, a great lawn, promenades with hot-pink benches and
##   chairs, raised planters of flowering beds and trees, lamps, walkers.
## - `concert_hall`, SYMPHONY HALL: curving brushed stainless steel sails round the auditorium
##   (a model made in Blender by tools/make_concert_hall.py, on shaders/brushed_steel), on a stone
##   podium with steps, glazing in the gaps between the sails.
## - `lattice_museum`, THE LATTICE: a white box wrapped in a deep honeycomb veil, lifted at its
##   corners, dimpled on its east face, over a dark vault and a glass lobby, with a grove on its
##   plaza.
## - `pueblo_station`, PUEBLO STATION: the mission-revival railway station - long white stucco
##   halls under red barrel-tile roofs, a tall arched entrance, arcades, a clock tower, a
##   forecourt of palms, and the platforms behind.
##
## Each takes the whole block its anchor falls in and fits itself to it (Landmarks.site_rect), so
## it never sits on a road. LandmarkGeo meshes (a surface per material) and a MultiMeshBatch for
## repeats; box collision for everything you can stand on.

const CITY_HALL_NAME := "CITY HALL"
const PARK_NAME := "CIVIC PARK"
const MUSEUM_NAME := "THE LATTICE"
const STATION_NAME := "PUEBLO STATION"

const HALL_STONE := Color(0.92, 0.90, 0.85)
## Grand-park pink: every bench and chair in the park.
const PARK_PINK := Color(0.93, 0.16, 0.52)
const STUCCO := Color(0.94, 0.90, 0.81)

## The concert hall model (tools/make_concert_hall.py).
const CONCERT_HALL_MODEL := "res://assets/models/concert_hall.glb"


static func build(id: String, anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var site := Landmarks.site_rect(plan, anchor)
	var y0 := LandmarkArenaDistrict.ground(plan, site)
	match id:
		"ziggurat_hall":
			_city_hall(site, y0, parent, statics, detailed)
		"civic_park":
			_park(site, y0, parent, statics, detailed)
		"concert_hall":
			_concert_hall(site, y0, parent, statics, detailed)
		"lattice_museum":
			_museum(site, y0, parent, statics, detailed)
		"pueblo_station":
			_station(site, y0, parent, statics, detailed)


static func crowds(id: String, anchor: Vector2, plan: CityPlan) -> Array:
	var s := Landmarks.site_rect(plan, anchor)
	match id:
		"civic_park":
			var loop := _park_loop(s)
			return [[loop, 6.0, 26], [_park_lawn(s).grow(-2.0), minf(_park_lawn(s).size.x, _park_lawn(s).size.y) * 0.5 - 2.0, 10]]
		"pueblo_station":
			var f := Rect2(s.position + Vector2(1.0, 2.0), Vector2(_station_court(s) - 2.0, s.size.y - 4.0))
			return [[f, f.size.x * 0.5, 16]]
		"lattice_museum":
			var p := Rect2(Vector2(s.position.x + 2.0, _museum_box(s).end.y + 2.0), Vector2(s.size.x - 4.0, s.end.y - _museum_box(s).end.y - 3.0))
			if p.size.y > 4.0:
				return [[p, minf(p.size.x, p.size.y) * 0.5, 8]]
	return []


# ============================================================================================
# City hall
# ============================================================================================

static func _city_hall(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var c := s.get_center()
	var stone_tex := "plaster_white"
	var hall := LandmarkMats.facade("hall_wings", stone_tex, 3.0,
		{"tint": HALL_STONE, "roughness": 0.8, "texture_contrast": 0.6, "win_pitch": Vector2(2.4, 3.6), "win_size": Vector2(0.44, 0.58), "win_sill": 0.22,
		"win_band": Vector2(y0 + 3.4, y0 + 30.0), "lit_ratio": 0.3, "grime": 0.25, "base_y": y0,
		"flood_strength": 0.9, "flood_base_y": y0 + 2.2, "flood_reach": 14.0, "flood_floor": 0.25, "flood_spacing": 4.8, "seed": 3.0})
	var tower := LandmarkMats.facade("hall_tower", stone_tex, 3.0,
		{"tint": HALL_STONE, "roughness": 0.78, "texture_contrast": 0.6, "win_pitch": Vector2(2.4, 3.6), "win_size": Vector2(0.40, 0.60), "win_sill": 0.2,
		"win_band": Vector2(y0 + 36.0, y0 + 106.0), "lit_ratio": 0.28, "grime": 0.0,
		"flood_strength": 1.15, "flood_base_y": y0 + 30.0, "flood_reach": 45.0, "flood_floor": 0.35, "flood_spacing": 4.8,
		"flood_top_y": y0 + 118.0, "flood_top_reach": 9.0, "seed": 7.0})
	var crown := LandmarkMats.facade("hall_crown", stone_tex, 3.0,
		{"tint": Color(0.95, 0.93, 0.88), "roughness": 0.7, "texture_contrast": 0.5,
		"flood_strength": 1.4, "flood_base_y": y0 + 106.0, "flood_reach": 14.0, "flood_floor": 0.4, "flood_spacing": 3.0})
	var trim := LandmarkMats.facade("hall_trim", stone_tex, 3.0, {"tint": Color(0.88, 0.86, 0.80), "roughness": 0.75, "texture_contrast": 0.5,
		"flood_strength": 0.9, "flood_base_y": y0 + 2.2, "flood_reach": 20.0, "flood_floor": 0.3})
	var pier := LandmarkMats.facade("hall_pier", stone_tex, 3.0,
		{"tint": Color(0.96, 0.95, 0.91), "roughness": 0.74, "texture_contrast": 0.6,
		"flood_strength": 1.15, "flood_base_y": y0 + 30.0, "flood_reach": 45.0, "flood_floor": 0.35, "flood_spacing": 4.8})
	g.use("hall", hall)
	g.use("tower", tower)
	g.use("pier", pier)
	g.use("crown", crown)
	g.use("trim", trim)
	var bev := 0.12 if detailed else 0.0

	# The plinth and the steps down to the park (north).
	var pw := minf(74.0, s.size.x - 2.0)
	var pd := minf(72.0, s.size.y - 6.0)
	var ph := 2.2
	var pc := Vector3(c.x, y0 + ph * 0.5, c.y + (s.size.y - pd) * 0.5 - 1.0)
	g.box("trim", pc, Vector3(pw, ph, pd), Color.WHITE, Basis(), bev)
	LandmarkGeo.shape_box(statics, pc, Vector3(pw, ph, pd))
	var north := pc.z - pd * 0.5
	var steps := 6
	for k in steps:
		var h := ph * float(k + 1) / float(steps)
		var depth := 0.6 * float(steps - k)
		var at := Vector3(c.x, y0 + h * 0.5, north - depth * 0.5)
		g.box("trim", at, Vector3(44.0, h, depth), Color(0.96, 0.95, 0.92))
		LandmarkGeo.shape_box(statics, at, Vector3(44.0, h, depth))
	var top := y0 + ph
	# The wings, east and west, each with a set-back attic.
	var ww := 15.0
	var wd := pd - 10.0
	var wh := 22.0
	for side: float in [-1.0, 1.0]:
		var wc := Vector3(c.x + side * (pw * 0.5 - ww * 0.5 - 1.0), top + wh * 0.5, pc.z + 1.0)
		g.box("hall", wc, Vector3(ww, wh, wd), Color.WHITE, Basis(), bev, false, 2.4)
		LandmarkGeo.shape_box(statics, wc, Vector3(ww, wh, wd))
		g.box("trim", Vector3(wc.x, top + wh + 0.4, wc.z), Vector3(ww + 1.0, 0.8, wd + 1.0), Color.WHITE, Basis(), bev)
		var ac := Vector3(wc.x, top + wh + 0.8 + 2.6, wc.z)
		g.box("hall", ac, Vector3(ww - 3.0, 5.2, wd - 3.0), Color(0.97, 0.96, 0.94), Basis(), bev, false, 2.4)
		LandmarkGeo.shape_box(statics, ac, Vector3(ww - 3.0, 5.2, wd - 3.0))
	# The centre block between the wings, and the portico on its park face.
	var cw := pw - ww * 2.0 - 2.0
	var cd := wd - 8.0
	var ch := 28.0
	var cc := Vector3(c.x, top + ch * 0.5, pc.z + 4.0)
	g.box("hall", cc, Vector3(cw, ch, cd), Color.WHITE, Basis(), bev, false, 2.4)
	LandmarkGeo.shape_box(statics, cc, Vector3(cw, ch, cd))
	g.box("trim", Vector3(cc.x, top + ch + 0.5, cc.z), Vector3(cw + 1.2, 1.0, cd + 1.2), Color.WHITE, Basis(), bev)
	var face := cc.z - cd * 0.5
	var porch := 5.5
	var col_h := 15.0
	var cols := 8
	var span := minf(cw - 6.0, 32.0)
	for i in cols:
		var x := c.x - span * 0.5 + span * float(i) / float(cols - 1)
		var at := Vector3(x, top + col_h * 0.5, face - porch + 0.9)
		g.box("trim", at, Vector3(1.7, col_h, 1.7), Color.WHITE, Basis(), 0.1 if detailed else 0.0)
		LandmarkGeo.shape_box(statics, at, Vector3(1.7, col_h, 1.7))
		if detailed:
			g.box("trim", Vector3(x, top + 0.3, face - porch + 0.9), Vector3(2.3, 0.6, 2.3), Color.WHITE, Basis(), 0.06)
			g.box("trim", Vector3(x, top + col_h - 0.35, face - porch + 0.9), Vector3(2.2, 0.7, 2.2), Color.WHITE, Basis(), 0.06)
	var ent := Vector3(c.x, top + col_h + 1.6, face - porch * 0.5)
	g.box("trim", ent, Vector3(span + 4.0, 3.2, porch + 1.0), Color.WHITE, Basis(), bev)
	LandmarkGeo.shape_box(statics, ent, Vector3(span + 4.0, 3.2, porch + 1.0))
	batch.add("hall_name", Signage.text_mesh(CITY_HALL_NAME, 1.5, Signage.Letters.PRINT),
		Transform3D(LandmarkArenaDistrict._face(0.0, 1.0), Vector3(c.x, ent.y, ent.z - (porch + 1.0) * 0.5 - 0.05)), Color(0.35, 0.32, 0.28))
	batch.set_no_shadow("hall_name")

	# The tower: a transition base, the tall shaft with its piers, a cornice, the upper shaft,
	# the colonnaded belvedere, the stepped pyramid, the lantern and the beacon mast.
	var tx := c.x
	var tz := cc.z + 2.0
	var y := top + ch
	g.box("tower", Vector3(tx, y + 3.0, tz), Vector3(30.0, 6.0, 30.0), Color.WHITE, Basis(), bev, false, 2.4)
	LandmarkGeo.shape_box(statics, Vector3(tx, y + 3.0, tz), Vector3(30.0, 6.0, 30.0))
	y += 6.0
	var shaft := [[24.0, 58.0, 10], [20.0, 10.0, 8]]
	for k in shaft.size():
		var w: float = shaft[k][0]
		var h: float = shaft[k][1]
		var piers: int = shaft[k][2]
		g.box("tower", Vector3(tx, y + h * 0.5, tz), Vector3(w, h, w), Color.WHITE, Basis(), bev, false, w / float(piers))
		LandmarkGeo.shape_box(statics, Vector3(tx, y + h * 0.5, tz), Vector3(w, h, w))
		if detailed:
			# Piers standing proud between the window bays, full height: the vertical lines
			# that make the tower read as tall. Bevelled, so each one catches the light.
			var pitch := w / float(piers)
			for f in 4:
				var ang := float(f) * PI * 0.5
				var out := Vector3(sin(ang), 0.0, cos(ang))
				var along := Vector3(cos(ang), 0.0, -sin(ang))
				for i in piers + 1:
					var o := -w * 0.5 + pitch * float(i)
					var at := Vector3(tx, y + h * 0.5, tz) + out * (w * 0.5 + 0.25) + along * o
					g.box("pier", at, Vector3(0.62, h, 0.5), Color(1.0, 1.0, 1.0), LandmarkGeo.yaw(ang), 0.1)
		# Cornice.
		g.box("crown", Vector3(tx, y + h + 0.6, tz), Vector3(w + 2.2, 1.2, w + 2.2), Color.WHITE, Basis(), bev)
		LandmarkGeo.shape_box(statics, Vector3(tx, y + h + 0.6, tz), Vector3(w + 2.2, 1.2, w + 2.2))
		y += h + 1.2
	# The belvedere: a colonnade round a core.
	var bw := 17.0
	var bh := 8.6
	g.box("crown", Vector3(tx, y + bh * 0.5, tz), Vector3(bw - 5.0, bh, bw - 5.0), Color(0.9, 0.88, 0.84), Basis(), bev)
	LandmarkGeo.shape_box(statics, Vector3(tx, y + bh * 0.5, tz), Vector3(bw, bh, bw))
	if detailed:
		for f in 4:
			var ang := float(f) * PI * 0.5
			var out := Vector3(sin(ang), 0.0, cos(ang))
			var along := Vector3(cos(ang), 0.0, -sin(ang))
			for i in 5:
				var o := -bw * 0.5 + 0.5 + (bw - 1.0) * float(i) / 4.0
				g.box("crown", Vector3(tx, y + bh * 0.5, tz) + out * (bw * 0.5 - 0.5) + along * o, Vector3(0.9, bh, 0.9), Color.WHITE, LandmarkGeo.yaw(ang), 0.08)
	y += bh
	g.box("crown", Vector3(tx, y + 0.6, tz), Vector3(bw + 1.0, 1.2, bw + 1.0), Color.WHITE, Basis(), bev)
	y += 1.2
	# The stepped pyramid.
	var sw := bw
	for i in 7:
		g.box("crown", Vector3(tx, y + 1.0, tz), Vector3(sw, 2.0, sw), Color(1.0 - 0.012 * float(i), 1.0 - 0.012 * float(i), 1.0), Basis(), 0.08 if detailed else 0.0)
		LandmarkGeo.shape_box(statics, Vector3(tx, y + 1.0, tz), Vector3(sw, 2.0, sw))
		y += 2.0
		sw -= 2.0
	# Lantern, mast, beacon.
	g.use("glow", LandmarkMats.glow("hall_lantern", Color(1.0, 0.86, 0.6)))
	g.use("beacon", LandmarkMats.glow("hall_beacon", Color(1.0, 0.22, 0.18)))
	g.box("glow", Vector3(tx, y + 1.5, tz), Vector3(2.6, 3.0, 2.6), Color.WHITE)
	g.box("crown", Vector3(tx, y + 3.3, tz), Vector3(3.6, 0.6, 3.6), Color.WHITE, Basis(), 0.06 if detailed else 0.0)
	g.use("mast", LandmarkMats.plain("hall_mast", Color(0.8, 0.8, 0.82), 0.4, 0.6))
	g.cylinder("mast", Vector3(tx, y + 3.6, tz), 0.3, 8.0, 8)
	g.box("beacon", Vector3(tx, y + 12.0, tz), Vector3(0.8, 0.8, 0.8), Color.WHITE)
	if detailed:
		_hall_forecourt(g, batch, parent, s, y0, north, statics)
	g.commit(parent, "CityHall")
	batch.build(parent)
	LandmarkArenaDistrict._occluder(parent, [[Vector3(tx, top + ch + 6.0 + 29.0, tz), Vector3(24.0, 58.0, 24.0)], [cc, Vector3(cw, ch, cd)]])


## City hall's forecourt: paving in front of the steps, lamp standards, flag poles.
static func _hall_forecourt(g: LandmarkGeo, batch: MultiMeshBatch, parent: Node3D, s: Rect2, y0: float, north: float, statics: StaticBody3D) -> void:
	g.use("paving", LandmarkMats.paving("paving", 2.6, Color(0.9, 0.88, 0.84), 8812, 3.0, 0.2))
	g.cap("paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(Rect2(s.position, Vector2(s.size.x, north - s.position.y - 3.4)))), y0 + 0.03)
	var pole := PropFactory.cylinder("hall_flagpole", 0.1, 1.0, Color(0.85, 0.86, 0.88), 0.06, 8)
	for side: float in [-1.0, 1.0]:
		var at := Vector3(s.get_center().x + side * 26.0, y0, s.position.y + 2.5)
		batch.add("hall_flagpole", pole, Transform3D(Basis().scaled(Vector3(1.0, 16.0, 1.0)), at + Vector3(0.0, 8.0, 0.0)))
		g.box("trim", at + Vector3(0.0, 14.4, 1.3), Vector3(0.05, 2.0, 2.6), Color(0.3, 0.4, 0.62))
		LandmarkGeo.shape_box(statics, at + Vector3(0.0, 8.0, 0.0), Vector3(0.3, 16.0, 0.3))
	for x: float in [s.position.x + 6.0, s.end.x - 6.0, s.get_center().x - 14.0, s.get_center().x + 14.0]:
		batch.add("hall_lamp", PropFactory.model_lamp(), Transform3D(Basis(), Vector3(x, y0, s.position.y + 1.2)))
		batch.add("hall_pool", PropFactory.light_pool(), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(13.0, 1.0, 13.0)), Vector3(x, y0 + 0.06, s.position.y + 1.2)))
	batch.set_no_shadow("hall_pool")
	LandmarkArenaDistrict._add_light(parent, Vector3(s.get_center().x, y0 + 6.0, s.position.y + 2.0), 26.0)


# ============================================================================================
# The park
# ============================================================================================

## Depth of the raised fountain terrace at the park's north end, and its height.
const TERRACE_DEPTH := 24.0
const TERRACE_H := 1.2


static func _park_lawn(s: Rect2) -> Rect2:
	var side := clampf(s.size.x * 0.12, 6.0, 10.0) + 8.0
	return Rect2(Vector2(s.position.x + side, s.position.y + TERRACE_DEPTH + 4.0), Vector2(s.size.x - side * 2.0, s.size.y - TERRACE_DEPTH - 20.0))


## The promenade loop round the lawn that the park's walkers follow.
static func _park_loop(s: Rect2) -> Rect2:
	var lawn := _park_lawn(s)
	return Rect2(lawn.position - Vector2(7.0, 3.0), lawn.size + Vector2(14.0, 3.0 + (s.end.y - lawn.end.y) - 2.8))


static func _park(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var c := s.get_center()
	var lawn := _park_lawn(s)
	var concrete := LandmarkMats.facade("park_concrete", "concrete", 3.0,
		{"tint": Color(0.84, 0.82, 0.78), "roughness": 0.85, "joint_spacing": Vector2(3.0, 0.0), "joint_dark": 0.2, "grime": 0.35, "base_y": y0})
	g.use("concrete", concrete)
	g.use("paving", LandmarkMats.paving("pavers", 2.4, Color(0.95, 0.93, 0.89), 9131, 3.0, 0.2))
	g.use("lawn", PropFactory.lawn(Color(0.52, 0.66, 0.34), 9133, 0.25, 3.0))
	g.use("soil", LandmarkMats.plain("park_soil", Color(0.26, 0.21, 0.16), 0.95))
	var bev := 0.06 if detailed else 0.0
	# Paving over the whole park, then the lawn on top of it.
	g.cap("paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(s)), y0 + 0.03)
	g.cap("lawn", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(lawn)), y0 + 0.07)
	g.box("concrete", Vector3(lawn.get_center().x, y0 + 0.05, lawn.position.y - 0.15), Vector3(lawn.size.x + 0.3, 0.14, 0.3), Color.WHITE)
	g.box("concrete", Vector3(lawn.get_center().x, y0 + 0.05, lawn.end.y + 0.15), Vector3(lawn.size.x + 0.3, 0.14, 0.3), Color.WHITE)
	# The fountain terrace: a raised platform across the north end with the pool in it, and steps
	# down to the lawn the whole width of the pool.
	var tr := Rect2(Vector2(s.position.x + 2.0, s.position.y + 1.0), Vector2(s.size.x - 4.0, TERRACE_DEPTH - 1.0))
	var tc := Vector3(tr.get_center().x, y0 + TERRACE_H * 0.5, tr.get_center().y)
	g.box("concrete", tc, Vector3(tr.size.x, TERRACE_H, tr.size.y), Color.WHITE, Basis(), bev)
	LandmarkGeo.shape_box(statics, tc, Vector3(tr.size.x, TERRACE_H, tr.size.y))
	g.cap("paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(tr.grow(-0.3))), y0 + TERRACE_H + 0.01)
	var sw := minf(tr.size.x * 0.55, 44.0)
	for k in 4:
		var h := TERRACE_H * float(k + 1) / 4.0
		var d := 0.55 * float(4 - k)
		var at := Vector3(c.x, y0 + h * 0.5, tr.end.y + d * 0.5)
		g.box("concrete", at, Vector3(sw, h, d), Color(0.96, 0.95, 0.93))
		LandmarkGeo.shape_box(statics, at, Vector3(sw, h, d))
	# The pool: a long rim, dark water, a row of jets down its middle.
	var pool := Rect2(Vector2(c.x - minf(tr.size.x * 0.4, 17.0), tr.position.y + 4.0), Vector2(minf(tr.size.x * 0.8, 34.0), minf(tr.size.y - 8.0, 12.0)))
	var rim_y := y0 + TERRACE_H + 0.45
	for e: Array in [[Vector3(pool.get_center().x, 0.0, pool.position.y), Vector3(pool.size.x + 1.2, 0.9, 0.6)],
			[Vector3(pool.get_center().x, 0.0, pool.end.y), Vector3(pool.size.x + 1.2, 0.9, 0.6)],
			[Vector3(pool.position.x, 0.0, pool.get_center().y), Vector3(0.6, 0.9, pool.size.y)],
			[Vector3(pool.end.x, 0.0, pool.get_center().y), Vector3(0.6, 0.9, pool.size.y)]]:
		var at := Vector3((e[0] as Vector3).x, rim_y, (e[0] as Vector3).z)
		g.box("concrete", at, e[1], Color(0.93, 0.92, 0.9), Basis(), bev)
		LandmarkGeo.shape_box(statics, at, e[1])
	var jets := 11
	var spacing := pool.size.x / float(jets + 1)
	g.use("water", LandmarkMats.water("park_pool", {"jet_spacing": spacing, "jet_z": pool.get_center().y}))
	g.cap("water", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(pool)), y0 + TERRACE_H + 0.62)
	if detailed:
		g.use("jet", LandmarkMats.jet())
		for i in jets:
			var jx := pool.position.x + spacing * float(i + 1)
			var hgt := 3.6 + 2.2 * sin(float(i) / float(jets - 1) * PI)
			_jet(g, Vector3(jx, y0 + TERRACE_H + 0.62, pool.get_center().y), hgt)
		_park_detail(g, batch, parent, s, y0, lawn, tr, statics)
	g.commit(parent, "CivicPark")
	batch.build(parent)


## A fountain jet: two crossed quads on the jet shader.
static func _jet(g: LandmarkGeo, base: Vector3, height: float) -> void:
	var w := 0.9
	for a: float in [0.0, PI * 0.5]:
		var d := Vector3(cos(a), 0.0, sin(a)) * w * 0.5
		var n := Vector3(-sin(a), 0.0, cos(a))
		g.quad("jet", base - d + Vector3(0.0, height, 0.0), base + d + Vector3(0.0, height, 0.0), base + d, base - d, n,
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))


static func _park_detail(g: LandmarkGeo, batch: MultiMeshBatch, parent: Node3D, s: Rect2, y0: float, lawn: Rect2, tr: Rect2, statics: StaticBody3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55173
	# Grass on the great lawn, from the chunk's own grass (the same blades as every park).
	if parent is CityChunk:
		(parent as CityChunk)._add_grass(lawn.grow(-0.5), 0.9)
	# Raised planters down both sides, planted with flowering beds, grasses and jacarandas.
	var bed_w := clampf(s.size.x * 0.12, 6.0, 10.0)
	for side: float in [0.0, 1.0]:
		var bx := lerpf(s.position.x + 1.0 + bed_w * 0.5, s.end.x - 1.0 - bed_w * 0.5, side)
		var z0 := tr.end.y + 3.0
		var z1 := s.end.y - 18.0
		var n := maxi(1, int((z1 - z0) / 14.0))
		for i in n:
			var za := lerpf(z0, z1, float(i) / float(n)) + 0.8
			var zb := lerpf(z0, z1, float(i + 1) / float(n)) - 0.8
			var bc := Vector3(bx, y0 + 0.3, (za + zb) * 0.5)
			var bs := Vector3(bed_w, 0.6, zb - za)
			g.box("concrete", bc, bs, Color(0.9, 0.88, 0.85), Basis(), 0.05)
			LandmarkGeo.shape_box(statics, bc, bs)
			g.cap("soil", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(Rect2(Vector2(bx - bed_w * 0.5 + 0.3, za + 0.3), Vector2(bed_w - 0.6, zb - za - 0.6)))), y0 + 0.61)
			var tv := PropFactory.CITY_TREES.size() - 1 if i % 2 == 0 else 1 + i % 3
			var tsc := PropFactory.city_tree_scale(tv, rng.randf_range(7.0, 9.5))
			batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(tsc, tsc, tsc)), Vector3(bx, y0 + 0.6, bc.z)),
				Color.WHITE, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0)))
			var lead := (i + int(side) * 2) % PropFactory.FLOWERS.size()
			for k in 26:
				var p := Vector2(rng.randf_range(bx - bed_w * 0.5 + 0.6, bx + bed_w * 0.5 - 0.6), rng.randf_range(za + 0.6, zb - 0.6))
				if Vector2(p.x - bx, p.y - bc.z).length() < 1.4:
					continue
				var sc := rng.randf_range(0.8, 1.4)
				var at := Vector3(p.x, y0 + 0.61, p.y)
				var tint := Color(rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.1))
				if k % 3 == 0:
					batch.add("gclump_1", PropFactory.model_grass_clump(1), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), at), tint)
				else:
					batch.add("flower_%d" % lead, PropFactory.model_flower(lead), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), at), tint)
				batch.set_no_shadow("flower_%d" % lead)
				batch.set_draw_distance("flower_%d" % lead, 150.0)
	batch.set_no_shadow("gclump_1")
	batch.set_draw_distance("gclump_1", 135.0)
	# Hot-pink benches along the promenades facing the lawn, and loose chairs by the fountain and
	# on the lower plaza - the park's signature.
	var bench := _pink_bench()
	var chair := _pink_chair()
	var nb := maxi(2, int(lawn.size.y / 8.0))
	for i in nb:
		var z := lawn.position.y + (float(i) + 0.5) * lawn.size.y / float(nb)
		batch.add("park_bench", bench, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(lawn.position.x - 1.2, y0 + 0.04, z)))
		batch.add("park_bench", bench, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(lawn.end.x + 1.2, y0 + 0.04, z)))
	for i in 34:
		var near_pool := i < 18
		var p: Vector2
		if near_pool:
			p = Vector2(rng.randf_range(tr.position.x + 2.0, tr.end.x - 2.0), rng.randf_range(tr.position.y + 1.0, tr.position.y + 3.2))
			if i % 2 == 1:
				p.y = rng.randf_range(tr.end.y - 3.2, tr.end.y - 1.2)
		else:
			p = Vector2(rng.randf_range(s.position.x + 4.0, s.end.x - 4.0), rng.randf_range(lawn.end.y + 2.0, s.end.y - 2.0))
		var ya := y0 + (TERRACE_H + 0.02 if near_pool else 0.04)
		batch.add("park_chair", chair, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, ya, p.y)))
	# Lamps along the promenades, with their pools, and a few real lights.
	var nl := maxi(2, int(lawn.size.y / 16.0))
	for i in nl + 1:
		var z := lawn.position.y + lawn.size.y * float(i) / float(nl)
		for x: float in [lawn.position.x - 4.5, lawn.end.x + 4.5]:
			batch.add("park_lamp", PropFactory.model_lamp(), Transform3D(Basis(Vector3.UP, 0.0 if x < lawn.get_center().x else PI), Vector3(x, y0, z)))
			batch.add("park_pool", PropFactory.light_pool(), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(13.0, 1.0, 13.0)), Vector3(x, y0 + 0.08, z)))
			LandmarkGeo.shape_box(statics, Vector3(x, y0 + 1.95, z), Vector3(0.3, 3.9, 0.3))
	batch.set_no_shadow("park_pool")
	for z: float in [lawn.position.y + 6.0, lawn.end.y - 6.0]:
		LandmarkArenaDistrict._add_light(parent, Vector3(lawn.get_center().x, y0 + 7.0, z), 24.0)
	# The name on a low wall on the lower plaza, facing city hall across the street.
	var sign_at := Vector3(s.get_center().x, y0, s.end.y - 1.3)
	g.box("concrete", sign_at + Vector3(0.0, 0.6, 0.0), Vector3(16.0, 1.2, 0.8), Color.WHITE, Basis(), 0.06)
	LandmarkGeo.shape_box(statics, sign_at + Vector3(0.0, 0.6, 0.0), Vector3(16.0, 1.2, 0.8))
	batch.add("park_name", Signage.text_mesh(PARK_NAME, 0.8, Signage.Letters.PRINT), Transform3D(LandmarkArenaDistrict._face(PI, 1.0), sign_at + Vector3(0.0, 0.62, 0.42)), PARK_PINK)
	batch.set_no_shadow("park_name")


## A park bench in the park's hot pink: seat slats, a back, two legs. Faces -Z.
static func _pink_bench() -> Mesh:
	return _furniture("pink_bench", [[Vector3(0.0, 0.45, 0.0), Vector3(1.9, 0.06, 0.5)], [Vector3(0.0, 0.78, 0.23), Vector3(1.9, 0.5, 0.05)],
		[Vector3(-0.8, 0.22, 0.0), Vector3(0.07, 0.45, 0.45)], [Vector3(0.8, 0.22, 0.0), Vector3(0.07, 0.45, 0.45)]])


## A loose café chair in the same pink.
static func _pink_chair() -> Mesh:
	return _furniture("pink_chair", [[Vector3(0.0, 0.45, 0.0), Vector3(0.46, 0.04, 0.44)], [Vector3(0.0, 0.72, 0.21), Vector3(0.46, 0.5, 0.03)],
		[Vector3(-0.2, 0.22, -0.19), Vector3(0.03, 0.45, 0.03)], [Vector3(0.2, 0.22, -0.19), Vector3(0.03, 0.45, 0.03)],
		[Vector3(-0.2, 0.22, 0.19), Vector3(0.03, 0.45, 0.03)], [Vector3(0.2, 0.22, 0.19), Vector3(0.03, 0.45, 0.03)]])


static var _furniture_cache: Dictionary = {}


static func _furniture(key: String, parts: Array) -> Mesh:
	if _furniture_cache.has(key):
		return _furniture_cache[key]
	var g := LandmarkGeo.new()
	g.use("paint", LandmarkMats.plain("park_pink", PARK_PINK, 0.45, 0.2))
	for p: Array in parts:
		g.box("paint", p[0], p[1], Color.WHITE, Basis(), 0.012, false, 0.0, true)
	var holder := Node3D.new()
	var mi := g.commit(holder, key)
	var mesh := mi.mesh
	holder.free()
	_furniture_cache[key] = mesh
	return mesh


# ============================================================================================
# The concert hall
# ============================================================================================

static func _concert_hall(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var c := s.get_center()
	var stone := LandmarkMats.facade("concert_stone", "concrete_layers", 4.0,
		{"tint": Color(0.80, 0.74, 0.66), "roughness": 0.8, "texture_contrast": 0.7, "joint_spacing": Vector2(1.2, 0.6), "joint_dark": 0.25, "grime": 0.3, "base_y": y0})
	g.use("stone", stone)
	# The podium: a stone plinth over the site with steps up at the south-west corner, the
	# entrance, facing the park and downtown.
	var ph := 2.0
	# Inset 3.5 m on the entrance sides (south and west) so the steps stay inside the block.
	var pr := Rect2(s.position + Vector2(3.5, 1.0), s.size - Vector2(4.5, 4.5))
	var pc := Vector3(pr.get_center().x, y0 + ph * 0.5, pr.get_center().y)
	g.box("stone", pc, Vector3(pr.size.x, ph, pr.size.y), Color.WHITE, Basis(), 0.1 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, pc, Vector3(pr.size.x, ph, pr.size.y))
	for k in 5:
		var h := ph * float(k + 1) / 5.0
		var d := 0.6 * float(5 - k)
		for e: Array in [[Vector3(pr.position.x + 16.0, 0.0, pr.end.y + d * 0.5), Vector3(30.0, h, d)], [Vector3(pr.position.x - d * 0.5, 0.0, pr.end.y - 14.0), Vector3(d, h, 26.0)]]:
			var at: Vector3 = e[0] + Vector3(0.0, y0 + h * 0.5, 0.0)
			g.box("stone", at, e[1], Color(0.95, 0.93, 0.9))
			LandmarkGeo.shape_box(statics, at, e[1])
	var top := y0 + ph
	var base := Vector3(c.x, top, c.y)
	# The sails: the Blender model on the brushed steel, its glazing on the curtain glass.
	# The model is about 85 x 78 m at the curl of its sails (tools/make_concert_hall.py); its feet
	# sit well inside that, so the tops may overhang the pavement by a couple of metres.
	var fit := minf(1.0, minf((s.size.x + 4.0) / 85.0, (s.size.y + 4.0) / 78.0))
	var mesh := PropFactory.model_mesh(CONCERT_HALL_MODEL, [], PackedStringArray(["collision"]), Transform3D(Basis().scaled(Vector3(fit, fit, fit)), Vector3.ZERO))
	if mesh and mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "SymphonyHall"
		mi.mesh = mesh
		mi.position = base
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var nm := src.resource_name.to_lower() if src else ""
			if nm.contains("glass"):
				mi.set_surface_override_material(i, LandmarkMats.glass("concert", {"glass_tint": Color(0.16, 0.19, 0.21), "frame_color": Color(0.62, 0.63, 0.65),
					"grid": Vector2(1.8, 2.6), "frame_width": 0.08, "room_depth": 10.0, "storey": 9.0, "floor_y": top, "interior_night": 1.8, "interior_day": 0.2}))
			elif nm.contains("stone"):
				mi.set_surface_override_material(i, stone)
			else:
				mi.set_surface_override_material(i, LandmarkMats.steel("concert", {"flood_base_y": top}))
		parent.add_child(mi)
		if statics:
			var col := PropFactory.model_mesh(CONCERT_HALL_MODEL, PackedStringArray(["collision"]), [], Transform3D(Basis().scaled(Vector3(fit, fit, fit)), Vector3.ZERO), {}, false)
			if col and col.get_surface_count() > 0:
				var cs := CollisionShape3D.new()
				cs.shape = col.create_trimesh_shape()
				cs.position = base
				statics.add_child(cs)
	else:
		# Fallback when the model is missing: the massing in steel boxes, so the block is not empty.
		g.use("steel", LandmarkMats.steel("concert", {"flood_base_y": top}))
		g.box("steel", base + Vector3(4.0, 13.0, -4.0), Vector3(30.0, 26.0, 36.0))
		g.box("steel", base + Vector3(-14.0, 10.0, 12.0), Vector3(28.0, 20.0, 24.0), Color.WHITE, LandmarkGeo.yaw(0.4))
		LandmarkGeo.shape_box(statics, base + Vector3(4.0, 13.0, -4.0), Vector3(30.0, 26.0, 36.0))
	if detailed:
		# A garden on the podium's north-east corner, and uplights at the foot of the sails.
		var rng := RandomNumberGenerator.new()
		rng.seed = 30311
		var b := MultiMeshBatch.new()
		for i in 6:
			var p := Vector2(s.end.x - 5.0 - float(i % 3) * 5.0, s.position.y + 4.0 + float(i / 3) * 5.0)
			var tv := 1 + i % 2
			var tsc := PropFactory.city_tree_scale(tv, rng.randf_range(6.0, 8.0))
			b.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(tsc, tsc, tsc)), Vector3(p.x, top, p.y)),
				Color.WHITE, Color(rng.randf(), rng.randf(), rng.randf(), 0.8))
		b.build(parent)
		g.use("paving", LandmarkMats.paving("paving", 2.6, Color(0.86, 0.82, 0.76), 3317, 3.0, 0.2))
		g.cap("paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(pr.grow(-0.2))), top + 0.01)
		LandmarkArenaDistrict._add_light(parent, base + Vector3(-20.0, 4.0, 22.0), 26.0)
	g.commit(parent, "SymphonyHallPodium")
	LandmarkArenaDistrict._occluder(parent, [[base + Vector3(4.0, 13.0, -4.0), Vector3(26.0, 24.0, 30.0)]])


# ============================================================================================
# The museum
# ============================================================================================

static func _museum_box(s: Rect2) -> Rect2:
	var w := minf(52.0, s.size.x - 8.0)
	var d := minf(52.0, s.size.y - 20.0)
	return Rect2(Vector2(s.get_center().x - w * 0.5, s.position.y + 3.0), Vector2(w, d))


static func _museum(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var r := _museum_box(s)
	var h := 27.0
	var veil := LandmarkMats.facade("museum_veil", "concrete", 5.0,
		{"tint": Color(0.93, 0.93, 0.91), "roughness": 0.72, "texture_contrast": 0.35, "grime": 0.15, "base_y": y0,
		"flood_strength": 0.7, "flood_base_y": y0, "flood_reach": 16.0, "flood_floor": 0.3, "flood_spacing": 6.9, "flood_color": Color(0.9, 0.95, 1.0)})
	var vault := LandmarkMats.facade("museum_vault", "concrete", 4.0, {"tint": Color(0.28, 0.28, 0.29), "roughness": 0.8, "texture_contrast": 0.5})
	var lobby := LandmarkMats.glass("museum", {"glass_tint": Color(0.14, 0.16, 0.17), "frame_color": Color(0.2, 0.2, 0.21),
		"grid": Vector2(2.3, 5.0), "frame_width": 0.06, "room_depth": 14.0, "storey": 5.0, "floor_y": y0, "interior_day": 0.25, "interior_night": 1.6})
	g.use("veil", veil)
	g.use("vault", vault)
	g.use("lobby", lobby)
	# The vault inside (the dark mass seen through the veil and under its lifted corners), and the
	# glass lobby at the foot.
	var vc := Vector3(r.get_center().x, y0 + 5.0 + (h - 6.5) * 0.5, r.get_center().y)
	g.box("vault", vc, Vector3(r.size.x - 4.0, h - 6.5, r.size.y - 4.0))
	var lr := r.grow(-2.2)
	var u := 0.0
	var poly := LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(lr))
	for i in poly.size():
		u = g.wall("lobby", poly[i], poly[(i + 1) % poly.size()], y0, y0 + 5.2, Color.WHITE, false, u)
	LandmarkGeo.shape_box(statics, Vector3(r.get_center().x, y0 + h * 0.5, r.get_center().y), Vector3(r.size.x - 3.0, h, r.size.y - 3.0))
	# The veil: every face a lattice of deep splayed openings.
	var cell := Vector2(2.3, 3.0) if detailed else Vector2(4.6, 6.0)
	var faces := [[Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y)], [Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y)],
		[Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y)], [Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y)]]
	for fi in faces.size():
		var a: Vector2 = faces[fi][0]
		var b: Vector2 = faces[fi][1]
		# The dimple on the east face (fi 1), toward the concert hall.
		_veil_face(g, a, b, y0, h, cell, fi == 1, detailed)
	# The coping over the veil's top edge, and the roof.
	g.box("veil", Vector3(r.get_center().x, y0 + h + 0.35, r.get_center().y), Vector3(r.size.x + 0.4, 0.7, r.size.y + 0.4), Color.WHITE, Basis(), 0.1 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, Vector3(r.get_center().x, y0 + h + 0.35, r.get_center().y), Vector3(r.size.x + 0.4, 0.7, r.size.y + 0.4))
	batch.add("museum_name", Signage.text_mesh(MUSEUM_NAME, 0.7, Signage.Letters.PRINT),
		Transform3D(LandmarkArenaDistrict._face(PI, 1.0), Vector3(r.get_center().x, y0 + 3.0, r.end.y + 0.95)), Color(0.15, 0.15, 0.16))
	batch.set_no_shadow("museum_name")
	if detailed:
		# The plaza: paving and a grove of trees in a grid, with benches.
		var plaza := Rect2(Vector2(s.position.x, r.end.y + 1.5), Vector2(s.size.x, s.end.y - r.end.y - 1.5))
		g.use("paving", LandmarkMats.paving("paving", 2.4, Color(0.88, 0.86, 0.82), 4471, 2.4, 0.2))
		g.cap("paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(s)), y0 + 0.03)
		var rng := RandomNumberGenerator.new()
		rng.seed = 60137
		for i in 5:
			for j in 2:
				var p := Vector2(plaza.position.x + 6.0 + float(i) * (plaza.size.x - 12.0) / 4.0, plaza.position.y + plaza.size.y * (0.3 + 0.45 * float(j)))
				var tv := 3
				var tsc := PropFactory.city_tree_scale(tv, rng.randf_range(5.5, 7.0))
				batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(tsc, tsc, tsc)), Vector3(p.x, y0, p.y)),
					Color(0.9, 0.95, 0.85), Color(rng.randf(), rng.randf(), rng.randf(), 0.7))
		LandmarkArenaDistrict._add_light(parent, Vector3(plaza.get_center().x, y0 + 6.0, plaza.get_center().y), 24.0)
	g.commit(parent, "LatticeMuseum")
	batch.build(parent)
	LandmarkArenaDistrict._occluder(parent, [[vc, Vector3(r.size.x - 4.0, h - 6.5, r.size.y - 4.0)]])


## One face of the veil from a to b (a CCW footprint edge, so it faces out): cells of `cell`
## metres, each an opening whose reveals splay back and skew, the look of the real honeycomb.
## The bottom cells near each corner are left out - the veil LIFTS at the corners - and on the
## dimpled face the lattice is pushed in round a point, the oculus.
static func _veil_face(g: LandmarkGeo, a: Vector2, b: Vector2, y0: float, h: float, cell: Vector2, dimple: bool, detailed: bool) -> void:
	var length := a.distance_to(b)
	var along := (b - a) / length
	var out2 := Vector2(-along.y, along.x)
	var cols := maxi(4, roundi(length / cell.x))
	var rows := maxi(3, roundi((h - 1.0) / cell.y))
	var cw := length / float(cols)
	var ch := (h - 1.0) / float(rows)
	var depth := 0.95
	var frame := 0.32
	var n := Vector3(out2.x, 0.0, out2.y)
	var f := [a, along, out2, y0, h, length, dimple]
	for j in rows:
		for i in cols:
			var corner := mini(i, cols - 1 - i)
			var lift := 2 if corner == 0 else (1 if corner <= 1 else 0)
			if j < lift:
				continue
			var u0 := float(i) * cw
			var v0 := float(j) * ch
			var u1 := u0 + cw
			var v1 := v0 + ch
			# The opening at the face, and further in, skewed: every other cell leans the other
			# way, which is what turns a grid into a honeycomb.
			var skew := 0.22 * (1.0 if (i + j) % 2 == 0 else -1.0)
			var fa := _veil_p(f, u0, v0, 0.0)
			var fb := _veil_p(f, u1, v0, 0.0)
			var fc := _veil_p(f, u1, v1, 0.0)
			var fd := _veil_p(f, u0, v1, 0.0)
			var oa := _veil_p(f, u0 + frame, v0 + frame, 0.0)
			var ob := _veil_p(f, u1 - frame, v0 + frame, 0.0)
			var oc := _veil_p(f, u1 - frame, v1 - frame, 0.0)
			var od := _veil_p(f, u0 + frame, v1 - frame, 0.0)
			# The face of the frame round the opening.
			_veil_quad(g, fa, fb, ob, oa, n)
			_veil_quad(g, fb, fc, oc, ob, n)
			_veil_quad(g, fc, fd, od, oc, n)
			_veil_quad(g, fd, fa, oa, od, n)
			if not detailed:
				continue
			var ia := _veil_p(f, u0 + frame * 1.9 + skew, v0 + frame * 2.4, depth)
			var ib := _veil_p(f, u1 - frame * 1.9 + skew, v0 + frame * 2.4, depth)
			var ic := _veil_p(f, u1 - frame * 1.9 + skew, v1 - frame, depth)
			var id := _veil_p(f, u0 + frame * 1.9 + skew, v1 - frame, depth)
			# The reveals, splayed and skewed, facing into the opening.
			var centre := (oa + oc + ia + ic) * 0.25
			for q: Array in [[oa, ob, ib, ia], [ob, oc, ic, ib], [oc, od, id, ic], [od, oa, ia, id]]:
				var q0: Vector3 = q[0]
				var q1: Vector3 = q[1]
				var q2: Vector3 = q[2]
				var q3: Vector3 = q[3]
				var mid := (q0 + q1 + q2 + q3) * 0.25
				_veil_quad(g, q0, q1, q2, q3, (centre - mid).normalized() + n * 0.3, Color(0.92, 0.92, 0.9))


## A point on the veil: `u` along the face, `v` up it, `back` metres in from its outer face,
## pushed in round the oculus on the dimpled face. `f` is [a, along, out, y0, h, length, dimple].
static func _veil_p(f: Array, u: float, v: float, back: float) -> Vector3:
	var a: Vector2 = f[0]
	var along: Vector2 = f[1]
	var out2: Vector2 = f[2]
	var p := a + along * u + out2 * (1.1 - back)
	if f[6]:
		var dc := Vector2(u - float(f[5]) * 0.5, v - (float(f[4]) - 1.0) * 0.52)
		p -= out2 * exp(-dc.length_squared() / (2.0 * 5.2 * 5.2)) * 2.6
	return Vector3(p.x, float(f[3]) + 1.0 + v, p.y)


static func _veil_quad(g: LandmarkGeo, q0: Vector3, q1: Vector3, q2: Vector3, q3: Vector3, n: Vector3, col: Color = Color.WHITE) -> void:
	g.quad("veil", q0, q1, q2, q3, n, Vector2(q0.x + q0.z, q0.y), Vector2(q1.x + q1.z, q1.y), Vector2(q2.x + q2.z, q2.y), Vector2(q3.x + q3.z, q3.y), col)


# ============================================================================================
# The station
# ============================================================================================

## Depth of the forecourt between the avenue (west) and the station's face.
static func _station_court(s: Rect2) -> float:
	return clampf(s.size.x * 0.24, 10.0, 17.0)


static func _station(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var stucco := LandmarkMats.facade("station_stucco", "plaster_white", 3.0,
		{"tint": STUCCO, "roughness": 0.9, "texture_contrast": 0.8, "grime": 0.35, "base_y": y0,
		"win_pitch": Vector2(4.4, 12.0), "win_size": Vector2(0.4, 0.42), "win_sill": 0.2, "win_band": Vector2(y0 + 1.0, y0 + 11.0), "lit_ratio": 0.8,
		"lit_color": Color(1.0, 0.78, 0.5), "flood_strength": 0.8, "flood_base_y": y0, "flood_reach": 12.0, "flood_floor": 0.3, "flood_spacing": 4.4})
	var plain_stucco := LandmarkMats.facade("station_tower", "plaster_white", 3.0,
		{"tint": STUCCO, "roughness": 0.9, "texture_contrast": 0.8, "grime": 0.3, "base_y": y0,
		"flood_strength": 1.0, "flood_base_y": y0, "flood_reach": 26.0, "flood_floor": 0.35, "flood_spacing": 3.0})
	var tile := LandmarkMats.clay("station")
	var arch_glass := LandmarkMats.glass("station", {"glass_tint": Color(0.16, 0.14, 0.12), "frame_color": Color(0.28, 0.2, 0.14),
		"grid": Vector2(1.2, 1.6), "frame_width": 0.07, "room_depth": 18.0, "storey": 14.0, "floor_y": y0, "interior_day": 0.3, "interior_night": 2.0,
		"interior_color": Color(1.0, 0.78, 0.5)})
	var wood := LandmarkMats.plain("station_wood", Color(0.36, 0.24, 0.15), 0.7)
	g.use("stucco", stucco)
	g.use("plain", plain_stucco)
	g.use("tile", tile)
	g.use("arch", arch_glass)
	g.use("wood", wood)
	var bev := 0.08 if detailed else 0.0
	var court := _station_court(s)
	var fx := s.position.x + court # the station's west face
	# The main hall: long, under a gable of barrel tiles.
	var hall := Rect2(Vector2(fx + 4.0, s.position.y + 4.0), Vector2(minf(22.0, s.size.x * 0.33), s.size.y - 8.0))
	var hh := 12.0
	var hc := Vector3(hall.get_center().x, y0 + hh * 0.5, hall.get_center().y)
	g.box("stucco", hc, Vector3(hall.size.x, hh, hall.size.y), Color.WHITE, Basis(), bev, false, 4.4)
	LandmarkGeo.shape_box(statics, hc, Vector3(hall.size.x, hh, hall.size.y))
	_gable(g, "tile", "plain", Rect2(hall.position - Vector2(0.8, 0.8), hall.size + Vector2(1.6, 1.6)), y0 + hh, 5.5, true, statics)
	# The entrance: a taller block standing forward of the hall, its gable to the avenue, the great
	# arch in it.
	var ew := 18.0
	var ez := hall.get_center().y - 5.0
	var ent := Rect2(Vector2(fx, ez - ew * 0.5), Vector2(hall.position.x + hall.size.x * 0.5 - fx, ew))
	var eh := 17.0
	_arch_block(g, ent, y0, eh, 10.0, 13.0, statics, detailed)
	_gable(g, "tile", "plain", Rect2(ent.position - Vector2(0.8, 0.8), ent.size + Vector2(1.6, 1.6)), y0 + eh, 5.0, false, statics)
	# Arcades either side of the entrance, along the avenue face: arches on piers under a lean-to
	# of tiles.
	for side: float in [-1.0, 1.0]:
		var z0 := ent.position.y - 0.2 if side < 0.0 else ent.end.y + 0.2
		var z1 := hall.position.y + 1.0 if side < 0.0 else hall.end.y - 1.0
		_arcade(g, fx, minf(z0, z1), maxf(z0, z1), hall.position.x, y0, statics, detailed)
	# The clock tower, south of the entrance.
	var tw := 9.0
	var tcz := ent.end.y + tw * 0.5 + 2.0
	var tcx := hall.position.x + tw * 0.5 + 1.0
	var th := 30.0
	g.box("plain", Vector3(tcx, y0 + th * 0.5, tcz), Vector3(tw, th, tw), Color.WHITE, Basis(), bev)
	LandmarkGeo.shape_box(statics, Vector3(tcx, y0 + th * 0.5, tcz), Vector3(tw, th, tw))
	# The belfry: open arches on every face over a slim core, a cornice, the tiled pyramid, a finial.
	var by := y0 + th
	g.box("plain", Vector3(tcx, by + 3.0, tcz), Vector3(tw - 3.6, 6.0, tw - 3.6), Color(0.9, 0.86, 0.78))
	for f in 4:
		var ang := float(f) * PI * 0.5
		var out := Vector3(sin(ang), 0.0, cos(ang))
		var along := Vector3(cos(ang), 0.0, -sin(ang))
		for sgn: float in [-1.0, 1.0]:
			g.box("plain", Vector3(tcx, by + 3.0, tcz) + out * (tw * 0.5 - 0.5) + along * sgn * (tw * 0.5 - 0.6), Vector3(1.2, 6.0, 1.0), Color.WHITE, LandmarkGeo.yaw(ang), bev)
		g.box("plain", Vector3(tcx, by + 5.4, tcz) + out * (tw * 0.5 - 0.5), Vector3(tw, 1.2, 1.0), Color.WHITE, LandmarkGeo.yaw(ang), bev)
	LandmarkGeo.shape_box(statics, Vector3(tcx, by + 3.0, tcz), Vector3(tw, 6.0, tw))
	g.box("plain", Vector3(tcx, by + 6.4, tcz), Vector3(tw + 1.2, 0.8, tw + 1.2), Color.WHITE, Basis(), bev)
	_hip(g, "tile", Vector2(tcx, tcz), tw + 1.0, by + 6.8, 6.5, statics)
	g.use("finial", LandmarkMats.plain("station_finial", Color(0.72, 0.6, 0.3), 0.3, 0.8))
	g.cylinder("finial", Vector3(tcx, by + 13.3, tcz), 0.18, 2.4, 8)
	# Clock faces, one per side, lit after dark.
	g.use("clock", LandmarkMats.glow("station_clock", Color(1.0, 0.96, 0.84)))
	g.use("hands", LandmarkMats.plain("station_hands", Color(0.08, 0.08, 0.08), 0.5))
	for f in 4:
		var ang := float(f) * PI * 0.5
		var out := Vector3(sin(ang), 0.0, cos(ang))
		var face_c := Vector3(tcx, y0 + th - 4.5, tcz)
		# A stone surround proud of the wall, the dial on it, the hands on the dial.
		g.box("plain", face_c + out * (tw * 0.5 + 0.05), Vector3(4.2, 4.2, 0.1), Color(0.86, 0.8, 0.7), LandmarkGeo.yaw(ang))
		var cc := face_c + out * (tw * 0.5 + 0.12)
		_disc(g, "clock", cc, out, 1.8, 24)
		g.box("hands", cc + out * 0.03 + Vector3(0.0, 0.5, 0.0), Vector3(0.14, 1.1, 0.05), Color.WHITE, LandmarkGeo.yaw(ang))
		g.box("hands", cc + out * 0.03 + Vector3(cos(ang), 0.0, -sin(ang)) * 0.55, Vector3(1.1, 0.12, 0.05), Color.WHITE, LandmarkGeo.yaw(ang))
	# The name over the arch.
	batch.add("station_name", Signage.text_mesh(STATION_NAME, 1.1, Signage.Letters.PRINT),
		Transform3D(LandmarkArenaDistrict._face(PI * 0.5, 1.0), Vector3(fx - 0.06, y0 + 14.9, ent.get_center().y)), Color(0.3, 0.2, 0.12))
	batch.set_no_shadow("station_name")
	# The platforms behind: two islands under butterfly canopies, rails between them.
	var px0 := hall.end.x + 4.0
	if s.end.x - px0 > 12.0:
		_platforms(g, batch, Rect2(Vector2(px0, s.position.y + 1.0), Vector2(s.end.x - px0 - 1.0, s.size.y - 2.0)), y0, statics, detailed)
	if detailed:
		_station_court_detail(g, batch, parent, s, court, y0, ent)
	g.commit(parent, "PuebloStation")
	batch.build(parent)
	LandmarkArenaDistrict._occluder(parent, [[hc, Vector3(hall.size.x, hh, hall.size.y)]])


## A block with a great arched opening in its west face: the walls round the arch, the arch's
## soffit and jambs, and a glass screen with doors set back inside it.
static func _arch_block(g: LandmarkGeo, r: Rect2, y0: float, h: float, aw: float, ah: float, statics: StaticBody3D, detailed: bool) -> void:
	var x := r.position.x
	var zc := r.get_center().y
	var z0 := r.position.y
	var z1 := r.end.y
	var rad := aw * 0.5
	var spring := ah - rad
	var depth := 2.4
	# Back, sides and roof of the block as walls (the west face is built round the arch).
	# Its west face sits a little behind the glass screen in the arch, never in its plane.
	var back := Vector3(r.get_center().x + (depth + 0.1) * 0.5, y0 + h * 0.5, zc)
	g.box("plain", back, Vector3(r.size.x - depth - 0.1, h, r.size.y), Color.WHITE, Basis(), 0.0)
	LandmarkGeo.shape_box(statics, back, Vector3(r.size.x - depth - 0.1, h, r.size.y))
	# The block's side walls over the depth of the arch wall.
	for zz: float in [z0, z1]:
		var nz := -1.0 if zz == z0 else 1.0
		g.quad("plain", Vector3(x, y0, zz), Vector3(x + depth + 0.1, y0, zz), Vector3(x + depth + 0.1, y0 + h, zz), Vector3(x, y0 + h, zz), Vector3(0.0, 0.0, nz),
			Vector2(0.0, y0), Vector2(depth, y0), Vector2(depth, y0 + h), Vector2(0.0, y0 + h))
	# West face: left and right of the arch, full height; above the arch, down to its curve.
	var segs := 16 if detailed else 6
	var n := Vector3(-1.0, 0.0, 0.0)
	var face_x := x
	g.quad("plain", Vector3(face_x, y0, z0), Vector3(face_x, y0 + h, z0), Vector3(face_x, y0 + h, zc - rad), Vector3(face_x, y0, zc - rad), n,
		Vector2(0.0, y0), Vector2(0.0, y0 + h), Vector2(zc - rad - z0, y0 + h), Vector2(zc - rad - z0, y0))
	g.quad("plain", Vector3(face_x, y0, zc + rad), Vector3(face_x, y0 + h, zc + rad), Vector3(face_x, y0 + h, z1), Vector3(face_x, y0, z1), n,
		Vector2(zc + rad - z0, y0), Vector2(zc + rad - z0, y0 + h), Vector2(z1 - z0, y0 + h), Vector2(z1 - z0, y0))
	for i in segs:
		var a0 := PI * float(i) / float(segs)
		var a1 := PI * float(i + 1) / float(segs)
		var p0 := Vector3(face_x, y0 + spring + sin(a0) * rad, zc - cos(a0) * rad)
		var p1 := Vector3(face_x, y0 + spring + sin(a1) * rad, zc - cos(a1) * rad)
		var t0 := Vector3(face_x, y0 + h, p0.z)
		var t1 := Vector3(face_x, y0 + h, p1.z)
		g.quad("plain", p0, t0, t1, p1, n, Vector2(p0.z - z0, p0.y), Vector2(p0.z - z0, y0 + h), Vector2(p1.z - z0, y0 + h), Vector2(p1.z - z0, p1.y))
		# The soffit of the arch, facing down into the opening.
		var q0 := p0 + Vector3(depth, 0.0, 0.0)
		var q1 := p1 + Vector3(depth, 0.0, 0.0)
		var mid := (p0 + p1) * 0.5
		var inward := Vector3(0.0, y0 + spring, zc) - Vector3(0.0, mid.y, mid.z)
		g.quad("plain", p0, q0, q1, p1, Vector3(0.0, inward.y, inward.z).normalized(), Vector2(0.0, a0 * rad), Vector2(depth, a0 * rad), Vector2(depth, a1 * rad), Vector2(0.0, a1 * rad), Color(0.9, 0.86, 0.8))
		# The glass screen inside the arch, top part.
		var c0 := Vector3(face_x + depth, y0 + spring, zc)
		g.tri("arch", c0, p0 + Vector3(depth, 0.0, 0.0), p1 + Vector3(depth, 0.0, 0.0), n, Vector2(zc - z0, y0 + spring), Vector2(p0.z - z0, p0.y), Vector2(p1.z - z0, p1.y))
	# Jambs and the lower glass screen with the doors.
	for sgn: float in [-1.0, 1.0]:
		var zj := zc + sgn * rad
		g.quad("plain", Vector3(face_x, y0, zj), Vector3(face_x + depth, y0, zj), Vector3(face_x + depth, y0 + spring, zj), Vector3(face_x, y0 + spring, zj), Vector3(0.0, 0.0, -sgn),
			Vector2(0.0, y0), Vector2(depth, y0), Vector2(depth, y0 + spring), Vector2(0.0, y0 + spring), Color(0.9, 0.86, 0.8))
	g.quad("arch", Vector3(face_x + depth, y0, zc - rad), Vector3(face_x + depth, y0 + spring, zc - rad), Vector3(face_x + depth, y0 + spring, zc + rad), Vector3(face_x + depth, y0, zc + rad), n,
		Vector2(0.0, y0), Vector2(0.0, y0 + spring), Vector2(aw, y0 + spring), Vector2(aw, y0))
	if detailed:
		# Timber doors in the screen.
		for dz: float in [-2.6, 0.0, 2.6]:
			g.box("wood", Vector3(face_x + depth - 0.1, y0 + 1.6, zc + dz), Vector3(0.12, 3.2, 2.2), Color.WHITE)
		# A moulded surround round the arch.
		for i in segs:
			var a0 := PI * float(i) / float(segs)
			var a1 := PI * float(i + 1) / float(segs)
			var p := Vector3(face_x - 0.2, y0 + spring + sin((a0 + a1) * 0.5) * (rad + 0.45), zc - cos((a0 + a1) * 0.5) * (rad + 0.45))
			g.box("plain", p, Vector3(0.4, 0.8, PI * (rad + 0.45) / float(segs) + 0.05), Color(0.92, 0.88, 0.8), Basis(Vector3.RIGHT, -((a0 + a1) * 0.5 - PI * 0.5)), 0.05)


## An arcade along the west face from z0 to z1: piers, arches between them, a lean-to roof back
## to the hall wall at `back_x`.
static func _arcade(g: LandmarkGeo, fx: float, z0: float, z1: float, back_x: float, y0: float, statics: StaticBody3D, detailed: bool) -> void:
	var length := z1 - z0
	if length < 5.0:
		return
	var bays := maxi(1, int(length / 4.4))
	var bay := length / float(bays)
	var pier := 0.9
	var ah := 6.4
	var h := 8.0
	var deep := back_x - fx
	var rad := (bay - pier) * 0.5
	var spring := ah - rad
	var n := Vector3(-1.0, 0.0, 0.0)
	var segs := 8 if detailed else 3
	for b in bays:
		var za := z0 + bay * float(b)
		var zc := za + bay * 0.5
		# Pier.
		g.box("plain", Vector3(fx + 0.4, y0 + h * 0.5, za + pier * 0.25), Vector3(0.8, h, pier * 0.5), Color.WHITE)
		g.box("plain", Vector3(fx + 0.4, y0 + h * 0.5, za + bay - pier * 0.25), Vector3(0.8, h, pier * 0.5), Color.WHITE)
		# Spandrel over the arch.
		for i in segs:
			var a0 := PI * float(i) / float(segs)
			var a1 := PI * float(i + 1) / float(segs)
			var p0 := Vector3(fx, y0 + spring + sin(a0) * rad, zc - cos(a0) * rad)
			var p1 := Vector3(fx, y0 + spring + sin(a1) * rad, zc - cos(a1) * rad)
			g.quad("plain", p0, Vector3(fx, y0 + h, p0.z), Vector3(fx, y0 + h, p1.z), p1, n, Vector2(p0.z, p0.y), Vector2(p0.z, y0 + h), Vector2(p1.z, y0 + h), Vector2(p1.z, p1.y))
			if detailed:
				var q0 := p0 + Vector3(0.8, 0.0, 0.0)
				var q1 := p1 + Vector3(0.8, 0.0, 0.0)
				var mid := (p0 + p1) * 0.5
				var inward := Vector3(0.0, y0 + spring - mid.y, zc - mid.z).normalized()
				g.quad("plain", p0, q0, q1, p1, inward, Vector2(0.0, a0), Vector2(0.8, a0), Vector2(0.8, a1), Vector2(0.0, a1), Color(0.9, 0.86, 0.8))
	# The loggia's ceiling and lean-to roof back to the hall.
	g.box("plain", Vector3((fx + back_x) * 0.5, y0 + h - 0.2, (z0 + z1) * 0.5), Vector3(deep, 0.4, length), Color(0.88, 0.84, 0.76))
	LandmarkGeo.shape_box(statics, Vector3((fx + back_x) * 0.5, y0 + h - 0.2, (z0 + z1) * 0.5), Vector3(deep, 0.4, length))
	_shed(g, "tile", Rect2(Vector2(fx - 0.6, z0), Vector2(deep + 0.6, length)), y0 + h, 1.3)
	for b in bays + 1:
		LandmarkGeo.shape_box(statics, Vector3(fx + 0.4, y0 + h * 0.5, z0 + bay * float(b)), Vector3(0.8, h, pier))


## A gable roof over `r`: ridge along the rect's long axis (or along x when `along_z` is false),
## `rise` metres high, tiled slopes, stucco gable ends. Tile UV: u along the eave, v up the slope.
static func _gable(g: LandmarkGeo, tile_key: String, end_key: String, r: Rect2, y: float, rise: float, along_z: bool, statics: StaticBody3D) -> void:
	var c := r.get_center()
	if along_z:
		var hw := r.size.x * 0.5
		var slope := sqrt(hw * hw + rise * rise)
		for sgn: float in [-1.0, 1.0]:
			var e0 := Vector3(c.x + sgn * hw, y, r.position.y)
			var e1 := Vector3(c.x + sgn * hw, y, r.end.y)
			var r0 := Vector3(c.x, y + rise, r.position.y)
			var r1 := Vector3(c.x, y + rise, r.end.y)
			var n := Vector3(sgn * rise, hw, 0.0).normalized()
			g.quad(tile_key, e0, e1, r1, r0, n, Vector2(0.0, 0.0), Vector2(r.size.y, 0.0), Vector2(r.size.y, slope), Vector2(0.0, slope))
			# A slab under each slope, so a player can land on the roof and slide off it.
			var mid := (e0 + r1) * 0.5
			var down := Vector3(sgn * hw, -rise, 0.0).normalized()
			LandmarkGeo.shape_box(statics, mid - n * 0.2, Vector3(slope, 0.4, r.size.y), Basis(down, n, Vector3(0.0, 0.0, 1.0)))
		for zz: float in [r.position.y + 0.8, r.end.y - 0.8]:
			var nz := -1.0 if zz < c.y else 1.0
			g.tri(end_key, Vector3(c.x - hw + 0.8, y, zz), Vector3(c.x + hw - 0.8, y, zz), Vector3(c.x, y + rise - 0.3, zz), Vector3(0.0, 0.0, nz),
				Vector2(0.0, y), Vector2(r.size.x, y), Vector2(hw, y + rise))
	else:
		var hd := r.size.y * 0.5
		var slope := sqrt(hd * hd + rise * rise)
		for sgn: float in [-1.0, 1.0]:
			var e0 := Vector3(r.position.x, y, c.y + sgn * hd)
			var e1 := Vector3(r.end.x, y, c.y + sgn * hd)
			var r0 := Vector3(r.position.x, y + rise, c.y)
			var r1 := Vector3(r.end.x, y + rise, c.y)
			var n := Vector3(0.0, hd, sgn * rise).normalized()
			g.quad(tile_key, e0, e1, r1, r0, n, Vector2(0.0, 0.0), Vector2(r.size.x, 0.0), Vector2(r.size.x, slope), Vector2(0.0, slope))
		for xx: float in [r.position.x + 0.8, r.end.x - 0.8]:
			var nx := -1.0 if xx < c.x else 1.0
			g.tri(end_key, Vector3(xx, y, c.y - hd + 0.8), Vector3(xx, y, c.y + hd - 0.8), Vector3(xx, y + rise - 0.3, c.y), Vector3(nx, 0.0, 0.0),
				Vector2(0.0, y), Vector2(r.size.y, y), Vector2(hd, y + rise))
		LandmarkGeo.shape_box(statics, Vector3(c.x, y + rise * 0.4, c.y), Vector3(r.size.x, rise * 0.8, r.size.y * 0.6))


## A lean-to (shed) roof over `r` falling toward -X by `fall` metres.
static func _shed(g: LandmarkGeo, key: String, r: Rect2, y: float, fall: float) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.position.x, y, r.end.y)
	var cc := Vector3(r.end.x, y + fall, r.end.y)
	var d := Vector3(r.end.x, y + fall, r.position.y)
	var slope := sqrt(r.size.x * r.size.x + fall * fall)
	g.quad(key, a, b, cc, d, Vector3(-fall, r.size.x, 0.0).normalized(), Vector2(0.0, 0.0), Vector2(r.size.y, 0.0), Vector2(r.size.y, slope), Vector2(0.0, slope))


## A four-sided pyramid (hip) roof of tiles: square `w` at height y, apex `rise` above.
static func _hip(g: LandmarkGeo, key: String, c: Vector2, w: float, y: float, rise: float, statics: StaticBody3D) -> void:
	var h := w * 0.5
	var apex := Vector3(c.x, y + rise, c.y)
	var corners := [Vector3(c.x - h, y, c.y - h), Vector3(c.x + h, y, c.y - h), Vector3(c.x + h, y, c.y + h), Vector3(c.x - h, y, c.y + h)]
	var slope := sqrt(h * h + rise * rise)
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var mid := (a + b) * 0.5
		var out := Vector3(mid.x - c.x, 0.0, mid.z - c.y).normalized()
		var n := (out * rise + Vector3.UP * h).normalized()
		g.tri(key, a, b, apex, n, Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(h, slope))
	LandmarkGeo.shape_box(statics, Vector3(c.x, y + rise * 0.3, c.y), Vector3(w * 0.7, rise * 0.6, w * 0.7))


## A flat disc facing `n` (a clock face).
static func _disc(g: LandmarkGeo, key: String, at: Vector3, n: Vector3, r: float, segs: int) -> void:
	var right := n.cross(Vector3.UP).normalized()
	var up := Vector3.UP
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := at + (right * cos(a0) + up * sin(a0)) * r
		var p1 := at + (right * cos(a1) + up * sin(a1)) * r
		g.tri(key, at, p0, p1, n, Vector2(0.5, 0.5), Vector2(0.5 + 0.5 * cos(a0), 0.5 + 0.5 * sin(a0)), Vector2(0.5 + 0.5 * cos(a1), 0.5 + 0.5 * sin(a1)), Color(1.0, 0.97, 0.9))


## The platforms: island platforms under butterfly canopies on columns, rails between them.
static func _platforms(g: LandmarkGeo, batch: MultiMeshBatch, r: Rect2, y0: float, statics: StaticBody3D, detailed: bool) -> void:
	g.use("platform", LandmarkMats.facade("station_platform", "concrete", 3.0, {"tint": Color(0.72, 0.71, 0.69), "roughness": 0.9, "joint_spacing": Vector2(0.0, 0.0)}))
	g.use("steel", LandmarkMats.plain("station_steel", Color(0.22, 0.26, 0.24), 0.5, 0.6))
	g.use("ballast", LandmarkMats.plain("station_ballast", Color(0.36, 0.34, 0.32), 0.95))
	g.cap("ballast", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(r)), y0 + 0.02)
	var islands := 2 if r.size.x > 18.0 else 1
	var pitch := r.size.x / float(islands)
	for i in islands:
		var cx := r.position.x + pitch * (float(i) + 0.5)
		var pc := Vector3(cx, y0 + 0.5, r.get_center().y)
		g.box("platform", pc, Vector3(4.2, 1.0, r.size.y - 4.0), Color.WHITE, Basis(), 0.05 if detailed else 0.0)
		LandmarkGeo.shape_box(statics, pc, Vector3(4.2, 1.0, r.size.y - 4.0))
		# The butterfly canopy: two slopes rising outward from a central gutter.
		var cy := y0 + 5.2
		for sgn: float in [-1.0, 1.0]:
			var a := Vector3(cx, cy, r.position.y + 3.0)
			var b := Vector3(cx, cy, r.end.y - 3.0)
			var cc := Vector3(cx + sgn * 3.4, cy + 0.9, r.end.y - 3.0)
			var d := Vector3(cx + sgn * 3.4, cy + 0.9, r.position.y + 3.0)
			g.quad("steel", a, b, cc, d, Vector3(-sgn * 0.26, 1.0, 0.0).normalized(), Vector2(a.z, 0.0), Vector2(b.z, 0.0), Vector2(b.z, 3.4), Vector2(a.z, 3.4))
			g.quad("steel", a, d, cc, b, Vector3(sgn * 0.26, -1.0, 0.0).normalized(), Vector2(a.z, 0.0), Vector2(a.z, 3.4), Vector2(b.z, 3.4), Vector2(b.z, 0.0), Color(0.7, 0.7, 0.7))
		LandmarkGeo.shape_box(statics, Vector3(cx, cy + 0.45, r.get_center().y), Vector3(6.8, 0.9, r.size.y - 6.0))
		var cols := maxi(2, int((r.size.y - 6.0) / 9.0))
		for k in cols + 1:
			var z := r.position.y + 3.0 + (r.size.y - 6.0) * float(k) / float(cols)
			g.box("steel", Vector3(cx, y0 + 1.0 + (cy - y0 - 1.0) * 0.5, z), Vector3(0.3, cy - y0 - 1.0, 0.3), Color.WHITE)
	if detailed:
		# Rails: pairs of thin steel bars in the gaps between the platforms.
		var rail := PropFactory.box("station_rail", Vector3(0.08, 0.14, 1.0), Color(0.42, 0.40, 0.38))
		for i in islands + 1:
			var gx := r.position.x + pitch * float(i)
			if gx < r.position.x + 1.5 or gx > r.end.x - 1.5:
				continue
			for dx: float in [-0.72, 0.72]:
				batch.add("station_rail", rail, Transform3D(Basis().scaled(Vector3(1.0, 1.0, r.size.y - 2.0)), Vector3(gx + dx, y0 + 0.1, r.get_center().y)))


## The forecourt: paving, rows of palms, lamps, a lawn strip.
static func _station_court_detail(g: LandmarkGeo, batch: MultiMeshBatch, parent: Node3D, s: Rect2, court: float, y0: float, ent: Rect2) -> void:
	g.use("paving", LandmarkMats.paving("pavers", 2.6, Color(0.9, 0.84, 0.76), 7711, 3.0, 0.25))
	g.cap("paving", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(Rect2(s.position, Vector2(court + 4.0, s.size.y)))), y0 + 0.03)
	g.use("lawn", PropFactory.lawn(Color(0.5, 0.62, 0.32), 7713, 0.3, 3.0))
	for side: float in [-1.0, 1.0]:
		var za := ent.position.y - 4.0 if side < 0.0 else ent.end.y + 4.0
		var zb := s.position.y + 3.0 if side < 0.0 else s.end.y - 3.0
		var lr := Rect2(Vector2(s.position.x + 2.0, minf(za, zb)), Vector2(court - 5.0, absf(zb - za)))
		if lr.size.y > 3.0:
			g.cap("lawn", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(lr)), y0 + 0.07)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719
	for row: float in [s.position.x + 3.5, s.position.x + court - 3.0]:
		var n := maxi(3, int(s.size.y / 9.0))
		for i in n:
			var z := s.position.y + 4.0 + (s.size.y - 8.0) * float(i) / float(n - 1)
			if absf(z - ent.get_center().y) < 6.0:
				continue
			var v := (i + int(row)) % PropFactory.PALM_VARIANTS
			batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(row, y0, z)))
	for z: float in [ent.position.y - 2.0, ent.end.y + 2.0]:
		batch.add("station_lamp", PropFactory.model_lamp(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(s.position.x + court - 1.0, y0, z)))
		batch.add("station_pool", PropFactory.light_pool(), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(13.0, 1.0, 13.0)), Vector3(s.position.x + court - 1.0, y0 + 0.08, z)))
	batch.set_no_shadow("station_pool")
	LandmarkArenaDistrict._add_light(parent, Vector3(s.position.x + court * 0.5, y0 + 6.0, ent.get_center().y), 24.0)
