class_name Skyline
extends Node3D
## The city seen from miles away (owner, 2026-09-22: "how come i cant see far away stuff? ...
## the closer i go an entire city appears. it should look the way things do in real life").
##
## Before this there were two tiers and then nothing: FULL chunks to about two blocks, LOD boxes
## to seven, and beyond roughly 700 m the world was bare shaded ground. So the city had an edge,
## and walking toward it made a city materialise. A real skyline is visible from the far side of
## the basin.
##
## This is the coarse tier that fills that gap, the way an open-world game's furthest LOD does:
## one MultiMesh per TILE of `TILE_BLOCKS` x `TILE_BLOCKS` city blocks, a handful of boxes per
## block, no roads, no props, no collision, no per-building nodes. A tile is ONE draw call, so
## three kilometres of city costs about a hundred draws instead of the thousands the LOD tier
## would need.
##
## It deliberately does NOT try to reproduce the exact buildings the LOD tier builds. It cannot:
## `CityChunk` derives its lots from a single stateful rng threaded through the whole chunk build
## (palm roll, jacaranda roll, paving roll, then _build_lots), so matching it from outside would
## mean replaying every earlier call and would break the moment anything is inserted. Instead the
## massing is drawn from the same DISTRICT height band and the same skyline_boost, hashed per
## cell, so the silhouette is right even though individual buildings are not the same ones.
## Nothing ever sees both: each tile only draws BEYOND `draw_from` metres, which is where the LOD
## chunks stop, and Godot dithers it in over `fade_margin`.

## Blocks per tile edge. Bigger means fewer draw calls and coarser culling granularity.
const TILE_BLOCKS := 6
## Vegetation clumps on a hill block at full cover, falling to zero at the rock line.
const HILL_CLUMPS := 10
## Below this the tile is not drawn at all - the LOD chunks own that ground. Set from
## CityStreamer so the two always meet.
var draw_from: float = 700.0
## Distance over which the tile dithers in, so it does not appear in one frame.
var fade_margin: float = 120.0

var _plan: CityPlan
var _tiles: Dictionary = {}
## shaders/far_canopy.gdshader, sharing the ground follower's height uniforms (CityStreamer sets
## both). The hill planting draws with it, in its own MultiMesh per tile, because it has to stand
## on the ground the far plane actually draws rather than on MacroMap.height_at() - see the shader.
var _canopy: ShaderMaterial


func setup(plan: CityPlan, from: float, margin: float, canopy: ShaderMaterial = null) -> void:
	_plan = plan
	_canopy = canopy
	draw_from = from
	fade_margin = margin
	# Tile instances are placed at TRUE world coordinates, exactly like a CityChunk's children,
	# so this node carries the origin shift for all of them. CityStreamer.recenter() moves every
	# direct Node3D child of the scene root, which keeps this at -world_offset from here on.
	position = -WorldState.world_offset


func has_tile(t: Vector2i) -> bool:
	return _tiles.has(t)


func tile_count() -> int:
	return _tiles.size()


## Frees every tile outside `keep` tiles of `center`.
func trim(center: Vector2i, keep: int) -> void:
	for t in _tiles.keys():
		if maxi(absi(t.x - center.x), absi(t.y - center.y)) > keep:
			var node = _tiles[t]
			if node != null:
				(node as Node).queue_free()
			_tiles.erase(t)


