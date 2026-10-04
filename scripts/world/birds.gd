class_name Birds
extends Node3D
## The city's birds (VISUAL_ROADMAP #47, HANDOFF 9bh): pigeons on the plazas, parks, pavements and
## station forecourts, gulls on the beach, the piers and the port, crows on the suburbs' lawns and
## power lines, sparrows by the pavements. A Node3D in city.tscn, so the streamer's origin shifts
## carry it and everything under it; birds live in this node's own space.
##
## Nothing here is per chunk: the flocks are worked out round the player from the plan
## (`_survey()`, a hash of seed + block or cell + slot, so the same plaza always has its flock) and
## dropped again behind him. Only flocks near the player are simulated - a few hundred birds of
## plain GDScript, walking, pecking and bobbing on the ground, bursting up with wing claps when
## the player comes close, runs or flies at them, fires, or a car passes fast; then they wheel as
## a flock, and settle somewhere else: the ground further off, a roof edge, a power line.
## They are drawn by ONE MultiMesh per species and level of detail (BirdMesh), the instance
## buffer written whole each frame; the shader does the wings, the head and the legs.
##
## A bird is hit by a ray, not a body: every gun's hit path asks `hit_ray()` (AssaultRifle,
## Shotgun), a blast kills what is close (Explosion.blast_count is polled), and an alarm
## (Pedestrian.alarm) startles every flock in reach. A shot bird drops in a puff of feathers and
## lies where it falls; the police do not care.

enum Mode { STAND, WALK, PECK, SQUABBLE, TAKEOFF, FLY, LAND, PERCH, DEAD }
enum FlockState { GROUND, AIR, PERCHED }

const SPECIES := ["pigeon", "gull", "crow", "sparrow"]
## Per species: flush distance (m, on foot and still), how much faster movement adds to it (s),
## walk speed, stride length, wingbeat (Hz), cruise speed, circle radius, height over the ground,
## hit radius, near and mid LOD distances.
const KINDS := {
	"pigeon": {"flush": 3.2, "flush_speed": 0.55, "walk": 0.32, "stride": 0.07, "beat": 7.5, "cruise": 11.0,
		"orbit": 17.0, "height": Vector2(9.0, 18.0), "hit": 0.13, "near": 14.0, "mid": 45.0, "glide": 0.25, "circle": Vector2(5.0, 11.0)},
	"gull": {"flush": 7.0, "flush_speed": 0.6, "walk": 0.45, "stride": 0.12, "beat": 3.0, "cruise": 9.0,
		"orbit": 24.0, "height": Vector2(10.0, 22.0), "hit": 0.22, "near": 20.0, "mid": 70.0, "glide": 0.7, "circle": Vector2(7.0, 15.0)},
	"crow": {"flush": 10.0, "flush_speed": 0.6, "walk": 0.5, "stride": 0.11, "beat": 4.2, "cruise": 9.0,
		"orbit": 20.0, "height": Vector2(8.0, 16.0), "hit": 0.18, "near": 18.0, "mid": 60.0, "glide": 0.35, "circle": Vector2(5.0, 10.0)},
	"sparrow": {"flush": 2.6, "flush_speed": 0.5, "walk": 0.35, "stride": 0.035, "beat": 14.0, "cruise": 7.0,
		"orbit": 7.0, "height": Vector2(2.5, 5.0), "hit": 0.07, "near": 8.0, "mid": 26.0, "glide": 0.05, "circle": Vector2(2.0, 4.0)},
}
## Pigeon colour morphs (sRGB targets for the grey; black keeps the painted blue-bar bird) and how
## often each turns up in a feral flock.
const PIGEON_MORPHS := [
	[Color(0, 0, 0), 0.52], [Color(0.42, 0.44, 0.5), 0.16], [Color(0.17, 0.17, 0.2), 0.14],
	[Color(0.88, 0.88, 0.86), 0.08], [Color(0.5, 0.34, 0.26), 0.06], [Color(0.66, 0.6, 0.56), 0.04],
]

## How far round the player flocks are planned, and how far past that they are dropped (m).
@export var spawn_radius: float = 130.0
@export var despawn_margin: float = 50.0
## Birds alive at once at most (desktop / web); Quality takes this down at LOW and LOWEST.
@export var max_birds: int = 300
@export var web_max_birds: int = 110
## Seconds between surveys of the ground round the player (real clock).
@export var survey_interval: float = 0.8
## Nothing is drawn past this (m); birds past the mid distance get the far mesh.
@export var draw_distance: float = 230.0
## A dead bird lies this long (s).
@export var corpse_seconds: float = 45.0
## Odds per block or cell of a flock, by kind of place.
@export var plaza_flocks: int = 3
@export var pavement_odds: float = 0.4
@export var suburb_crow_odds: float = 0.45
@export var sparrow_odds: float = 0.3
@export var beach_odds: float = 0.45
@export var wire_odds: float = 0.55
## Sound: the chance a second, coos and caws per minute per flock in earshot.
@export var coo_per_minute: float = 7.0
@export var caw_per_minute: float = 2.5
@export var chirp_per_minute: float = 5.0
## Set false to remove every bird (the A/B; also BIRDS=0 in the environment).
@export var enabled: bool = true

static var _live: Birds = null
## Counted for the checks: takeoffs and kills since the scene started.
static var flushes: int = 0
static var kills: int = 0

var plan: CityPlan
var _player: Node3D
var _flocks: Dictionary = {} # id -> Flock
var _survey_left := 0.0
var _rng := RandomNumberGenerator.new()
var _blast_seen := 0
var _mm: Dictionary = {} # "species:lod" -> MultiMeshInstance3D
var _buf: Dictionary = {} # "species:lod" -> PackedFloat32Array being filled
var _count: Dictionary = {} # "species:lod" -> int
var _bounds: Dictionary = {} # "species:lod" -> AABB
var _frame := 0
var _cap := 300
var _dead: Array = [] # Bird corpses and falling birds, outside any flock
var _web := false


class Bird:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var bank := 0.0
	var mode: int = Mode.STAND
	var t := 0.0
	var phase := 0.0
	var spread := 0.0
	var peck := 0.0
	var walk := 0.0
	var amp := 0.0
	var tint := Color(0, 0, 0)
	var offset := Vector3.ZERO
	var delay := 0.0
	var target := Vector3.ZERO
	var gy := 0.0
	var scale := 1.0
	var glide := false
	var roll := 0.0
	var life := 0.0
	var species := ""


class Flock:
	var id := 0
	var species := "pigeon"
	var home := Vector3.ZERO
	var ground_y := 0.0
	var radius := 4.0
	var state: int = FlockState.GROUND
	var birds: Array = []
	var center := Vector3.ZERO
	var orbit_c := Vector3.ZERO
	var orbit_a := 0.0
	var orbit_r := 15.0
	var orbit_h := 12.0
	var orbit_dir := 1.0
	var air_left := 0.0
	var landing := false
	var land_slots: Array = []
	var land_yaws: Array = []
	var land_perch := false
	var perch_face := Vector3.ZERO
	var check_left := 0.0
	var sound_left := 0.0
	var squabble_left := 0.0
	var cars: Dictionary = {}
	var walk_box := 0.0


func _ready() -> void:
	_live = self
	_web = OS.has_feature("web")
	_rng.seed = 4242
	if OS.get_environment("BIRDS") == "0":
		enabled = false
	_cap = web_max_birds if _web else max_birds
	for sp: String in SPECIES:
		for lod in 3:
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = BirdMesh.mesh(sp, lod)
			mm.instance_count = 0
			mmi.multimesh = mm
			mmi.material_override = BirdMesh.material(sp)
			mmi.name = "Birds_%s_%d" % [sp, lod]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(mmi)
			_mm["%s:%d" % [sp, lod]] = mmi


