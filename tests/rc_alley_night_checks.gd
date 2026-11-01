extends RefCounted
## The alley at night (AlleyNight, refcam alley_night), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Builds the refcam's FULL chunk (the downtown alley at (1797, -71.7)) and checks: the ground wears
## its own copy of the alley shader with the water on and the chunk's lamp heads in it (as many as
## lamps, up to the array); the heads hang on the walls over the alley's ground; the lamps carry
## NightAtmos halos and a wider pool; the alley wall got more tags than StreetWear alone gives; the
## steam plumes (if any) stand inside the chunk on its ground; the shader keeps the water off a
## material without `wet_on`; and with AlleyNight off the ground is the shared material again.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var k: Vector2i = plan.block_index_at(Vector2(1815.0, -71.7))
	_t._check(not Alleys.spec(plan, k.x, k.y).is_empty(), "the alley_night refcam's block %d,%d has a service alley" % [k.x, k.y])
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var ground: MeshInstance3D = chunk.get_node_or_null("AlleyGround")
	var mat := ground.material_override as ShaderMaterial if ground else null
	var lamps := int((chunk.get_meta("alley_props", {}) as Dictionary).get("lamp", 0))
	var count := int(mat.get_shader_parameter("lamp_count")) if mat else -1
	_t._check(mat != null and mat != Alleys.ground_material() and mat.shader == Alleys.ground_material().shader
		and float(mat.get_shader_parameter("wet_on")) > 0.5, "the alley's ground is its own copy of the alley shader with the water on")
	_t._check(lamps > 0 and count == mini(lamps, AlleyNight.MAX_HEADS), "the ground mirrors each of the chunk's %d alley lamps (%d heads)" % [lamps, count])
	var heads: Array = mat.get_shader_parameter("lamp_heads") if mat else []
	var high := true
	for i in maxi(count, 0):
		var h: Vector4 = heads[i]
		var gy := CityChunk.SIDEWALK_TOP + chunk._gy(h.x, h.z)
		high = high and h.y - gy > 2.2 and h.y - gy < 4.6
	_t._check(count > 0 and high, "every mirrored head hangs on a wall 2.2-4.6 m over the alley")
	var halos := 0
	var steam := 0
	for c in chunk.get_children():
		var mm := c as MultiMeshInstance3D
		if mm == null or mm.multimesh == null:
			continue
		if String(c.name) == "Batch_" + NightAtmos.HALO_KEY:
			halos += mm.multimesh.instance_count
		if String(c.name) == "Batch_" + AlleyNight.STEAM_KEY:
			steam += mm.multimesh.instance_count
	_t._check(halos >= lamps, "each alley lamp carries a halo (%d halos for %d lamps)" % [halos, lamps])
	_t._check(steam <= AlleyNight.MAX_STEAM, "the alley's steam plumes (%d) are capped at %d a chunk" % [steam, AlleyNight.MAX_STEAM])
	_t._check(int(chunk.get_meta("alley_wear", 0)) >= 20, "the alley's back walls carry tags (%d wear pieces)" % int(chunk.get_meta("alley_wear", 0)))
	_t._check(is_equal_approx(AlleyNight.pool_size(), AlleyNight.POOL_SIZE) and AlleyNight.pool_strength() > 0.85, "the alley lamps' pools are wider and stronger")
	_free(chunk)
	# The shader: water and the mirror only behind the switch, the emission only in the water.
	var src := FileAccess.get_file_as_string("res://shaders/alley_ground.gdshader")
	_t._check(src.contains("if (wet_on > 0.5 && kind < 0.5)") and src.contains("if (pool > 0.01 && lamp_factor > 0.01)")
		and src.contains("uniform float wet_on = 0.0;"), "the alley shader keeps the water and its mirror behind wet_on (off by default)")
	# The A/B: off, the shared material.
	var was := AlleyNight.enabled
	AlleyNight.enabled = false
	var c2: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	c2.build()
	var g2: MeshInstance3D = c2.get_node_or_null("AlleyGround")
	_t._check(g2 != null and g2.material_override == Alleys.ground_material() and is_equal_approx(AlleyNight.pool_size(), 7.5),
		"ALLEY_NIGHT=0 puts the shared ground material and the old pools back")
	_free(c2)
	AlleyNight.enabled = was


## A built chunk and the parked cars it put under the city root (the flake rules).
func _free(chunk: CityChunk) -> void:
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and car is Node:
			(car as Node).free()
	chunk.free()
