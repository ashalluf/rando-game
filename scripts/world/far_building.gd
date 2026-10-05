class_name FarBuilding
extends RefCounted
## A Building as the far tiers draw it (owner, 2026-10-04: GAME_PLAN G7, "real impostors for the
## far city's towers instead of shaded boxes"): the LOD chunks' `lod_box` batch, which the far
## city (Skyline) captures as it is, so both far tiers draw exactly this.
##
## What a far building has to keep of the near one, measured against it rather than guessed:
## - its massing: every part as its own box - podium, setbacks, crown tiers - with the plinth
##   folded into the parts that stand on the ground (one instance a building fewer) and the
##   parapet's height on top of any part whose roof edge carries one, so the roofline is where
##   the near building's is;
## - its facade, cell for cell: the same window style, finish, storefront, storeys and bays
##   (Building.part_grid(), the one function both use), the same palette entries for the wall,
##   the glass tint and the lit colour, the roof covering, and after dark the same lit offices
##   (window_lights.gdshaderinc, rolled from integers by both shaders);
## - its roof plant: the very units Building puts on its roofs (Building.roof_plan(), on a
##   stream of its own), each as one box - every one in the LOD ring, only the ones that make a
##   silhouette (stair bulkheads, water tanks, cooling towers, billboards, spires and masts with
##   their beacons) in the far city, where the rest are under a pixel.
##
## Why boxes and not baked impostors: a far building is a box already - its silhouette IS its
## parts - and there are 22,000 facade parts in the far city alone, every one of them unique. An
## octahedral impostor set (8 x 8 views at 64 px) per building would be 63 GB of atlas and a
## fifteen-minute bake of every near building; a card set at 16 views of 32 px still 3.9 GB. The
## box with the near building's own data costs 12 triangles, no texture memory, lights under
## the real sun and dissolves per block like everything else in the tier. Impostors win where
## the source is detail a box cannot carry (trees, the landmark towers' crowns); those have
## their own far meshes (PropFactory.canopy_blob(), LandmarkDowntown).
##
## THE CODE. Compatibility hands a MultiMesh's INSTANCE_CUSTOM and COLOR over as half floats (11
## bits), far too few for a building's facade data, but its transform as full floats. A building
## part is an axis-aligned box, so its basis is diagonal and the six off-diagonal entries are
## free: each carries a 20-bit code as code * 2^-28 (exact in a float32: 20 significant bits
## times a power of two), and building_lod.gdshader rebuilds the box from the diagonal alone
## (skip_vertex_transform). The codes shear the box by at most 4 mm, so the MultiMesh's bounds,
## culling and every check that takes a box's AABB see the box. INSTANCE_CUSTOM.a PART_FLAG
## marks a coded part; anything else in the batch (houses, slabs, plates, decks) is drawn as a
## plain transform. Proven bit-exact on both renderers by a probe (docs/HANDOFF.md, the far city's
## buildings): 548 instances, six codes each, up to 2^20 - 1, under a node offset like Skyline's.