func _exit_tree() -> void:
	if _live == self:
		_live = null


func _setup() -> bool:
	if plan != null and _player != null and is_instance_valid(_player):
		return true
	var city := get_parent()
	if city == null or not ("plan" in city):
		return false
	plan = city.get("plan") as CityPlan
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return plan != null and plan.macro != null and _player != null


func _process(delta: float) -> void:
	if _live == null:
		_live = self
	if not enabled or not _setup():
		_draw_nothing()
		return
	_frame += 1
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	_survey_left -= real_dt
	if _survey_left <= 0.0:
		_survey_left = survey_interval
		_cap_from_quality()
		_survey()
	if Explosion.blast_count != _blast_seen:
		_blast_seen = Explosion.blast_count
		_blasted(to_local(WorldState.to_local(Explosion.last_blast_world)))
	var eye := _player_local()
	var dt := minf(delta, 0.1)
	for f: Flock in _flocks.values():
		_tick_flock(f, dt, eye)
	_tick_dead(dt)
	_draw()


func _player_local() -> Vector3:
	return to_local(_player.global_position)


func _cap_from_quality() -> void:
	var q := get_parent().get_node_or_null("Quality")
	var lv := int(q.get("level")) if q != null and q.get("level") != null else 0
	var base := web_max_birds if _web else max_birds
	_cap = int(base * [1.0, 1.0, 0.6, 0.35][clampi(lv, 0, 3)])


# --- Where the birds are -------------------------------------------------------------------

func _bird_total() -> int:
	var n := 0
	for f: Flock in _flocks.values():
		n += f.birds.size()
	return n


## Plans the flocks round the player and drops the ones he has left behind.
func _survey() -> void:
	var eye := _player_local()
	var w := WorldState.to_world(to_global(eye))
	var keep_r := spawn_radius + despawn_margin
	for id in _flocks.keys():
		var f: Flock = _flocks[id]
		var c := f.center if f.state == FlockState.AIR else f.home
		if Vector2(c.x - eye.x, c.z - eye.z).length() > keep_r:
			_flocks.erase(id)
	# Night and storms empty the streets of birds; dusk thins them.
	var dark := clampf(DayNight.lamp_now, 0.0, 1.0)
	var presence := 1.0 - smoothstep(0.35, 0.8, dark)
	if presence <= 0.02:
		return
	var total := _bird_total()
	var spots := _spots_near(Vector2(w.x, w.z))
	for s: Dictionary in spots:
		if total >= _cap:
			break
		var id: int = s.id
		if _flocks.has(id):
			continue
		if _hash01([plan.seed, id, "night"]) > presence:
			continue
		var at: Vector2 = s.at
		if at.distance_to(Vector2(w.x, w.z)) > spawn_radius:
			continue
		var f := _spawn(s)
		if f != null:
			_flocks[id] = f
			total += f.birds.size()


## Every flock spot within reach of world point `w`: {"id", "at" (world xz), "species", "count",
## "kind" ("ground" | "wire"), "radius", optional "wire": [a, b, sag]}.
func _spots_near(w: Vector2) -> Array:
	var out: Array = []
	var macro := plan.macro
	var c := plan.block_index_at(w)
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var ix := c.x + dx
			var iz := c.y + dz
			var b := plan.block(ix, iz)
			var rect: Rect2 = b.rect
			if rect.size.x < 8.0 or rect.size.y < 8.0:
				continue
			if rect.grow(spawn_radius).has_point(w) == false:
				continue
			var centre := rect.get_center()
			if macro.zone_at(centre) != MacroMap.Zone.CITY:
				continue
			var district: int = b.district
			var kind: int = b.kind
			var park := kind == CityPlan.BlockKind.PARK or kind == CityPlan.BlockKind.PLAZA or b.has("site") or Landmarks.claims(rect)
			if park:
				var n := plaza_flocks if kind != CityPlan.BlockKind.PARK else plaza_flocks - 1
				for k in n:
					var h := _hash01([plan.seed, "birdpark", ix, iz, k])
					if h > 0.75:
						continue
					var p := rect.position + rect.size * Vector2(lerpf(0.15, 0.85, _hash01([plan.seed, "bpx", ix, iz, k])), lerpf(0.15, 0.85, _hash01([plan.seed, "bpz", ix, iz, k])))
					var sp := "pigeon"
					if district == CityPlan.District.SUBURBS or district == CityPlan.District.BEACHTOWN:
						sp = "crow" if h < 0.35 else "pigeon"
					var cnt := int(lerpf(12.0, 40.0, _hash01([plan.seed, "bpn", ix, iz, k]))) if sp == "pigeon" else int(lerpf(3.0, 8.0, h * 2.0))
					out.append({"id": hash([ix, iz, "park", k]), "at": p, "species": sp, "count": cnt, "kind": "ground", "radius": 4.0 + float(cnt) * 0.12})
				continue
			if kind != CityPlan.BlockKind.BUILDINGS and kind != CityPlan.BlockKind.MALL and kind != CityPlan.BlockKind.BIGBOX:
				continue
			# A face of the block's pavement: by a corner, 1.2-2.6 m in from the kerb.
			var side := int(_hash01([plan.seed, "bface", ix, iz]) * 4.0)
			var along := lerpf(0.12, 0.88, _hash01([plan.seed, "balong", ix, iz]))
			var inset := lerpf(1.3, 2.6, _hash01([plan.seed, "binset", ix, iz]))
			var pave := _face_point(rect, side, along, inset)
			if district == CityPlan.District.DOWNTOWN or district == CityPlan.District.MIDTOWN or district == CityPlan.District.CAMPUS:
				if _hash01([plan.seed, "bpave", ix, iz]) < pavement_odds:
					var cnt := int(lerpf(6.0, 18.0, _hash01([plan.seed, "bpaven", ix, iz])))
					out.append({"id": hash([ix, iz, "pave"]), "at": pave, "species": "pigeon", "count": cnt, "kind": "ground", "radius": 2.2})
			if district == CityPlan.District.SUBURBS or district == CityPlan.District.BEACHTOWN or district == CityPlan.District.INDUSTRIAL:
				if _hash01([plan.seed, "bcrow", ix, iz]) < suburb_crow_odds:
					var cnt := int(lerpf(3.0, 8.0, _hash01([plan.seed, "bcrown", ix, iz])))
					var spans := _wire_spans(ix, iz)
					if not spans.is_empty() and _hash01([plan.seed, "bwire", ix, iz]) < wire_odds:
						var sp_i := int(_hash01([plan.seed, "bspan", ix, iz]) * spans.size()) % spans.size()
						var span: Array = spans[sp_i]
						var mid := (span[0] as Vector3).lerp(span[1], 0.5)
						out.append({"id": hash([ix, iz, "wire"]), "at": Vector2(mid.x, mid.z), "species": "crow", "count": cnt, "kind": "wire", "radius": 3.0, "wire": span})
					else:
						# A front lawn: further in from the kerb than the pavement.
						var lawn := _face_point(rect, side, along, lerpf(6.5, 9.0, _hash01([plan.seed, "blawn", ix, iz])))
						out.append({"id": hash([ix, iz, "lawn"]), "at": lawn, "species": "crow", "count": cnt, "kind": "ground", "radius": 3.5})
			if _hash01([plan.seed, "bsparrow", ix, iz]) < sparrow_odds and district != CityPlan.District.INDUSTRIAL:
				var p2 := _face_point(rect, (side + 2) % 4, lerpf(0.2, 0.8, _hash01([plan.seed, "bsa", ix, iz])), 1.6)
				var cnt := int(lerpf(4.0, 9.0, _hash01([plan.seed, "bsn", ix, iz])))
				out.append({"id": hash([ix, iz, "sparrow"]), "at": p2, "species": "sparrow", "count": cnt, "kind": "ground", "radius": 1.6})
	# The shore, the piers and the port, on a 60 m grid of cells.
	var cell := 60.0
	var cx := floori(w.x / cell)
	var cz := floori(w.y / cell)
	var reach := int(ceil(spawn_radius / cell))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var gx := cx + dx
			var gz := cz + dz
			var p := Vector2((float(gx) + _hash01([plan.seed, "gcx", gx, gz])) * cell, (float(gz) + _hash01([plan.seed, "gcz", gx, gz])) * cell)
			if p.distance_to(w) > spawn_radius:
				continue
			var zone := macro.zone_at(p)
			var odds := 0.0
			var kind := "ground"
			if zone == MacroMap.Zone.BEACH:
				odds = beach_odds
			elif zone == MacroMap.Zone.PORT:
				odds = beach_odds * 0.6
			elif zone == MacroMap.Zone.OCEAN and _near_pier(p):
				odds = 0.8
				kind = "pier"
			if odds <= 0.0 or _hash01([plan.seed, "gull", gx, gz]) > odds:
				continue
			var cnt := int(lerpf(3.0, 14.0, _hash01([plan.seed, "gulln", gx, gz])))
			out.append({"id": hash([gx, gz, "gull"]), "at": p, "species": "gull", "count": cnt, "kind": kind, "radius": 5.0})
	return out


