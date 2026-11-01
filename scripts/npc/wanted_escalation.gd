class_name WantedEscalation
extends RefCounted
## What each wanted star brings (fleet wave 4, "the five stars as distinct"). One table, read by
## the Police node (caps, roadblocks, which unit a dispatch sends), AirTraffic (how many
## helicopters, and the gunship), the cruisers' sirens and the radio (WantedAudio) and the HUD's
## line under the stars (WantedTicker):
##
##   1  one patrol cruiser, a slow wail, a dispatch beep and a call now and then;
##   2  several cruisers, wail and yelp traded as they close in, more chatter;
##   3  the police helicopter (AirTraffic) and roadblocks ahead of a player in a car;
##   4  tactical vans every other unit (three officers with carbines and ballistic helmets), a
##      second helicopter, the vans' air horns, the radio near continuous;
##   5  the BASIN DEFENSE CORPS (invented agency): olive drab troop trucks with four troopers in
##      field drab, and a matte gunship over the player with the brightest searchlight; the
##      trucks' own hi-lo two-tone, the emergency tone on the radio.
##
## The agency, its trucks and its gunship are original: no real army, guard or police force's
## name, insignia or livery. `WANTED_ESCALATION=0` in the environment puts the old response back
## (the A/B): the caps, roadblocks at four, vans at five, two helicopters, one siren.

## Off (the A/B): every hook below leaves the old behaviour.
static var enabled: bool = OS.get_environment("WANTED_ESCALATION") != "0"

## The invented agency that comes at five stars, and its paint (RGB as the car paint takes it).
const AGENCY := "BASIN DEFENSE CORPS"
const AGENCY_SHORT := "BDC"
const AGENCY_OLIVE := Color(0.235, 0.255, 0.150)
const AGENCY_BAND := Color(0.110, 0.120, 0.080)
## The gunship's matte charcoal and its dark olive belly.
const GUNSHIP_TOP := Color(0.040, 0.044, 0.042)
const GUNSHIP_LOW := Color(0.070, 0.080, 0.055)

## Unit kinds a dispatch can send.
enum Unit { CRUISER, VAN, TRUCK }

## Per star (index = stars, 0..5).
const CRUISERS := [0, 1, 3, 4, 5, 7]
const OFFICERS := [0, 2, 6, 8, 12, 18]
## Police helicopters over the player (AirTraffic); the last one at five stars is the gunship.
const HELICOPTERS := [0, 0, 0, 1, 2, 3]
## Roadblocks from three stars, tactical vans from four, the agency at five.
const ROADBLOCK_STARS := 3
const VAN_STARS := 4
const AGENCY_STARS := 5
## Which unit the n-th dispatch at this level is (cycled): four stars every other unit a van;
## five stars the agency's trucks two in four, a van and a cruiser between them.
const PATTERN := {
	4: [Unit.CRUISER, Unit.VAN],
	5: [Unit.TRUCK, Unit.VAN, Unit.TRUCK, Unit.CRUISER],
}
## Seconds between radio calls at each level (WantedAudio), 0 = none.
const RADIO_GAP := [0.0, 13.0, 9.0, 6.5, 4.5, 3.0]
## The siren a unit plays at each level (WantedAudio picks per car): which voices are in the mix
## and how close (m) to the player a cruiser trades its wail for the yelp.
const YELP_REACH := [0.0, 0.0, 70.0, 95.0, 120.0, 150.0]
## The line under the stars when a level is reached (WantedTicker).
const CALLS := ["", "PATROL UNIT RESPONDING", "UNITS CONVERGING", "AIR SUPPORT · ROADBLOCKS",
		"TACTICAL UNITS DEPLOYED", "BASIN DEFENSE CORPS MOBILIZED"]


## Puts the per-star caps on the Police node (from Police._ready). Values only: the A/B leaves
## the node's exports as they were.
static func apply(police: Node) -> void:
	if not enabled or police == null:
		return
	police.set("cruisers_per_star", PackedInt32Array(CRUISERS))
	police.set("officers_per_star", PackedInt32Array(OFFICERS))
	police.set("roadblock_stars", ROADBLOCK_STARS)
	police.set("heavy_stars", VAN_STARS)