## The coded far boxes on (CityChunk's LOD path); off draws the old shaded boxes. FAR_CODED=0 in
## the environment starts the game with them off: the A/B for geo_count and the stills.
static var enabled: bool = OS.get_environment("FAR_CODED") != "0"
## Cut corners as geometry (GAME_PLAN G7, "cut-corner geometry on the far boxes"): a chamfered
## part (Building.part_grid()'s cut_x > 0) is drawn as three instances of the same unit box - its
## middle (the part's own entry, the box narrowed in x by one bay at each end) and two end pieces
## appended after everything else, each a trapezoid whose outer corners building_lod.gdshader
## pulls in by one bay - which together are exactly the near part's octagonal prism, with the
## true diagonal faces lit by the sun. Which piece is in INSTANCE_CUSTOM.r (PIECE_*); the cut
## sizes are the part's own bays, already in its code. No new mesh, batch or draw: +24 triangles
## a cut part. FAR_CORNERS=0 in the environment draws the old box with the piers painted on.
static var corners: bool = OS.get_environment("FAR_CORNERS") != "0"
## INSTANCE_CUSTOM.r of a coded part: the whole box, or one of a cut part's three pieces.
const PIECE_WHOLE := 0.0
const PIECE_MIDDLE := 1.0
const PIECE_PLUS_X := 2.0
const PIECE_MINUS_X := 3.0
## Codes ride in the off-diagonals as code * CODE_SCALE.
const CODE_SCALE := 1.0 / 268435456.0
## INSTANCE_CUSTOM.a of a coded part, and of a roof plant box (building_lod.gdshader).
const PART_FLAG := -1.0
const PLANT_FLAG := 4.0
## Roof plant kinds (INSTANCE_CUSTOM.r of a plant box): a solid unit, a mast drawn at least a
## pixel wide, a mast with an aviation beacon on its tip, glazing (skylights, solar arrays), a
## sign panel.
enum Plant { UNIT, MAST, BEACON_MAST, GLAZING, PANEL, HELIPAD, POOL }
## Plant the far city keeps (INSTANCE_CUSTOM.g 1): what still makes a silhouette past the LOD
## ring. The rest - air handlers, duct runs, solar arrays, skylights, vents - is under a pixel
## out there and stays in the LOD chunks only.
const SILHOUETTE := ["bulkhead", "water_tower", "cooling_tower", "billboard", "spire", "antenna"]
## Concrete of the plinth folded into the ground parts (what the LOD plinth box was drawn in).
const PLINTH_COLOR := Color(0.66, 0.66, 0.66)
## The wall texture sets, in the order the code numbers them (keys of Building.WALL_TEXTURE_MEAN;
## building_lod.gdshader's wall_tex_mean() lists their means in the same order).
const WALL_SETS := ["brick_red", "brick_mossy", "brick_factory", "brick", "plaster_painted", "plaster_beige",
	"plaster_white", "concrete_painted", "concrete_cracked", "concrete_layers", "concrete", "metal",
	"metal_corrugated", "metal_factory"]
## Bounds of the integer fields (their bit widths below), checked by the smoke test.
const MAX_COLS := 127
const MAX_ROWS := 127