func _near_pier(p: Vector2) -> bool:
	for e: Dictionary in Landmarks.all():
		var id: String = e.id
		if id.ends_with("pier") and p.distance_to(e.anchor) < float(e.radius) * 1.4:
			return true
	return false


## A point on a block's pavement ring: face 0 -x, 1 +x, 2 -z, 3 +z, `along` 0..1 of it, `inset` in
## from the kerb.
static func _face_point(rect: Rect2, face: int, along: float, inset: float) -> Vector2:
	match face:
		0:
			return Vector2(rect.position.x + inset, rect.position.y + along * rect.size.y)
		1:
			return Vector2(rect.end.x - inset, rect.position.y + along * rect.size.y)
		2:
			return Vector2(rect.position.x + along * rect.size.x, rect.position.y + inset)
	return Vector2(rect.position.x + along * rect.size.x, rect.end.y - inset)


## The overhead power spans along block (ix, iz), as StreetDetail lays them: [a, b, sag] in
## world space, the top power wire's ends (a crow sits on the top wire).
func _wire_spans(ix: int, iz: int) -> Array:
	var out: Array = []
	var b := plan.block(ix, iz)
	var rect: Rect2 = b.rect
	var faces := [[CityPlan.AXIS_X, ix, 1], [CityPlan.AXIS_X, ix + 1, 0], [CityPlan.AXIS_Z, iz, 1], [CityPlan.AXIS_Z, iz + 1, 0]]
	for f in faces:
		var axis: int = f[0]
		var index: int = f[1]
		var side: int = f[2]
		if absi(hash([plan.seed, "pole_side", axis, index])) % 2 != side:
			continue
		if not StreetDetail._has_poles(plan, ix, iz, axis, index):
			continue
		var along_z := axis == CityPlan.AXIS_X
		var kerb: float = (rect.position.x if side == 1 else rect.end.x) if along_z else (rect.position.y if side == 1 else rect.end.y)
		var line := kerb + (StreetDetail.POLE_INSET if side == 1 else -StreetDetail.POLE_INSET)
		var u0: float = rect.position.y if along_z else rect.position.x
		var u1: float = rect.end.y if along_z else rect.end.x
		var phase := float(absi(hash([plan.seed, "pole_phase", axis, index])) % 1000) * 0.001 * StreetDetail.POLE_SPACING
		var first := ceili((u0 + StreetDetail.POLE_EDGE_MARGIN - phase) / StreetDetail.POLE_SPACING)
		var last := floori((u1 - StreetDetail.POLE_EDGE_MARGIN - phase) / StreetDetail.POLE_SPACING)
		for k in range(first, last):
			var ua := phase + float(k) * StreetDetail.POLE_SPACING
			var ub := ua + StreetDetail.POLE_SPACING
			var h := CityChunk.SIDEWALK_TOP + StreetDetail.POWER_ARM_HEIGHT + 0.2
			var a := Vector3(line, h, ua) if along_z else Vector3(ua, h, line)
			var bb := Vector3(line, h, ub) if along_z else Vector3(ub, h, line)
			a.y += _relief(a.x, a.z)
			bb.y += _relief(bb.x, bb.z)
			out.append([a, bb, StreetDetail.POWER_SAG])
	return out


## The city chunks' relief, as CityChunk._gy() samples it (the FULL lattice).
func _relief(x: float, z: float) -> float:
	var step := CityChunk.RELIEF_STEP
	var fx := x / step
	var fz := z / step
	var i := floori(fx)
	var j := floori(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var m := plan.macro
	var r := func(a: int, b: int) -> float: return m.relief_at(Vector2(a * step, b * step))
	return lerpf(lerpf(r.call(i, j), r.call(i + 1, j), tx), lerpf(r.call(i, j + 1), r.call(i + 1, j + 1), tx), tz)


## A point on a sagging span, on the very polyline StreetDetail draws (CABLE_SEGMENTS pieces).
static func wire_point(a: Vector3, b: Vector3, sag: float, s: float) -> Vector3:
	var n := StreetDetail.CABLE_SEGMENTS
	var k := clampi(int(floor(s * n)), 0, n - 1)
	var s0 := float(k) / float(n)
	var s1 := float(k + 1) / float(n)
	var p0 := a.lerp(b, s0) - Vector3(0.0, sag * 4.0 * s0 * (1.0 - s0), 0.0)
	var p1 := a.lerp(b, s1) - Vector3(0.0, sag * 4.0 * s1 * (1.0 - s1), 0.0)
	return p0.lerp(p1, (s - s0) / (s1 - s0))


## World xz -> this node's space, at height y (world).
func _local(w: Vector3) -> Vector3:
	return to_local(WorldState.to_local(w))


## The ground under a local point: a ray down onto the world layer. Returns NAN when nothing was
## hit, or the hit is not open ground (a roof, a car, a bench, a slope).
func _ground_at(local: Vector3, max_above: float = 1.2) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var g := to_global(local)
	var analytic: float = to_local(Vector3(g.x, _street_y(g), g.z)).y
	var q := PhysicsRayQueryParameters3D.create(Vector3(g.x, g.y + 30.0, g.z), Vector3(g.x, g.y - 30.0, g.z), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	var n: Vector3 = hit.normal
	if n.y < 0.85:
		return NAN
	var y: float = to_local(hit.position).y
	if max_above < INF and y > analytic + max_above:
		return NAN
	return y


## The street-level height under a global point (the plan's ground, global space).
func _street_y(g: Vector3) -> float:
	var w := WorldState.to_world(g)
	var h := maxf(plan.height_at(Vector2(w.x, w.z)), 0.0) + CityChunk.SIDEWALK_TOP
	return h - WorldState.world_offset.y


func _spawn(s: Dictionary) -> Flock:
	var at: Vector2 = s.at
	var sp: String = s.species
	# Rays start from the plan's street height (the valley floor is a plateau a hundred metres up),
	# or from the height a staged flock was given.
	var y_world: float = float(s.get("y", maxf(plan.height_at(at), 0.0) + CityChunk.SIDEWALK_TOP))
	var home := _local(Vector3(at.x, y_world, at.y))
	var f := Flock.new()
	f.id = s.id
	f.species = sp
	f.radius = s.radius
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(int(s.id)) + 17
	var n: int = mini(int(s.count), maxi(_cap - _bird_total(), 0))
	if n <= 0:
		return null
	if s.kind == "wire":
		var span: Array = s.wire
		var a := _local(span[0])
		var b := _local(span[1])
		if not _pole_there(a) or not _pole_there(b):
			return null
		f.home = a.lerp(b, 0.5)
		f.state = FlockState.PERCHED
		f.land_perch = true
		var dir := (b - a).normalized()
		f.perch_face = Vector3(-dir.z, 0.0, dir.x)
		for i in n:
			var bird := _new_bird(sp, rng)
			var t := clampf(0.5 + (float(i) - float(n - 1) * 0.5) * rng.randf_range(0.022, 0.045), 0.08, 0.92)
			bird.pos = wire_point(a, b, float(span[2]), t)
			bird.yaw = atan2(-f.perch_face.x, -f.perch_face.z) + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.3, 0.3)
			bird.mode = Mode.PERCH
			bird.t = rng.randf_range(1.0, 6.0)
			f.birds.append(bird)
		f.center = f.home
		f.ground_y = f.home.y
		return f
	if s.kind == "pier":
		# A pier's deck: the ray must hit something above the sea.
		var y := _deck_at(home)
		if is_nan(y):
			return null
		home.y = y
	else:
		var y := _ground_at(home, INF if s.has("y") else 1.2)
		if is_nan(y):
			return null
		home.y = y
	f.home = home
	f.ground_y = home.y
	f.center = home
	for i in n:
		var bird := _new_bird(sp, rng)
		var r := sqrt(rng.randf()) * f.radius
		var ang := rng.randf() * TAU
		bird.pos = home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		bird.gy = home.y
		bird.pos.y = home.y
		bird.yaw = rng.randf() * TAU
		bird.mode = [Mode.STAND, Mode.PECK, Mode.WALK][rng.randi() % 3]
		bird.target = bird.pos
		bird.t = rng.randf_range(0.2, 3.0)
		bird.phase = rng.randf()
		f.birds.append(bird)
	f.squabble_left = rng.randf_range(8.0, 30.0)
	f.sound_left = rng.randf_range(1.0, 8.0)
	return f


func _new_bird(sp: String, rng: RandomNumberGenerator) -> Bird:
	var b := Bird.new()
	b.species = sp
	b.scale = rng.randf_range(0.92, 1.08)
	if sp == "pigeon":
		var roll := rng.randf()
		for m in PIGEON_MORPHS:
			roll -= float(m[1])
			if roll <= 0.0:
				var c: Color = m[0]
				# A little spread inside a morph, so a flock of blue-bars is not one bird.
				if c.r + c.g + c.b > 0.0:
					c = c * rng.randf_range(0.9, 1.08)
					c.a = 1.0
				b.tint = c
				break
	b.offset = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)) * 2.5
	return b


