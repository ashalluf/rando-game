extends RefCounted
## The metro_station refcam (wave 7: MetroLook, MetroCrowd, MetroRider's escalators; docs/HANDOFF.md
## "The metro station refcam") for tests/smoke_test.gd. Loaded at run time, so it compiles after
## the autoloads. Builds the underground station into a chunk of its own (not the city's: nothing
## the city streams is touched), with and without MetroLook, and frees it.
##
## Checks: the camera row (on the platform, a train held at the terminus); the ad cells are the
## billboard shader's; the station's mesh carries ad lightboxes and its material the floor mirror
## and the atlas, and the A/B carries none; the escalator riders stand on the step at both ends
## and step off onto their floor; the station starts with people on both escalators; the bullet's
## letter faces out of the car; the cars' saloons switch to their own lights underground.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var line := LightRail.of(plan)
	var f := MetroStation.frame(line) if line else {}
	_check(not f.is_empty(), "rc4 metro: the underground station resolves")
	if f.is_empty():
		return
	_camera(f)
	_cells()
	_escalator(line, f)
	_letter()
	_saloon()
	var was := MetroLook.enabled
	var on := _build(city, plan, f)
	MetroLook.enabled = false
	var off := _build(city, plan, f)
	MetroLook.enabled = was
	_check(int(on.ads) >= 7 and float(on.mirror) > 0.0 and bool(on.atlas),
		"rc4 metro: ad lightboxes on the walls (%d quads' vertices / 6), the floors mirror, the atlas is set" % int(on.ads))
	_check(int(off.ads) == 0 and float(off.mirror) == 0.0, "rc4 metro: METRO_LOOK=0 builds the station as it was")
	_check(int(on.down) >= MetroCrowd.START_DOWN and int(on.up) >= MetroCrowd.START_UP,
		"rc4 metro: people ride both escalators from the start (%d down, %d up)" % [int(on.down), int(on.up)])


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func _camera(f: Dictionary) -> void:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var cam := {}
	if table is Dictionary:
		for c: Dictionary in table.get("cameras", []):
			if String(c.get("name", "")) == "metro_station":
				cam = c
	_check(not cam.is_empty() and String(cam.get("rail_at", "")).begins_with("0"), "rc4 metro: the camera row holds a train at the terminus")
	if cam.is_empty():
		return
	var e: Array = cam.eye
	var p := MetroStation.to_frame(f, Vector3(float(e[0]), float(e[1]), float(e[2])))
	_check(absf(p.x) < LightRail.PLATFORM_LENGTH * 0.5 and absf(p.z) < MetroStation.PLATFORM_WIDTH * 0.5 \
		and p.y > float(f.plat) + 1.2 and p.y < float(f.plat) + 2.2,
		"rc4 metro: the eye stands on the island at eye height (u %.1f, v %.1f, %.2f m up)" % [p.x, p.z, p.y - float(f.plat)])


func _cells() -> void:
	# MetroLook.cell() is billboard_face.gdshader's cell() (the same numbers): read them back.
	var src := FileAccess.get_file_as_string("res://shaders/billboard_face.gdshader")
	_check(src.find("1788.0 + float(i / 4) * 256.0") >= 0 and src.find("float(i / 2) * 298.0") >= 0,
		"rc4 metro: the poster and bulletin cells are the billboard shader's")
	var r := MetroLook.cell(MetroLook.POSTER, 11)
	_check(r.end.x <= 1.0 and r.end.y <= 1.0 and r.position.y > 0.5, "rc4 metro: every poster cell is inside the atlas")


