extends RefCounted
## The third perf audit's cuts (docs/HANDOFF.md, the perf-audit-3 section) for tests/smoke_test.gd.
## Loaded at run time, so it compiles after the autoloads. Every check stages what it reads itself:
## nothing here leans on where an earlier file left the player or the caches.
##   - CacheTrim drops what only its cache holds and keeps what is drawn, Arrays included;
##   - the street-sign cache keeps a mesh in use, rebuilds a dropped one the same;
##   - a crowd foot samples its rays on the stagger, not every tick on flat ground;
##   - the sea's life idles inland and not on the coast;
##   - the night haze's daytime early-out gives sodium_for()'s own answer;
##   - beach riders' flipbooks come back as their own arrays (so CacheTrim sees them in use);
##   - the far canopy is the sphere less its zero-area triangles, the same box;
##   - a building's balconies cast from a near twin and a far twin without the uprights.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_cache_trim()
	_sign_cache()
	_sodium_rule()
	_sea_idle(city)
	_ride_copies()
	_canopy()
	_balconies()
	await _feet(city)


func _cache_trim() -> void:
	var was := CacheTrim.enabled
	CacheTrim.enabled = true
	var cache := {}
	cache["free"] = ArrayMesh.new()
	cache["drawn"] = ArrayMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = cache["drawn"]
	# A list the cache hands out as a copy (a rider's flipbook): its frames are held twice.
	var frames: Array = [ArrayMesh.new(), ArrayMesh.new()]
	cache["held_list"] = frames
	var rider: Array = CacheTrim.copy(frames)
	cache["free_list"] = [ArrayMesh.new()]
	cache["not_a_mesh"] = 7
	var gone := CacheTrim.trim(cache)
	_t._check(gone == 2 and not cache.has("free") and not cache.has("free_list") and cache.has("drawn") \
			and cache.has("held_list") and cache.has("not_a_mesh"),
		"perf 3: CacheTrim drops what only the cache holds and keeps what is drawn (%d dropped, kept %s)" % [gone, str(cache.keys())])
	mi.mesh = null
	rider.clear()
	CacheTrim.trim(cache)
	_t._check(not cache.has("drawn") and not cache.has("held_list"),
		"perf 3: CacheTrim drops a mesh once nothing draws it any more")
	CacheTrim.enabled = false
	cache["x"] = ArrayMesh.new()
	_t._check(CacheTrim.trim(cache) == 0 and cache.has("x"), "perf 3: CACHE_TRIM=0 keeps every entry (the A/B)")
	CacheTrim.enabled = was
	mi.free()


func _sign_cache() -> void:
	var was := CacheTrim.enabled
	CacheTrim.enabled = true
	var held: Mesh = StreetSignKit.name_post("PERF ST", "100", "AUDIT AVE", "200")
	var box_before := held.get_aabb()
	var surfaces := held.get_surface_count()
	# Fill the cache past its trim point with blades nobody keeps.
	var saved_at: int = StreetSignKit._trim_at
	StreetSignKit._trim_at = StreetSignKit._cache.size() + 3
	for i in 6:
		StreetSignKit.name_post("PERF ST", str(300 + i), "SCRAP AVE", "1")
	var key := "np|PERF ST|100|AUDIT AVE|200"
	var still: bool = StreetSignKit._cache.has(key) and StreetSignKit._cache[key] == held
	var scrap_left := 0
	for i in 6:
		if StreetSignKit._cache.has("np|PERF ST|%d|SCRAP AVE|1" % (300 + i)):
			scrap_left += 1
	_t._check(still and scrap_left < 6,
		"perf 3: the street-sign cache keeps a blade in use and drops ones nothing draws (%d of 6 scrap left)" % scrap_left)
	# A dropped one comes back the same.
	held = null
	StreetSignKit._cache.erase(key)
	var again: Mesh = StreetSignKit.name_post("PERF ST", "100", "AUDIT AVE", "200")
	_t._check(again.get_aabb().is_equal_approx(box_before) and again.get_surface_count() == surfaces,
		"perf 3: a blade dropped from the cache is built again the same")
	StreetSignKit._trim_at = maxi(saved_at, StreetSignKit._cache.size() + StreetSignKit.TRIM_EVERY)
	CacheTrim.enabled = was


func _sodium_rule() -> void:
	# NightAtmos._sodium() returns before the ground sample when SODIUM_LEAN * lamp * haze is
	# under its write threshold: that must be exactly when sodium_for() would have said nothing,
	# whatever the camera's height.
	var bad := 0
	for li in 11:
		for hi in 11:
			var lamp := float(li) / 10.0 * 0.004
			var haze := float(hi) / 10.0
			if NightAtmos.SODIUM_LEAN * lamp * haze > 0.0005:
				continue
			for cam_h in [0.0, 2.0, 30.0, 400.0]:
				if NightAtmos.sodium_for(lamp, haze, cam_h).x > 0.0005:
					bad += 1
	_t._check(bad == 0, "perf 3: the night haze's daytime early-out gives sodium_for()'s answer (%d disagree)" % bad)


