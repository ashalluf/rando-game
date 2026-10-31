extends RefCounted
## The GI review (fleet wave 3, `gi-review`; docs/HANDOFF.md "Grounded light"), for
## tests/smoke_test.gd: the indirect light's numbers per Quality level (GiTuning) pinned, and the
## contact shadows (ContactShadows) under cars and street furniture. Under --headless nothing is
## drawn and a MultiMesh reads its transforms back as identity, so the checks hold the tables, the
## footprints worked out from a car's _dims(), the shader's sources and the BatchContact wiring;
## tools/gi_review/gi_shot.gd shows the pixels. Every switch and Environment it touches is its own
## (a fresh Environment, a fresh car under its own node), so nothing leans on an earlier check.

var _t: Node


func run(t: Node, city: Node3D = null) -> void:
	_t = t
	_tuning_tables()
	_tuning_applies()
	_scene_switches()
	_shader_source()
	await _car_footprint()
	_batch_contacts(city)


## The table: every row has a value per level, and the numbers stay inside what was measured.
func _tuning_tables() -> void:
	for table: Dictionary in [GiTuning.SSAO, GiTuning.SSIL]:
		for k: String in table:
			_t._check((table[k] as Array).size() == 4, "GiTuning row %s has a value per Quality level" % k)
	_t._check(float(GiTuning.SSAO.radius[0]) <= 1.5 and float(GiTuning.SSAO.detail[0]) >= 0.8,
		"HIGH's SSAO is tight and detailed (radius %.1f m, detail %.2f): darkness in the creases, not a grey veil" % [GiTuning.SSAO.radius[0], GiTuning.SSAO.detail[0]])
	_t._check(float(GiTuning.SSAO.light_affect[1]) > float(GiTuning.SSAO.light_affect[0]),
		"MEDIUM's SSAO darkens more of the light than HIGH's (no SDFGI to occlude the sky there)")
	_t._check(float(GiTuning.SDFGI.energy[0]) > 1.0 and float(GiTuning.SDFGI.bounce_feedback[0]) > 0.5,
		"HIGH's SDFGI is stronger and bounces more than city.tscn's (a shaded alley stays readable, warm off the sunlit wall)")
	_t._check(float(GiTuning.SKY_FILL[0]) == 1.0 and float(GiTuning.SKY_FILL[1]) < 1.0,
		"the sky fill is turned down only where SDFGI is off (MEDIUM and below: its shade was twice HIGH's)")
	_t._check(float(GiTuning.UNDER_FILL[0]) > 0.0 and float(GiTuning.UNDER_FILL[1]) == 0.0,
		"the freeway soffit's daylight fill is HIGH's alone (below it the sky lights a soffit already)")
	_t._check(FileAccess.get_file_as_string("res://shaders/freeway_structure.gdshader").contains("uniform float under_fill = 0.0;"),
		"freeway_structure.gdshader's under_fill defaults to off")
	_t._check(float(GiTuning.SSIL.radius[0]) >= 5.0 and float(GiTuning.SSIL.intensity[0]) > 0.5,
		"HIGH's SSIL reaches across a street (radius %.1f m, intensity %.2f)" % [GiTuning.SSIL.radius[0], GiTuning.SSIL.intensity[0]])


## apply() sets a fresh Environment to the table at every level and switches nothing on or off.
func _tuning_applies() -> void:
	var was := GiTuning.enabled
	var kept := [GiTuning.gi_scale, GiTuning.ambient_scale, GiTuning.sky_contribution]
	var fill_was: Variant = FreewayKit.structure_material().get_shader_parameter("under_fill")
	GiTuning.enabled = true
	for level in 4:
		var env := Environment.new()
		env.ssao_enabled = false
		env.sdfgi_enabled = false
		GiTuning.apply(env, null, level)
		_t._check(is_equal_approx(env.ssao_radius, float(GiTuning.SSAO.radius[level]))
			and is_equal_approx(env.ssil_intensity, float(GiTuning.SSIL.intensity[level]))
			and is_equal_approx(env.ssao_light_affect, float(GiTuning.SSAO.light_affect[level])),
			"GiTuning.apply() sets level %d's SSAO / SSIL numbers" % level)
		_t._check(not env.ssao_enabled and not env.sdfgi_enabled, "GiTuning.apply() leaves the effects' switches to Quality (level %d)" % level)
		_t._check(is_equal_approx(GiTuning.gi_scale, float(GiTuning.SDFGI.energy[level])) and is_equal_approx(GiTuning.sky_contribution, float(GiTuning.SKY_FILL[level])),
			"GiTuning.apply() hands DayNight level %d's SDFGI energy and sky fill" % level)
	GiTuning.enabled = false
	var env2 := Environment.new()
	var before := env2.ssao_radius
	GiTuning.apply(env2, null, 0)
	_t._check(is_equal_approx(env2.ssao_radius, before) and is_equal_approx(GiTuning.gi_scale, 1.0) and is_equal_approx(GiTuning.sky_contribution, 1.0),
		"GI_REVIEW=0 leaves the scene's numbers and DayNight's alone")
	GiTuning.enabled = was
	GiTuning.gi_scale = kept[0]
	GiTuning.ambient_scale = kept[1]
	GiTuning.sky_contribution = kept[2]
	FreewayKit.structure_material().set_shader_parameter("under_fill", fill_was if fill_was != null else 0.0)