## The unit the `n`-th dispatch sends at `stars` (pure).
static func unit_for(stars: int, n: int) -> Unit:
	if not enabled:
		# The old rule: every other unit a van from five stars.
		return Unit.VAN if stars >= 5 and n % 2 == 1 else Unit.CRUISER
	var key := clampi(stars, 0, 5)
	if not PATTERN.has(key):
		return Unit.CRUISER
	var p: Array = PATTERN[key]
	return p[posmod(n, p.size())]


## Helicopters wanted over the player at `stars` (AirTraffic); `old_from` is AirTraffic's own
## police_stars for the A/B rule (one at that level, two above).
static func helicopters(stars: int, old_from: int) -> int:
	if not enabled:
		if stars < old_from:
			return 0
		return 1 if stars == old_from else 2
	return HELICOPTERS[clampi(stars, 0, 5)]


## True for the pursuer slot that is the gunship (the third over the player at five stars).
static func is_gunship_slot(stars: int, index: int) -> bool:
	return enabled and stars >= AGENCY_STARS and index >= 2


static func radio_gap(stars: int) -> float:
	return RADIO_GAP[clampi(stars, 0, 5)]


static func yelp_reach(stars: int) -> float:
	return YELP_REACH[clampi(stars, 0, 5)] if enabled else 0.0


static func call_for(stars: int) -> String:
	return CALLS[clampi(stars, 0, 5)]


# --- The agency's truck --------------------------------------------------------------------------

## Matte steel for the truck's push bar and roof gear.
const BAR_STEEL := Color(0.035, 0.037, 0.034)
static var _bar_mesh: ArrayMesh
static var _bar_mat: StandardMaterial3D


## Dresses an agency PoliceCar (a BOX_TRUCK body, from PoliceCar._ready): a grille guard across
## the nose and a rack of gear boxes on the box roof, one code-built mesh shared by every truck.
static func dress_truck(car: Vehicle) -> void:
	var d := car._dims()
	var length: float = d.length
	var lamp_y: float = d.lamp_y
	var mi := MeshInstance3D.new()
	mi.name = "AgencyGear"
	mi.mesh = truck_gear_mesh(length, float(d.width), lamp_y, car._model_top_y if car._has_model else 3.3)
	if _bar_mat == null:
		_bar_mat = StandardMaterial3D.new()
		_bar_mat.vertex_color_use_as_albedo = true
		_bar_mat.vertex_color_is_srgb = true
		_bar_mat.roughness = 0.62
		_bar_mat.metallic = 0.55
	mi.material_override = _bar_mat
	mi.visibility_range_end = 160.0
	car.add_child(mi)


## The grille guard (two uprights, three rails, four grille bars) a hand ahead of the nose, and
## two gear lockers on the box roof behind the light bar. Body space: -Z the nose.
static func truck_gear_mesh(length: float, width: float, lamp_y: float, top: float) -> ArrayMesh:
	if _bar_mesh != null:
		return _bar_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := -length * 0.5 - 0.16
	var y0 := lamp_y - 0.55
	var y1 := lamp_y + 0.42
	var half := width * 0.5 - 0.18
	for x: float in [-half * 0.62, half * 0.62]:
		_box(st, Vector3(x, (y0 + y1) * 0.5, z), Vector3(0.09, y1 - y0, 0.09), BAR_STEEL)
		# The bracket back to the chassis.
		_box(st, Vector3(x, y0 + 0.12, z + 0.22), Vector3(0.07, 0.07, 0.42), BAR_STEEL)
	for y: float in [y0 + 0.10, lamp_y - 0.08, y1 - 0.04]:
		_box(st, Vector3(0.0, y, z), Vector3(half * 2.0, 0.07, 0.07), BAR_STEEL)
	for x: float in [-0.30, -0.10, 0.10, 0.30]:
		_box(st, Vector3(x, (lamp_y - 0.08 + y1) * 0.5, z - 0.01), Vector3(0.035, y1 - lamp_y + 0.08, 0.035), BAR_STEEL)
	# Lockers on the box roof.
	var olive := AGENCY_OLIVE.lightened(0.05)
	for k in 2:
		_box(st, Vector3(0.0, top + 0.17, -length * 0.5 + 4.0 + 1.6 * float(k)), Vector3(width * 0.62, 0.34, 1.1), olive)
	st.generate_normals()
	_bar_mesh = st.commit()
	return _bar_mesh


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	# Clockwise seen from outside (PoliceCar._bar_box's order).
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(p[f[k]])


# --- The gunship ---------------------------------------------------------------------------------

