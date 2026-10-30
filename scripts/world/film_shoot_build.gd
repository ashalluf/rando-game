class_name FilmShootBuild
extends RefCounted
## Lays a film shoot (FilmShoot) out in the chunk that owns its street: the steps a block adds
## (CityChunk._block_steps(), one hook line after the farmers' market's). FULL: the closure
## (barricades, cones, the arrow sign), the notices down both kerbs, the basecamp (trailers, the
## grip and electric trucks with their lift gates and carts, the generator, the catering tent),
## the set (track and dolly, the crane, HMIs, the balloon light, flags and bounces, video village,
## piles of kit, cables), the lettering (ONE detail mesh a chunk), the lights after dark, then the
## crew in black (FilmCrew), the actors on their marks and the extras in holding (FilmExtra), each
## a build step and in the crowd cap. LOD: the trailers, trucks, tent and balloon. The far city's
## capture: nothing (a trailer is a few pixels from there). Static: call with the chunk.

## How far the pieces draw (m) and cast shadows.
const BIG_DRAW := 360.0
const SET_DRAW := 170.0
const SMALL_DRAW := 110.0
const DETAIL_DRAW := 90.0
const SHADOW_REACH := 70.0
## The grip / electric trucks' paints.
const TRUCK_PAINTS := [Color(0.93, 0.93, 0.91), Color(0.93, 0.93, 0.91), Color(0.82, 0.83, 0.84), Color(0.18, 0.2, 0.24)]
## The balloon's light and the fill at the action after dark (desktop only; DayNight sets the energy).
const BALLOON_RANGE := 26.0
const FILL_RANGE := 13.0

static var _bodies: Dictionary = {}


