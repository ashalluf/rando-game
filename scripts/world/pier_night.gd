class_name PierNight
extends RefCounted
## The pier at night (wave 4, refcam pier_night: "the pier and its wheel from the beach, 21:00"):
## what made RANDO PIER read dead from the sand, fixed where the park is built.
##
## * **The wheel's LEDs from afar** (`wheel_glow()`): the LED strips are 13 cm wide, a fifth of a
##   pixel from the beach, so the wheel drew as its white steel with a few specks of colour. Two
##   quads in the wheel's plane on `shaders/pier_wheel_glow.gdshader` draw every strip and ring
##   analytically, at their real place and pattern, at least a pixel wide with their own light
##   spread over it, once the real strips are under a couple of pixels; and a soft glow of the
##   wheel's colour in the air round it.
## * **The deck's lights as points of light** (`halos()`): the lamp globes, the strings of bulbs,
##   the stands' and booths' fronts, the carousel's crown and a new row of chaser bulbs along the
##   coaster's track were under a pixel past 80 m, so the deck was a black slab under a lit wheel.
##   Each gets a NightAtmos halo (night_halo.gdshader: a core never under a couple of pixels, the
##   glow by the air) - one MultiMesh, one draw, collapsed by day in the vertex stage.
## * **The coaster's chaser bulbs** (`coaster_bulbs()`, PierCoaster's near track mesh): a bulb
##   every BULB_STEP metres on the outside of each rail, chasing along the track (pier_park's bulb
##   kind), like the real pier rides.
##
## Nothing here rolls anything: positions are the park's own constants. `PIER_NIGHT=0` in the
## environment is the A/B (the park exactly as before).

static var enabled: bool = OS.get_environment("PIER_NIGHT") != "0"

## Chaser bulbs along the coaster: spacing (m), how far outside the rail, their size and colours.
const BULB_STEP := 2.4
const BULB_OUT := 0.13
const BULB_R := 0.07
const BULB_COLORS: Array[Color] = [Color(1.0, 0.86, 0.55), Color(1.0, 0.86, 0.55), Color(1.0, 0.45, 0.35), Color(0.55, 0.8, 1.0)]
## Halo radii (m) and strengths (night_halo's INSTANCE_CUSTOM.r) per kind of light.
const LAMP_HALO := 0.55
const LAMP_GAIN := 1.0
const STRING_HALO := 0.22
const STRING_GAIN := 0.55
const STRING_EVERY := 3
const COASTER_HALO := 0.24
const COASTER_GAIN := 0.6
const FRONT_HALO := 2.4
const FRONT_GAIN := 0.7
const CROWN_HALO := 5.5
const CROWN_GAIN := 0.55
## The far copy (a kilometre and more off): every FAR_THIN-th string and coaster bulb, at FAR_GAIN
## of its strength - all of them, each a core of a pixel or two, ran into one blown-out smear.
const FAR_THIN := 4
const FAR_GAIN := 0.4

static var _cache: Dictionary = {}


## The dressing for one build of the park (near or far): the wheel's glow on `wheel`, the halos
## under `park`. A no-op with the A/B off.
static func dress(park: Node3D, wheel: Node3D, deck: float, detailed: bool) -> void:
	if not enabled:
		return
	if wheel != null:
		wheel_glow(wheel)
	halos(park, deck, detailed)


# --- The wheel ----------------------------------------------------------------------------------

