class_name FireStationNight
extends RefCounted
## What an open firehouse bay shows at night (wave 8, rc5-fire-station-night, docs/HANDOFF.md
## "The fire station at night"). The bay behind a rolled-up door was a bare grey box with three
## ceiling strips: from across the street it read as a hole. Now each bay has what a real one has on
## its back and side walls - a row of gear lockers with turnout coats, trousers in their boots and
## helmets on top, a red-painted wainscot and a hose rack, yellow guide lines on the floor - and, on
## desktop, a light inside each bay (an OmniLight in `lamp_light`, so DayNight drives it with the
## street lamps); out of an open door a pool of the bay's light spills on the apron
## (light_pool.gdshader, lamp_factor-gated; shown while the door is up, FireStation.open_door()).
## Built once per station in its own frame by FireStation._build_detail() (one hook line), ONE
## mesh with a surface per material. FIRE_STATION_NIGHT=0 in the environment is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("FIRE_STATION_NIGHT") != "0"
## A bay light's share of the street lamps' level (DayNight's lamp_gain) and its reach (m).
const BAY_LIGHT_GAIN := 1.1
const BAY_LIGHT_RANGE := 11.0
## The lamp over each door's share (it is 0.9 m over the door, 8 m reach).
const DOOR_LIGHT_GAIN := 0.55
static var _mats: Dictionary = {}


## Dresses the bays of a station node: `doors` the door centres along x, `w` / `d` the building's
## width and depth, `bay_w` a door's width (the frame of FireStation._build_detail).
static func dress(node: Node3D, doors: Array, w: float, d: float, bay_w: float) -> void:
	if not enabled:
		return
	var g := FireStation.Geo.new()
	var back := -d + 0.32
	var hb := FireStation.BAY_H
	for x: float in doors:
		# Gear lockers along the back wall: open cubbies, a coat on a hook, trousers in boots, a
		# helmet on the shelf over each.
		var n := 6
		var span := bay_w + 0.9
		var cw := span / float(n)
		for k in n:
			var cx := x - span * 0.5 + (float(k) + 0.5) * cw
			g.box("fsn_locker", Vector3(cx, 1.05, back + 0.27), Vector3(cw - 0.04, 2.1, 0.04))
			g.box("fsn_locker", Vector3(cx - cw * 0.5 + 0.02, 1.05, back + 0.04 + 0.25), Vector3(0.03, 2.1, 0.5))
			g.box("fsn_locker", Vector3(cx, 1.92, back + 0.29), Vector3(cw - 0.02, 0.03, 0.5))
			var hue := 0.0 if (k + int(x * 3.0)) % 5 != 0 else 1.0
			g.box("fsn_turnout" if hue < 0.5 else "fsn_turnout_dark", Vector3(cx, 1.28, back + 0.42), Vector3(cw * 0.7, 0.78, 0.26))
			g.box("fsn_stripe", Vector3(cx, 1.08, back + 0.56), Vector3(cw * 0.72, 0.06, 0.02))
			g.box("fsn_stripe", Vector3(cx, 1.40, back + 0.56), Vector3(cw * 0.72, 0.06, 0.02))
			g.box("fsn_turnout", Vector3(cx, 0.42, back + 0.48), Vector3(cw * 0.62, 0.5, 0.3))
			g.box("fsn_boot", Vector3(cx, 0.12, back + 0.5), Vector3(cw * 0.66, 0.24, 0.32))
			g.box("fsn_helmet", Vector3(cx, 2.05, back + 0.4), Vector3(0.3, 0.2, 0.34))
		# A red wainscot round the bay and a band at head height, a hose rack on the side wall.
		g.box("fsn_red", Vector3(x, 0.6, back + 0.02), Vector3(bay_w + 1.2, 1.2, 0.03))
		for sx: float in [-1.0, 1.0]:
			var wx := x + sx * (bay_w * 0.5 + 0.55)
			g.box("fsn_red", Vector3(wx, 0.6, -d * 0.5), Vector3(0.03, 1.2, d - 1.0))
		var rx := x + (bay_w * 0.5 + 0.5)
		for k in 4:
			g.box("fsn_hose", Vector3(rx - 0.12, 1.3 + float(k) * 0.32, -d * 0.62), Vector3(0.22, 0.3, 1.6))
		g.box("fsn_locker", Vector3(rx - 0.05, 1.8, -d * 0.62), Vector3(0.1, 1.9, 1.8))
		# Yellow guide lines on the floor, the width of a unit apart, and the exhaust hose drop.
		for sx: float in [-1.0, 1.0]:
			g.box("fsn_yellow", Vector3(x + sx * 1.35, 0.025, -d * 0.5 + 0.4), Vector3(0.12, 0.012, d - 2.2))
		g.box("fsn_hose", Vector3(x, hb - 1.6, -d * 0.6), Vector3(0.22, 3.0, 0.22))
	var mi := MeshInstance3D.new()
	mi.name = "BayDress"
	mi.mesh = _commit(g)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	node.add_child(mi)
	for i in doors.size():
		var x: float = doors[i]
		if not OS.has_feature("web"):
			var l := OmniLight3D.new()
			l.name = "BayLight%d" % i
			l.position = Vector3(x, hb - 1.0, -d * 0.42)
			l.omni_range = BAY_LIGHT_RANGE
			l.omni_attenuation = 1.2
			l.light_color = Color(1.0, 0.93, 0.82)
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 110.0
			l.distance_fade_length = 30.0
			l.set_meta("lamp_gain", BAY_LIGHT_GAIN)
			l.add_to_group("lamp_light")
			node.add_child(l)
			# The lamp over the door lights the brick round it and the apron (the "lamp" boxes
			# beside each door glowed and lit nothing).
			var wl := OmniLight3D.new()
			wl.name = "DoorLight%d" % i
			wl.position = Vector3(x, FireStation.BAY_DOOR.y + 0.9, 0.8)
			wl.omni_range = 8.0
			wl.omni_attenuation = 1.4
			wl.light_color = Color(1.0, 0.86, 0.66)
			wl.light_energy = 0.0
			wl.shadow_enabled = false
			wl.distance_fade_enabled = true
			wl.distance_fade_begin = 110.0
			wl.distance_fade_length = 30.0
			wl.set_meta("lamp_gain", DOOR_LIGHT_GAIN)
			wl.add_to_group("lamp_light")
			node.add_child(wl)
		# The bay's light out of the open door on the apron (a quad laid flat, +Z out of the door).
		var spill := MeshInstance3D.new()
		spill.name = "BaySpill%d" % i
		spill.mesh = FwdReviewH.display_pool(PropFactory.light_pool(Color(1.0, 0.9, 0.74), 1.15, 1.6))
		spill.transform = Transform3D(Basis(Vector3.RIGHT * (bay_w + 2.2), Vector3.BACK * 7.5, Vector3.DOWN), Vector3(x, 0.05, 2.6))
		spill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spill.visibility_range_end = 180.0
		spill.visible = false
		node.add_child(spill)


