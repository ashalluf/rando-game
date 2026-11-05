extends RefCounted
## The wingsuit at golden hour (the wingsuit_golden reference camera in tools/refcams/cameras_w8.json;
## WingsuitFx's look2 and Rc5Wingsuit), for tests/smoke_test.gd. Loaded at run time, not named
## there, so it compiles after the autoloads.
##
## Checks: the camera row and its wingsuit staging; the inflated two-skin membrane (top and bottom
## skins apart by an airfoil's depth, closed at the trailing edge and the wingtip, cells on the top
## skin); the old single sheet under WINGSUIT_LOOK=0; the vapour starts at a trimmed glide's speed;
## the vapour and fabric shaders' passes off by default; THE LATTICE's roof lattice and its A/B.

var _t: Object


func run(t: Object) -> void:
	_t = t
	_camera()
	_membrane()
	_shaders()
	_roof()


func _camera() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in parsed.get("cameras", []):
			if String(c.get("name", "")) == "wingsuit_golden":
				row = c
	var ws: Dictionary = row.get("wingsuit", {})
	var at: Array = ws.get("at", [])
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 18.0 and String(row.get("weather", "")) == "clear"
		and at.size() == 3 and float(at[1]) >= 100.0 and float(at[1]) <= 140.0 and float(ws.get("dist", 0.0)) == 6.0,
		"the wingsuit_golden camera: 18:00 clear, the hero ~120 m up, the chase camera 6 m behind")
	# Over Bunker Hill (LaHills' polygon: x 2100-2855, z -1097..-9).
	_t._check(at.size() == 3 and float(at[0]) > 2100.0 and float(at[0]) < 2855.0 and float(at[2]) > -1097.0 and float(at[2]) < -9.0,
		"the glide passes over Bunker Hill")
	_t._check(ResourceLoader.exists("res://tools/refcams/wingsuit_stage.gd")
		and FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd").contains("wingsuit_stage.gd"),
		"refcams_shot stages a wingsuit row through wingsuit_stage.gd")


func _membrane() -> void:
	var was: bool = WingsuitFx.look2
	var fx := WingsuitFx.new()
	# A flat 1.0 x 0.8 m membrane facing up (his back, -front, is +Y).
	var front := Vector3.DOWN
	var shape := func(u: float, v: float) -> Vector3:
		return Vector3(u * 1.0, 0.0, v * 0.8)
	WingsuitFx.look2 = true
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	fx.call("_grid", verts, normals, tangents, uvs, uv2s, idx, front, 1.0, 0.0, shape)
	var per := (WingsuitFx.GRID_U2 + 1) * (WingsuitFx.GRID_V2 + 1)
	_t._check(verts.size() == per * 2, "the inflated wing is two skins (%d vertices, %d a skin)" % [verts.size(), per])
	var deepest := 0.0
	var trailing := 0.0
	var tip := 0.0
	var below := true
	for j in WingsuitFx.GRID_V2 + 1:
		for i in WingsuitFx.GRID_U2 + 1:
			var k := j * (WingsuitFx.GRID_U2 + 1) + i
			var gap := verts[k].y - verts[per + k].y
			below = below and gap >= -1e-5 and uv2s[per + k].y >= 3.5 and uv2s[k].y < 1.5
			if j == WingsuitFx.GRID_V2:
				trailing = maxf(trailing, absf(gap))
			if i == WingsuitFx.GRID_U2:
				tip = maxf(tip, absf(gap))
			deepest = maxf(deepest, gap)
	_t._check(below and deepest > 0.06 and deepest < 0.2,
		"the top skin stands over the bottom one by an airfoil's depth (%.3f m at its deepest), the bottom skin marked in UV2" % deepest)
	_t._check(trailing < 0.002 and tip < 0.01, "the skins meet at the trailing edge (%.4f m) and the wingtip (%.4f m)" % [trailing, tip])
	# Cells: along a chord line at a third, the top skin rises and falls between the seams.
	var lo := INF
	var hi := -INF
	var j3 := int(round(WingsuitFx.GRID_V2 / 3.0))
	for i in range(1, int(WingsuitFx.GRID_U2 * 0.7)):
		var y := verts[j3 * (WingsuitFx.GRID_U2 + 1) + i].y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	_t._check(hi - lo > 0.01, "the top skin bulges between the chordwise seams (%.3f m)" % (hi - lo))
	WingsuitFx.look2 = false
	verts.clear()
	normals.clear()
	tangents.clear()
	uvs.clear()
	uv2s.clear()
	idx.clear()
	fx.call("_grid", verts, normals, tangents, uvs, uv2s, idx, front, 1.0, 0.0, shape)
	_t._check(verts.size() == (WingsuitFx.GRID_U + 1) * (WingsuitFx.GRID_V + 1), "WINGSUIT_LOOK=0: the old single sheet")
	WingsuitFx.look2 = was
	fx.free()


func _shaders() -> void:
	var vap := FileAccess.get_file_as_string("res://shaders/wingsuit_vapour.gdshader")
	_t._check(vap.contains("uniform float look = 0.0;") and vap.contains("tree_sun") and vap.contains("cs_out(col)"),
		"the vapour takes the sun's and the sky's light under the pass, off by default")
	var fab := FileAccess.get_file_as_string("res://shaders/wingsuit_fabric.gdshader")
	_t._check(fab.contains("uniform float look = 0.0;") and fab.contains("v_bottom = step(3.5, v);") and fab.contains("RIM ="),
		"the fabric decodes the bottom skin and adds the nylon's sheen under the pass, off by default")
	var src := FileAccess.get_file_as_string("res://scripts/player/wingsuit_fx.gd")
	var i := src.find("if look2:\n\t\t# Vapour")
	_t._check(i > 0 and src.find("vapour_min = 20.0", i) > i, "the vapour starts at a trimmed glide's speed (20 m/s, was 32)")


func _roof() -> void:
	var g := LandmarkGeo.new()
	g.use("vault", StandardMaterial3D.new())
	g.use("veil", StandardMaterial3D.new())
	var r := Rect2(Vector2(0.0, 0.0), Vector2(52.0, 52.0))
	var n := Rc5Wingsuit.museum_roof(g, r, 30.0, false)
	var cols := roundi((52.0 - 2.0 * Rc5Wingsuit.ROOF_BORDER) / Rc5Wingsuit.ROOF_CELL.x)
	var rows := roundi((52.0 - 2.0 * Rc5Wingsuit.ROOF_BORDER) / Rc5Wingsuit.ROOF_CELL.y)
	_t._check(n == cols + rows + 3, "THE LATTICE's roof is a skylight lattice: %d ribs over the glazing" % (n - 1))
	var src := FileAccess.get_file_as_string("res://scripts/world/landmark_civic_center.gd")
	_t._check(src.contains("if Rc5Wingsuit.enabled:\n\t\tRc5Wingsuit.museum_roof("), "RC5_WINGSUIT=0 leaves the old flat roof")
