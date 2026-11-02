extends RefCounted
## The container terminal refcam (fleet wave 5, rc2-port; docs/HANDOFF.md "The container terminal
## from the crane"): checks for tests/smoke_test.gd. CPU and source only (headless reads no pixel):
##   * PortFill tops a pile up and never down, from its own stream (the same seed, the same yard),
##     and fills most of the empty slots;
##   * the high mast's head is a ring of lit floodlights, not the old 3.8 m panel box;
##   * the ship's bow rakes forward over the water and not at the waterline or aft;
##   * the mooring lines run from the bollards in the pattern's spans to the ship's side;
##   * the container roofs' dust is a uniform the switch clears;
##   * the camera row is at the port.
## PORT_FILL=0, PORT_SHIP=0, PORT_MOORING=0, PORT_ROOF=0 are the A/Bs.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_fill()
	_mast()
	_ship()
	_mooring()
	_roof()
	_camera()


func _fill() -> void:
	if not PortFill.enabled:
		_t._check(true, "rc2-port: PortFill off (PORT_FILL=0)")
		return
	var a := PortFill.rng_for(1337, 26, 51)
	var b := PortFill.rng_for(1337, 26, 51)
	var same := true
	var down := 0
	var tall := 0
	for i in 400:
		var n := 1 + i % 4
		var ta := PortFill.target(n, a)
		var tb := PortFill.target(n, b)
		same = same and ta == tb
		if ta < n or ta > 4:
			down += 1
		if ta >= 3:
			tall += 1
	_t._check(same, "rc2-port: the fill is a pure function of seed and chunk")
	_t._check(down == 0, "rc2-port: a pile is topped up to 1..4 tiers, never cut down (%d bad)" % down)
	_t._check(tall > 300, "rc2-port: most piles stand 3-4 high (%d of 400)" % tall)
	var r := PortFill.rng_for(1337, 27, 51)
	var filled := 0
	for i in 1000:
		if PortFill.fills_slot(r):
			filled += 1
	_t._check(filled > 700 and filled < 860, "rc2-port: %d of 1000 empty slots get a pile" % filled)


func _mast() -> void:
	var m := PortKit.mast_mesh()
	var aabb := m.get_aabb()
	_t._check(aabb.size.y > PortKit.MAST_H and aabb.size.x < 4.0 and aabb.size.z < 4.0, "rc2-port: the mast stands %.1f m with a head %.1f m across" % [aabb.size.y, aabb.size.x])
	var arr := m.surface_get_arrays(0)
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	if uv2.is_empty():
		_t._check(true, "rc2-port: no mesh data here (the dummy renderer): the mast's parts unread")
		return
	var lamps := 0
	var yellow := 0
	for i in uv2.size():
		if absf(uv2[i].x - PortKit.S_LAMP) < 0.1:
			lamps += 1
		if col[i].r > 0.8 and col[i].g > 0.6 and col[i].b < 0.3:
			yellow += 1
	_t._check(lamps >= 10 * 24 and yellow == 0, "rc2-port: ten lit floodlight lenses on the head (%d lamp vertices), no yellow panels (%d)" % [lamps, yellow])


func _ship() -> void:
	if not PortKit.SHIP_LOOK:
		_t._check(true, "rc2-port: the ship's new bow is off (PORT_SHIP=0)")
		return
	var x := PortKit.SHIP_BOW_X + 2.0
	var sec := PortKit._ship_section(x, 1.0)
	_t._check(sec[4].x < x - 4.0 and is_equal_approx(sec[2].x, x), "rc2-port: the bow rakes %.1f m forward at the deck, none at the waterline" % (x - sec[4].x))
	_t._check(sec[0].x < x - 1.0, "rc2-port: a bulb noses forward under the water")
	var aft := PortKit._ship_section(20.0, 1.0)
	_t._check(aft[4].x == 20.0 and aft[0].x == 20.0, "rc2-port: amidships and aft the sections are as before")
	var aabb := PortKit.ship_mesh().get_aabb()
	_t._check(aabb.position.x < PortKit.SHIP_BOW_X - 4.0, "rc2-port: the ship mesh reaches %.1f m (stem at the deck)" % aabb.position.x)
	var src := FileAccess.get_file_as_string("res://shaders/port_steel.gdshader")
	_t._check(src.contains("vec3 hull_plates(") and src.contains("part == 14"), "rc2-port: the hull's shell plating is drawn (part 14)")


func _mooring() -> void:
	if not PortMooring.enabled:
		_t._check(true, "rc2-port: mooring lines off (PORT_MOORING=0)")
		return
	var ship := Vector2(3065.0, 6541.0)
	var qz := ship.y - 21.3
	var bollards: Array = []
	var x := ship.x - 160.0
	while x < ship.x + 160.0:
		bollards.append(Vector3(x, 0.5, qz - 0.75))
		x += 16.0
	var mi := PortMooring.build(bollards, ship)
	_t._check(mi != null and mi.mesh.get_surface_count() == 1, "rc2-port: the quay's bollards hold lines")
	if mi:
		var aabb: AABB = mi.mesh.get_aabb()
		_t._check(aabb.position.z > qz - 1.5 and aabb.end.z < ship.y - 6.0 and aabb.end.y < PortKit.SHIP_DECK_Y + 5.0, "rc2-port: the lines run between the quay and the ship's side (z %.1f..%.1f)" % [aabb.position.z, aabb.end.z])
		_t._check(aabb.position.x > ship.x - 140.0 and aabb.end.x < ship.x + 135.0, "rc2-port: the lines stay within the pattern's spans")
		mi.free()
	_t._check(PortMooring.build([Vector3(ship.x, 0.5, qz)], ship) == null, "rc2-port: a bollard amidships holds no line")
	_t._check(PortMooring.build(bollards, Vector2(INF, INF)) == null, "rc2-port: no ship, no lines")


func _roof() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/container.gdshader")
	_t._check(src.contains("uniform float roof_dust") and src.contains("part == 1 && roof_dust > 0.0"), "rc2-port: container roofs carry dust, stains and rust")
	var want := 0.0 if OS.get_environment("PORT_ROOF") == "0" else 1.0
	var got: Variant = PortKit.container_material().get_shader_parameter("roof_dust")
	_t._check(got == null and want == 1.0 or got != null and is_equal_approx(float(got), want), "rc2-port: the roof dust follows PORT_ROOF")


func _camera() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w5.json"))
	var found := false
	if d is Dictionary:
		for c: Dictionary in d.get("cameras", []):
			if c.name == "port_crane":
				var e: Array = c.eye
				found = Rect2(2700.0, 5900.0, 750.0, 700.0).has_point(Vector2(e[0], e[2])) and float(c.hour) == 16.5
	_t._check(found, "rc2-port: the port_crane camera stands over the terminal at 16:30")