## The far boxes of `building` (planned: plan_only() has run; `style` is what it returned), in
## the building's own space: [[Transform3D, Color, Color custom], ...] - its parts, then its roof
## plant. `plinth` is how far its plinth reaches below its base (Building.plinth_depth), folded
## into the parts on the ground. The caller places them (CityChunk adds the lot's relief).
static func boxes(building: Building, style: Dictionary, plinth: float) -> Array:
	var out: Array = []
	var seed1000 := building.seed % 1000
	var lit_idx := maxi(Building.LIT_COLORS.find(style.lit), 0)
	var tint_idx := maxi(Building.WINDOW_TINTS.find(style.tint), 0)
	var spans := building._shop_spans()
	var crown_up := building.crown_shade() > 1.0
	var weather := clampi(roundi(float(style.weathering) * 31.0), 0, 31)
	var lit_q := clampi(roundi(float(style.lit_ratio) * 65535.0), 0, 65535)
	var tall := building.height > 30.0
	var paints: Array = Building.FRAME_PAINTS.get(building.finish, Building.FRAME_PAINTS[Building.Finish.FLAT])
	var frame_idx := maxi(paints.find(building.frame_paint()), 0)
	var wall_set: Array = style.get("wall_set", [])
	var wall_idx := WALL_SETS.find(wall_set[0]) if wall_set.size() == 2 else -1
	# 15: no set (the shader's untextured wall).
	if wall_idx < 0:
		wall_idx = 15
	var bseed := float(building.seed % 997) / 997.0
	var rises: Array[float] = []
	# A cut part's two end pieces (see `corners`), appended after the plant so part i stays box i.
	var ends: Array = []
	for part: Dictionary in building.parts:
		var size: Vector3 = part.size
		var c: Vector3 = part.center
		var grid := building.part_grid(part, style)
		var bottom := c.y - size.y * 0.5
		var ext := plinth if bool(grid.on_ground) and plinth > 0.05 else 0.0
		var rise := building.parapet_rise(part)
		rises.append(rise)
		var a := seed1000 | (int(building.finish) << 10) | (int(building.window_style) << 12) \
			| (building.roof_style << 14) | (lit_idx << 16) | ((1 if building.shape == Building.Shape.WAREHOUSE else 0) << 18) \
			| ((1 if crown_up else 0) << 19)
		var b := tint_idx | (weather << 3)
		for f in 4:
			b |= (int(spans[f]) - 2) << (8 + 2 * f)
		b |= (1 if float(grid.storefront) > 0.0 else 0) << 16
		b |= (1 if bool(grid.parking) else 0) << 17
		b |= (1 if float(grid.cut_x) > 0.0 else 0) << 18
		b |= (1 if float(grid.crown) >= 0.0 else 0) << 19
		var cc := lit_q | ((1 if tall else 0) << 16) | (frame_idx << 17)
		var d := mini(int(grid.cols_x), MAX_COLS) | (mini(int(grid.cols_z), MAX_COLS) << 7) | (wall_idx << 14)
		var e := mini(int(grid.rows), MAX_ROWS) | (clampi(roundi(float(grid.base_h) * 10.0), 0, 255) << 7)
		var f2 := clampi(roundi(ext * 100.0), 0, 2047) | (clampi(roundi(rise * 100.0), 0, 127) << 11)
		# The box: the part, down over the plinth and up over the parapet.
		var box := Vector3(size.x, size.y + ext + rise, size.z)
		var centre := Vector3(c.x, bottom - ext + box.y * 0.5, c.z)
		var colour: Color = building.part_lod_color(part)
		var xf := Transform3D(encode(box, [a, b, cc, d, e, f2]), centre)
		var cut := corners and float(grid.cut_x) > 0.0
		out.append([xf, Color(colour.r, colour.g, colour.b, 1.0), Color(PIECE_MIDDLE if cut else PIECE_WHOLE, 0.0, bseed, PART_FLAG)])
		if cut:
			for piece: float in [PIECE_PLUS_X, PIECE_MINUS_X]:
				ends.append([xf, Color(colour.r, colour.g, colour.b, 1.0), Color(piece, 0.0, bseed, PART_FLAG)])
	var plant_props := building.roof_plan()
	# The small plant a rooftop piece stands in place of (Rooftops.hidden(), as the near one).
	var roof_pieces := Rooftops.plan(building)
	var covered := Rooftops.hidden(building, roof_pieces)
	for pi in plant_props.size():
		if covered.has(pi):
			continue
		var prop: Array = plant_props[pi]
		var rise: float = rises[int(prop[3])] if int(prop[3]) >= 0 and int(prop[3]) < rises.size() else 0.0
		for pb: Array in plant(prop, building.height):
			var xf: Transform3D = pb[0]
			xf.origin.y += rise
			out.append([xf, pb[1], pb[2]])
	# The rooftop pieces (Rooftops: helipads, pool decks, penthouses, masts), planned from the
	# plant roof_plan() just laid, as the near building plans them.
	out.append_array(Rooftops.far_boxes(building, roof_pieces))
	out.append_array(ends)
	return out


## The footprint a cut part's three pieces draw (building_lod.gdshader's vertex reshape, in the
## box's unit space, -0.5..0.5): the octagon, counter-clockwise from the +x face. For the checks.
static func cut_outline(cols_x: int, cols_z: int) -> PackedVector2Array:
	var cx := 1.0 / float(maxi(cols_x, 1))
	var cz := 1.0 / float(maxi(cols_z, 1))
	return PackedVector2Array([Vector2(0.5, -(0.5 - cz)), Vector2(0.5, 0.5 - cz), Vector2(0.5 - cx, 0.5), Vector2(-(0.5 - cx), 0.5),
		Vector2(-0.5, 0.5 - cz), Vector2(-0.5, -(0.5 - cz)), Vector2(-(0.5 - cx), -0.5), Vector2(0.5 - cx, -0.5)])