## The steps of chunk `ch`'s shoot, or none.
static func steps(ch: CityChunk, _block: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	if ch.capturing or not FilmShoot.enabled:
		return out
	var m := FilmShoot.shoot_of_chunk(ch.plan, ch.ix, ch.iz)
	if m.is_empty():
		return out
	ch.market_road = m.rect
	if ch.level != CityChunk.Level.FULL:
		out.append(func() -> void: build_lod(ch, m))
		return out
	out.append(func() -> void: build(ch, m))
	var lay := FilmShoot.layout(m)
	for i in (lay.crew as Array).size():
		out.append(func() -> void: spawn_crew(ch, m, i))
	for i in 2:
		out.append(func() -> void: spawn_actor(ch, m, i))
	for i in FilmShoot.MAX_EXTRAS:
		out.append(func() -> void: spawn_extra(ch, m, i))
	return out


## A transform at (t, o) on the shoot's street, its +z toward the street direction `face` (t, o).
static func xf_at(m: Dictionary, t: float, o: float, face: Vector2) -> Transform3D:
	var p := FilmShoot.point(m, t, o)
	var d := FilmShoot.dirs(m)
	var w: Vector2 = d[0] * face.x + d[1] * face.y
	var z3 := Vector3(w.x, 0.0, w.y).normalized()
	if z3.length_squared() < 0.5:
		z3 = Vector3.BACK
	return Transform3D(Basis(Vector3.UP.cross(z3), Vector3.UP, z3), Vector3(p.x, CityChunk.ROAD_TOP, p.y))


static func build_lod(ch: CityChunk, m: Dictionary) -> void:
	var lay := FilmShoot.layout(m)
	_camp(ch, m, lay, false)
	var b: Dictionary = lay.balloon
	ch._batch.add("fs_balloon", FilmShootKit.balloon(), xf_at(m, float(b.t), float(b.o), Vector2(1, 0)))
	for k: String in ch._batch.keys():
		if k.begins_with("fs_"):
			ch._batch.set_no_shadow(k)


## Everything a FULL chunk draws of its shoot.
static func build(ch: CityChunk, m: Dictionary) -> void:
	var lay := FilmShoot.layout(m)
	var d := FarmersMarketBuild.Detail.new(ch)
	var cs := float(m.camp_side)
	var ss := -cs
	_ends(ch, m, lay, d)
	_notices(ch, m, lay, d)
	_camp(ch, m, lay, true)
	# The set.
	var tr: Dictionary = lay.track
	var tmid := (float(tr.t0) + float(tr.t1)) * 0.5
	ch._batch.add("fs_track", FilmShootKit.track(FilmShoot.TRACK_LEN), xf_at(m, tmid, float(tr.o), Vector2(0, 1)))
	ch._batch.add("fs_dolly", FilmShootKit.dolly(), xf_at(m, float(lay.dolly_t), float(tr.o), Vector2(0, ss)) * Transform3D(Basis(), Vector3(0, 0.1, 0)))
	var cr: Dictionary = lay.crane
	var act: Dictionary = lay.action
	var to_act := Vector2(float(act.t) - float(cr.t), float(act.o) - float(cr.o)).normalized()
	var cxf := xf_at(m, float(cr.t), float(cr.o), to_act)
	ch._batch.add("fs_crane", FilmShootKit.crane(), cxf)
	ch._add_shape(Vector3(1.6, 1.6, 1.6), cxf.origin + Vector3(0, 0.8 + ch._gy(cxf.origin.x, cxf.origin.z), 0))
	var n := 0
	for h: Dictionary in lay.hmis:
		_item(ch, "fs_hmi", FilmShootKit.hmi(), xf_at(m, float(h.t), float(h.o), h.aim), "hmi_%d" % n, Vector3(1.2, 3.9, 1.2), 1.95, 90.0)
		n += 1
	var bl: Dictionary = lay.balloon
	_item(ch, "fs_balloon", FilmShootKit.balloon(), xf_at(m, float(bl.t), float(bl.o), Vector2(1, 0)), "balloon", Vector3(1.4, 7.4, 1.4), 3.7, 70.0)
	n = 0
	for f: Dictionary in lay.flags:
		_item(ch, "fs_flag", FilmShootKit.c_stand(false), xf_at(m, float(f.t), float(f.o), f.aim), "flag_%d" % n, Vector3(0.9, 2.9, 0.9), 1.45, 40.0)
		n += 1
	n = 0
	for f: Dictionary in lay.bounces:
		_item(ch, "fs_bounce", FilmShootKit.c_stand(true), xf_at(m, float(f.t), float(f.o), f.aim), "bounce_%d" % n, Vector3(0.9, 2.9, 0.9), 1.45, 40.0)
		n += 1
	var vl: Dictionary = lay.village
	var vxf := xf_at(m, float(vl.t), float(vl.o), Vector2(0, -cs))
	# Video village: the monitors face the chairs (+z of the piece away from the set), under a
	# black pop-up (the farmers' market's canopy in black canvas).
	_item(ch, "fs_village", FilmShootKit.village(), vxf, "village", Vector3(2.4, 1.6, 2.0), 0.8, 60.0)
	ch._batch.add("fs_popup", FarmersMarketKit.canopy(), vxf * Transform3D(Basis(), Vector3(0, 0, -0.2)), Color.WHITE, Color(0.05, 0.05, 0.055))
	ch._batch.add("fs_pile", FilmShootKit.kit_pile(), xf_at(m, tmid - 3.0, float(tr.o) - ss * 1.6, Vector2(0, ss)))
	ch._batch.add("fs_pile", FilmShootKit.kit_pile(), xf_at(m, float(cr.t) + 2.5, float(cr.o) - ss * 2.2, Vector2(1, 0)))
	# Cables from the power to the lights.
	for line: Array in lay.cables:
		_cable(ch, m, d, line)
	d.commit("FilmShootDetail")
	# The detail mesh is FarmersMarketBuild's; its surfaces wear this kit's shader (the codes here).
	var dm := ch.get_node_or_null("FilmShootDetail") as MeshInstance3D
	if dm != null:
		for si in dm.mesh.get_surface_count():
			dm.mesh.surface_set_material(si, FilmShootKit.material())
	_lights(ch, m, lay)
	for k: String in ch._batch.keys():
		if not k.begins_with("fs_"):
			continue
		if k.begins_with("fs_trailer") or k.begins_with("fs_truck") or k == "fs_balloon" or k == "fs_catering" or k == "fs_crane":
			ch._batch.set_draw_distance(k, BIG_DRAW)
		elif k == "fs_cone" or k == "fs_notice" or k == "fs_pile" or k == "fs_track":
			ch._batch.set_draw_distance(k, SMALL_DRAW)
		else:
			ch._batch.set_draw_distance(k, SET_DRAW)
		ch._batch.set_shadow_reach(k, SHADOW_REACH)


## The basecamp: trailers, trucks (and their tails), the generator, the catering tent.
static func _camp(ch: CityChunk, m: Dictionary, lay: Dictionary, full: bool) -> void:
	var cs := float(m.camp_side)
	for i in (lay.camp as Array).size():
		var c: Dictionary = lay.camp[i]
		var kind := String(c.kind)
		var t := float(c.t)
		var o := float(c.o)
		var length := float(c.len)
		if kind == "honeywagon" or kind == "cast":
			var mesh := FilmShootKit.trailer(length, kind == "honeywagon")
			var xf := xf_at(m, t, o, Vector2(0, -cs))
			ch._batch.add("fs_trailer_%s_%.1f" % [kind, length], mesh, xf)
			if full:
				ch._add_shape_xf(Vector3(length, 3.0, 2.55), Transform3D(xf.basis, xf.origin + Vector3(0, 2.45 + ch._gy(xf.origin.x, xf.origin.z), 0)))
		elif kind == "genny":
			# The tongue (+x) toward the trailers it was towed in behind.
			var gxf := xf_x(m, t, o, Vector2(float(c.dir), 0.0))
			ch._batch.add("fs_genny", FilmShootKit.genny(), gxf)
			if full:
				ch._add_shape_xf(Vector3(3.4, 2.2, 1.9), Transform3D(gxf.basis, gxf.origin + Vector3(0, 1.1 + ch._gy(gxf.origin.x, gxf.origin.z), 0)))
		else:
			_truck(ch, m, c, kind == "electric", full)
	var tent: Dictionary = lay.tent
	var txf := xf_at(m, float(tent.t), float(tent.o), Vector2(0, -cs))
	ch._batch.add("fs_catering", FilmShootKit.catering(), txf)


## A transform at (t, o) whose +x runs along the street direction `xdir` (t, o).
static func xf_x(m: Dictionary, t: float, o: float, xdir: Vector2) -> Transform3D:
	var p := FilmShoot.point(m, t, o)
	var d := FilmShoot.dirs(m)
	var w: Vector2 = d[0] * xdir.x + d[1] * xdir.y
	var x3 := Vector3(w.x, 0.0, w.y).normalized()
	return Transform3D(Basis(x3, Vector3.UP, x3.cross(Vector3.UP)), Vector3(p.x, CityChunk.ROAD_TOP, p.y))


## A grip or electric truck: the box truck's far body parked along the kerb, nose toward the
## basecamp's direction, its lift gate down behind it with the carts.
static func _truck(ch: CityChunk, m: Dictionary, c: Dictionary, electric: bool, full: bool) -> void:
	var paint := int(c.paint) % TRUCK_PAINTS.size()
	var body := body_mesh(Vehicle.BodyType.BOX_TRUCK, paint)
	var p := FilmShoot.point(m, float(c.t), float(c.o))
	var along: Vector2 = FilmShoot.dirs(m)[0] * float(c.dir)
	var fwd := Vector3(along.x, 0.0, along.y)
	var length := float(c.len)
	if not body.is_empty():
		var basis := Basis.looking_at(-fwd if bool(body.flip) else fwd, Vector3.UP)
		var xf := Transform3D(basis, Vector3(p.x, CityChunk.ROAD_TOP, p.y)) * Transform3D(Basis(), body.offset)
		ch._batch.add("fs_truck_%d" % paint, body.mesh, xf)
		var size: Vector3 = body.size
		length = maxf(size.x, size.z)
		if full:
			ch._add_shape(Vector3(size.x, size.y, size.z) if not bool(body.length_x) else Vector3(size.z, size.y, size.x),
				Vector3(p.x, CityChunk.ROAD_TOP + size.y * 0.5 + ch._gy(p.x, p.y), p.y), atan2(fwd.x, fwd.z))
	if not full:
		return
	# The tail at the back bumper, +x away from the truck.
	var back := -fwd
	var rear := Vector3(p.x, CityChunk.ROAD_TOP, p.y) + back * length * 0.5
	var basis2 := Basis(back, Vector3.UP, back.cross(Vector3.UP))
	ch._batch.add("fs_tail_%s" % electric, FilmShootKit.truck_tail(electric), Transform3D(basis2, rear))


## The road bodies' far twin (FarmersMarketBuild.van_mesh()'s way) for any body type, painted.
static func body_mesh(type: int, paint: int) -> Dictionary:
	var key := "%d_%d" % [type, paint]
	if _bodies.has(key):
		return _bodies[key]
	var out := {}
	_bodies[key] = out
	var path: String = Vehicle.BODY_MODELS.get(type, "")
	if path == "" or not ResourceLoader.exists(path):
		return out
	var inst := (load(path) as PackedScene).instantiate()
	var far: ArrayMesh = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if String((mi as MeshInstance3D).name).ends_with("_far"):
			far = (mi as MeshInstance3D).mesh as ArrayMesh
	inst.free()
	if far == null or far.get_surface_count() == 0:
		return out
	var mesh := far.duplicate() as ArrayMesh
	var box := far.get_aabb()
	for si in mesh.get_surface_count():
		var src := mesh.surface_get_material(si) as StandardMaterial3D
		if src == null:
			continue
		if String(src.resource_name).begins_with("paint"):
			mesh.surface_set_material(si, FarmersMarketBuild._paint(src, box, TRUCK_PAINTS[paint]))
		else:
			var pm := Vehicle._part_material(src)
			if pm != null:
				mesh.surface_set_material(si, pm)
	out.mesh = mesh
	var shadow := BoxMesh.new()
	shadow.size = box.size * Vector3(0.92, 0.94, 0.97)
	var sm := ArrayMesh.new()
	var sarr := shadow.get_mesh_arrays()
	var verts: PackedVector3Array = sarr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += box.get_center() - Vector3(0.0, box.size.y * 0.03, 0.0)
	sarr[Mesh.ARRAY_VERTEX] = verts
	sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sarr)
	PropFactory._shadow_proxies[mesh] = sm
	out.offset = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	out.length_x = box.size.x > box.size.z
	out.size = box.size
	out.flip = true
	return out