## Builds one tile. Returns false if it held no city at all, which is most of the map - ocean,
## hills and the basin's empty ground all produce nothing and cost one block scan.
func build_tile(t: Vector2i) -> bool:
	if _tiles.has(t) or _plan == null:
		return false
	var macro: MacroMap = _plan.macro
	var xforms: Array[Transform3D] = []
	var colors: PackedColorArray = PackedColorArray()
	var customs: PackedColorArray = PackedColorArray()
	var veg: Array[Transform3D] = []
	var veg_colors: PackedColorArray = PackedColorArray()
	for bx in TILE_BLOCKS:
		for bz in TILE_BLOCKS:
			var ix := t.x * TILE_BLOCKS + bx
			var iz := t.y * TILE_BLOCKS + bz
			_add_block(ix, iz, macro, xforms, colors, customs, veg, veg_colors)
	if xforms.is_empty() and veg.is_empty():
		# Remember the emptiness too, or an ocean tile is rescanned every single update. Stored
		# as a plain marker rather than a node: most of the map is water, hills and empty basin,
		# and an empty Node3D each would be thousands of nodes for nothing.
		_tiles[t] = null
		return false
	var node := _tile_node(t, xforms, colors, customs)
	var planting := _planting_node(t, veg, veg_colors)
	if node == null:
		node = planting
	elif planting != null:
		node.add_child(planting)
	add_child(node)
	_tiles[t] = node
	return true


## The tile's buildings, plates, containers and houses: one MultiMesh on the LOD box shader.
func _tile_node(t: Vector2i, xforms: Array[Transform3D], colors: PackedColorArray, customs: PackedColorArray) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = PropFactory.unit_box()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Sky_%d_%d" % [t.x, t.y]
	node.multimesh = mm
	# The same shader the LOD boxes use, so the far skyline carries the facade typology and the
	# glazing response rather than reading as flat grey slabs.
	node.material_override = PropFactory.building_lod_material()
	# Never casts: it is kilometres away, well past any shadow cascade, and it would only cost
	# cascade fill.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# This is what stops the coarse tier ever being seen next to the real one: it only draws
	# once the camera is further away than the LOD chunks reach.
	node.visibility_range_begin = draw_from
	node.visibility_range_begin_margin = fade_margin
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return node


