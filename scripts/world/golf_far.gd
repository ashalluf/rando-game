class_name GolfFar
extends RefCounted
## The golf course in the far city (Skyline): what a site block of the course draws past the LOD
## ring. The block's plate is the rough's colour (GolfBuild.capture_steps() records the ground);
## on it, thin plate-flagged boxes (building_lod.gdshader's ground branch: plain colour, a slow
## mottle) for the fairways - a box per centre-line segment, turned to it -, the greens, the
## bunkers, the range and the pond, lifted a little over the plate; the course's trees as
## canopies standing on the real ground; the clubhouse comes with the capture (HouseKit's boxes).

## Far colours (linear, like CityChunk.far_tint()).
const ROUGH_FAR := Color(0.105, 0.17, 0.065)
const FAIRWAY_FAR := Color(0.16, 0.27, 0.085)
const GREEN_FAR := Color(0.12, 0.25, 0.08)
const SAND_FAR := Color(0.62, 0.55, 0.42)
const WATER_FAR := Color(0.035, 0.055, 0.06)
const RANGE_FAR := Color(0.15, 0.25, 0.08)
## How far over the plate the turf boxes stand (m): enough that the far depth buffer keeps them
## apart from it, too little to see.
const LIFT := 0.35
const PLATE_FLAG := 2.0


static func add(plan: CityPlan, k: Vector2i, ch: CityChunk, work: Dictionary) -> void:
	var lay := GolfCourse.layout(plan)
	if lay.is_empty():
		return
	var area := plan.owned_rect(k.x, k.y).intersection(lay.rect as Rect2)
	if area.size.x < 1.0 or area.size.y < 1.0:
		return
	var xforms: Array = work.xforms
	var colors: Array = work.colors
	var customs: Array = work.customs
	var put := func(c: Vector2, dir: Vector2, w: float, l: float, col: Color, lift: float) -> void:
		var right := Vector3(-dir.y, 0.0, dir.x)
		var fwd := Vector3(dir.x, 0.0, dir.y)
		var y := ch._gy(c.x, c.y) + CityChunk.SIDEWALK_TOP + lift
		xforms.append(Transform3D(Basis(right * w, Vector3(0.0, 0.3, 0.0), fwd * l), Vector3(c.x, y - 0.15, c.y)))
		colors.append(Color(col.r, col.g, col.b, 1.0))
		customs.append(Color(0.0, 0.0, float(absi(hash([k, xforms.size()])) % 997) / 997.0, PLATE_FLAG))
	var r: Rect2 = lay.range
	if area.has_point(r.get_center()):
		put.call(r.get_center(), Vector2(0.0, 1.0), r.size.x, r.size.y, RANGE_FAR, LIFT)
	for h: Dictionary in lay.holes:
		var fw: PackedVector2Array = h.fw
		for i in fw.size() - 1:
			var m := (fw[i] + fw[i + 1]) * 0.5
			if not area.has_point(m):
				continue
			var d := fw[i + 1] - fw[i]
			put.call(m, d.normalized(), float(h.fw_half) * 1.9, d.length() + float(h.fw_half), FAIRWAY_FAR, LIFT)
		var g: Dictionary = h.green
		if area.has_point(g.c):
			put.call(g.c, Vector2.from_angle(float(g.ang)), float(g.b) * 1.7, float(g.a) * 1.7, GREEN_FAR, LIFT + 0.05)
		for bk: Dictionary in h.bunkers:
			if area.has_point(bk.c):
				put.call(bk.c, Vector2.from_angle(float(bk.ang)), float(bk.b) * 1.6, float(bk.a) * 1.6, SAND_FAR, LIFT + 0.1)
		for t: Dictionary in h.tees:
			if area.has_point(t.c):
				put.call(t.c, t.u, (t.half as Vector2).x * 2.0, (t.half as Vector2).y * 2.0, FAIRWAY_FAR, LIFT + 0.05)
	var pb: Rect2 = lay.pond_bounds
	if area.has_point(pb.get_center()):
		put.call(pb.get_center(), Vector2(0.0, 1.0), pb.size.x * 0.8, pb.size.y * 0.8, WATER_FAR, LIFT + 0.1)
	# The trees, as canopies on the real ground.
	var veg: Array = work.veg
	var veg_colors: Array = work.veg_colors
	var veg_custom: Array = work.veg_custom
	for t: Array in lay.trees:
		var p: Vector2 = t[0]
		if not area.has_point(p):
			continue
		var v := float(t[2])
		var gy := ch._gy(p.x, p.y) + CityChunk.SIDEWALK_TOP
		var rr: float
		var th: float
		var lift: float
		var col: Color
		match int(t[1]):
			1, 4:
				rr = 3.2 + v
				th = 9.0 + v * 4.0
				lift = 3.0
				col = Color(0.05, 0.085, 0.045)
			2:
				rr = 5.0 + v * 2.0
				th = 5.0
				lift = 3.0
				col = Color(0.30, 0.25, 0.48)
			3:
				rr = 3.6 + v
				th = 2.2
				lift = 9.0 + v * 4.0
				col = Color(0.13, 0.17, 0.08)
			_:
				rr = 5.0 + v * 2.5
				th = 5.0 + v * 2.0
				lift = 2.6
				col = Color(0.075, 0.115, 0.050).lerp(Color(0.135, 0.170, 0.075), v)
		veg.append(Transform3D(Basis(Vector3.UP, v * 6.28).scaled(Vector3(rr, th, rr * 0.9)), Vector3(p.x, gy + lift + th * 0.5, p.y)))
		veg_colors.append(col)
		veg_custom.append(Color(1.0, 0.0, 0.0, 0.0))