func _pole_there(local: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	# The wire end hangs off the pole's crossarm; the pole's collision box tops out ~1 m above.
	var g := to_global(local)
	var q := PhysicsRayQueryParameters3D.create(g + Vector3(0.0, 3.0, 0.0), g - Vector3(0.0, 2.0, 0.0), 1)
	var hit := space.intersect_ray(q)
	return not hit.is_empty()


func _deck_at(local: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var g := to_global(local)
	var q := PhysicsRayQueryParameters3D.create(Vector3(g.x, g.y + 40.0, g.z), Vector3(g.x, g.y - 5.0, g.z), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.85:
		return NAN
	var y: float = to_local(hit.position).y
	return y if y > _local(Vector3.ZERO).y + 1.5 else NAN


# --- Behaviour --------------------------------------------------------------------------------

func _tick_flock(f: Flock, dt: float, eye: Vector3) -> void:
	var k: Dictionary = KINDS[f.species]
	var to_eye := eye - (f.center if f.state == FlockState.AIR else f.home)
	var dist := to_eye.length()
	# Far flocks on the ground tick at a quarter rate (they are a few pixels, barely moving).
	if f.state != FlockState.AIR and dist > 60.0 and (_frame + f.id) % 4 != 0:
		return
	var step := dt if f.state == FlockState.AIR or dist <= 60.0 else dt * 4.0
	match f.state:
		FlockState.GROUND, FlockState.PERCHED:
			_threats(f, step, eye, k)
			if f.state == FlockState.AIR:
				return
			_ground_flock(f, step, eye, k)
		FlockState.AIR:
			_air_flock(f, step, eye, k)


func _threats(f: Flock, dt: float, eye: Vector3, k: Dictionary) -> void:
	f.check_left -= dt
	if f.check_left > 0.0:
		return
	f.check_left = 0.1
	var pv: Vector3 = _player.get("velocity") if _player.get("velocity") != null else Vector3.ZERO
	var speed := pv.length()
	var reach: float = float(k.flush) + speed * float(k.flush_speed)
	if f.state == FlockState.PERCHED:
		reach = maxf(reach * 0.7, 2.5)
	for b: Bird in f.birds:
		if b.pos.distance_to(eye) < reach:
			_flush(f, eye)
			return
	# A fast car through the flock (sampled at 2 Hz, near the player only).
	if f.state == FlockState.GROUND and eye.distance_to(f.home) < 80.0 and (_frame + f.id) % 5 == 0:
		_car_check(f)


func _car_check(f: Flock) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var shape := SphereShape3D.new()
	shape.radius = f.radius + 4.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), to_global(f.home))
	q.collision_mask = 4
	q.collide_with_areas = false
	var now := Time.get_ticks_msec()
	var seen := {}
	for r in space.intersect_shape(q, 8):
		var c: Object = r.collider
		if not (c is Vehicle):
			continue
		var key := (c as Node).get_instance_id()
		var p := (c as Node3D).global_position
		seen[key] = [p, now]
		if f.cars.has(key):
			var prev: Array = f.cars[key]
			var dts := float(now - int(prev[1])) * 0.001
			if dts > 0.02 and p.distance_to(prev[0]) / dts > 6.0:
				_flush(f, to_local(p))
				return
	f.cars = seen


## Up they go: every bird in the flock leaves the ground within a third of a second, the ones
## nearest the threat first, away from it.
func _flush(f: Flock, threat: Vector3) -> void:
	if f.state == FlockState.AIR:
		return
	var k: Dictionary = KINDS[f.species]
	f.state = FlockState.AIR
	f.landing = false
	flushes += 1
	var away := f.home - threat
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	away = away.normalized()
	var h: Vector2 = k.height
	f.orbit_h = f.ground_y + _rng.randf_range(h.x, h.y)
	f.orbit_r = float(k.orbit) * _rng.randf_range(0.8, 1.25)
	f.orbit_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	f.orbit_c = f.home + away * f.orbit_r * 0.7
	f.orbit_a = atan2(f.home.z - f.orbit_c.z, f.home.x - f.orbit_c.x)
	var c: Vector2 = k.circle
	f.air_left = _rng.randf_range(c.x, c.y)
	f.center = f.home
	for b: Bird in f.birds:
		if b.mode == Mode.DEAD:
			continue
		var d := b.pos.distance_to(threat)
		b.mode = Mode.TAKEOFF
		b.delay = clampf(d * 0.03, 0.0, 0.25) + _rng.randf_range(0.0, 0.18)
		var out := (b.pos - threat)
		out.y = 0.0
		out = (out.normalized() if out.length() > 0.05 else away) * _rng.randf_range(1.5, 3.0) + away * 1.5
		b.vel = out + Vector3.UP * _rng.randf_range(3.0, 4.8)
		b.offset = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1, 1)) * (1.5 + 0.12 * float(f.birds.size()))
	var at := to_global(f.home)
	if f.species == "pigeon" or f.species == "crow":
		Sfx.play("wings", at, -2.0 + minf(float(f.birds.size()) * 0.15, 4.0))
		if f.birds.size() > 18:
			Sfx.play("wings", at + Vector3(1.0, 0.5, 0.0), -4.0)
	elif f.species == "sparrow":
		Sfx.play("wings", at, -10.0, 1.5)
	if f.species == "gull":
		Sfx.play("gull_close", at + Vector3.UP * 2.0, -2.0)
	elif f.species == "crow":
		Sfx.play("crow", at + Vector3.UP * 2.0, -1.0)


