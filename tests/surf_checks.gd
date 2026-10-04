extends RefCounted
## The surf and the beach (shaders/surf.gdshaderinc, scripts/world/surf.gd, the ocean, the sand's
## swash, the spray) for tests/smoke_test.gd. Loaded at run time, so it compiles after the
## autoloads and can name CityChunk and Weather. Maths on Surf (the GDScript mirror of the
## shader model) plus one shoreline chunk built at full detail. Checks: a storm's surf is far
## bigger, breaks further out and runs further up the sand than a calm day's; the surf lifts
## the water nowhere landward of the waterline (the sea swelling up through the beach, fixed
## once on main and guarded here) and peaks at its break point; the shader's copies of the
## mirrored numbers and project.godot's defaults match Surf; the piers' lamp rows stand over
## the water; and a shoreline chunk lays its sand on the swash material with the waterline in
## UV2, covers the street strip at its +Z side, and carries the spray.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var macro: MacroMap = plan.macro
	_params()
	_envelope()
	_mirrors()
	if macro:
		_piers(macro)
		await _chunk(plan, macro, city)


func _params() -> void:
	var calm := Surf.params(1.0)
	var storm := Surf.params(6.0)
	var c0: Vector4 = calm[0]
	var c1: Vector4 = calm[1]
	var s0: Vector4 = storm[0]
	var s1: Vector4 = storm[1]
	_t._check(s0.x > c0.x * 2.5 and s0.w > c0.w * 2.0 and s1.x > c1.x * 1.5 and s1.z > c1.z * 1.8 and s0.z > c0.z,
		"a storm's surf is taller, breaks further out, runs further up the sand and has a wider zone (face %.1f -> %.1f m, break %.0f -> %.0f m, run-up %.0f -> %.0f m)"
		% [c0.x, s0.x, c0.w, s0.w, c1.x, s1.x])
	var zero := Surf.params(1.0, 0.0)
	_t._check((zero[0] as Vector4).x == 0.0, "Weather.surf_gain 0 flattens the surf")


func _envelope() -> void:
	var worst_land := 0.0
	var peak_at := {}
	for ws: float in [1.0, 1.8, 3.2, 6.0]:
		var p := Surf.params(ws)
		var shape: Vector4 = p[0]
		var extra: Vector4 = p[1]
		var best := -1.0
		var best_s := 0.0
		for g: float in [Surf.H_LO, 1.0, Surf.H_LO + Surf.H_SPAN]:
			# Landward of the waterline and right at it: nothing.
			for s: float in [-300.0, -50.0, -1.0, 0.0]:
				worst_land = maxf(worst_land, absf(Surf.crest_height(shape, extra, s, g)))
		for i in 400:
			var s := float(i) * 0.75
			var h := Surf.crest_height(shape, extra, s, 1.0)
			if h > best:
				best = h
				best_s = s
		peak_at[ws] = [best_s, shape.w, best, Surf.crest_height(shape, extra, extra.z + 5.0, Surf.H_LO + Surf.H_SPAN)]
	_t._check(worst_land < 0.0001, "the surf lifts the water nowhere landward of the waterline (worst %.5f m)" % worst_land)
	var why := ""
	for ws: float in peak_at:
		var v: Array = peak_at[ws]
		if absf(float(v[0]) - float(v[1])) > float(v[1]) * 0.2 or float(v[2]) <= 0.0 or absf(float(v[3])) > 0.0001:
			why += " %.1f:peak %.0f m vs break %.0f m, %.2f m, past zone %.3f" % [ws, float(v[0]), float(v[1]), float(v[2]), float(v[3])]
	_t._check(why == "", "each sea's surf peaks at its break point and is gone past its zone%s" % why)