static func wheel_glow(wheel: Node3D) -> MeshInstance3D:
	if not _cache.has("wheel_glow"):
		_cache["wheel_glow"] = _wheel_glow_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "WheelGlow"
	mi.mesh = _cache["wheel_glow"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wheel.add_child(mi)
	return mi


static func _wheel_glow_mesh() -> ArrayMesh:
	var hub := Vector3(0.0, FerrisWheel.HUB_H, 0.0)
	var h := FerrisWheel.RADIUS * 1.6
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for zs: float in [-1.0, 1.0]:
		var z := zs * (FerrisWheel.RIM_Z + 0.16)
		var c := [hub + Vector3(-h, -h, z), hub + Vector3(h, -h, z), hub + Vector3(h, h, z), hub + Vector3(-h, h, z)]
		# Godot's front faces wind clockwise seen from the front: the +z quad is seen from +z.
		var order := [0, 2, 1, 0, 3, 2] if zs > 0.0 else [0, 1, 2, 0, 2, 3]
		for k: int in order:
			v.append(c[k])
			n.append(Vector3(0.0, 0.0, zs))
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pier_wheel_glow.gdshader")
	mat.set_shader_parameter("hub", hub)
	mat.set_shader_parameter("omega", FerrisWheel.OMEGA)
	mat.set_shader_parameter("radius", FerrisWheel.RADIUS)
	mat.set_shader_parameter("inner", FerrisWheel.RADIUS - FerrisWheel.RIM_DEPTH)
	mat.set_shader_parameter("spokes", float(FerrisWheel.SPOKES))
	m.surface_set_material(0, mat)
	return m


# --- The coaster's bulbs ------------------------------------------------------------------------

## The bulbs' places along the coaster (park frame): [position, outward side vector, index].
static func coaster_points(deck: float) -> Array:
	var key := "coaster_%.2f" % deck
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var s := 0.5
	var i := 0
	while s < PierCoaster.length:
		var p := PierCoaster.point(s, deck)
		var b := PierCoaster.frame(s, deck)
		for side: float in [-1.0, 1.0]:
			out.append([p + b.x * side * (PierCoaster.GAUGE * 0.5 + BULB_OUT) - b.y * 0.05, b.x * side, i])
		i += 1
		s += BULB_STEP
	_cache[key] = out
	return out


## Writes the bulbs into the coaster's near track mesh (pier_park's bulb kind: they chase by index).
static func coaster_bulbs(g: PierMesh, deck: float) -> void:
	if not enabled:
		return
	var kind := g.kind
	var anim := g.anim
	g.kind = PierMesh.K_BULB
	for pt: Array in coaster_points(deck):
		g.anim = float(pt[2])
		g.ellipsoid(Transform3D(Basis(), pt[0]), Vector3.ONE * BULB_R, BULB_COLORS[int(pt[2]) % BULB_COLORS.size()], 4, 2)
	g.kind = kind
	g.anim = anim


# --- Halos --------------------------------------------------------------------------------------

## Every halo of the park: [park-frame position, radius, colour (raw sRGB), strength, kind (0 a
## lamp: a hot core; 1 a lit front: a broad glow)].
static func halo_points(deck: float, far: bool = false) -> Array:
	var key := "halos_%.2f_%s" % [deck, far]
	var thin := FAR_THIN if far else 1
	var gain := FAR_GAIN if far else 1.0
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	for i in PierPark.LAMP_COUNT:
		var x := PierPark.LAMP_FROM - float(i) * PierPark.LAMP_STEP
		for zs: float in [-1.0, 1.0]:
			for xs: float in [-0.55, 0.55]:
				out.append([Vector3(x + xs, deck + 5.35, zs * PierPark.LAMP_Z), LAMP_HALO, Color(1.0, 0.86, 0.62), LAMP_GAIN, 0.0])
	# The strings between the lamps, every few bulbs (their sag as PierPark._strings() hangs them).
	var palette: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.4, 0.35), Color(0.45, 0.8, 1.0), Color(0.6, 1.0, 0.5), Color(1.0, 0.8, 0.3)]
	var spans: Array = []
	for i in range(2, PierPark.LAMP_COUNT):
		var x := PierPark.LAMP_FROM - float(i) * PierPark.LAMP_STEP
		spans.append([Vector3(x, deck + 5.0, -PierPark.LAMP_Z), Vector3(x - PierPark.LAMP_STEP * 0.5, deck + 5.0, PierPark.LAMP_Z)])
		spans.append([Vector3(x - PierPark.LAMP_STEP * 0.5, deck + 5.0, PierPark.LAMP_Z), Vector3(x - PierPark.LAMP_STEP, deck + 5.0, -PierPark.LAMP_Z)])
	spans.append([Vector3(-203.0, deck + 4.5, 16.0), Vector3(-203.0, deck + 4.5, 58.0)])
	for sp: Array in spans:
		var a: Vector3 = sp[0]
		var b: Vector3 = sp[1]
		var length := a.distance_to(b)
		var sag := length * 0.05
		var steps := int(length / 0.8)
		for k in range(1, steps):
			if k % (STRING_EVERY * thin) != 0:
				continue
			var t := float(k) / float(steps)
			var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t) + 0.08, 0)
			out.append([p, STRING_HALO, palette[k % palette.size()], STRING_GAIN * gain, 0.0])
	for pt: Array in coaster_points(deck):
		if int(pt[2]) % thin != 0:
			continue
		var p: Vector3 = pt[0]
		out.append([p, COASTER_HALO, BULB_COLORS[int(pt[2]) % BULB_COLORS.size()], COASTER_GAIN * gain, 0.0])
	for s: Array in PierPark.STANDS:
		var yaw := float(s[2])
		var face := Vector3(sin(yaw), 0.0, cos(yaw))
		out.append([Vector3(s[0], deck + 2.4, s[1]) + face * 1.6, FRONT_HALO, Color(1.0, 0.82, 0.55), FRONT_GAIN, 1.0])
	for bt: Array in PierPark.BOOTHS:
		out.append([Vector3(bt[0], deck + 2.4, PierPark.BOOTH_Z + 1.8), FRONT_HALO * 0.8, Color(1.0, 0.8, 0.5), FRONT_GAIN, 1.0])
	out.append([Vector3(PierPark.CAROUSEL_AT.x, deck + 5.6, PierPark.CAROUSEL_AT.y), CROWN_HALO, Color(1.0, 0.78, 0.45), CROWN_GAIN, 1.0])
	_cache[key] = out
	return out


static func halos(park: Node3D, deck: float, detailed: bool) -> MultiMeshInstance3D:
	var key := "halo_mm_near" if detailed else "halo_mm_far"
	if not _cache.has(key):
		var pts := halo_points(deck, not detailed)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = NightAtmos.halo_mesh()
		mm.instance_count = pts.size()
		for i in pts.size():
			var pt: Array = pts[i]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * float(pt[1])), pt[0]))
			mm.set_instance_color(i, pt[2])
			mm.set_instance_custom_data(i, Color(float(pt[3]), float(pt[4]), 0.0, 0.0))
		_cache[key] = mm
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PierHalos"
	mmi.multimesh = _cache[key]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	park.add_child(mmi)
	return mmi
