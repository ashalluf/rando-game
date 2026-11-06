extends RefCounted
## The film shoot at 22:00 (FilmShootNight, the film_shoot_night reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the camera row stands outside a shoot's closure behind its barricades and looks down the
## street at the set; the shoot chunk built FULL carries the glow mesh (a bloom over each HMI and
## the balloon, a shaft per HMI, the pools), an HMI spotlight per lamp aimed at the action whose
## energy follows the lamps (hidden by day), the balloon's light widened; the barricades' sheeting
## glow is turned down; the set's pavement is cleared of scooters and bikes; FILM_SHOOT_NIGHT=0 is
## the shoot as before.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var was := FilmShootNight.enabled
	FilmShootNight.enabled = true
	var plan: CityPlan = city.get("plan")
	var m := _camera(plan)
	if not m.is_empty():
		_chunk(city, plan, m)
		FilmShootNight.enabled = false
		_t._check(FilmShootNight.keep_clear_points(plan, int(m.owner.x), int(m.owner.y)).is_empty(),
			"FILM_SHOOT_NIGHT=0: the set's pavement keeps its scooters as before")
		var ch: CityChunk = city.call("_new_chunk", m.owner, CityChunk.Level.FULL)
		ch.build()
		_t._check(ch.get_node_or_null("FilmShootNightGlow") == null and ch.get_node_or_null("FilmNightLights") == null,
			"FILM_SHOOT_NIGHT=0: the shoot builds no glow and no HMI lights")
		ch.get_parent().remove_child(ch)
		ch.free()
	FilmShootNight.enabled = was


## The camera row: outside the closure, within a few metres of its end, looking at the set.
func _camera(plan: CityPlan) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if parsed is Dictionary:
		for c: Dictionary in (parsed as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "film_shoot_night":
				row = c
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 22.0 and String(row.get("weather", "")) == "clear",
		"the film_shoot_night camera row is in cameras_w8.json (22:00 clear)")
	if row.is_empty():
		return {}
	var eye: Array = row.eye
	var e := Vector2(float(eye[0]), float(eye[2]))
	var m := FilmShoot.decide(plan, FilmShoot._cell_of(e))
	_t._check(not m.is_empty(), "a film shoot stands where the camera is (cell %s)" % FilmShoot._cell_of(e))
	if m.is_empty():
		return {}
	var lay := FilmShoot.layout(m)
	var along: Vector2 = FilmShoot.dirs(m)[0]
	var t := e.dot(along)
	var ends: Array = lay.ends
	var outside := t < float(ends[0]) or t > float(ends[1])
	var near_end := minf(absf(t - float(ends[0])), absf(t - float(ends[1]))) < 10.0
	var yaw := deg_to_rad(float(eye[3]))
	var look := Vector2(-sin(yaw), -cos(yaw))
	var act: Dictionary = lay.action
	var to_set := (FilmShoot.point(m, float(act.t), float(act.o)) - e).normalized()
	_t._check(outside and near_end and look.dot(to_set) > 0.97,
		"the camera stands behind the barricades and looks at the set (%.1f m past the end, %.1f deg off the action)" % [
			minf(absf(t - float(ends[0])), absf(t - float(ends[1]))), rad_to_deg(acos(clampf(look.dot(to_set), -1.0, 1.0)))])
	return m


func _chunk(city: Node, plan: CityPlan, m: Dictionary) -> void:
	var lay := FilmShoot.layout(m)
	var ch: CityChunk = city.call("_new_chunk", m.owner, CityChunk.Level.FULL)
	ch.build()
	var glow := ch.get_node_or_null("FilmShootNightGlow") as MeshInstance3D
	var quads := 0
	var blooms := 0
	var shafts := 0
	var pools := 0
	if glow != null and glow.mesh != null:
		var arr := glow.mesh.surface_get_arrays(0)
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		quads = uv2.size() / 4
		for q in quads:
			var k := uv2[q * 4].x
			if k < 0.5:
				blooms += 1
			elif k < 1.5:
				shafts += 1
			else:
				pools += 1
	var camp := (lay.camp as Array).size()
	var hmis := (lay.hmis as Array).size()
	_t._check(glow != null and blooms == hmis + 1 + camp and shafts == hmis and pools == hmis + 1 + camp,
		"the shoot's glow mesh: a bloom per HMI, the balloon and each work light (%d), a shaft per HMI (%d), the pools (%d)" % [blooms, shafts, pools])
	_t._check(glow != null and glow.material_override != null and glow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the glow is one shadowless additive mesh")
	var holder := ch.get_node_or_null("FilmNightLights") as FilmNightLights
	var aimed := 0
	var act: Dictionary = lay.action
	var a2 := FilmShoot.point(m, float(act.t), float(act.o))
	if holder != null:
		for s in holder.spots:
			var to := Vector3(a2.x, s.position.y, a2.y) - s.position
			var fwd := -s.transform.basis.z
			if Vector2(fwd.x, fwd.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.97 and fwd.y < 0.0:
				aimed += 1
	_t._check(holder != null and holder.spots.size() == hmis and aimed == hmis,
		"an HMI spotlight per lamp, aimed down at the action (%d of %d)" % [aimed, hmis])
	if holder != null:
		var keep := DayNight.lamp_now
		DayNight.lamp_now = 0.0
		holder._apply()
		var off := holder.spots.all(func(s: SpotLight3D) -> bool: return not s.visible)
		DayNight.lamp_now = 1.0
		holder._apply()
		var on := holder.spots.all(func(s: SpotLight3D) -> bool: return s.visible and s.light_energy > 1.0)
		DayNight.lamp_now = keep
		holder._apply()
		_t._check(off and on, "the HMI lights follow the lamps: hidden by day, lit at night")
	var bl := ch.get_node_or_null("FilmBalloonLight") as OmniLight3D
	_t._check(bl == null or (is_equal_approx(bl.omni_range, FilmShootNight.BALLOON_RANGE) and float(bl.get_meta("lamp_gain", 1.0)) > 1.0),
		"the balloon's light is a balloon's: wide and over a street lamp's")
	_t._check(is_equal_approx(float(FilmShootKit.material().get_shader_parameter("stripe_glow")), FilmShootNight.STRIPE_GLOW),
		"the barricades' sheeting glows %.2f after dark (was 0.35)" % FilmShootNight.STRIPE_GLOW)
	_t._check(is_equal_approx(float(FilmShootKit.material().get_shader_parameter("canvas_look")), 1.0),
		"the catering tent's canvas sags, seams and soils (canvas_look 1)")
	# The set's pavement: no scooters, bikes or racks within the cleared stretch.
	var pts := FilmShootNight.keep_clear_points(plan, int(m.owner.x), int(m.owner.y))
	var near := 0
	for c in ch.get_children():
		if c is Node3D and String(c.name).begins_with("Micro_"):
			var p := Vector2((c as Node3D).position.x, (c as Node3D).position.z)
			for k: Array in pts:
				if p.distance_to(k[0]) < float(k[1]) - 0.5:
					near += 1
					break
	_t._check(not pts.is_empty() and near == 0, "the set's pavement is cleared of scooters and bikes (%d keep-clear points, %d items on them)" % [pts.size(), near])
	ch.get_parent().remove_child(ch)
	ch.free()