func _ground_flock(f: Flock, dt: float, eye: Vector3, k: Dictionary) -> void:
	var n := f.birds.size()
	var walk_speed: float = k.walk
	var stride: float = k.stride
	f.center = f.home
	# A pair of gulls falls out now and then: wings up, beaks at each other, calling.
	if f.species == "gull" and f.state == FlockState.GROUND and n >= 2:
		f.squabble_left -= dt
		if f.squabble_left <= 0.0:
			f.squabble_left = _rng.randf_range(12.0, 40.0)
			var a: Bird = f.birds[_rng.randi() % n]
			var b: Bird = f.birds[_rng.randi() % n]
			if a != b and a.mode != Mode.DEAD and b.mode != Mode.DEAD:
				var mid := (a.pos + b.pos) * 0.5
				a.pos = mid + Vector3(0.22, 0, 0)
				b.pos = mid - Vector3(0.22, 0, 0)
				a.yaw = atan2(1.0, 0.0)
				b.yaw = atan2(-1.0, 0.0)
				for g: Bird in [a, b]:
					g.mode = Mode.SQUABBLE
					g.t = _rng.randf_range(1.4, 2.4)
				if eye.distance_to(mid) < 90.0:
					Sfx.play("gull_close", to_global(mid) + Vector3.UP * 0.5, -3.0)
	_voice(f, dt, eye)
	for i in n:
		var b: Bird = f.birds[i]
		b.t -= dt
		match b.mode:
			Mode.DEAD:
				continue
			Mode.PERCH:
				b.walk = 0.0
				b.spread = maxf(b.spread - dt * 4.0, 0.0)
				b.amp = 0.0
				# Preening and looking about: a slow dip of the head now and then.
				b.peck = lerpf(b.peck, 0.35 if fmod(b.t, 5.0) < 0.8 else 0.0, dt * 3.0)
				if b.t < 0.0:
					b.t = _rng.randf_range(2.0, 7.0)
					b.yaw += _rng.randf_range(-0.6, 0.6)
				continue
			Mode.STAND:
				b.walk = maxf(b.walk - dt * 4.0, 0.0)
				b.peck = maxf(b.peck - dt * 3.0, 0.0)
				if b.t < 0.0:
					_next_ground_mode(f, b, k)
			Mode.PECK:
				b.walk = maxf(b.walk - dt * 4.0, 0.0)
				# Quick jabs at the ground.
				var j := fmod(b.t * 2.6, 1.0)
				b.peck = smoothstep(0.0, 0.25, j) * (1.0 - smoothstep(0.4, 0.75, j))
				if b.t < 0.0:
					b.peck = 0.0
					_next_ground_mode(f, b, k)
			Mode.WALK:
				var to := b.target - b.pos
				to.y = 0.0
				var d := to.length()
				if d < 0.05 or b.t < 0.0:
					b.mode = Mode.PECK if _rng.randf() < 0.6 else Mode.STAND
					b.t = _rng.randf_range(0.8, 3.5)
				else:
					var want := atan2(-to.x, -to.z)
					b.yaw = lerp_angle(b.yaw, want, minf(dt * 7.0, 1.0))
					var fwd := Vector3(-sin(b.yaw), 0.0, -cos(b.yaw))
					var v := walk_speed * b.scale * clampf(d * 3.0, 0.3, 1.0)
					b.pos += fwd * v * dt
					b.walk = minf(b.walk + dt * 5.0, 1.0)
					b.phase = fmod(b.phase + v * dt / stride, 1.0)
					b.peck = maxf(b.peck - dt * 3.0, 0.0)
			Mode.SQUABBLE:
				b.spread = 0.32 + 0.08 * sin(b.t * 9.0)
				b.amp = 0.6
				b.phase = fmod(b.phase + dt * 5.0, 1.0)
				b.peck = 0.5 + 0.4 * sin(b.t * 7.0 + float(i))
				if b.t < 0.0:
					b.mode = Mode.STAND
					b.t = _rng.randf_range(1.0, 3.0)
				continue
		b.spread = maxf(b.spread - dt * 3.0, 0.0)
		b.amp = maxf(b.amp - dt * 3.0, 0.0)
		# Keep apart: test two neighbours a frame, a different pair each frame.
		if n > 1:
			for m in 2:
				var o: Bird = f.birds[(i + 1 + (_frame * (m + 1) + m * 7) % (n - 1)) % n]
				var sep := b.pos - o.pos
				sep.y = 0.0
				var dd := sep.length()
				var min_sep := 0.22 * b.scale if f.species != "gull" else 0.45
				if f.species == "sparrow":
					min_sep = 0.1
				if dd < min_sep and dd > 1e-4:
					b.pos += sep / dd * (min_sep - dd) * 0.5
		b.pos.y = lerpf(b.pos.y, b.gy, minf(dt * 10.0, 1.0))
	# One bird a frame checks the ground under it; a bench or a wall turns it back home.
	if n > 0 and f.state == FlockState.GROUND and eye.distance_to(f.home) < 70.0:
		var b: Bird = f.birds[_frame % n]
		if b.mode != Mode.DEAD:
			var y := _ground_at(Vector3(b.pos.x, f.ground_y, b.pos.z), 0.45)
			if is_nan(y) or absf(y - f.ground_y) > 0.45:
				b.target = f.home + (f.home - b.pos).normalized() * 0.3
				b.mode = Mode.WALK
				b.t = 4.0
			else:
				b.gy = y


func _next_ground_mode(f: Flock, b: Bird, _k: Dictionary) -> void:
	var r := _rng.randf()
	if r < 0.45:
		b.mode = Mode.WALK
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * f.radius
		b.target = f.home + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		b.t = 8.0
	elif r < 0.8:
		b.mode = Mode.PECK
		b.t = _rng.randf_range(0.8, 3.0)
	else:
		b.mode = Mode.STAND
		b.t = _rng.randf_range(1.0, 4.0 if f.species != "gull" else 9.0)


## Coos, caws and chirps from a flock the player can hear.
func _voice(f: Flock, dt: float, eye: Vector3) -> void:
	var d := eye.distance_to(f.home)
	var per_min := 0.0
	var name := ""
	var reach := 30.0
	match f.species:
		"pigeon":
			per_min = coo_per_minute
			name = "pigeon_coo"
			reach = 26.0
		"crow":
			per_min = caw_per_minute
			name = "crow"
			reach = 140.0
		"sparrow":
			per_min = chirp_per_minute
			name = "sparrow"
			reach = 22.0
	if name == "" or d > reach:
		return
	f.sound_left -= dt * per_min / 60.0
	if f.sound_left > 0.0:
		return
	f.sound_left = _rng.randf_range(0.5, 1.5)
	if f.birds.is_empty():
		return
	var b: Bird = f.birds[_rng.randi() % f.birds.size()]
	if b.mode == Mode.DEAD:
		return
	Sfx.play(name, to_global(b.pos) + Vector3.UP * 0.15, -8.0 if name == "pigeon_coo" else -4.0)