## One roof prop as its far box or boxes: [[Transform3D (building space), Color, Color custom]].
## Sizes are the near prop's envelope (Building._build_prop()); `at` is its foot on the roof.
static func plant(prop: Array, building_height: float) -> Array:
	var kind: String = prop[0]
	var at: Vector3 = prop[1]
	var rolls: Dictionary = prop[2]
	var big := 1.0 if SILHOUETTE.has(kind) else 0.0
	var out: Array = []
	match kind:
		"ac":
			var rusted: bool = rolls.get("rusted", false)
			_unit(out, at, big, Vector3(1.4, 1.5, 1.4), Vector3(0.0, 0.85, 0.0), Color(0.52, 0.45, 0.38) if rusted else Color(0.74, 0.74, 0.72), Plant.UNIT, float(rolls.get("yaw", 0.0)))
		"vents":
			_unit(out, at, big, Vector3(7.0, 0.7, 0.9), Vector3(0.0, 0.35, 0.0), Color(0.62, 0.63, 0.64))
		"ducts":
			var yaw: float = rolls.get("yaw", 0.0)
			# The run lies along (cos, sin) of its heading in x / z, from -3.6 to +3.8 m.
			_unit(out, at, big, Vector3(7.4, 1.15, 0.62), Vector3(cos(yaw), 0.0, sin(yaw)) * 0.1 + Vector3(0.0, 0.58, 0.0), Color(0.63, 0.64, 0.66), Plant.UNIT, -yaw)
		"solar":
			_unit(out, at, big, Vector3(5.3, 0.5, 3.2), Vector3(0.0, 0.45, 0.0), Color(0.07, 0.09, 0.16), Plant.GLAZING)
		"skylight":
			_unit(out, at, big, Vector3(2.4, 0.48, 2.4), Vector3(0.0, 0.24, 0.0), Color(0.60, 0.68, 0.72), Plant.GLAZING)
		"cooling_tower":
			_unit(out, at, big, Vector3(2.5, 2.1, 2.5), Vector3(0.0, 1.05, 0.0), Color(0.58, 0.59, 0.60))
		"bulkhead":
			_unit(out, at, big, Vector3(3.2, 2.6, 3.2), Vector3(0.0, 1.3, 0.0), Color(0.55, 0.55, 0.53))
		"water_tower":
			# The tank on its stand; the legs are four 12 cm posts, under a pixel past the FULL ring.
			_unit(out, at, big, Vector3(3.1, 3.6, 3.1), Vector3(0.0, 4.7, 0.0), Color(0.46, 0.34, 0.22))
		"spire":
			var h: float = rolls.get("h", 0.2 * maxf(building_height, 60.0))
			_unit(out, at, big, Vector3(2.2, 3.0, 2.2), Vector3(0.0, 1.5, 0.0), Color(0.70, 0.70, 0.74))
			_unit(out, at, big, Vector3(0.6, h + 0.6, 0.6), Vector3(0.0, 3.0 + (h + 0.6) * 0.5, 0.0), Color(0.80, 0.80, 0.84), Plant.BEACON_MAST)
		"antenna":
			var h: float = rolls.get("h", 10.0)
			_unit(out, at, big, Vector3(0.16, h + 0.25, 0.16), Vector3(0.0, (h + 0.25) * 0.5, 0.0), Color(0.75, 0.75, 0.78), Plant.BEACON_MAST)
		"billboard":
			var yaw: float = rolls.get("yaw", 0.0)
			var paint: Color = rolls.get("color", Color(0.8, 0.76, 0.68))
			if Billboards.enabled:
				# The poster Billboards builds there: its face in the ad's colour, lit at night.
				var ad: int = rolls.get("ad", 0)
				_unit(out, at, big, Vector3(Billboards.POSTER.x, Billboards.POSTER.y, 0.6), Basis(Vector3.UP, yaw) * Vector3(0.0, Billboards.LEG_POSTER + Billboards.POSTER.y * 0.5, -0.3),
					Billboards.far_color(Billboards.Fmt.POSTER, ad), Plant.PANEL, yaw)
				out.back()[2] = Color(float(Plant.PANEL), big, 1.0, PLANT_FLAG)
			else:
				_unit(out, at, big, Vector3(6.0, 3.0, 0.24), Basis(Vector3.UP, yaw) * Vector3(0.0, 4.0, 0.0), paint, Plant.PANEL, yaw)
	return out


