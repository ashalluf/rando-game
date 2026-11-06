extends RefCounted
## The Googie motel refcam (fleet wave 8, rc5-googie-motel; docs/HANDOFF.md "The Googie motel at
## 21:00"): checks for tests/smoke_test.gd. CPU only (no pixel is read headless):
##   * the googie_motel row is in tools/refcams/cameras_w8.json at 21:00 clear, and a motel stands
##     within sight of its eye;
##   * Motels claims exactly the car parks a Googie pole sign stands at the corner of, and the plan
##     is pure (twice the same), inside its lot, with the court open to the street;
##   * the shader's room grid is Motels' (ROOM_W, STOREY);
##   * the pole sign's halos and coloured pools (MotelSignGlow) sit on the sign and the ground.
## MOTELS=0 is the A/B (the car park again), MOTEL_SIGN_GLOW=0 the sign's light's.

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan") if city else null
	_shader_grid()
	if not Motels.enabled:
		_t._check(true, "rc5-googie-motel: off (MOTELS=0)")
		return
	if plan == null or not BoulevardSigns.enabled:
		_t._check(true, "rc5-googie-motel: no plan or no boulevard signs")
		return
	_camera_row(plan)
	_claims(plan)
	_glow()


func _row() -> Dictionary:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	if f == null:
		return {}
	var table: Variant = JSON.parse_string(f.get_as_text())
	if table is Dictionary:
		for cam: Dictionary in (table as Dictionary).get("cameras", []):
			if String(cam.get("name", "")) == "googie_motel":
				return cam
	return {}


func _shader_grid() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/motel.gdshader")
	_t._check(src.contains("const float ROOM_W = %.1f;" % Motels.ROOM_W) and src.contains("const float STOREY = %.2f;" % Motels.STOREY),
		"rc5-googie-motel: the shader's room grid is Motels' (ROOM_W %.1f, STOREY %.2f)" % [Motels.ROOM_W, Motels.STOREY])


func _camera_row(plan: CityPlan) -> void:
	var row := _row()
	_t._check(not row.is_empty() and is_equal_approx(float(row.get("hour", 0.0)), 21.0)
		and String(row.get("weather", "")) == "clear", "rc5-googie-motel: the camera row is at 21:00 clear")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var at := Vector2(float(eye[0]), float(eye[2]))
	var found := _motels_near(plan, at, 90.0)
	_t._check(not found.is_empty(), "rc5-googie-motel: a motel stands within 90 m of the eye (%s)" % [at])


## [[ix, iz, lot, pole], ...] of the motels on the blocks within `r` of `at`.
func _motels_near(plan: CityPlan, at: Vector2, r: float) -> Array:
	var out: Array = []
	var b0 := plan.block_index_at(at - Vector2(r, r))
	var b1 := plan.block_index_at(at + Vector2(r, r))
	for ix in range(b0.x, b1.x + 1):
		for iz in range(b0.y, b1.y + 1):
			for lot: Dictionary in plan.lots(ix, iz):
				var p := Motels.pole_for(plan, ix, iz, lot)
				if not p.is_empty() and (lot.center as Vector2).distance_to(at) < r + 40.0:
					out.append([ix, iz, lot, p])
	return out


func _claims(plan: CityPlan) -> void:
	var row := _row()
	var c := Vector2(1300.0, 650.0)
	if not row.is_empty():
		c = Vector2(float(row.eye[0]), float(row.eye[2]))
	var motels := _motels_near(plan, c, 700.0)
	_t._check(motels.size() >= 2, "rc5-googie-motel: motels round the camera (%d within 700 m)" % motels.size())
	var bad := 0
	var outside := 0
	var no_court := 0
	var not_pure := 0
	for m: Array in motels:
		var lot: Dictionary = m[2]
		var p: Dictionary = m[3]
		if int(p.kind) != BoulevardSigns.Pole.MOTEL or String(p.src) != "park" or not bool(lot.get("parking", false)):
			bad += 1
		var L := Motels.layout(plan, int(m[0]), int(m[1]), lot, p)
		var L2 := Motels.layout(plan, int(m[0]), int(m[1]), lot, p)
		if str(L) != str(L2):
			not_pure += 1
		var cell: Rect2 = (L.cell as Rect2).grow(0.05)
		for w: Dictionary in L.wings:
			var o: Vector2 = w.o
			var al: Vector2 = w.al
			var ou: Vector2 = w.out
			for q: Vector2 in [o, o + al * float(w.L), o - ou * float(w.D), o + al * float(w.L) - ou * float(w.D)]:
				if not cell.has_point(q):
					outside += 1
			# The court in front of the rooms: walk, a stall and an aisle before the lot's edge.
			var front := o + ou * (Motels.WALK + Motels.STALL_D)
			if not cell.has_point(front):
				no_court += 1
		# The pole sign stands at the lot's front corner, in front of the office's far end.
		if (p.at as Vector2).distance_to(L.cell.get_center()) > (L.cell as Rect2).size.length():
			bad += 1
	_t._check(bad == 0, "rc5-googie-motel: every motel is a motel sign's car park (%d not)" % bad)
	_t._check(not_pure == 0, "rc5-googie-motel: the plan is pure (%d differ)" % not_pure)
	_t._check(outside == 0, "rc5-googie-motel: the wings stand inside their lots (%d corners out)" % outside)
	_t._check(no_court == 0, "rc5-googie-motel: every wing has its stalls in the lot (%d not)" % no_court)
	# A lot with no motel sign stays a car park.
	var parks := 0
	var claimed := 0
	var b0 := plan.block_index_at(c - Vector2(700.0, 700.0))
	var b1 := plan.block_index_at(c + Vector2(700.0, 700.0))
	for ix in range(b0.x, b1.x + 1):
		for iz in range(b0.y, b1.y + 1):
			for lot: Dictionary in plan.lots(ix, iz):
				if bool(lot.get("parking", false)):
					parks += 1
					if Motels.claims(plan, ix, iz, lot):
						claimed += 1
	_t._check(claimed > 0 and claimed < parks, "rc5-googie-motel: some car parks, not all, are motels (%d of %d)" % [claimed, parks])


func _glow() -> void:
	if not MotelSignGlow.enabled:
		_t._check(true, "rc5-googie-motel: the sign's glow is off (MOTEL_SIGN_GLOW=0)")
		return
	var parts := MotelSignGlow.parts(Transform3D.IDENTITY, 0, 0)
	var halos := 0
	var pools := 0
	var bad := 0
	for q: Array in parts:
		var xf: Transform3D = q[2]
		if String(q[0]) == NightAtmos.SHOP_KEY:
			halos += 1
			if xf.origin.y < 4.0 or xf.origin.y > SignKit.MOTEL_POLE_TOP + 1.0:
				bad += 1
		elif String(q[0]).begins_with(MotelSignGlow.POOL_KEY):
			pools += 1
			if absf(xf.origin.y - 0.07) > 0.01:
				bad += 1
	var want_halos := MotelSignGlow.HALOS.size() if NightAtmos.enabled else 0
	_t._check(halos == want_halos and pools == MotelSignGlow.POOLS.size() and bad == 0,
		"rc5-googie-motel: a motel sign carries its halos (%d) on the sign and its pools (%d) on the ground (%d misplaced)" % [halos, pools, bad])