func _air_flock(f: Flock, dt: float, eye: Vector3, k: Dictionary) -> void:
	var cruise: float = k.cruise
	var beat: float = k.beat
	var glide_share: float = k.glide
	# The leader: round the orbit, then down to the landing spot.
	f.air_left -= dt
	var leader := Vector3.ZERO
	var leader_v := Vector3.ZERO
	if not f.landing:
		f.orbit_a += f.orbit_dir * cruise / f.orbit_r * dt
		leader = f.orbit_c + Vector3(cos(f.orbit_a), 0.0, sin(f.orbit_a)) * f.orbit_r
		leader.y = f.orbit_h + sin(f.orbit_a * 1.7) * 1.5
		leader_v = Vector3(-sin(f.orbit_a), 0.0, cos(f.orbit_a)) * f.orbit_dir * cruise
		if f.air_left <= 0.0:
			_choose_landing(f, eye, k)
	var all_down := true
	var sum := Vector3.ZERO
	var alive := 0
	for i in f.birds.size():
		var b: Bird = f.birds[i]
		if b.mode == Mode.DEAD:
			continue
		alive += 1
		match b.mode:
			Mode.TAKEOFF:
				all_down = false
				b.delay -= dt
				if b.delay > 0.0:
					b.walk = 0.0
					sum += b.pos
					continue
				# Clap and climb: full beats, the body pitched up.
				b.spread = minf(b.spread + dt * 7.0, 1.0)
				b.amp = 1.0
				b.vel.y = maxf(b.vel.y - 4.0 * dt, 1.2)
				b.pos += b.vel * dt
				b.phase = fmod(b.phase + dt * beat * 1.2, 1.0)
				b.walk = 0.0
				b.peck = 0.0
				if b.pos.y > b.gy + 2.5 or b.spread >= 1.0 and b.pos.y > b.gy + 1.4:
					b.mode = Mode.FLY
			Mode.FLY:
				all_down = false
				var target := leader + b.offset
				var slot := -1
				if f.landing:
					slot = i % maxi(f.land_slots.size(), 1)
					target = f.land_slots[slot]
					var dh := (target - b.pos)
					dh.y = 0.0
					# Come in above the slot, then drop onto it.
					target.y += clampf(dh.length() * 0.35, 0.0, 12.0)
				var to := target - b.pos
				var desired := leader_v + to * 1.4
				if f.landing:
					desired = to * clampf(to.length() * 0.5, 1.2, cruise * 1.1) / maxf(to.length(), 0.01)
				if desired.length() > cruise * 1.35:
					desired = desired.normalized() * cruise * 1.35
				b.vel = b.vel.lerp(desired, minf(dt * 2.2, 1.0))
				b.pos += b.vel * dt
				b.spread = 1.0
				# Beat while climbing or slow, glide when level and fast enough.
				if _rng.randf() < dt * 0.6:
					b.glide = _rng.randf() < glide_share
				var climbing := b.vel.y > 0.8
				var want_amp := 1.0 if climbing or not b.glide or b.vel.length() < cruise * 0.6 else 0.0
				b.amp = move_toward(b.amp, want_amp, dt * 3.0)
				b.phase = fmod(b.phase + dt * beat * lerpf(0.6, 1.0, b.amp), 1.0)
				if f.landing and slot >= 0:
					var ls: Vector3 = f.land_slots[slot]
					if b.pos.distance_to(ls) < 1.4:
						b.mode = Mode.LAND
						b.target = ls
						b.t = 0.0
			Mode.LAND:
				all_down = all_down and true
				# The flare: wings beating hard, the body upright, onto the spot.
				b.t += dt
				var to := b.target - b.pos
				b.vel = b.vel.lerp(to * 3.0, minf(dt * 6.0, 1.0))
				b.pos += b.vel * dt
				b.amp = 1.0
				b.phase = fmod(b.phase + dt * beat * 1.3, 1.0)
				if to.length() < 0.04 or b.t > 1.6:
					b.pos = b.target
					b.vel = Vector3.ZERO
					b.gy = b.target.y
					b.mode = Mode.PERCH if f.land_perch else Mode.STAND
					b.t = _rng.randf_range(0.5, 2.5)
					var land_i := i % maxi(f.land_yaws.size(), 1)
					if f.land_yaws.size() > 0:
						b.yaw = float(f.land_yaws[land_i])
			_:
				pass
		if b.mode == Mode.STAND or b.mode == Mode.PERCH:
			b.spread = maxf(b.spread - dt * 5.0, 0.0)
			b.amp = maxf(b.amp - dt * 5.0, 0.0)
		else:
			all_down = false
		sum += b.pos
		# Face the way it flies, pitched with the climb, banked into the turn.
		if b.mode == Mode.TAKEOFF or b.mode == Mode.FLY or b.mode == Mode.LAND:
			var hv := Vector2(b.vel.x, b.vel.z)
			if hv.length() > 0.3:
				var want := atan2(-b.vel.x, -b.vel.z)
				var turn := wrapf(want - b.yaw, -PI, PI)
				b.yaw = lerp_angle(b.yaw, want, minf(dt * 5.0, 1.0))
				b.bank = lerpf(b.bank, clampf(-turn * 2.0, -0.8, 0.8), minf(dt * 4.0, 1.0))
			var up_pitch := atan2(b.vel.y, maxf(hv.length(), 0.5))
			if b.mode == Mode.LAND:
				up_pitch = 0.9
			b.pitch = lerpf(b.pitch, clampf(up_pitch, -0.6, 1.0), minf(dt * 4.0, 1.0))
		else:
			b.pitch = lerpf(b.pitch, 0.0, minf(dt * 6.0, 1.0))
			b.bank = lerpf(b.bank, 0.0, minf(dt * 6.0, 1.0))
	if alive > 0:
		f.center = sum / float(alive)
	if f.landing and all_down:
		f.state = FlockState.PERCHED if f.land_perch else FlockState.GROUND
		f.home = f.land_slots[0] if f.land_perch else f.home
		f.ground_y = f.home.y
		f.center = f.home
		f.landing = false
		if f.species != "sparrow" and eye.distance_to(f.home) < 60.0:
			Sfx.play("wings", to_global(f.home), -10.0)


## Where the flock comes down: a roof edge or a power line sometimes, the ground further off
## from the player otherwise, or back home if he has gone.
func _choose_landing(f: Flock, eye: Vector3, k: Dictionary) -> void:
	f.landing = true
	f.land_slots.clear()
	f.land_yaws.clear()
	f.land_perch = false
	var n := f.birds.size()
	var r := _rng.randf()
	var w := WorldState.to_world(to_global(f.center))
	var district := plan.district_at(Vector2(w.x, w.z))
	if f.species == "crow" or (f.species == "pigeon" and r < 0.3):
		var c := plan.block_index_at(Vector2(w.x, w.z))
		var spans := _wire_spans(c.x, c.y)
		if not spans.is_empty() and _rng.randf() < 0.75:
			var span: Array = spans[_rng.randi() % spans.size()]
			var a := _local(span[0])
			var b := _local(span[1])
			var dir := (b - a).normalized()
			var face := Vector3(-dir.z, 0.0, dir.x)
			for i in n:
				var t := clampf(0.5 + (float(i) - float(n - 1) * 0.5) * _rng.randf_range(0.02, 0.035), 0.08, 0.92)
				f.land_slots.append(wire_point(a, b, float(span[2]), t))
				f.land_yaws.append(atan2(-face.x, -face.z) + (PI if _rng.randf() < 0.5 else 0.0))
			f.land_perch = true
			f.home = (a + b) * 0.5
			return
	if f.species == "pigeon" and r < 0.55 and (district == CityPlan.District.DOWNTOWN or district == CityPlan.District.MIDTOWN):
		if _roof_edge(f, n):
			return
	# The ground: a few tries for open, level ground away from the player.
	for tries in 8:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(15.0, 45.0)
		var p := f.center + Vector3(cos(ang), 0.0, sin(ang)) * dist
		if Vector2(p.x - eye.x, p.z - eye.z).length() < 18.0:
			continue
		var wp := WorldState.to_world(to_global(p))
		var zone := plan.macro.zone_at(Vector2(wp.x, wp.z))
		if f.species == "gull":
			if zone != MacroMap.Zone.BEACH and zone != MacroMap.Zone.PORT:
				continue
		elif zone != MacroMap.Zone.CITY:
			continue
		if zone == MacroMap.Zone.CITY:
			var bi := plan.block_index_at(Vector2(wp.x, wp.z))
			if not (plan.block(bi.x, bi.y).rect as Rect2).has_point(Vector2(wp.x, wp.z)):
				continue # a carriageway
		p.y = f.ground_y + 2.0
		var y := _ground_at(p, 2.5)
		if is_nan(y):
			continue
		p.y = y
		_ground_slots(f, p, n)
		return
	# Home again (it may be where the player stands: then they will flush again, as real ones do).
	_ground_slots(f, Vector3(f.home.x, f.ground_y, f.home.z), n)


