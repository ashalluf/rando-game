extends RefCounted
## The ER's ambulance court at night (RcHospitalEr, the hospital_er reference camera in
## tools/refcams/cameras_w7.json), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks: the EMERGENCY light box is a deep red that stays under the salmon line (red-heavy HDR
## through AgX); the medical centre's FULL chunk builds the lit soffit, the fascia words at the new
## size and more glazing on the ER wall; the camera row stands in the ER street facing the court and
## is staged; RC4_HOSPITAL=0 builds the old court (no soffit).

var _t: Object
var _city: Node


func run(t: Object, city: Node) -> void:
	_t = t
	_city = city
	var was := RcHospitalEr.enabled
	_sign()
	_camera()
	var plan: CityPlan = city.get("plan")
	var med := Hospital.medical_block(plan) if plan != null else Vector2i.MAX
	_t._check(med != Vector2i.MAX, "the medical centre stands on this seed")
	if med != Vector2i.MAX:
		RcHospitalEr.enabled = true
		var on := _build(med)
		RcHospitalEr.enabled = false
		var off := _build(med)
		_t._check(on.soffit and not off.soffit, "the canopy's lit soffit is built, and not under RC4_HOSPITAL=0 (%s / %s)" % [on.soffit, off.soffit])
		_t._check(on.words > off.words, "the fascia's AMBULANCE ENTRANCE is bigger (%.2f m against %.2f m)" % [on.words, off.words])
		_t._check(on.glaze >= 2 and off.glaze == 0, "the ER wall is glazed either side of the doors (%d runs)" % on.glaze)
	RcHospitalEr.enabled = was


func _sign() -> void:
	var m := RcHospitalEr.box_material()
	var glow: Vector3 = m.get_shader_parameter("glow_color")
	var e := float(m.get_shader_parameter("night_energy"))
	# Under 1 in red at full night and green held to a few % of red: no salmon after AgX.
	_t._check(glow.x * e * 1.0 < 1.0 and glow.y < 0.06 * glow.x and glow.z < glow.y,
		"the EMERGENCY box glows a deep red under 1 (%.2f, green %.3f of red)" % [glow.x * e, glow.y / glow.x])
	var face: Vector3 = m.get_shader_parameter("face_color")
	_t._check(face.x < 0.4 and face.y < 0.03, "the box's unlit face is a dark red (%s)" % face)
	_t._check(float(m.get_shader_parameter("box_face")) == 1.0, "it is still a light box (brighter in its middle)")


func _camera() -> void:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var row: Dictionary = {}
	for c: Dictionary in (table as Dictionary).get("cameras", []):
		if c.get("name", "") == "hospital_er":
			row = c
	_t._check(not row.is_empty() and String(row.get("stage", "")) == "hospital" and float(row.get("hour", 0.0)) == 23.0,
		"the hospital_er camera row is staged and at 23:00")
	if row.is_empty():
		return
	var plan: CityPlan = _city.get("plan")
	var med := Hospital.medical_block(plan)
	var lay := Hospital.layout(plan, med.x, med.y)
	var eye := Vector2(float(row.eye[0]), float(row.eye[2]))
	var court := Hospital.fr(lay, lay.canopy)
	var d := court.get_center() - eye
	var yaw := rad_to_deg(atan2(-d.x, -d.y))
	_t._check(absf(wrapf(yaw - float(row.eye[3]), -180.0, 180.0)) < 20.0 and d.length() < 45.0,
		"the eye looks at the canopy from %.0f m (yaw off by %.0f degrees)" % [d.length(), wrapf(yaw - float(row.eye[3]), -180.0, 180.0)])
	_t._check(not (lay.inner as Rect2).has_point(eye), "the eye stands in the ER street, off the campus")


func _build(med: Vector2i) -> Dictionary:
	var chunk: CityChunk = _city.call("_new_chunk", med, CityChunk.Level.FULL)
	chunk.build()
	var out := {"soffit": false, "words": 0.0, "glaze": 0}
	for n in chunk.get_children():
		if not n.is_in_group("hospital"):
			continue
		out.soffit = n.get_node_or_null("ERSoffit") != null
		var w := n.get_node_or_null("AmbulanceWords") as MeshInstance3D
		if w and w.mesh is TextMesh:
			out.words = (w.mesh as TextMesh).pixel_size * 48.0
		out.glaze = int(n.get_meta("rc4_glaze", 0))
	chunk.free()
	return out