## The city scene's environment still has the effects GiTuning tunes, and Quality calls it.
func _scene_switches() -> void:
	var q := FileAccess.get_file_as_string("res://scripts/util/quality.gd")
	_t._check(q.contains("GiTuning.apply(_env, _sun, i)"), "Quality._apply_render() applies GiTuning's level")
	var dn := FileAccess.get_file_as_string("res://scripts/world/day_night.gd")
	_t._check(dn.contains("day_gi_energy * GiTuning.gi_scale") and dn.contains("lerpf(GiTuning.sky_contribution, 0.35, moonlight)"),
		"DayNight takes GiTuning's SDFGI energy (by day only) and sky fill")
	var v := FileAccess.get_file_as_string("res://scripts/vehicles/vehicle.gd")
	_t._check(v.contains("ContactShadows.ensure(self)"), "every Vehicle makes sure the contact shadows exist")
	var m := FileAccess.get_file_as_string("res://scripts/util/multimesh_batch.gd")
	_t._check(m.contains("ContactShadows.batch_contacts(") and m.contains("ContactShadows.hide_contact("),
		"MultiMeshBatch builds the furniture's contact quads and hides a broken prop's")


## The quad darkens (alpha-blended black, no fog, no shadow) and reads its numbers from where
## ContactShadows writes them.
func _shader_source() -> void:
	var s := FileAccess.get_file_as_string("res://shaders/contact_shadow.gdshader")
	_t._check(s.contains("blend_mix") and s.contains("unshaded") and s.contains("fog_disabled") and s.contains("depth_draw_never"),
		"contact_shadow.gdshader is an unshaded, fog-free darkening that writes no depth")
	_t._check(s.contains("ALBEDO = vec3(0.0)"), "the contact quad darkens (black, by alpha) on both renderers")
	_t._check(s.contains("v_margin = COLOR.r") and s.contains("INSTANCE_CUSTOM"), "the shader reads the margin from COLOR.r and the footprint from INSTANCE_CUSTOM")
	_t._check(not s.contains("instance uniform"), "contact_shadow.gdshader uses no instance uniforms (Compatibility's global buffer)")


## A sedan's footprint comes from its _dims(), its contact plane is the road under its wheels,
## and a car with no wheels and no traffic (a helicopter, a boat) gets nothing.
func _car_footprint() -> void:
	var holder := Node3D.new()
	holder.name = "GiReviewCheck"
	_t.get_tree().root.add_child(holder)
	var car = (load("res://scripts/vehicles/vehicle.gd") as GDScript).new()
	car.call("setup", 0, Color(0.5, 0.5, 0.5), 0)
	holder.add_child(car)
	await _t.get_tree().process_frame
	var d: Dictionary = car.call("_dims")
	var info: Array = ContactShadows._info(car, 0)
	_t._check(info.size() == 2 and is_equal_approx((info[0] as Vector4).x, float(d.length)) and is_equal_approx((info[0] as Vector4).y, float(d.width)),
		"a sedan's contact footprint is its _dims() length and width (%s)" % [info])
	_t._check(info.size() == 2 and is_equal_approx(float(info[1]), float(d.get("road", d.get("ride", 0.0)))),
		"the quad lies in the car's own contact plane (_dims() road)")
	_t._check(car.has_meta("contact_info"), "the footprint is cached on the car")
	var cs := ContactShadows.instance()
	if ContactShadows.enabled:
		_t._check(cs != null, "the first car makes the ContactShadows node (under the tree root)")
		if cs:
			_t._check(cs.get_parent() == _t.get_tree().root, "ContactShadows lives under the tree root (origin shifts never touch it)")
			var wheelless := Node3D.new()
			wheelless.set("name", "NoWheels")
			holder.add_child(wheelless)
			_t._check(is_equal_approx(cs._grounded(wheelless), 0.0), "something with no wheels and no traffic (a helicopter, a boat) casts no contact quad")
	holder.queue_free()


## FULL chunks have a BatchContact node, and the furniture batches point at it.
func _batch_contacts(city: Node3D) -> void:
	if city == null or not ContactShadows.enabled:
		return
	var found := 0
	var linked := 0
	for n in city.find_children("BatchContact", "MultiMeshInstance3D", true, false):
		found += 1
		var mmi := n as MultiMeshInstance3D
		_t._check(mmi.material_override == ContactShadows.prop_material(), "every BatchContact shares the one furniture material")
		break
	for key in ContactShadows.CONTACT_KEYS:
		for n in city.find_children("Batch_" + key, "MultiMeshInstance3D", true, false):
			if n.has_meta("contact_twin"):
				linked += 1
	_t._check(found > 0 and linked > 0, "FULL chunks lay contact quads under their street furniture (%d batches linked)" % linked)
