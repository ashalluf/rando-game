class_name FridayLights
extends RefCounted
## A high school stadium on a game night (wave 8 refcam5 "friday_lights", docs/HANDOFF.md "Friday
## night lights"). Schools builds the stadium's kit (Schools._track_kit: goal posts, scoreboard,
## six light standards whose lenses glow on a game night) and hands each lit standard and the
## stadium itself here (hook lines in schools.gd); what this adds:
##
## - LIGHT: each lit standard throws a real SpotLight3D down onto the field (Forward+ and
##   Compatibility; never the web or below MEDIUM, where DayNight's lamp_scale is 0), so the turf,
##   the track, the players, the stands and the posts are lit the way a stadium is, not by six
##   additive pools. The energy follows DayNight.lamp_now on a slow tick (FridayRig).
## - GLARE: a bloom over each standard's bank of lenses (StadiumNight's stadium_bank_glow shader:
##   a hot core and a soft skirt, turned to the camera), which is what reads as "the lights are on"
##   from the car park.
## - PLAYERS: two teams lined up at a line of scrimmage, the benches on each sideline and three
##   officials - crowd rigs posed once and baked (BeachFigure / CampFigure's way) in the school's
##   colour or white, merged into one BeachFigureMesh. Adults only (the crowd has no child rigs).
## - THE HOME STANDS: people sitting on the bleacher rows (BonfireFigure's clothed bakes in the
##   beach chair pose on the foot boards), a few standing.
## - THE CAR PARK: a school car park that straddles a chunk border was plain asphalt (Schools
##   built the lot only where one chunk held all of it): the chunk owning its centre now lays the
##   whole lot, full on a game night (car_park()).
##
## Every roll is a hash of the seed and the school's cell; nothing Schools rolls moves.
## RC5_FRIDAY_LIGHTS=0 is the A/B (the stadium exactly as before).

## Spotlight energy at full lamp level, its range and cone (degrees), and how much of it the
## volumetric fog takes (Forward+ HIGH: the haze over the field).
const SPOT_ENERGY := 9.0
const SPOT_RANGE := 150.0
const SPOT_ANGLE := 58.0
const SPOT_ATTENUATION := 0.7
const SPOT_FOG := 0.35
## LED sports lighting, a cool white (linear).
const TINT := Color(1.0, 0.97, 0.92)
## The bloom over a bank of lenses: its size (m) and the smallest it is drawn (radians of view).
const BLOOM_SIZE := 9.0
## How far the figures are drawn (m) and where their shadows stop.
const FIGURE_DRAW := 320.0
const FIGURE_SHADOW := 60.0
## The rigs players and officials wear the uniform on (trousers, short hair: PoliceOfficer's).
const PLAYER_MODELS := [0, 3, 7]
## The rigs and look salts of the home crowd (the bonfire's clothed people).
const FAN_MODELS := [0, 3, 4, 7, 12, 13, 14, 16]
const FAN_SALTS := [7, 11]
## How full the home stands are, the seat pitch along a row (m) and the share standing.
const FAN_FILL := 0.55
const FAN_PITCH := 0.62
const FAN_STAND := 0.12
## How full the car park is on a game night.
const LOT_FILL := 0.95
## Where a seated figure's feet go on its row (bleacher frame: z back from the track, y up) and
## how much it is lifted over the foot board (the camp chair pose: knees bent square).
const FAN_FEET := Vector2(-0.2, 0.0)

static var _enabled := -1
static var _bloom_mat: ShaderMaterial = null
static var _team_mats: Dictionary = {}
static var _player_baked: Dictionary = {}


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if OS.get_environment("RC5_FRIDAY_LIGHTS") == "0" else 1
	return _enabled == 1


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 1000003) / 1000003.0


# --- The car park ------------------------------------------------------------------------------