func _escalator(line: LightRail, f: Dictionary) -> void:
	var m := MetroRider.new()
	m.line = line
	m.frame = f
	m.ride(1, -MetroStation.BANK_U + 0.3)
	var top := MetroStation.to_frame(f, m.position)
	var foot := MetroStation.to_frame(f, m._esc_point(MetroStation.BANK_U - 0.3))
	var mid := MetroStation.to_frame(f, m._esc_point(0.0))
	_check(absf(top.y - MetroStation.CONC_FLOOR - 0.06) < 0.02 and absf(foot.y - float(f.plat) - 0.06) < 0.02,
		"rc4 metro: an escalator rider stands on the concourse at the top and the island at the foot")
	var mid_want := (MetroStation.CONC_FLOOR + float(f.plat)) * 0.5 + 0.06
	_check(absf(mid.y - mid_want) < 0.05 and absf(mid.z) < 0.01, "rc4 metro: and on the incline between, in the down lane (%.2f)" % mid.y)
	m.ride(-1, 0.0)
	var up_lane := MetroStation.to_frame(f, m.position)
	_check(absf(up_lane.z - 1.45) < 0.01, "rc4 metro: the up escalator is the other lane")
	m.free()


func _letter() -> void:
	var n := Vector3(1, 0, 0)
	var mesh := MetroLook.bullet_letter(Vector3(1.338, 2.0, -5.05), n, Vector3.UP, 0.135, 0.088, Color.WHITE)
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cw := 0
	for i in range(0, v.size(), 3):
		if (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).dot(n) < 0.0:
			cw += 1
	_check(v.size() > 0 and cw == v.size() / 3, "rc4 metro: the bullet's C faces out of the car (clockwise fronts, %d of %d)" % [cw, v.size() / 3])


## The station alone in a FULL chunk of its own: what it carries.
func _build(city: Node3D, plan: CityPlan, f: Dictionary) -> Dictionary:
	var key := plan.chunk_index_at(f.o)
	var ch := CityChunk.new()
	ch.plan = plan
	ch.ix = key.x
	ch.iz = key.y
	ch.level = CityChunk.Level.FULL
	ch.style = city.chunk_style()
	ch._crowd_room = 40
	ch.name = "Rc4MetroCheck"
	_t.get_tree().root.add_child(ch)
	var kit := MetroBuild.new(ch)
	var ok := kit.build()
	var out := {"ok": ok, "ads": 0, "mirror": 0.0, "atlas": false, "down": 0, "up": 0}
	var mi := ch.get_node_or_null("MetroStation") as MeshInstance3D
	if mi and mi.mesh:
		var ads := 0
		for si in mi.mesh.get_surface_count():
			var cols: PackedColorArray = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_COLOR]
			for c in cols:
				if roundi(c.a * 32.0) == MetroBuild.K_AD:
					ads += 1
		out.ads = ads / 6
		var mat := mi.material_override as ShaderMaterial
		if mat:
			var g: Variant = mat.get_shader_parameter("mirror_gain")
			out.mirror = float(g) if g != null else 0.0
			out.atlas = mat.get_shader_parameter("ad_atlas") != null
	for n in ch.get_children():
		var r := n as MetroRider
		if r and r.level == 2:
			if r.esc_dir > 0:
				out.down += 1
			else:
				out.up += 1
	_t.get_tree().root.remove_child(ch)
	ch.free()
	return out


## The cars' glass: lit by its LED strips while the camera is down in the station, the old shader
## (underground 0) everywhere else and under METRO_LOOK=0.
func _saloon() -> void:
	var m := LightRailTrain.glass_material()
	var was := MetroLook.enabled
	MetroLook.saloon(true)
	var down := float(m.get_shader_parameter("underground"))
	MetroLook.saloon(false)
	var up := float(m.get_shader_parameter("underground"))
	MetroLook.enabled = false
	MetroLook.saloon(true)
	var ab := float(m.get_shader_parameter("underground"))
	MetroLook.enabled = was
	MetroLook.saloon(MetroStation.showing)
	_check(down == 1.0 and up == 0.0 and ab == 0.0,
		"rc4 metro: the cars' saloons use their own lights underground (%.0f), the sky's on the street (%.0f), and not under METRO_LOOK=0 (%.0f)" % [down, up, ab])
	var src := FileAccess.get_file_as_string("res://shaders/lrv_glass.gdshader")
	_check(src.count("if (underground > 0.0)") == 1 and src.contains("underground > 0.0 ? mix(strip_color"),
		"rc4 metro: lrv_glass's underground light is gated (0 draws the old saloon)")