## The numbers Surf and the shaders both hold, and the ocean's flat beach.
func _mirrors() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/surf.gdshaderinc")
	var why := ""
	for pair in [["SURF_H_LO", Surf.H_LO], ["SURF_H_SPAN", Surf.H_SPAN]]:
		var re := RegEx.create_from_string("const float " + str(pair[0]) + "\\s*=\\s*([0-9.]+)")
		var m := re.search(inc)
		if m == null or absf(m.get_string(1).to_float() - float(pair[1])) > 0.0001:
			why += " " + str(pair[0])
	for snippet in ["float bore = 0.5 * sqrt(max(sig, 0.0)) + 0.5 * smoothstep(0.80, 1.0, sig);",
			"return env * smoothstep(0.0, 4.0, s);", "float start = max(surf_extra.z, brk * 1.4);"]:
		if not inc.contains(str(snippet)):
			why += " [" + str(snippet) + "]"
	var sea := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	for snippet in ['#include "res://shaders/surf.gdshaderinc"', "d = d > -300.0 ? 0.0 : 300.0;", "if (sd.x > 0.01 && sd.x < zone) {"]:
		if not sea.contains(str(snippet)):
			why += " [ocean: " + str(snippet) + "]"
	for f in ["res://shaders/beach_sand.gdshader", "res://shaders/surf_spray.gdshader"]:
		if not FileAccess.get_file_as_string(f).contains('#include "res://shaders/surf.gdshaderinc"'):
			why += " [" + f + "]"
	_t._check(why == "", "the surf model's numbers agree in Surf and the shaders, and the ocean keeps the beach flat%s" % why)
	var calm := Surf.params(1.0)
	var got_shape: Variant = ProjectSettings.get_setting("shader_globals/surf_shape", {}).get("value")
	var got_extra: Variant = ProjectSettings.get_setting("shader_globals/surf_extra", {}).get("value")
	var ok := got_shape is Vector4 and got_extra is Vector4 \
		and (got_shape as Vector4).is_equal_approx(calm[0]) and ((got_extra as Vector4) - (calm[1] as Vector4)).length() < 0.2
	_t._check(ok, "project.godot's surf globals default to a calm day's surf (%s %s)" % [str(got_shape), str(got_extra)])


func _piers(macro: MacroMap) -> void:
	var lines := Weather.pier_light_lines()
	var dry := 0
	for l: Array in lines:
		var a: Vector4 = l[0]
		var mid := Vector2((a.x + a.z) * 0.5, (a.y + a.w) * 0.5)
		if mid.x > macro.coast_x(mid.y):
			dry += 1
	_t._check(lines.size() >= 9 and lines.size() <= 10 and dry == 0,
		"the piers' lamp rows (%d) stand over the water for the night reflections (%d over land)" % [lines.size(), dry])


func _chunk(plan: CityPlan, macro: MacroMap, city: Node3D) -> void:
	# A plain stretch of the basin's beach, well away from the piers and the replica.
	var z := 600.0
	var k: Vector2i = plan.chunk_index_at(Vector2(macro.coast_x(z), z))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var sand: MeshInstance3D = chunk.get_node_or_null("Sand")
	var spray: MultiMeshInstance3D = chunk.get_node_or_null("SurfSpray")
	var mat_ok := sand != null and sand.material_override == PropFactory.beach_sand_material()
	var uv2 := false
	var covers := false
	if sand and sand.mesh:
		uv2 = (sand.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
		var box := sand.mesh.get_aabb()
		var own := chunk.owned_rect()
		var replica_here := macro.replica != null and own.end.y > macro.replica.coast_range().x - 200.0
		covers = replica_here or box.end.z >= own.end.y - 0.5
	var spray_ok := spray != null and spray.multimesh.instance_count >= 4 and spray.multimesh.use_custom_data \
		and spray.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_t._check(mat_ok and uv2 and covers and spray_ok,
		"a shoreline chunk lays its sand on the swash material with the waterline in UV2, over the street strip, and carries the spray (material %s, uv2 %s, strip %s, spray %s)"
		% [mat_ok, uv2, covers, spray_ok])
	chunk.queue_free()