## Schools' "parking" piece `r` that no one chunk holds whole: the chunk owning its centre lays
## the whole lot (stalls, cars, poles); the others lay their part of the asphalt a little lower,
## under it, so a lot whose owner is not built yet is not a hole. True when handled.
static func car_park(ch: CityChunk, pl: Dictionary, r: Rect2) -> bool:
	if not enabled():
		return false
	var own := ch.plan.owned_rect(ch.ix, ch.iz)
	if not own.has_point(r.get_center()):
		var f := {"c": r.get_center(), "u": Vector2(1.0, 0.0)}
		Schools._gp(ch, f, -r.size.x * 0.5, r.size.x * 0.5, -r.size.y * 0.5, r.size.y * 0.5, Parks.G_ASPHALT, 0.0, 0.0, 1.0, r.size * 0.5, ch.style.asphalt, 0.03)
		return true
	var key := hash([ch.plan.seed, pl.cell, "school_lot", r.position])
	var fill := LOT_FILL if bool(pl.get("game_night", false)) else -1.0
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		LotFill._car_park(ch, r, key, fill)
		return true
	# Last, so the lot's poles take prop ids after everything the chunk already had.
	ch._run_last(func() -> bool:
		LotFill._car_park(ch, r, key, fill)
		return true)
	return true


# --- The light standards -----------------------------------------------------------------------

## One lit standard Schools has just built at `at` (its foot, chunk space = true world), `h` high,
## aimed at `aim` on the field: its spotlight and the bloom over its lenses.
static func standard(ch: CityChunk, at: Vector3, aim: Vector3, h: float) -> void:
	if not enabled() or ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	var rig := _rig(ch)
	var head := at + Vector3(0.0, h + 0.3, 0.0)
	var dir := Vector3(aim.x - at.x, 0.0, aim.z - at.z)
	var flat := dir.normalized() if dir.length() > 0.1 else Vector3(1.0, 0.0, 0.0)
	rig.banks.append([head + flat * 0.45, flat, aim])
	if OS.has_feature("web"):
		return
	var spot := SpotLight3D.new()
	spot.name = "FridaySpot_%d" % rig.spots.size()
	spot.light_color = TINT
	spot.light_energy = 0.0
	spot.spot_range = SPOT_RANGE
	spot.spot_angle = SPOT_ANGLE
	spot.spot_attenuation = SPOT_ATTENUATION
	spot.spot_angle_attenuation = 0.6
	spot.light_volumetric_fog_energy = SPOT_FOG
	spot.light_specular = 0.35
	spot.shadow_enabled = false
	spot.distance_fade_enabled = true
	spot.distance_fade_begin = 420.0
	spot.distance_fade_length = 80.0
	# Aimed between the standard's own aim point and the field's middle, low enough that the
	# beam's edge reaches the near touchline.
	var target := aim
	spot.position = head
	rig.add_child(spot)
	spot.look_at_from_position(head, target, Vector3.UP if absf((target - head).normalized().y) < 0.99 else Vector3.FORWARD)
	spot.visible = false
	rig.spots.append(spot)


static func _rig(ch: CityChunk) -> FridayRig:
	var rig := ch.get_node_or_null("FridayLights") as FridayRig
	if rig == null:
		rig = FridayRig.new()
		rig.name = "FridayLights"
		ch.add_child(rig)
	return rig


## The bloom material (StadiumNight's: nothing by day, the core over the lenses after dark).
static func bloom_material() -> ShaderMaterial:
	if _bloom_mat == null:
		_bloom_mat = ShaderMaterial.new()
		_bloom_mat.shader = load("res://shaders/stadium_bank_glow.gdshader")
		_bloom_mat.set_shader_parameter("bloom_energy", 0.85)
		_bloom_mat.set_shader_parameter("shaft_energy", 0.03)
		_bloom_mat.set_shader_parameter("min_angle", 0.006)
	return _bloom_mat