## The tile's hill planting and hill houses, on the canopy shader, which seats every one of them
## on the far ground. One more draw per hill tile; the city tiles have none.
func _planting_node(t: Vector2i, veg: Array[Transform3D], veg_colors: PackedColorArray) -> MultiMeshInstance3D:
	if veg.is_empty() or _canopy == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PropFactory.unit_box()
	mm.instance_count = veg.size()
	for i in veg.size():
		mm.set_instance_transform(i, veg[i])
		mm.set_instance_color(i, veg_colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Planting_%d_%d" % [t.x, t.y]
	node.multimesh = mm
	node.material_override = _canopy
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves every clump by up to tens of metres, so the MultiMesh's own bounds (built
	# from the CPU positions) can be off by that much; pad them rather than have a clump culled
	# while it is still on screen.
	node.extra_cull_margin = 120.0
	node.visibility_range_begin = draw_from
	node.visibility_range_begin_margin = fade_margin
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return node


func _add_block(ix: int, iz: int, macro: MacroMap, xforms: Array[Transform3D], colors: PackedColorArray, customs: PackedColorArray,
		veg: Array[Transform3D], veg_colors: PackedColorArray) -> void:
	var b := _plan.block(ix, iz)
	var rect: Rect2 = b.rect
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	var center: Vector2 = rect.get_center()
	var zone: int = macro.zone_at(center) if macro else MacroMap.Zone.CITY
	if zone == MacroMap.Zone.OCEAN:
		return
	var ground_here: float = macro.height_at(center) if macro else 0.0
	# Everything that is NOT plain city blocks gets handled first. Measured over the basin from
	# an aerial camera, the far tier was drawing 17.6% of the blocks in view, and the single
	# biggest hole was the HILLS at 44.8% of the area - which carry roads and mansions up close
	# and drew as bare ground from the air. That gap IS the "closer i go, more stuff appears".
	if zone != MacroMap.Zone.CITY:
		_add_wild(zone, rect, center, ground_here, macro, xforms, colors, customs, veg, veg_colors)
		return
	# Parks and plazas carry no buildings, but they are still GROUND - grass and paving, not
	# bare dirt. Skipping them entirely left holes in the middle of the far city.
	if b.kind == CityPlan.BlockKind.PARK or b.kind == CityPlan.BlockKind.PLAZA:
		xforms.append(Transform3D(
			Basis().scaled(Vector3(rect.size.x, 0.4, rect.size.y)),
			Vector3(center.x, ground_here + 0.2, center.y)))
		colors.append(Color(0.24, 0.32, 0.20) if b.kind == CityPlan.BlockKind.PARK else Color(0.44, 0.44, 0.43))
		customs.append(Color(0.0, 0.0, 0.0, 1.0))
		return
	var boost: float = macro.skyline_boost(center) if macro else 0.0
	var ground: float = ground_here
	# A flat plate over the whole block first. From the air most of a city is not building - it
	# is roof, yard, car park and service ground BETWEEN the buildings, and without it the bare
	# macro ground showed through every gap.
	xforms.append(Transform3D(
		Basis().scaled(Vector3(rect.size.x, 0.4, rect.size.y)),
		Vector3(center.x, ground + 0.2, center.y)))
	colors.append(_ground_plate(b.district))
	customs.append(Color(0.0, 0.0, 0.0, 1.0))
	# THE REAL BUILDINGS. Same lots, same massing height, same seeds as the detailed city builds
	# from - so approaching the skyline resolves it into detail instead of replacing it with a
	# different city. This is what "the skyline is fake and fades away" meant: the far tier used
	# to invent its own massing because it could not see these.
	for lot in _plan.lots(ix, iz):
		var lot_size: Vector2 = lot.size
		var lot_centre: Vector2 = lot.center
		var hs: int = int(lot.seed)
		var h: float = _plan.lot_height(hs, b.district, boost)
		xforms.append(Transform3D(
			Basis().scaled(Vector3(lot_size.x, h, lot_size.y)),
			Vector3(lot_centre.x, ground + h * 0.5, lot_centre.y)))
		colors.append(_facade(hs))
		# (window style / 4, lit ratio, seed, plain flag) - what building_lod.gdshader reads.
		customs.append(Color(float(absi(hash([hs, "w"])) % 4) / 4.0, 0.0,
			float(absi(hs) % 997) / 997.0, 0.0))


## The ground a block sits on, seen from above: asphalt and concrete, darker downtown where the
## streets are in shadow most of the day and there is more of them.
func _ground_plate(district: int) -> Color:
	match district:
		CityPlan.District.DOWNTOWN:
			return Color(0.30, 0.305, 0.325)
		CityPlan.District.INDUSTRIAL:
			return Color(0.38, 0.375, 0.365)
		CityPlan.District.CAMPUS:
			return Color(0.33, 0.375, 0.315)
		CityPlan.District.SUBURBS:
			return Color(0.34, 0.375, 0.315)
		_:
			return Color(0.345, 0.35, 0.355)


## Facade colour by the same logic the LOD tier uses: the palette IS the typology signal, so a
## far skyline has to carry the same spread of glass, brick, panel and flat or it reads as one
## material.
func _facade(hs: int) -> Color:
	var r := absi(hash([hs, "c"])) % 100
	var v := float(absi(hash([hs, "v"])) % 1000) / 1000.0
	if r < 34:
		return Color(0.20, 0.24, 0.30).lerp(Color(0.34, 0.42, 0.50), v)      # glass
	if r < 58:
		return Color(0.46, 0.30, 0.24).lerp(Color(0.62, 0.44, 0.34), v)      # brick
	if r < 82:
		return Color(0.48, 0.48, 0.50).lerp(Color(0.68, 0.68, 0.70), v)      # panel
	return Color(0.72, 0.70, 0.66).lerp(0.92 * Color(1.0, 0.99, 0.96), v)    # flat


## The basin is mostly NOT city blocks, and from the air all of it is inhabited or textured.
## Hills carry the mansions HillRoads already places, the port has its yards, the airport its
## aprons, and a beach town its low buildings. Each is a handful of instances in the same
## MultiMesh, so none of it adds a draw call.
func _add_wild(zone: int, rect: Rect2, center: Vector2, ground: float, macro: MacroMap,
		xforms: Array[Transform3D], colors: PackedColorArray, customs: PackedColorArray,
		veg: Array[Transform3D], veg_colors: PackedColorArray) -> void:
	match zone:
		MacroMap.Zone.HILLS:
			# Vegetation first, and it is the bulk of it. The hills are 45% of an aerial and the
			# mansions alone left them nearly bare, because HillRoads only places houses along
			# its roads. A real hillside at two kilometres is chaparral and tree cover with
			# houses threaded through it, and the cover is what stops it reading as bare dirt.
			#
			# Density falls with elevation the way the planting actually does - scrub on the
			# lower slopes, thinning through the tree line, bare rock on the tops - which is
			# both what it should look like and cheaper than blanketing every peak.
			var elev: float = ground
			var cover: float = clampf(1.0 - (elev - 60.0) / 520.0, 0.0, 1.0)
			var clumps: int = int(round(cover * float(HILL_CLUMPS)))
			for i in clumps:
				var hs := hash([_plan.seed, "veg", int(center.x), int(center.y), i])
				var p := _spot(rect, hs)
				# Only a first guess at the height: far_canopy.gdshader moves the clump onto the
				# ground the far plane really draws here, which on a ridge is tens of metres
				# lower than height_at(). At the real height, every clump along a skyline ridge
				# hung in the air above it.
				var gy: float = macro.height_at(p) if macro else ground
				# Wide and low: a canopy clump, not a post. At this distance the silhouette is
				# all that survives, and a tall thin box reads as a pole.
				var r: float = 7.0 + float(absi(hash([hs, "r"])) % 9)
				var th: float = 4.0 + float(absi(hash([hs, "t"])) % 6)
				veg.append(Transform3D(
					Basis(Vector3.UP, float(absi(hs) % 628) * 0.01).scaled(Vector3(r, th, r * 0.85)),
					Vector3(p.x, gy + th * 0.45, p.y)))
				veg_colors.append(_scrub(hs, cover))
			# The houses that are actually up there. No plate: a hillside is landscape, and a
			# flat slab laid over a slope would cut into it.
			if macro == null or macro.hill_roads == null:
				return
			for m in macro.hill_roads.mansions_in(rect):
				var pos: Vector2 = m.pos
				# `height` on a mansion lot is the ROAD DECK ELEVATION the pad was cut at -
				# metres above sea level, 400+ up here - NOT a building size. Reading it as one
				# stood a four-hundred-metre white spike on every lot and turned the range into
				# a bed of nails. The house gets its own storey count; `height` places it.
				# The ACTUAL ground, not the road deck height: height_at() already includes the
				# pad carved for this lot, and using the deck elevation instead left houses
				# floating above hillsides wherever the two differ. Even that is only a first
				# guess out here, for the same reason as the planting: the drawn far ground is
				# not height_at(), and at it the houses stood in the sky over the ridges. So they
				# go in with the planting and far_canopy.gdshader seats them.
				var pad_y: float = macro.height_at(pos)
				var h: float = 6.0 + float(absi(hash([m.seed, "h"])) % 6)
				var w: float = 16.0 + float(absi(hash([m.seed, "w"])) % 10)
				var d: float = 12.0 + float(absi(hash([m.seed, "d"])) % 9)
				veg.append(Transform3D(
					Basis(Vector3.UP, float(m.yaw)).scaled(Vector3(w, h, d)),
					Vector3(pos.x, pad_y + h * 0.5, pos.y)))
				veg_colors.append(Color(0.70, 0.67, 0.62).lerp(Color(0.84, 0.82, 0.78),
					float(absi(hash([m.seed, "c"])) % 1000) / 1000.0))
		MacroMap.Zone.PORT:
			# Yard, then stacks of containers on it.
			_plate(rect, center, ground, Color(0.34, 0.335, 0.33), xforms, colors, customs)
			# A container yard is PACKED - that is what a port looks like from the air, and 14
			# stacks on a block left the harbour reading as a blank concrete slab in the middle
			# of the city, which is the emptiest thing in the whole aerial.
			for i in 55:
				var hs := hash([_plan.seed, "port", int(center.x), int(center.y), i])
				var p := _spot(rect, hs)
				var h: float = 5.0 + float(absi(hash([hs, "h"])) % 8)
				xforms.append(Transform3D(Basis().scaled(Vector3(12.0, h, 5.0)),
					Vector3(p.x, ground + h * 0.5, p.y)))
				colors.append(_container(hs))
				customs.append(Color(0.0, 0.0, 0.0, 1.0))
		MacroMap.Zone.AIRPORT:
			# Apron, plus the odd hangar. Mostly it should read as a huge flat pale surface,
			# which is exactly what an airport looks like from above.
			_plate(rect, center, ground, Color(0.50, 0.50, 0.49), xforms, colors, customs)
			for i in 5:
				var hs := hash([_plan.seed, "apt", int(center.x), int(center.y), i])
				if absi(hs) % 100 < 45:
					continue
				var p := _spot(rect, hs)
				xforms.append(Transform3D(Basis().scaled(Vector3(46.0, 14.0, 34.0)),
					Vector3(p.x, ground + 7.0, p.y)))
				colors.append(Color(0.78, 0.79, 0.80))
				customs.append(Color(0.0, 0.0, 0.0, 1.0))
		MacroMap.Zone.BEACH:
			# Sand reads on its own; the beach towns are what is missing from the air.
			for i in 5:
				var hs := hash([_plan.seed, "bch", int(center.x), int(center.y), i])
				if absi(hs) % 100 < 45:
					continue
				var p := _spot(rect, hs)
				var h: float = 6.0 + float(absi(hash([hs, "h"])) % 7)
				xforms.append(Transform3D(Basis().scaled(Vector3(14.0, h, 12.0)),
					Vector3(p.x, ground + h * 0.5, p.y)))
				colors.append(Color(0.86, 0.84, 0.80))
				customs.append(Color(0.25, 0.0, float(absi(hs) % 997) / 997.0, 0.0))


func _plate(rect: Rect2, center: Vector2, ground: float, col: Color,
		xforms: Array[Transform3D], colors: PackedColorArray, customs: PackedColorArray) -> void:
	xforms.append(Transform3D(
		Basis().scaled(Vector3(rect.size.x, 0.4, rect.size.y)),
		Vector3(center.x, ground + 0.2, center.y)))
	colors.append(col)
	customs.append(Color(0.0, 0.0, 0.0, 1.0))


func _spot(rect: Rect2, hs: int) -> Vector2:
	return rect.position + Vector2(
		rect.size.x * float(absi(hash([hs, "x"])) % 1000) / 1000.0,
		rect.size.y * float(absi(hash([hs, "z"])) % 1000) / 1000.0)


## Hill planting, matching the bands the terrain and macro-ground shaders already use: olive
## chaparral low down, greyer sage as it dries out with height, so the far hills do not read as
## one flat green.
func _scrub(hs: int, cover: float) -> Color:
	var v: float = float(absi(hash([hs, "v"])) % 1000) / 1000.0
	var lush := Color(0.155, 0.205, 0.105).lerp(Color(0.225, 0.255, 0.130), v)
	var dry := Color(0.235, 0.230, 0.145).lerp(Color(0.285, 0.275, 0.185), v)
	return dry.lerp(lush, clampf(cover, 0.0, 1.0))


func _container(hs: int) -> Color:
	var pal := [Color(0.42, 0.20, 0.17), Color(0.17, 0.28, 0.40), Color(0.28, 0.36, 0.22),
		Color(0.55, 0.45, 0.16), Color(0.40, 0.40, 0.42)]
	return pal[absi(hash([hs, "p"])) % pal.size()]
