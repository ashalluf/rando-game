extends RefCounted
## A police station at night (PoliceStation's night pass) for tests/smoke_test.gd. Loaded at run
## time, so it compiles after the autoloads. Checks: a station's chunk carries a real light for the
## entrance and one per floodlight pole, all OmniLight3Ds in the lamp group (DayNight drives that
## group as OmniLight3D) and switched on by DayNight's level; the department's lettering wears the
## lit-letter material, dark by day and glowing after dark; the glass traces its rooms; and
## POLICE_NIGHT=0's path builds the old single car-park light.

var _t: Node
var _tree: SceneTree
var _city: Node3D
var _plan: CityPlan


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_city = city
	_plan = city.plan
	var found := {}
	var c := PoliceStation._cell_of(Vector2(1500.0, 0.0))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			if found.is_empty():
				found = PoliceStation.for_cell(_plan, c + Vector2i(dx, dz))
	_check(not found.is_empty(), "night: there is a station to light")
	if found.is_empty():
		return
	var n := await _lights_of(found)
	var lay: Dictionary = found.layout
	var poles := maxi(2, int(float(lay.L) / 22.0)) + 1
	_check(n.all == poles + 1 and n.omni == n.all and n.grouped == n.all,
			"night: the entrance and every floodlight pole carry a lamp-group omni light (%d of %d)" % [n.all, poles + 1])
	var day := _city.get_node_or_null("DayNight")
	var scale: float = day.get("lamp_scale") if day else 0.0
	_check(n.lit == n.all or scale <= 0.0, "night: DayNight switches the station's lights on after dark (%d of %d, lamp scale %.1f)" % [n.lit, n.all, scale])
	# The lettering.
	var mat := PoliceStation.letter_material()
	var code := (mat.shader as Shader).code
	_check(code.contains("lamp_factor") and code.contains("EMISSION") and float(mat.get_shader_parameter("energy")) > 0.5,
			"night: the department's name is lit lettering after dark")
	var glass := PoliceStation.material("lobby") as ShaderMaterial
	_check(glass != null and float(glass.get_shader_parameter("trace")) == 1.0 and (glass.shader as Shader).code.contains("room_hit"),
			"night: the lobby and office glass trace their rooms")
	# The A/B: the old night.
	PoliceStation.night_detail = false
	var old := await _lights_of(found)
	PoliceStation.night_detail = true
	_check(old.all == 2, "night: POLICE_NIGHT=0 builds the old two lights (%d)" % old.all)


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


## The station's lights in a freshly built FULL chunk of its block, after DayNight has had a few
## frames at 21:00.
func _lights_of(found: Dictionary) -> Dictionary:
	var day := _city.get_node_or_null("DayNight")
	var hour: float = day.get("hour") if day else 12.0
	if day:
		day.set("hour", 21.0)
	var chunk: CityChunk = _city._new_chunk(found.block, CityChunk.Level.FULL)
	chunk.build()
	for i in 30:
		await _tree.process_frame
	var out := {"all": 0, "omni": 0, "grouped": 0, "lit": 0}
	for n in chunk.get_children():
		if n.is_in_group("police_station"):
			for l: Light3D in n.find_children("*", "Light3D", false, false):
				out.all += 1
				out.omni += 1 if l is OmniLight3D else 0
				out.grouped += 1 if l.is_in_group("lamp_light") else 0
				out.lit += 1 if l.visible and l.light_energy > 0.0 else 0
	if day:
		day.set("hour", hour)
	chunk.queue_free()
	await _tree.process_frame
	return out