func _ground_slots(f: Flock, p: Vector3, n: int) -> void:
	f.home = p
	f.ground_y = p.y
	for i in n:
		var ang := _rng.randf() * TAU
		var rad := sqrt(_rng.randf()) * f.radius
		f.land_slots.append(p + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad))
		f.land_yaws.append(_rng.randf() * TAU)


## A roof edge near the flock: a ray down onto a roof, then out to where it ends; the birds line
## up along it facing out over the street.
func _roof_edge(f: Flock, n: int) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	for tries in 6:
		var ang := _rng.randf() * TAU
		var p := f.center + Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(10.0, 35.0)
		var g := to_global(p)
		var street := _street_y(g)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(g.x, street + 120.0, g.z), Vector3(g.x, street - 2.0, g.z), 1))
		if hit.is_empty() or (hit.normal as Vector3).y < 0.9:
			continue
		var roof: float = (hit.position as Vector3).y
		if roof - street < 5.0 or roof - street > 70.0:
			continue
		for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var q := Vector3(g.x, roof, g.z)
			var last := q
			var found := false
			for s in 24:
				q += dir * 0.6
				var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 2.0, q - Vector3.UP * 2.5, 1))
				if h.is_empty() or (h.position as Vector3).y < roof - 1.0:
					found = true
					break
				if absf((h.position as Vector3).y - roof) > 0.6:
					break
				last = Vector3(q.x, (h.position as Vector3).y, q.z)
			if not found:
				continue
			var edge := last - dir * 0.15
			var along := Vector3(-dir.z, 0.0, dir.x)
			var yaw := atan2(-dir.x, -dir.z)
			for i in n:
				var o := (float(i) - float(n - 1) * 0.5) * _rng.randf_range(0.26, 0.4)
				f.land_slots.append(to_local(edge + along * o))
				f.land_yaws.append(yaw + _rng.randf_range(-0.4, 0.4))
			f.land_perch = true
			f.home = to_local(edge)
			return true
	return false


# --- Death ------------------------------------------------------------------------------------

## The first bird a shot from `from` to `to` (global) passes through, if any: it dies. Called by
## every gun's hit path; true when a bird was hit.
static func hit_ray(from: Vector3, to: Vector3) -> bool:
	if _live == null or not _live.enabled:
		return false
	return _live._hit(from, to)


func _hit(from_g: Vector3, to_g: Vector3) -> bool:
	var a := to_local(from_g)
	var b := to_local(to_g)
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-6:
		return false
	var best: Bird = null
	var best_f: Flock = null
	var best_t := INF
	for f: Flock in _flocks.values():
		# The flock as a whole first.
		var c := f.center if f.state == FlockState.AIR else f.home
		var tc := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		var spread := f.radius + (30.0 if f.state == FlockState.AIR else 2.0)
		if (a + ab * tc).distance_to(c) > spread:
			continue
		var hr: float = KINDS[f.species].hit
		for bird: Bird in f.birds:
			if bird.mode == Mode.DEAD:
				continue
			var body := bird.pos + Vector3.UP * (0.12 * bird.scale if bird.spread < 0.5 else 0.0) * (2.0 if f.species == "gull" else 1.0)
			var t := clampf((body - a).dot(ab) / len2, 0.0, 1.0)
			if (a + ab * t).distance_to(body) < hr * (1.4 if bird.spread > 0.5 else 1.0) and t < best_t:
				best_t = t
				best = bird
				best_f = f
	if best == null:
		return false
	_kill(best_f, best, ab.normalized())
	return true


func _kill(f: Flock, b: Bird, dir: Vector3) -> void:
	kills += 1
	f.birds.erase(b)
	b.mode = Mode.DEAD
	b.vel = dir * 3.0 + Vector3.UP * 1.0 + b.vel * 0.5
	b.amp = 0.0
	b.spread = 0.6
	b.life = corpse_seconds
	b.roll = 0.0
	var ground := _ground_at(Vector3(b.pos.x, maxf(f.ground_y, b.pos.y), b.pos.z), 60.0)
	b.gy = ground if not is_nan(ground) else f.ground_y
	_dead.append(b)
	_feathers(to_global(b.pos), b.species)
	if f.state != FlockState.AIR:
		_flush(f, b.pos)


func _blasted(at: Vector3) -> void:
	for f: Flock in _flocks.values():
		var c := f.center if f.state == FlockState.AIR else f.home
		if c.distance_to(at) > 60.0:
			continue
		for b: Bird in f.birds.duplicate():
			if b.mode != Mode.DEAD and b.pos.distance_to(at) < 7.0:
				_kill(f, b, (b.pos - at).normalized())
		_flush(f, at)


func _tick_dead(dt: float) -> void:
	for i in range(_dead.size() - 1, -1, -1):
		var b: Bird = _dead[i]
		b.life -= dt
		if b.life <= 0.0:
			_dead.remove_at(i)
			continue
		if b.pos.y > b.gy + 0.01 or b.vel.length_squared() > 0.01:
			b.vel.y -= 9.8 * dt
			b.vel *= 1.0 - minf(dt * 0.6, 0.5)
			b.pos += b.vel * dt
			b.roll += dt * 9.0
			b.spread = 0.5 + 0.3 * sin(b.roll * 1.3)
			if b.pos.y <= b.gy:
				b.pos.y = b.gy
				b.vel = Vector3.ZERO
				b.roll = PI * 0.5 * (1.0 if b.offset.x > 0.0 else -1.0)
				b.spread = 0.35
		b.amp = 0.0