## The banks' blooms and shafts as one mesh (stadium_bank_glow's layout: StadiumNight.bank_mesh).
static func bank_mesh(banks: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for b: Array in banks:
		var c: Vector3 = b[0]
		var face: Vector3 = b[1]
		var aim: Vector3 = b[2]
		for k: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			v.append(c)
			nrm.append(face)
			uv.append(k)
			uv2.append(Vector2(0.0, BLOOM_SIZE))
		var axis := aim - c
		var run := axis.length() * 0.85
		axis = axis.normalized()
		var e := c + axis * run
		for k: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(1, 1), Vector2(-1, 0), Vector2(1, 1), Vector2(-1, 1)]:
			v.append(c if k.y < 0.5 else e)
			nrm.append(axis)
			uv.append(k)
			uv2.append(Vector2(1.0, run * 0.42))
		lo = lo.min(c).min(e)
		hi = hi.max(c).max(e)
	var m := ArrayMesh.new()
	if v.is_empty():
		return m
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, bloom_material())
	m.custom_aabb = AABB(lo - Vector3(40.0, 40.0, 40.0), hi - lo + Vector3(80.0, 80.0, 80.0))
	return m


# --- The game: players and the home crowd ------------------------------------------------------

## The stadium (Schools' track facility `f` of school `pl`) on a game night, after its kit: the
## players on the field from the chunk that owns its middle, the crowd from the chunk that owns
## the stands' middle (deferred steps: a figure is baked the first time it is needed).
static func stadium(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	if not enabled() or ch.capturing or ch.level != CityChunk.Level.FULL or not bool(pl.get("game_night", false)):
		return
	var own := ch.plan.owned_rect(ch.ix, ch.iz)
	if own.has_point(Parks.fp(f, 0.0, 0.0)) and float(f.get("football", 0.0)) > 0.0:
		ch._run_or_defer(func() -> bool:
			_players(ch, pl, f)
			return true)
	for s: Dictionary in pl.fac:
		if s.t == "bleachers" and own.has_point((s.r as Rect2).get_center()):
			ch._run_or_defer(func() -> bool:
				_fans(ch, pl, s)
				return true)


static func _top(ch: CityChunk, p: Vector2) -> float:
	return CityChunk.SIDEWALK_TOP + Parks.LIFT + ch._gy(p.x, p.y)


static func _figures(ch: CityChunk, name: String) -> BeachFigureMesh:
	var m := ch.get_node_or_null(name) as BeachFigureMesh
	if m == null:
		m = BeachFigureMesh.new()
		m.name = name
		m.draw_distance = FIGURE_DRAW
		m.shadow_distance = FIGURE_SHADOW
	return m


## A uniform for `model`'s body: team 0 the school's colour over white, 1 white over the school's
## colour (the visitors), 2 the officials (black over white).
static func _uniform(albedo: Texture2D, team: int, colour: Color) -> ShaderMaterial:
	var key := "%d_%d_%d" % [albedo.get_instance_id(), team, colour.to_rgba32()]
	if _team_mats.has(key):
		return _team_mats[key]
	var base := Pedestrian.character_material(albedo, 1)
	if base == null:
		return null
	var mat := base.duplicate() as ShaderMaterial
	var white := Color(0.92, 0.92, 0.9)
	var top: Color = [colour, white, Color(0.06, 0.06, 0.07)][team]
	var low: Color = [white, colour.darkened(0.2), white][team]
	mat.set_shader_parameter("cloth_hue", top.h)
	mat.set_shader_parameter("cloth_sat", top.s)
	mat.set_shader_parameter("cloth_value", top.v)
	mat.set_shader_parameter("cloth_strength", 0.96)
	mat.set_shader_parameter("pants_hue", low.h)
	mat.set_shader_parameter("pants_sat", low.s)
	mat.set_shader_parameter("pants_value", low.v)
	mat.set_shader_parameter("pants_strength", 0.96)
	mat.set_shader_parameter("cloth_shade_keep", 0.35)
	_team_mats[key] = mat
	return mat


## A player (rig `model`, team `team` in `colour`) standing, baked once ([near, far] or null).
static func player_mesh(model: int, team: int, colour: Color, pose_key: String) -> Array:
	var key := "%d|%d|%d|%s" % [model, team, colour.to_rgba32(), pose_key]
	if _player_baked.has(key):
		return _player_baked[key]
	_player_baked[key] = []
	var host := BeachFigure._bake_parent()
	if host == null:
		return []
	var ped := BeachGoer.new()
	ped.clothed = true
	ped.setup_sleeper(Rect2(0.0, 0.0, 10.0, 10.0), 2.0, BeachGoer.seed_for(model, 23), RoughSleeper.Pose.STAND, Vector2.ZERO, 0.0)
	ped.beach_pose = pose_key
	host.add_child(ped)
	if ped._visual:
		ped._visual.scale = Vector3.ONE
		ped._visual.position = Vector3.ZERO
	BeachFigure._refresh(ped)
	for node in ped.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.skin or Pedestrian.is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := _uniform(src.albedo_texture, team, colour)
			if mat:
				mi.material_override = mat
	var near := CampFigure._bake(ped, Pedestrian.mid_triangles)
	var far := CampFigure._bake(ped, Pedestrian.far_triangles) if near else null
	BeachFigure._drop(ped)
	_player_baked[key] = [near, far] if near else []
	return _player_baked[key]


## Where the people on the field stand, in the field's frame (a along u from the middle, b across
## it, the facing +1 toward +u): [a, b, team, facing, pose]. A line of scrimmage at `los`, both
## benches along the sidelines, three officials.
static func line_up(pl: Dictionary, f: Dictionary) -> Array:
	var fb: float = f.football
	var half_w := Parks.FOOTBALL.y * 0.5 * fb
	var los := (_h01([pl.cell, "friday_los"]) - 0.5) * 50.0 * fb
	var out: Array = []
	# Offence (home, facing +u) and defence (visitors, facing -u): seven on the line, four back.
	var offence := [[0.0, 0.0], [-1.0, -1.4], [-1.0, 1.4], [-1.0, -2.8], [-1.0, 2.8], [-1.1, -4.4], [-1.1, 4.4],
		[-5.5, 0.0], [-7.0, 0.3], [-1.6, -9.5], [-1.6, 11.0]]
	var defence := [[1.0, -0.7], [1.0, 0.7], [1.0, -2.6], [1.0, 2.6], [4.5, -3.5], [4.5, 0.5], [4.6, 4.0],
		[8.0, -10.0], [8.5, 9.5], [12.0, -3.0], [12.5, 3.5]]
	for p: Array in offence:
		out.append([los + float(p[0]), float(p[1]), 0, 1.0, "crouch" if float(p[0]) > -1.5 and absf(float(p[1])) < 5.0 else ""])
	for p: Array in defence:
		out.append([los + float(p[0]), float(p[1]), 1, -1.0, "crouch" if float(p[0]) < 2.0 else ""])
	# The officials: one behind the defence, one each side on the sideline.
	out.append([los + 14.0, 1.0, 2, -1.0, ""])
	out.append([los, -half_w - 1.5, 2, 0.0, ""])
	out.append([los - 6.0, half_w + 1.5, 2, 0.0, ""])
	# The benches: the home team on the -b sideline, the visitors on the +b one, standing in a
	# loose crowd between the 30s (a hash per player).
	for team in 2:
		var side := -1.0 if team == 0 else 1.0
		for i in 16:
			var a := (_h01([pl.cell, team, i, "bench_a"]) - 0.5) * 36.0 * fb
			var b := side * (half_w + 4.0 + _h01([pl.cell, team, i, "bench_b"]) * 3.0)
			out.append([a, b, team, 0.0, ""])
	return out


static func _players(ch: CityChunk, pl: Dictionary, f: Dictionary) -> void:
	var merged := _figures(ch, "FridayPlayers")
	var colour: Color = pl.colour
	var u: Vector2 = f.u
	var v := Parks.perp(u)
	var count := 0
	for i in line_up(pl, f).size():
		var p: Array = line_up(pl, f)[i]
		var model: int = PLAYER_MODELS[absi(hash([pl.cell, i, "friday_rig"])) % PLAYER_MODELS.size()]
		var team: int = p[2]
		var key: String = p[4]
		var meshes := player_mesh(model, team, colour, "")
		if meshes.is_empty():
			continue
		var at := Parks.fp(f, float(p[0]), float(p[1]))
		var face := u * float(p[3])
		if float(p[3]) == 0.0:
			# Sideline people face the field.
			face = -v * signf(float(p[1]))
		face = face.rotated((_h01([pl.cell, i, "friday_turn"]) - 0.5) * 0.5)
		# A figure faces -Z: yaw for a facing direction d is atan2(-d.x, -d.y).
		var yaw := atan2(-face.x, -face.y)
		var basis := Basis(Vector3.UP, yaw)
		if key == "crouch":
			# Linemen and the backs in a set stance: bent forward over the knees.
			basis = basis * Basis(Vector3.RIGHT, -0.38).scaled(Vector3(1.0, 0.86, 1.0))
		merged.add_figure(meshes[0], meshes[1], Transform3D(basis, Vector3(at.x, _top(ch, at), at.y)))
		count += 1
	if count > 0:
		ch.add_child(merged)


static func _fans(ch: CityChunk, pl: Dictionary, s: Dictionary) -> void:
	var depth: float = s.W
	var rows := clampi(int((depth - 0.8) / 0.72), 3, 12)
	var to_track: Vector2 = ((s.facing as Vector2) - (s.c as Vector2))
	var back := -Vector2(0.0, signf(to_track.y)) if absf((s.u as Vector2).x) > 0.5 else -Vector2(signf(to_track.x), 0.0)
	var x := Vector2(back.y, -back.x)
	var front_c: Vector2 = (s.c as Vector2) - back * depth * 0.5
	var y0 := _top(ch, front_c)
	var xf := ParkKit.frame(Vector3(front_c.x, y0, front_c.y), x)
	var len: float = s.L - 2.0
	var merged := _figures(ch, "FridayFans")
	var n := int((len - 1.0) / FAN_PITCH)
	var count := 0
	for r in rows:
		var y := 0.42 + 0.36 * float(r)
		var z := 0.3 + 0.72 * float(r)
		for i in n:
			var hk := [pl.cell, r, i, "friday_fan"]
			# Fuller toward the middle of the stands (the 50), thinning to the ends.
			var t := absf((float(i) + 0.5) / float(n) - 0.5) * 2.0
			if _h01(hk) > FAN_FILL * (1.15 - 0.55 * t * t):
				continue
			var model: int = FAN_MODELS[absi(hash(hk + ["m"])) % FAN_MODELS.size()]
			var salt: int = FAN_SALTS[absi(hash(hk + ["s"])) % FAN_SALTS.size()]
			var standing := _h01(hk + ["up"]) < FAN_STAND
			var pose := RoughSleeper.Pose.STAND if standing else RoughSleeper.Pose.CHAIR
			var pose_key := ""
			var mesh := BonfireFigure.bonfire_mesh(BeachGoer.seed_for(model, salt), pose, pose_key, model)
			if mesh == null:
				continue
			var lx := -len * 0.5 + 0.5 + (float(i) + 0.5) * FAN_PITCH + (_h01(hk + ["x"]) - 0.5) * 0.2
			var local: Vector3
			if standing:
				# On the seat board, facing the field.
				local = Vector3(lx, y + 0.03, z + 0.18)
			else:
				local = Vector3(lx, y - 0.38 + 0.02 + FAN_FEET.y, z + FAN_FEET.x)
			var turn := (_h01(hk + ["t"]) - 0.5) * 0.5
			var fxf := xf * Transform3D(Basis(Vector3.UP, turn), local)
			merged.add_figure(mesh, CampFigure.shadow_for(mesh), fxf)
			count += 1
	if count > 0:
		ch.add_child(merged)