## A knockable piece (an EncampmentItem over its batch instance): blown over or hit by a car it
## flies off as a real body and stays gone (WorldState).
static func _item(ch: CityChunk, key: String, mesh: Mesh, xf: Transform3D, id: String, size: Vector3, centre_y: float, mass: float) -> void:
	var item_id := "fs_" + id
	if WorldState.is_destroyed(ch.key, item_id):
		return
	var idx := ch._batch.add(key, mesh, xf)
	var item := EncampmentItem.new()
	item.name = "FilmShoot_%s" % id
	item.chunk = ch
	item.item_id = item_id
	item.instances = [[key, idx]]
	item.mesh = mesh
	item.mass_kg = mass
	item.health = 80.0
	item.setup(size, centre_y)
	item.transform = Transform3D(xf.basis, xf.origin + Vector3(0.0, ch._gy(xf.origin.x, xf.origin.z), 0.0))
	ch.add_child(item)


## Both ends: a row of barricades across the street with cones in front, the yellow arrow sign
## and a notice "STREET CLOSED FOR FILMING" by the kerb.
static func _ends(ch: CityChunk, m: Dictionary, lay: Dictionary, d: FarmersMarketBuild.Detail) -> void:
	var half := float(m.width) * 0.5
	for end in 2:
		var t := float(lay.ends[end])
		var out_dir := -1.0 if end == 0 else 1.0
		var n := maxi(2, int((half * 2.0 - 2.0) / 2.7))
		for k in n:
			var o := lerpf(-half + 1.6, half - 1.6, (float(k) + 0.5) / float(n)) if n > 1 else 0.0
			# The middle gap for the crew's carts: the barricade there stands turned aside.
			var turned := k == n / 2 and n >= 3
			var face := Vector2(out_dir, 0.0)
			var xf := xf_at(m, t + (0.8 * out_dir if turned else 0.0), o, face)
			if turned:
				xf = xf * Transform3D(Basis(Vector3.UP, 0.6), Vector3.ZERO)
			_item(ch, "fs_barricade", FilmShootKit.barricade(), xf, "bar_%d_%d" % [end, k], Vector3(2.5, 1.6, 0.6), 0.8, 30.0)
		for k in 4:
			var o := lerpf(-half + 1.0, half - 1.0, (float(k) + 0.5) / 4.0)
			ch._batch.add("fs_cone", FilmShootKit.cone(), xf_at(m, t + out_dir * 2.4, o, Vector2(out_dir, 0)))
		# The arrow sign at the right-hand kerb as you come up to the closure, pointing in.
		var side := 1.0 if end == 0 else -1.0
		var sxf := xf_at(m, t + out_dir * 1.0, side * (half + 0.6), Vector2(out_dir, 0.0))
		ch._batch.add("fs_arrow", FilmShootKit.arrow_sign(), sxf)
		_arrow_text(d, ch, sxf, m)


