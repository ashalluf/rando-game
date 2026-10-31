class_name OceanCloseup
## The Pacific close up (shaders/ocean_closeup.gdshaderinc, included by ocean.gdshader; the piles'
## waterline, shaders/waterline_wet.gdshaderinc). Fragment-only detail faded out before the
## hand-over to the far sea: capillary ripples, wind streaks and gusts, sun glitter as separate
## flashing facets, light through the thin tops of the waves, the deep blue scatter looking down,
## the cloud base mirrored, foam that ages into lace and is torn down the wind, a foam line where a
## hull or a pile meets the water, and the piles darkened, weeded and wet where they stand in it.
##
## OCEAN_CLOSEUP=0 in the environment is the A/B: the `ocean_closeup` shader global goes to 0 (the
## water and the piles as they were) and the beach piers keep their old pile materials.
##
## apply(mat) is called by Weather when it pushes the coast to the ocean material.

## The most pile grids the shader takes (ocean_closeup.gdshaderinc PILE_GRIDS).
const MAX_GRIDS := 12


static func enabled() -> bool:
	return OS.get_environment("OCEAN_CLOSEUP") != "0"


## Sets the A/B global and hands the ocean material the piers' pile grids.
static func apply(mat: ShaderMaterial) -> void:
	RenderingServer.global_shader_parameter_set("ocean_closeup", 1.0 if enabled() else 0.0)
	WaterReview.apply()
	if mat == null:
		return
	var grids := pile_grids()
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for g: Array in grids:
		if a.size() >= MAX_GRIDS:
			break
		a.append(g[0])
		b.append(g[1])
	var n := a.size()
	while a.size() < MAX_GRIDS:
		a.append(Vector4.ZERO)
		b.append(Vector4.ZERO)
	mat.set_shader_parameter("pile_a", a)
	mat.set_shader_parameter("pile_b", b)
	mat.set_shader_parameter("pile_count", n)
	mat.set_shader_parameter("pier_wheel", wheel_hub())
	mat.set_shader_parameter("pier_deck", wheel_deck())


## The pier park's Ferris wheel for the ocean's night mirror (ocean_closeup.gdshaderinc
## oc_wheel_mirror()): the hub in TRUE world and the rim radius, from FerrisWheel / PierPark's own
## constants (PierPark.build() puts the wheel at anchor + WHEEL_AT on the deck). Zero when there is
## no pier.
static func wheel_hub() -> Vector4:
	for lm: Dictionary in Landmarks.all():
		if str(lm.id) == "pier":
			var at: Vector2 = lm.anchor
			return Vector4(at.x + PierPark.WHEEL_AT.x, PierPark.DECK_TOP + FerrisWheel.HUB_H,
				at.y + PierPark.WHEEL_AT.y, FerrisWheel.RADIUS)
	return Vector4.ZERO


## The piers' piles as grids in TRUE world XZ: [Vector4(first x, first z, step x, step z),
## Vector4(count x, count z, radius, 0)], worked out from the constants the piers are built with
## (PierPark._piles(), LandmarkBeachPiers._mh_piles() / _rd_piles(); the Redondo arc and the
## Manhattan head's ring are left out).
static func pile_grids() -> Array:
	var out: Array = []
	for lm: Dictionary in Landmarks.all():
		var at: Vector2 = lm.anchor
		match str(lm.id):
			"pier":
				for r: Rect2 in [PierPark.MAIN, PierPark.NORTH, PierPark.SOUTH]:
					var xs: Array[float] = []
					var x := r.end.x - 4.0
					while x > r.position.x + 1.0:
						xs.append(x)
						x -= 8.0
					var nz := 0
					var z := r.position.y + 2.0
					while z <= r.end.y - 1.9:
						nz += 1
						z += 6.0
					if xs.is_empty() or nz == 0:
						continue
					out.append([Vector4(at.x + xs[-1], at.y + r.position.y + 2.0, 8.0, 6.0), Vector4(xs.size(), nz, 0.4, 0.0)])
			"manhattan_pier":
				var straight := LandmarkBeachPiers.MH_LENGTH - LandmarkBeachPiers.MH_END_RADIUS
				var head_x := at.x - straight
				var xs: Array[float] = []
				var x := at.x - 5.0
				while x > head_x - LandmarkBeachPiers.MH_END_RADIUS * 0.5:
					xs.append(x)
					x -= LandmarkBeachPiers.MH_PILE_STEP
				if not xs.is_empty():
					var g := LandmarkBeachPiers.MH_PILE_GAUGE
					out.append([Vector4(xs[-1], at.y - g, LandmarkBeachPiers.MH_PILE_STEP, g * 2.0),
						Vector4(xs.size(), 2, LandmarkBeachPiers.MH_PILE_R, 0.0)])
			"redondo_pier":
				var steps := LandmarkBeachPiers.RD_STRAIGHT_STEPS
				var step := LandmarkBeachPiers.RD_STRAIGHT / float(steps)
				var x0 := at.x - LandmarkBeachPiers.RD_ROOT_X - LandmarkBeachPiers.RD_STRAIGHT
				var g := LandmarkBeachPiers.RD_PILE_GAUGE
				for leg: float in [-1.0, 1.0]:
					var zc := at.y + leg * LandmarkBeachPiers.RD_HALF_SPAN
					out.append([Vector4(x0, zc - g, step, g * 2.0), Vector4(steps + 1, 2, LandmarkBeachPiers.RD_PILE_R, 0.0)])
	return out


## The beach piers' pile material: its surface and its waterline (shaders/pile_wet.gdshader), one
## shared copy per look. `fallback` is what the pier used before (returned when OCEAN_CLOSEUP=0).
static func pile_material(base: Color, rough: float, timber: bool, fallback: Material) -> Material:
	if not enabled():
		return fallback
	var key := "%s|%.2f|%d" % [base.to_html(), rough, int(timber)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pile_wet.gdshader")
	# Plain uniform, written linear.
	var lin := base.srgb_to_linear()
	m.set_shader_parameter("base_color", Vector3(lin.r, lin.g, lin.b))
	m.set_shader_parameter("base_rough", rough)
	m.set_shader_parameter("timber", 1.0 if timber else 0.0)
	_mats[key] = m
	return m


static var _mats: Dictionary = {}


## The pier park's decks (PierPark.MAIN, NORTH, SOUTH) as one box in TRUE world (x0, z0, x1, z1):
## the night mirror draws no wheel under them.
static func wheel_deck() -> Vector4:
	for lm: Dictionary in Landmarks.all():
		if str(lm.id) == "pier":
			var at: Vector2 = lm.anchor
			var r := PierPark.MAIN.merge(PierPark.NORTH).merge(PierPark.SOUTH)
			return Vector4(at.x + r.position.x, at.y + r.position.y, at.x + r.end.x, at.y + r.end.y)
	return Vector4.ZERO