## Shows or hides the spill under each open door of a station node (FireStation.open_door()).
static func show_spill(node: Node, on: bool) -> void:
	for c in node.get_children():
		if String(c.name).begins_with("BaySpill"):
			(c as Node3D).visible = on


static func _commit(g: FireStation.Geo) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key: String in g._st:
		var st: SurfaceTool = g._st[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key))
	return mesh


static func _material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var col := Color(0.5, 0.5, 0.5)
	var rough := 0.8
	var metal := 0.0
	match key:
		"fsn_locker":
			col = Color(0.30, 0.31, 0.33)
			rough = 0.5
			metal = 0.6
		"fsn_turnout":
			col = Color(0.55, 0.46, 0.30)
		"fsn_turnout_dark":
			col = Color(0.12, 0.12, 0.13)
		"fsn_stripe":
			col = Color(0.85, 0.88, 0.40)
			rough = 0.35
		"fsn_boot":
			col = Color(0.05, 0.05, 0.05)
			rough = 0.45
		"fsn_helmet":
			col = Color(0.92, 0.70, 0.10)
			rough = 0.3
		"fsn_red":
			col = Color(0.55, 0.06, 0.04)
			rough = 0.55
		"fsn_hose":
			col = Color(0.62, 0.58, 0.48)
		"fsn_yellow":
			col = Color(0.85, 0.68, 0.10)
			rough = 0.6
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m