static func _arrow_text(d: FarmersMarketBuild.Detail, ch: CityChunk, xf0: Transform3D, m: Dictionary) -> void:
	var xf := Transform3D(xf0.basis, xf0.origin + Vector3(0, ch._gy(xf0.origin.x, xf0.origin.z), 0))
	var black := Color(0.05, 0.05, 0.05, 0.0)
	d._text(xf * Transform3D(Basis(), Vector3(-0.08, 2.27, 0.005)), String(m.code), 0.22, black, 0.5)
	d._text(xf * Transform3D(Basis(), Vector3(0.26, 2.25, 0.005)), ">", 0.28, black, 0.2)
	var red := Color(0.7, 0.06, 0.04, 0.0)
	d._text(xf * Transform3D(Basis(), Vector3(0.0, 1.76, 0.005)), "STREET CLOSED", 0.07, red, 0.56)
	d._text(xf * Transform3D(Basis(), Vector3(0.0, 1.64, 0.005)), "FOR FILMING", 0.07, red, 0.56)
	d._text(xf * Transform3D(Basis(), Vector3(0.0, 1.52, 0.005)), "LOCAL ACCESS ONLY", 0.045, black, 0.56)


## The orange notices on posts down both kerbs (on the pavement's edge, facing the road).
static func _notices(ch: CityChunk, m: Dictionary, lay: Dictionary, d: FarmersMarketBuild.Detail) -> void:
	var half := float(m.width) * 0.5
	for nt: Dictionary in lay.notices:
		var side := float(nt.side)
		var xf := xf_at(m, float(nt.t), side * (half + 0.45), Vector2(0, -side))
		ch._batch.add("fs_notice", FilmShootKit.notice(), xf)
		var lx := Transform3D(xf.basis, xf.origin + Vector3(0, ch._gy(xf.origin.x, xf.origin.z), 0))
		var black := Color(0.04, 0.04, 0.04, 0.0)
		d._text(lx * Transform3D(Basis(), Vector3(0, 1.92, 0.005)), "NOTICE", 0.07, black, 0.38)
		d._text(lx * Transform3D(Basis(), Vector3(0, 1.83, 0.005)), "FILMING IN PROGRESS", 0.03, black, 0.38)
		d._text(lx * Transform3D(Basis(), Vector3(0, 1.74, 0.005)), String(m.title), 0.034, black, 0.38)
		d._text(lx * Transform3D(Basis(), Vector3(0, 1.66, 0.005)), String(m.company), 0.02, black, 0.38)
		d._text(lx * Transform3D(Basis(), Vector3(0, 1.56, 0.005)), "TEMPORARY", 0.03, black, 0.38)
		d._text(lx * Transform3D(Basis(), Vector3(0, 1.51, 0.005)), "NO PARKING - TOW AWAY", 0.026, Color(0.6, 0.05, 0.03, 0.0), 0.38)
		d._text(lx * Transform3D(Basis(), Vector3(0, 1.45, 0.005)), "6 AM - 2 AM", 0.024, black, 0.38)


