extends RefCounted
## The walk of fame at night (WalkOfFameNight; refcam walk_of_fame_night), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The camera row; the pure hours (the premiere's evening, the tourists by the hour); then the
## palace's block built FULL at 22:00 with the crowd cap full: the premiere's carpet, carts and
## beams, its key fans, every planned character, the tourists on the walk's pavement, the lamps'
## lit star medallions; the same block at noon (no premiere); and with RC5_WALK_OF_FAME off
## (no premiere, the characters refused by a full cap as before).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_row()
	_pure()
	var plan: CityPlan = city.plan
	var p := StarBoulevard.plan_for(plan)
	var pal: Dictionary = p.get("palace", {})
	_t._check(not pal.is_empty(), "the walk of fame and its palace exist on this seed (walk_of_fame_night frames them)")
	if pal.is_empty():
		return
	var was_test := WalkOfFameNight.force_in_test
	WalkOfFameNight.force_in_test = true
	_night(city, plan, pal)
	_noon(city, pal)
	_off(city, plan, pal)
	WalkOfFameNight.force_in_test = was_test
	WalkOfFameNight.force_hour = -1.0
	WalkOfFameNight.enabled = true


func _row() -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text()) if f else null
	var row := {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if String(c.get("name", "")) == "walk_of_fame_night":
				row = c
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 22.0 and String(row.get("weather", "")) == "clear" and (row.eye as Array).size() == 5,
		"the walk_of_fame_night refcam row: 22:00 clear, an eye on the walk")


func _pure() -> void:
	var ok := WalkOfFameNight.premiere_on(22.0) and WalkOfFameNight.premiere_on(0.5) \
		and not WalkOfFameNight.premiere_on(12.0) and not WalkOfFameNight.premiere_on(1.5) and not WalkOfFameNight.premiere_on(19.0)
	_t._check(ok, "the Celeste's premiere is on every evening from 19:30 to 01:00, never by day")
	_t._check(WalkOfFameNight.tourist_count(22.0) == WalkOfFameNight.TOURISTS and WalkOfFameNight.tourist_count(4.0) <= 1
		and WalkOfFameNight.tourist_count(13.0) < WalkOfFameNight.tourist_count(21.0),
		"the walk's tourists by the hour: busiest at night (%d at 22:00), nearly none at 04:00" % WalkOfFameNight.tourist_count(22.0))


## Builds the palace's block FULL with the crowd cap full (no room for anyone).
func _build(city: Node3D, k: Vector2i, hour: float) -> CityChunk:
	WalkOfFameNight.force_hour = hour
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var cap: int = city.get("max_pedestrians")
	city.set("max_pedestrians", 0)
	city.set("_crowd_frame", -1)
	chunk.build()
	city.set("max_pedestrians", cap)
	city.set("_crowd_frame", -1)
	return chunk


func _night(city: Node3D, plan: CityPlan, pal: Dictionary) -> void:
	var k: Vector2i = pal.block
	WalkOfFameNight.fans_spawned = 0
	WalkOfFameNight.tourists_spawned = 0
	var chunk := _build(city, k, 22.0)
	var holder := chunk.get_node_or_null("WalkPremiere")
	var beams := 0
	var carpet := false
	if holder:
		for c in holder.get_children():
			if c is SkyBeam:
				beams += 1
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_nl_premiere_"):
			carpet = (c as MultiMeshInstance3D).multimesh.instance_count == 1
	_t._check(holder != null and carpet and beams == 4,
		"22:00: the Celeste's premiere - the red carpet to the kerb and four searchlights (%d)" % beams)
	# The carpet runs from the palace's doors out to the kerb.
	var f := StarBoulevard.palace_frame(chunk, pal)
	var to_kerb := float(f[3])
	_t._check(to_kerb > StarBoulevard.FORECOURT and to_kerb < StarBoulevard.FORECOURT + 9.0,
		"the carpet crosses the forecourt and the pavement (%.1f m)" % to_kerb)
	var fans := 0
	var chars := 0
	var tourists := 0
	var rect: Rect2 = plan.block(k.x, k.y).rect
	var kz := StarBoulevard.kerb_z(rect, int(pal.side))
	for c in chunk.get_children():
		if c is NightGoer and (c as NightGoer).role == NightGoer.Role.FAN:
			fans += 1
		elif c is StreetCharacter:
			chars += 1
		elif c.get_script() == Pedestrian and (c as Node3D).has_meta("no_trim"):
			var z := (c as Node3D).position.z
			if absf(z - kz) <= plan.sidewalk_width + 0.5:
				tourists += 1
	_t._check(fans >= WalkOfFameNight.KEY_FANS, "the premiere's fans stand behind the barriers with the crowd cap full (%d)" % fans)
	var want := 0
	for i in StarBoulevard.MAX_CHARACTERS:
		if not StarBoulevard.character_spot(plan, k.x, k.y, rect, int(pal.side), i).is_empty():
			want += 1
	_t._check(chars == want, "every planned character stands on the stars with the crowd cap full (%d of %d)" % [chars, want])
	_t._check(tourists >= WalkOfFameNight.KEY_TOURISTS, "tourists on the walk's pavement at night with the cap full (%d)" % tourists)
	var medal := StarBoulevard.medallion_mesh()
	var size := medal.get_aabb().size
	var plate := medal.surface_get_material(0) as ShaderMaterial
	_t._check(size.y > WalkOfFameNight.MEDALLION_R * 1.8 and plate != null and float(plate.get_shader_parameter("plate")) == 1.0,
		"the lamps' star medallion is %.2f m and its plate lit after dark (star_neon plate)" % size.y)
	_free(chunk)


func _noon(city: Node3D, pal: Dictionary) -> void:
	var chunk := _build(city, pal.block, 12.0)
	_t._check(chunk.get_node_or_null("WalkPremiere") == null, "no premiere at noon")
	_free(chunk)


func _off(city: Node3D, plan: CityPlan, pal: Dictionary) -> void:
	WalkOfFameNight.enabled = false
	var chunk := _build(city, pal.block, 22.0)
	var chars := 0
	for c in chunk.get_children():
		if c is StreetCharacter:
			chars += 1
	_t._check(chunk.get_node_or_null("WalkPremiere") == null and chars == 0,
		"RC5_WALK_OF_FAME=0: no premiere, and a full crowd cap refuses the characters as before")
	WalkOfFameNight.enabled = true
	_free(chunk)


func _free(chunk: CityChunk) -> void:
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and (car as Node).get_parent() != chunk:
			(car as Node).get_parent().remove_child(car)
			(car as Node).free()
	chunk.get_parent().remove_child(chunk)
	chunk.free()
