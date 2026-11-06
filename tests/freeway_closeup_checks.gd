extends RefCounted
## The freeway close up (FreewayCloseup, shaders/freeway_deck.gdshader and the `closeup` pass on
## freeway_structure / freeway_paint) for tests/smoke_test.gd. Loaded at run time. Checks: the deck
## shader's copy of Freeway.lane_layout()'s numbers, its sampler count (the web's limit), the deck
## material on a built deck chunk and the kit's two materials switched on; the deck top's UVs
## (metres along, metres across inside the half width, the layout code); the same chunk built with
## the pass off draws the same structure and paint geometry (the pass is shading only: no rng, no
## triangles); the rush hours fill the freeway's free slots, the small hours leave them, and the
## A/B is the old flat rate. Builds its own chunk; leans on nothing an earlier check left.

const WEB_SAMPLERS := 9

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_shader_copies()
	_skip()
	var plan: CityPlan = city.plan
	var fw: Freeway = plan.macro.freeway if plan.macro else null
	_t._check(fw != null and not fw.routes.is_empty(), "freeway close-up: the freeway has routes")
	if fw == null or fw.routes.is_empty():
		return
	await _chunk(city, plan, fw)


func _shader_copies() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/freeway_deck.gdshader")
	var want := {"lane_inner": Freeway.LANE_INNER, "lane_max": Freeway.LANE_MAX,
		"outer_shoulder_min": Freeway.OUTER_SHOULDER_MIN, "outer_inset": Freeway.LANE_OUTER_INSET, "lanes": float(Freeway.LANES)}
	var ok := true
	for k: String in want:
		var re := RegEx.create_from_string("uniform float %s = ([0-9.]+);" % k)
		var m := re.search(src)
		ok = ok and m != null and absf(float(m.get_string(1)) - float(want[k])) < 1e-4
	_t._check(ok, "the deck shader's lane layout is Freeway.lane_layout()'s")
	var samplers := 0
	for p: String in ["res://shaders/freeway_deck.gdshader", "res://shaders/freeway_structure.gdshader", "res://shaders/freeway_paint.gdshader"]:
		var n := FileAccess.get_file_as_string(p).count("sampler2D")
		samplers = maxi(samplers, n)
	_t._check(samplers <= WEB_SAMPLERS, "the freeway shaders stay within the web's samplers (%d)" % samplers)
	_t._check(FreewayCloseup.enabled, "the freeway close-up is on by default (FREEWAY_CLOSEUP=0 is the A/B)")
	_t._check(FreewayCloseup.deck_material().shader.resource_path == "res://shaders/freeway_deck.gdshader"
		and bool(FreewayKit.structure_material().get_shader_parameter("closeup")) == FreewayCloseup.enabled
		and bool(FreewayKit.paint_material().get_shader_parameter("closeup")) == FreewayCloseup.enabled
		and FreewayKit.structure_material().get_shader_parameter("tag_atlas") != null,
		"the deck material and the kit's close-up pass are set up")


func _skip() -> void:
	var rush := FreewayCloseup.spawn_skip(8.0)
	var noon := FreewayCloseup.spawn_skip(13.0)
	var late := FreewayCloseup.spawn_skip(3.0)
	_t._check(rush < noon and noon < late and rush >= FreewayCloseup.SKIP_RUSH - 1e-4 and late <= FreewayCloseup.SKIP_QUIET + 1e-4,
		"the freeway fills by the hour: rush %.2f < noon %.2f < 03:00 %.2f empty slots" % [rush, noon, late])
	var was := FreewayCloseup.enabled
	FreewayCloseup.enabled = false
	var off := FreewayCloseup.spawn_skip(8.0)
	FreewayCloseup.enabled = was
	_t._check(is_equal_approx(off, 0.35), "with the close-up off the freeway fills at the old flat rate")
	var src := FileAccess.get_file_as_string("res://scripts/npc/traffic.gd")
	_t._check(src.count("_rng.randf() < skip") == 1 and src.count("_rng.randf() < 0.35") == 0,
		"the fill still makes one roll a slot (no rng drift)")


func _chunk(city: Node3D, plan: CityPlan, fw: Freeway) -> void:
	var key := Vector2i(999999, 0)
	for ri in fw.routes.size():
		var pts: PackedVector2Array = fw.routes[ri].points
		for i in range(4, pts.size() - 1, 7):
			var mid := pts[i].lerp(pts[i + 1], 0.5)
			if plan.zone_at(mid) == MacroMap.Zone.CITY:
				key = plan.block_index_at(mid)
				break
		if key.x != 999999:
			break
	_t._check(key.x != 999999, "freeway close-up: a city block under a deck")
	if key.x == 999999:
		return
	var chunk: CityChunk = city._new_chunk(key, CityChunk.Level.FULL)
	chunk.build()
	var deck := chunk.get_node_or_null("FreewayDeck") as MeshInstance3D
	_t._check(deck != null and deck.material_override == FreewayCloseup.deck_material(), "a deck chunk's driving surface wears the concrete deck shader")
	var segs := chunk._freeway_segments()
	var area := chunk.owned_rect()
	var kit := FreewayKit.new(chunk)
	var built := kit.build_segments(segs, area)
	var top := kit.top.commit_to_arrays()
	var verts: PackedVector3Array = top[Mesh.ARRAY_VERTEX] if top.size() > 0 else PackedVector3Array()
	var uv: PackedVector2Array = top[Mesh.ARRAY_TEX_UV] if top.size() > 0 and top[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2: PackedVector2Array = top[Mesh.ARRAY_TEX_UV2] if top.size() > 0 and top[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var ok := built > 0 and verts.size() > 0 and uv.size() == verts.size() and uv2.size() == verts.size()
	var half_max := 0.0
	for i in uv.size():
		if not ok:
			break
		var half := uv2[i].x
		half_max = maxf(half_max, half)
		ok = ok and half > 4.0 and half < 30.0 and absf(absf(uv[i].y) - half) < 0.01 and uv[i].x >= -0.01 and uv2[i].y >= 1.0
	_t._check(ok, "the deck top carries metres along and across and the layout code (%d vertices, half %.2f m)" % [verts.size(), half_max])
	# The pass is shading only: the same chunk's kit off and on builds the same geometry.
	var counts_on := _counts(kit)
	var was := FreewayCloseup.enabled
	FreewayCloseup.enabled = false
	var kit_off := FreewayKit.new(chunk)
	kit_off.build_segments(segs, area)
	FreewayCloseup.enabled = was
	var counts_off := _counts(kit_off)
	_t._check(counts_on == counts_off, "the close-up adds no geometry and moves no roll (%s)" % [counts_on])
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	await _t.get_tree().process_frame


func _counts(kit: FreewayKit) -> Array:
	var out := []
	for st: SurfaceTool in [kit.body, kit.paint, kit.glow]:
		var arr := st.commit_to_arrays()
		var n := 0
		var sum := 0.0
		if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			n = vs.size()
			for v in vs:
				sum += v.x + v.y * 3.0 + v.z * 7.0
		out.append([n, snappedf(sum, 0.01)])
	return out