## A cable along the road, a run of tube from point to point a hair above the asphalt.
static func _cable(ch: CityChunk, m: Dictionary, d: FarmersMarketBuild.Detail, line: Array) -> void:
	var prev := Vector3.ZERO
	var first := true
	var black := FilmShootKit.col(Color(0.03, 0.03, 0.03), FilmShootKit.C_RUBBER)
	for q: Vector2 in line:
		var p2 := FilmShoot.point(m, q.x, q.y)
		var p := Vector3(p2.x, CityChunk.ROAD_TOP + 0.022 + ch._gy(p2.x, p2.y), p2.y)
		if not first:
			d.g.tube(prev, p, 0.014, 5, black, Vector2(0.8, 0.0))
		prev = p
		first = false


## After dark: an OmniLight in the balloon and a fill at the action (desktop only; DayNight sets
## their energy with the street lamps' and hides them by day).
static func _lights(ch: CityChunk, m: Dictionary, lay: Dictionary) -> void:
	if OS.has_feature("web"):
		return
	var bl: Dictionary = lay.balloon
	var act: Dictionary = lay.action
	for spec: Array in [[FilmShoot.point(m, float(bl.t), float(bl.o)), FilmShootKit.BALLOON_Y, BALLOON_RANGE, Color(1.0, 0.96, 0.88), "FilmBalloonLight"],
			[FilmShoot.point(m, float(act.t), float(act.o) * 0.82), 4.0, FILL_RANGE, Color(0.86, 0.92, 1.0), "FilmFillLight"]]:
		var p: Vector2 = spec[0]
		var l := OmniLight3D.new()
		l.name = spec[4]
		l.omni_range = float(spec[2])
		l.omni_attenuation = 1.2
		l.light_color = spec[3]
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 150.0
		l.distance_fade_length = 40.0
		l.position = Vector3(p.x, CityChunk.ROAD_TOP + float(spec[1]) + ch._gy(p.x, p.y), p.y)
		l.add_to_group("lamp_light")
		ch.add_child(l)