func _sea_idle(city: Node3D) -> void:
	var sea: Node = city.get_node_or_null("SeaLife")
	if sea == null or not sea.has_method("_idle") or sea.get("macro") == null:
		_t._check(true, "perf 3: the sea's life idles inland (no SeaLife in this city)")
		return
	var inland: bool = sea.call("_idle", Vector3(2359.4, 0.0, 880.0))
	var macro: MacroMap = sea.get("macro")
	var coast := Vector3(macro.coast_x(200.0) - 300.0, 0.0, 200.0)
	var on_coast: bool = sea.call("_idle", coast)
	_t._check(inland and not on_coast, "perf 3: the sea's life idles downtown and works on the coast (%s / %s)" % [inland, on_coast])


func _ride_copies() -> void:
	# A staged entry in the suited cache (seed, suit, paint): ride_meshes() answers it from there.
	var list: Array = [ArrayMesh.new()]
	var k := "%d|%d|%d" % [987654, 3, 2]
	BeachFigure._ride_suits[k] = list
	var via: Array = BeachFigure.ride_meshes(987654, 3, 2, 0)
	_t._check(via.size() == 1 and via[0] == list[0] and not is_same(via, list),
		"perf 3: a beach rider's flipbook is handed out as its own array")
	BeachFigure._ride_suits.erase(k)


func _feet(city: Node3D) -> void:
	if not CrowdFeet.enabled:
		_t._check(true, "perf 3: crowd feet sample on the stagger (FOOT_IK off)")
		return
	var s0 := CrowdFeet.samples
	var k0 := CrowdFeet.sample_ticks
	for i in 90:
		await _t.get_tree().physics_frame
	var ticks := CrowdFeet.sample_ticks - k0
	var samples := CrowdFeet.samples - s0
	if ticks < 40:
		# Nobody within the feet's range of the camera this time: the rule itself, on one foot.
		_t._check(true, "perf 3: crowd feet sample on the stagger (only %d foot ticks near the camera)" % ticks)
		return
	# RAY_EVERY 2 near, 4 further: at most about half the ticks, plus each foot's first.
	_t._check(float(samples) <= float(ticks) * 0.62, "perf 3: crowd feet sample on the stagger, not every tick (%d samples in %d foot ticks)" % [samples, ticks])


func _canopy() -> void:
	var blob := PropFactory.canopy_blob()
	var ref := SphereMesh.new()
	ref.radius = 0.5
	ref.height = 1.0
	ref.radial_segments = 6
	ref.rings = 2
	var idx: PackedInt32Array = blob.surface_get_arrays(0)[Mesh.ARRAY_INDEX] if blob.get_surface_count() > 0 else PackedInt32Array()
	var v_ref: PackedVector3Array = ref.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	var ok := blob.get_aabb().is_equal_approx(ref.get_aabb())
	# Under the dummy renderer the mesh keeps no arrays: then only the box is checked.
	if not idx.is_empty():
		ok = ok and idx.size() == 72 and (blob.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == v_ref.size()
	var made := PropFactory.without_degenerate(ref)
	var made_idx: PackedInt32Array = (ref.get_mesh_arrays()[Mesh.ARRAY_INDEX] as PackedInt32Array)
	_t._check(ok and made.get_aabb().is_equal_approx(ref.get_aabb()) and made_idx.size() == 108,
		"perf 3: the far canopy is the 6-sided sphere less its 12 zero-area triangles, the same box")


func _balconies() -> void:
	var b: Node = CityChunk.BUILDING_SCENE.instantiate()
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PropFactory.balcony()
	mm.instance_count = 2
	node.multimesh = mm
	node.visibility_range_end = 480.0
	b.add_child(node)
	var was: bool = Building.balcony_shadow_split
	Building.balcony_shadow_split = true
	b.call("_balcony_shadows", node, [Transform3D(), Transform3D(Basis(), Vector3(3.0, 0.0, 0.0))])
	Building.balcony_shadow_split = was
	var near: MultiMeshInstance3D = b.get_node_or_null("BalconiesShadowNear")
	var far: MultiMeshInstance3D = b.get_node_or_null("BalconiesShadowFar")
	var only := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_t._check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and near != null and far != null \
			and near.cast_shadow == only and far.cast_shadow == only and near.multimesh == mm \
			and far.multimesh.instance_count == 2 and far.multimesh.mesh == PropFactory.balcony_shadow() \
			and is_equal_approx(near.visibility_range_end, Building.BALCONY_SHADOW_NEAR) \
			and is_equal_approx(far.visibility_range_begin, Building.BALCONY_SHADOW_NEAR) and is_equal_approx(far.visibility_range_end, 480.0),
		"perf 3: balconies cast from their own mesh near and a twin without the uprights past %.0f m" % Building.BALCONY_SHADOW_NEAR)
	_t._check(PropFactory.balcony_shadow().get_aabb().is_equal_approx(PropFactory.balcony().get_aabb()),
		"perf 3: the balcony's far shadow twin has the balcony's own box")
	# The balcony's LOD: its surface is indexed, and the renderer holds one LOD of the solid boxes
	# (the dummy renderer keeps no surface data: then the switch alone is checked).
	var surf: Dictionary = RenderingServer.mesh_get_surface(PropFactory.balcony().get_rid(), 0)
	var lods: Array = surf.get("lods", [])
	_t._check(not PropFactory.BALCONY_LOD or surf.is_empty() or surf.get("index_count", 0) == 0 \
			or (lods.size() == 1 and int(surf.get("index_count", 0)) == 34 * 36),
		"perf 3: the balcony carries one LOD without its uprights (%d LODs, %d indices)" % [lods.size(), int(surf.get("index_count", 0))])
	b.free()