## The gunship's orbit round the player: radius (m), and how much higher than the police
## helicopters it flies (m).
const GUNSHIP_ORBIT := Vector2(128.0, 24.0)
## Its searchlight: energy and cone over a police helicopter's.
const GUNSHIP_LIGHT_GAIN := 1.8
const GUNSHIP_LIGHT_ANGLE := 9.5
static var _pods_mesh: ArrayMesh
static var _gun_paint: Array = []


## Turns a police helicopter into the agency's gunship (once; from AirTraffic's pursuit orders):
## matte charcoal over a dark olive belly, the police lettering painted out, stub wings with two
## rocket pods each, and a brighter, wider searchlight.
static func arm_gunship(h: Node3D) -> void:
	if h == null or h.has_meta("gunship"):
		return
	h.set_meta("gunship", true)
	var visual := h.get("_visual") as Node3D
	if _gun_paint.is_empty():
		for c: Color in [GUNSHIP_TOP, GUNSHIP_LOW, GUNSHIP_TOP.lightened(0.04)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.78
			m.metallic = 0.1
			_gun_paint.append(m)
	if visual:
		var liv: Array = Helicopter.LIVERIES[Helicopter.Role.POLICE]
		for n in visual.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for si in mi.mesh.get_surface_count():
				var o := mi.get_surface_override_material(si) as StandardMaterial3D
				if o == null:
					continue
				for k in 4:
					if o.albedo_color.is_equal_approx(liv[k]):
						# Paint, belly, stripe; the lettering goes the paint's colour.
						mi.set_surface_override_material(si, _gun_paint[k if k < 3 else 0])
						break
		var pods := MeshInstance3D.new()
		pods.name = "GunshipPods"
		pods.mesh = pods_mesh()
		# Both faces: the cans are written without caring which way round they wind.
		var pm := (_gun_paint[1] as StandardMaterial3D).duplicate() as StandardMaterial3D
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pods.material_override = pm
		visual.add_child(pods)
	h.set("searchlight_energy", float(h.get("searchlight_energy")) * GUNSHIP_LIGHT_GAIN)
	h.set("searchlight_angle", GUNSHIP_LIGHT_ANGLE)
	var spot := h.get("_spot") as SpotLight3D
	if spot:
		spot.spot_angle = GUNSHIP_LIGHT_ANGLE


## Stub wings out of the cabin's sides, a pylon and a rocket pod under each tip and mid-span:
## a pod is a sixteen-sided can with a blunt nose ring. Helicopter model space (+Z the tail).
static func pods_mesh() -> ArrayMesh:
	if _pods_mesh != null:
		return _pods_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(1, 1, 1)
	for side: float in [-1.0, 1.0]:
		# The wing: a tapered slab, root at the cabin's side.
		_box(st, Vector3(side * 1.55, 1.02, -0.35), Vector3(1.5, 0.09, 0.85), col)
		for x: float in [1.25, 2.05]:
			_box(st, Vector3(side * x, 0.86, -0.35), Vector3(0.08, 0.26, 0.45), col)
			_can(st, Vector3(side * x, 0.62, -0.45), 0.19, 1.55, 16)
	st.generate_normals()
	_pods_mesh = st.commit()
	return _pods_mesh


## A capped cylinder along Z centred at `c`, radius `r`, length `l`.
static func _can(st: SurfaceTool, c: Vector3, r: float, l: float, seg: int) -> void:
	var z0 := c.z - l * 0.5
	var z1 := c.z + l * 0.5
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := Vector2(cos(a0), sin(a0)) * r
		var p1 := Vector2(cos(a1), sin(a1)) * r
		var a := Vector3(c.x + p0.x, c.y + p0.y, z0)
		var b := Vector3(c.x + p1.x, c.y + p1.y, z0)
		var cc := Vector3(c.x + p1.x, c.y + p1.y, z1)
		var d := Vector3(c.x + p0.x, c.y + p0.y, z1)
		# Clockwise from outside.
		for v: Vector3 in [a, cc, b, a, d, cc]:
			st.set_color(Color.WHITE)
			st.add_vertex(v)
		# Caps (the front one a little recessed ring is left to the shading).
		for v: Vector3 in [Vector3(c.x, c.y, z0), a, b]:
			st.set_color(Color.WHITE)
			st.add_vertex(v)
		for v: Vector3 in [Vector3(c.x, c.y, z1), cc, d]:
			st.set_color(Color.WHITE)
			st.add_vertex(v)