# --- People ------------------------------------------------------------------------------------

static func _yaw_of(m: Dictionary, face: Vector2) -> float:
	var d := FilmShoot.dirs(m)
	var w: Vector2 = d[0] * face.x + d[1] * face.y
	return atan2(-w.x, -w.y)


## The `index`-th crew member at their post, in black, under the crowd cap.
static func spawn_crew(ch: CityChunk, m: Dictionary, index: int) -> void:
	var lay := FilmShoot.layout(m)
	var c: Dictionary = lay.crew[index]
	if not ch._take_crowd_room():
		return
	var ped := FilmCrew.new()
	var at := FilmShoot.point(m, float(c.t), float(c.o))
	ped.role = String(c.role)
	ped.setup_vendor(ch.plan.block(ch.ix, ch.iz).rect, hash([ch.plan.seed, m.seed, index, "crew"]), at, _yaw_of(m, c.aim), false, 0.0)
	ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + 0.05, at.y)
	ch.add_child(ped)


## The actors on their marks on the set side's pavement, facing each other.
static func spawn_actor(ch: CityChunk, m: Dictionary, index: int) -> void:
	var lay := FilmShoot.layout(m)
	var a: Dictionary = lay.actors[index]
	if not ch._take_crowd_room():
		return
	var ped := StreetVendor.new()
	var at := FilmShoot.point(m, float(a.t), float(a.o))
	var face := Vector2(1.0 if index == 0 else -1.0, 0.0)
	ped.setup_vendor(ch.plan.block(ch.ix, ch.iz).rect, hash([ch.plan.seed, m.seed, index, "actor"]), at, _yaw_of(m, face), false, 0.0)
	ped.add_to_group("film_actor")
	ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + 0.05, at.y)
	ch.add_child(ped)


## The `index`-th extra, waiting about in holding (between the basecamp and the set).
static func spawn_extra(ch: CityChunk, m: Dictionary, index: int) -> void:
	if not ch._take_crowd_room():
		return
	var ped := FilmExtra.new()
	ped.setup_market(m, FilmShoot.holding(m), ch.plan.block(ch.ix, ch.iz).rect, hash([ch.plan.seed, m.seed, index, "extra"]))
	ped.remove_from_group("market_shopper")
	ped.add_to_group("film_extra")
	var start := ped._random_ring_point(4.0)
	ped.position = Vector3(start.x, ch.ground_y(start.x, start.y) + 0.1, start.y)
	ch.add_child(ped)