## One plant box into `out`: `size`, its centre `centre` from the prop's foot `at`, turned `yaw`.
static func _unit(out: Array, at: Vector3, big: float, size: Vector3, centre: Vector3, colour: Color, plant_kind: int = Plant.UNIT, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled_local(size) if yaw != 0.0 else Basis.from_scale(size)
	out.append([Transform3D(basis, at + centre), colour, Color(float(plant_kind), big, 0.0, PLANT_FLAG)])


## A diagonal basis of `size` carrying six 20-bit codes in its off-diagonals.
static func encode(size: Vector3, codes: Array) -> Basis:
	var q := CODE_SCALE
	return Basis(Vector3(size.x, float(codes[0]) * q, float(codes[1]) * q),
		Vector3(float(codes[2]) * q, size.y, float(codes[3]) * q),
		Vector3(float(codes[4]) * q, float(codes[5]) * q, size.z))


## The six codes of a coded basis (encode()'s inverse; building_lod.gdshader reads them the same
## way: column 0 rows 1-2, column 1 rows 0 and 2, column 2 rows 0-1).
static func codes(b: Basis) -> PackedInt32Array:
	var k := 1.0 / CODE_SCALE
	return PackedInt32Array([roundi(b.x.y * k), roundi(b.x.z * k), roundi(b.y.x * k), roundi(b.y.z * k), roundi(b.z.x * k), roundi(b.z.y * k)])


## A coded part's fields, decoded the way the shader decodes them (for the checks).
static func decode(b: Basis) -> Dictionary:
	var c := codes(b)
	var spans := []
	for f in 4:
		spans.append(2 + ((c[1] >> (8 + 2 * f)) & 3))
	return {
		"size": Vector3(b.x.x, b.y.y, b.z.z),
		"seed": c[0] & 1023, "finish": (c[0] >> 10) & 3, "window_style": (c[0] >> 12) & 3,
		"roof_style": (c[0] >> 14) & 3, "lit": (c[0] >> 16) & 3, "warehouse": (c[0] >> 18) & 1, "crown_up": (c[0] >> 19) & 1,
		"tint": c[1] & 7, "weathering": float((c[1] >> 3) & 31) / 31.0, "spans": spans,
		"storefront": (c[1] >> 16) & 1, "parking": (c[1] >> 17) & 1, "chamfer": (c[1] >> 18) & 1, "crown": (c[1] >> 19) & 1,
		"lit_ratio": float(c[2] & 65535) / 65535.0, "tall": (c[2] >> 16) & 1, "frame": (c[2] >> 17) & 7,
		"cols_x": c[3] & 127, "cols_z": (c[3] >> 7) & 127, "wall_set": (c[3] >> 14) & 15, "rows": c[4] & 127, "base_h": float((c[4] >> 7) & 255) / 10.0,
		"ext": float(c[5] & 2047) / 100.0, "rise": float((c[5] >> 11) & 127) / 100.0,
	}


## The far city keeps a lod_box instance unless it is roof plant under a pixel out there.
static func far_keeps(custom: Color) -> bool:
	return not (is_equal_approx(custom.a, PLANT_FLAG) and custom.g < 0.5)