## A puff of feathers where a bird was hit: the species' own covert feathers, tumbling down.
func _feathers(at: Vector3, sp: String) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 22 if sp != "sparrow" else 10
	p.lifetime = 3.2
	p.local_coords = false
	var quad := QuadMesh.new()
	var s := 0.05 if sp == "gull" else (0.022 if sp == "sparrow" else 0.035)
	quad.size = Vector2(s * 0.6, s)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(BirdMesh.TEXTURE_DIR + sp + "_albedo.png")
	var slot: Rect2 = BirdMesh.SLOTS["COV_M"]
	mat.uv1_scale = Vector3(slot.size.x / BirdMesh.ATLAS, slot.size.y / BirdMesh.ATLAS, 1.0)
	mat.uv1_offset = Vector3(slot.position.x / BirdMesh.ATLAS, slot.position.y / BirdMesh.ATLAS, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.roughness = 0.8
	quad.material = mat
	p.mesh = quad
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0.0, -0.9, 0.0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.emitting = true
	get_parent().add_child(p)
	p.global_position = at
	var timer := get_tree().create_timer(p.lifetime + 0.5, false)
	timer.timeout.connect(p.queue_free)


# --- Drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := to_local(cam.global_position) if cam else _player_local()
	for key: String in _mm:
		_buf[key] = PackedFloat32Array()
		_count[key] = 0
		_bounds[key] = AABB()
	for f: Flock in _flocks.values():
		var k: Dictionary = KINDS[f.species]
		for b: Bird in f.birds:
			_put(f.species, k, b, eye)
	for b: Bird in _dead:
		_put(b.species, KINDS[b.species], b, eye)
	for key: String in _mm:
		var mmi: MultiMeshInstance3D = _mm[key]
		var mm := mmi.multimesh
		var n: int = _count[key]
		var buf: PackedFloat32Array = _buf[key]
		if n == 0:
			mm.visible_instance_count = 0
			mmi.visible = false
			continue
		if mm.instance_count < n:
			mm.instance_count = 0
			mm.instance_count = int(ceil(float(n) / 16.0)) * 16
		var cap := mm.instance_count
		if buf.size() < cap * 20:
			var pad := PackedFloat32Array()
			pad.resize(cap * 20 - buf.size())
			buf.append_array(pad)
		mm.buffer = buf
		mm.visible_instance_count = n
		var bb: AABB = _bounds[key]
		mmi.custom_aabb = bb.grow(1.0)
		mmi.visible = true


func _put(sp: String, k: Dictionary, b: Bird, eye: Vector3) -> void:
	var d := b.pos.distance_to(eye)
	if d > draw_distance:
		return
	var lod := 0 if d < float(k.near) else (1 if d < float(k.mid) else 2)
	var key := "%s:%d" % [sp, lod]
	var basis := Basis.from_euler(Vector3(b.pitch, b.yaw, b.bank), EULER_ORDER_YXZ)
	if b.mode == Mode.DEAD:
		basis = Basis.from_euler(Vector3(b.pitch, b.yaw, b.roll), EULER_ORDER_YXZ)
	basis = basis.scaled(Vector3.ONE * b.scale)
	var buf: PackedFloat32Array = _buf[key]
	var o := b.pos
	buf.append_array([basis.x.x, basis.y.x, basis.z.x, o.x,
		basis.x.y, basis.y.y, basis.z.y, o.y,
		basis.x.z, basis.y.z, basis.z.z, o.z,
		b.tint.r, b.tint.g, b.tint.b, b.amp,
		b.spread, b.phase, b.peck, b.walk])
	_buf[key] = buf
	_count[key] = int(_count[key]) + 1
	var bb: AABB = _bounds[key]
	if int(_count[key]) == 1:
		bb = AABB(o, Vector3.ZERO)
	else:
		bb = bb.expand(o)
	_bounds[key] = bb


func _draw_nothing() -> void:
	for key: String in _mm:
		(_mm[key] as MultiMeshInstance3D).visible = false


# --- For other systems and the checks -----------------------------------------------------------

## Pedestrian.alarm() calls this for every gunshot, blast and police round: every flock within
## `radius` (a little more: birds startle further than people) goes up.
static func startle(at_global: Vector3, radius: float) -> void:
	if _live == null or not _live.enabled or not _live.is_inside_tree():
		return
	var at := _live.to_local(at_global)
	var r := radius * 1.3
	for f: Flock in _live._flocks.values():
		if f.state != FlockState.AIR and f.home.distance_to(at) < r:
			_live._flush(f, at)


## Somewhere a real gull is within `reach` of global point `eye`, for Ambience's gull calls (so
## the calls come from the birds); Vector3.INF when there is none.
static func gull_at(eye_global: Vector3, reach: float) -> Vector3:
	if _live == null or not _live.enabled or not _live.is_inside_tree():
		return Vector3.INF
	var eye := _live.to_local(eye_global)
	var pick := Vector3.INF
	var seen := 0
	for f: Flock in _live._flocks.values():
		if f.species != "gull" or f.birds.is_empty():
			continue
		var c := f.center if f.state == FlockState.AIR else f.home
		if c.distance_to(eye) > reach:
			continue
		seen += 1
		if _live._rng.randi() % seen == 0:
			var b: Bird = f.birds[_live._rng.randi() % f.birds.size()]
			pick = _live.to_global(b.pos + Vector3.UP * 0.4)
	return pick


## The live node, its flocks and counts (tests, stills).
static func live() -> Birds:
	return _live


func flock_count() -> int:
	return _flocks.size()


func bird_count() -> int:
	return _bird_total()


## Every flock as {"species", "state", "home" (global), "count"} (tests, stills).
func flocks_info() -> Array:
	var out: Array = []
	for f: Flock in _flocks.values():
		out.append({"id": f.id, "species": f.species, "state": f.state, "home": to_global(f.home), "count": f.birds.size(), "center": to_global(f.center)})
	return out


## Puts a flock at a global point now (stills and tests): `kind` "ground" or "wire".
func stage(species: String, at_global: Vector3, count: int, radius: float = 4.0) -> int:
	var w := WorldState.to_world(at_global)
	var id := hash(["staged", species, int(w.x), int(w.z)])
	var f := _spawn({"id": id, "at": Vector2(w.x, w.z), "y": w.y, "species": species, "count": count, "kind": "ground", "radius": radius})
	if f == null:
		return 0
	_flocks[id] = f
	return id


## Stages birds for a still (tools/glshot/still_shot.gd BIRD=...): `kind` "ground" puts a flock
## `dist` metres ahead of `cam` on the ground, "flush" does that and flushes it from the camera,
## letting `fly` seconds pass, "wire" seats crows on the power span nearest that point. Returns
## the flock's id (0 when nothing was found).
func stage_for_shot(kind: String, cam: Camera3D, dist: float, species: String, count: int, fly: float) -> int:
	if not _setup():
		return 0
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := cam.global_position + fwd * dist
	if kind == "wire":
		var w := WorldState.to_world(at)
		var c := plan.block_index_at(Vector2(w.x, w.z))
		var best: Array = []
		var best_d := INF
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for span: Array in _wire_spans(c.x + dx, c.y + dz):
					var mid: Vector3 = (span[0] as Vector3).lerp(span[1], 0.5)
					var d := Vector2(mid.x - w.x, mid.z - w.z).length()
					if d < best_d:
						best_d = d
						best = span
		if best.is_empty():
			print("BIRD: no power line near ", w)
			return 0
		var mid_w: Vector3 = (best[0] as Vector3).lerp(best[1], 0.5)
		var id := hash(["staged_wire", int(mid_w.x), int(mid_w.z)])
		var f := _spawn({"id": id, "at": Vector2(mid_w.x, mid_w.z), "species": species if species != "" else "crow", "count": count, "kind": "wire", "radius": 3.0, "wire": best})
		if f == null:
			print("BIRD: the span at ", mid_w, " has no pole standing")
			return 0
		_flocks[id] = f
		print("BIRD wire flock at world ", mid_w, " span ", best[0], " -> ", best[1])
		return id
	var sp := species if species != "" else "pigeon"
	var id := 0
	for tries in 12:
		var p := at + Vector3(cos(tries * 2.1), 0.0, sin(tries * 2.1)) * float(tries) * 1.5
		id = stage(sp, p, count, 3.0 + float(count) * 0.08)
		if id != 0:
			break
	if id == 0:
		print("BIRD: no open ground near ", WorldState.to_world(at))
		return 0
	print("BIRD %s flock of %d at world %s" % [sp, count, WorldState.to_world(to_global(_flocks[id].home))])
	if kind == "flush":
		flush_flock(id, cam.global_position)
		advance(fly)
	else:
		advance(maxf(fly, 0.5))
	return id


## Flushes the flock with `id` as if the player had walked into it at `from_global`.
func flush_flock(id: int, from_global: Vector3) -> void:
	if _flocks.has(id):
		_flush(_flocks[id], to_local(from_global))


## Moves every simulated flock `seconds` on (tests and stills: minutes of flight in a frame).
func advance(seconds: float, step: float = 1.0 / 30.0) -> void:
	if not _setup():
		return
	var eye := _player_local()
	var t := 0.0
	while t < seconds:
		_frame += 1
		for f: Flock in _flocks.values():
			_tick_flock(f, step, eye)
		_tick_dead(step)
		t += step
	_draw()


static func _hash01(key: Array) -> float:
	return float(absi(hash(key)) % 100000) / 100000.0
