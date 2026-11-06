extends RefCounted
## Gunplay at arm's length (docs/HANDOFF.md "Gunplay at arm's length", GunplayFeel) for
## tests/smoke_test.gd:
## - the flash is a volume (crossed lances, a crown, tongues: the mesh's contract with
##   muzzle_flash.gdshader) with its lights on the hands and ahead, and it heats the barrel, which
##   smokes after the burst and cools;
## - a tracer is one camera-facing quad of the round's length, gone after its flight;
## - every surface has its own baked marks (files, not painted at load), flesh and sanctuaries
##   none, and a mark without decals (this dummy renderer, the web) is a lit quad in the pool;
## - the shotgun's pattern smudge only where three pellets bunch in one surface;
## - the recoil spring kicks, rises, overshoots past rest and settles, and is identity at rest;
## - GUNPLAY_FEEL=0 (enabled false) hands WeaponFX back its old flash, tracer and holes.

var _t: Node
var _made: Array = []


func run(t: Node, city: Node3D) -> void:
	_t = t
	_mesh()
	_textures()
	_recoil()
	_marks(city)
	_flash(city)
	_switch(city)
	for n in _made:
		if is_instance_valid(n):
			(n as Node).queue_free()


func _mesh() -> void:
	var m := GunplayFeel.flash_mesh()
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var pieces := {}
	var reach := 0.0
	for i in uv2.size():
		pieces[int(round(uv2[i].x))] = int(pieces.get(int(round(uv2[i].x)), 0)) + 1
		reach = minf(reach, verts[i].z)
	_t._check(verts.size() == 9 * 6 and pieces.get(0, 0) == 24 and pieces.get(1, 0) == 6 and pieces.get(2, 0) == 24,
		"gunplay: the flash is four lances, a crown and four tongues (%d vertices, %s)" % [verts.size(), str(pieces)])
	_t._check(reach < -0.3, "gunplay: the flash's lances run down the bore (-Z, %.2f m)" % reach)
	var tm := GunplayFeel.tracer_mesh()
	_t._check(tm.surface_get_array_len(0) == 6, "gunplay: a tracer is one quad")


func _textures() -> void:
	var sets := 0
	var files := 0
	for s in GunplayFeel.baked_surfaces():
		for v in GunplayFeel.VARIANTS:
			var maps := GunplayFeel.hole_textures(s, v)
			sets += 1
			for tex in maps:
				if tex is Texture2D and (tex as Texture2D).resource_path.begins_with(GunplayFeel.HOLE_DIR):
					files += 1
	_t._check(sets == 15 and files == 45, "gunplay: five surfaces' marks, three variants each, loaded from the baked files (%d sets, %d files)" % [sets, files])
	var pat := GunplayFeel.pattern_textures()
	_t._check(pat.size() == 3 and (pat[0] as Texture2D).resource_path.begins_with(GunplayFeel.HOLE_DIR),
		"gunplay: the shotgun pattern's smudge is baked too")
	var a := GunplayFeel.hole_textures(WeaponFX.Surface.CONCRETE, 0)
	var b := GunplayFeel.hole_textures(WeaponFX.Surface.METAL, 0)
	_t._check(a[0] != b[0], "gunplay: concrete and metal leave different marks")
	var atlas := WarmRehearsal.atlas_textures()
	var found := 0
	for maps in atlas:
		if maps[0] == a[0] or maps[0] == pat[0]:
			found += 1
	_t._check(found == 2, "gunplay: the marks are kept in the decal atlas for the session")


func _recoil() -> void:
	var gun := AssaultRifle.new()
	_t._check(gun.recoil_local() == Transform3D(), "gunplay: the recoil is identity at rest")
	gun.call("_recoil_kick")
	var peak := 0.0
	var dipped := false
	var back := 0.0
	var steps := 0
	for i in 90:
		gun.call("_recoil_step", 1.0 / 60.0)
		var rec: Vector4 = gun.get("_rec")
		peak = maxf(peak, rad_to_deg(rec.y))
		back = maxf(back, rec.x)
		if peak > 0.5 and rec.y < -1e-4:
			dipped = true
		steps = i
	var rest: Vector4 = gun.get("_rec")
	_t._check(peak > gun.recoil_rise_deg * 0.5 and peak < gun.recoil_rise_deg * 1.7,
		"gunplay: a round lifts the rifle about its recoil_rise_deg (%.2f of %.2f deg)" % [peak, gun.recoil_rise_deg])
	_t._check(back > gun.kick_distance * 0.4 and back < gun.kick_distance * 1.7,
		"gunplay: and throws it back about kick_distance (%.3f m)" % back)
	_t._check(dipped, "gunplay: the spring overshoots past rest before it settles")
	_t._check(absf(rest.y) < 0.002 and absf(rest.x) < 0.002, "gunplay: and it has settled within a second and a half (%s)" % str(rest))
	# The pivot: lifted about the butt, the muzzle rises and the butt barely moves.
	gun.set("_rec", Vector4(0.0, deg_to_rad(5.0), 0.0, 0.0))
	var xf := gun.recoil_local()
	var muzzle := xf * Vector3(0.0, 0.0, -0.55)
	var butt := xf * gun.recoil_pivot
	_t._check(muzzle.y > 0.05 and butt.distance_to(gun.recoil_pivot) < 1e-4,
		"gunplay: the gun turns about the butt in the shoulder (muzzle up %.3f m)" % muzzle.y)
	gun.free()


func _marks(city: Node3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 0
	city.add_child(body)
	_made.append(body)
	var n0 := int(GunplayFeel.stats["holes"])
	var made := 0
	for s in GunplayFeel.baked_surfaces():
		var mark := GunplayFeel.hole(city, body.global_position + Vector3(0, 1, 0), Vector3.BACK, s, body)
		if mark != null and mark.is_in_group("bullet_hole") and mark.get_parent() == body:
			made += 1
	_t._check(made == 5 and int(GunplayFeel.stats["holes"]) == n0 + 5, "gunplay: a mark for every surface, on what was hit (%d)" % made)
	_t._check(GunplayFeel.hole(city, Vector3.ZERO, Vector3.UP, WeaponFX.Surface.FLESH, body) == null, "gunplay: no hole in a person")
	if RenderingServer.get_rendering_device() == null:
		var q := 0
		for c in body.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is QuadMesh:
				q += 1
		_t._check(q == 5, "gunplay: with no decals the marks are lit quads (%d)" % q)
	# Pellets: pits a fraction of a round's hole.
	GunplayFeel.pellet_mode = true
	var pit := GunplayFeel.hole(city, body.global_position, Vector3.BACK, WeaponFX.Surface.CONCRETE, body)
	GunplayFeel.pellet_mode = false
	var full := GunplayFeel.hole(city, body.global_position, Vector3.BACK, WeaponFX.Surface.CONCRETE, body)
	_t._check(pit != null and full != null and _width(pit) < _width(full) * 0.7, "gunplay: a pellet leaves a pit, not a round's hole")
	# The pattern: three pellets bunched in one surface, and not when they are spread wide.
	var p0 := int(GunplayFeel.stats["patterns"])
	var c := body.global_position
	GunplayFeel.spread_mark(city, c + Vector3(0, 0, 6), [[body, c, Vector3.BACK], [body, c + Vector3(0.1, 0, 0), Vector3.BACK], [body, c + Vector3(0, 0.12, 0), Vector3.BACK]])
	_t._check(int(GunplayFeel.stats["patterns"]) == p0 + 1, "gunplay: bunched pellets leave the pattern's smudge")
	GunplayFeel.spread_mark(city, c + Vector3(0, 0, 6), [[body, c, Vector3.BACK], [body, c + Vector3(3, 0, 0), Vector3.BACK], [body, c + Vector3(0, 3, 0), Vector3.BACK]])
	GunplayFeel.spread_mark(city, c + Vector3(0, 0, 6), [[body, c, Vector3.BACK], [body, c + Vector3(0.1, 0, 0), Vector3.BACK]])
	_t._check(int(GunplayFeel.stats["patterns"]) == p0 + 1, "gunplay: but not where they spread wide, or only two hit")
	# A place of worship takes no marks (Sanctuary).
	var holy := StaticBody3D.new()
	holy.add_to_group("sanctuary")
	city.add_child(holy)
	_made.append(holy)
	_t._check(GunplayFeel.hole(city, Vector3.ZERO, Vector3.UP, WeaponFX.Surface.CONCRETE, holy) == null, "gunplay: no marks on a sanctuary")


func _width(n: Node3D) -> float:
	if n is Decal:
		return (n as Decal).size.x
	return ((n as MeshInstance3D).mesh as QuadMesh).size.x


func _flash(city: Node3D) -> void:
	var player := city.get_tree().get_first_node_in_group("player") as Node3D
	var wm: Node = player.get("weapon_manager") if player != null else null
	var rifle: Weapon = null
	if wm != null:
		for w in wm.get_children():
			if w is AssaultRifle:
				rifle = w
	_t._check(rifle != null, "gunplay: the player carries the rifle")
	if rifle == null:
		return
	var parent := WeaponFX.fx_parent(rifle)
	var before := {}
	for c in parent.get_children():
		before[c.get_instance_id()] = true
	var f0 := int(GunplayFeel.stats["flashes"])
	WeaponFX.flash(rifle, rifle.muzzle.global_position)
	var flashes := 0
	var lights := 0
	for c in parent.get_children():
		if before.has(c.get_instance_id()):
			continue
		if c.name.begins_with("MuzzleFlash"):
			flashes += 1
		elif c is OmniLight3D:
			lights += 1
		_made.append(c)
	_t._check(flashes == 1 and int(GunplayFeel.stats["flashes"]) == f0 + 1, "gunplay: WeaponFX.flash draws the volume flash")
	_t._check(lights >= (1 if OS.has_feature("web") else 2), "gunplay: and lights the hands and ahead (%d lights)" % lights)
	var smoke := rifle.muzzle.get_node_or_null("BarrelSmoke") as CPUParticles3D
	_t._check(smoke != null and float(smoke.get("heat")) > 0.0, "gunplay: a round heats the barrel")
	if smoke != null:
		var shown := rifle.visible
		rifle.visible = true
		for i in 12:
			WeaponFX.flash(rifle, rifle.muzzle.global_position)
		var hot := float(smoke.get("heat"))
		smoke.call("_process", 0.3)
		_t._check(smoke.emitting and hot > GunplayFeel.smoke_from_heat, "gunplay: after a burst the barrel smokes")
		smoke.call("_process", 5.0)
		_t._check(not smoke.emitting and float(smoke.get("heat")) == 0.0, "gunplay: and stops once it has cooled")
		smoke.queue_free()
		rifle.visible = shown
	for c in parent.get_children():
		if not before.has(c.get_instance_id()):
			_made.append(c)
	# A tracer: one quad scaled to the round's length.
	var from := rifle.muzzle.global_position
	GunplayFeel.tracer(rifle, from, from + Vector3(0, 0, -40), Color(1, 0.85, 0.4), 0.06, 0.03)
	var tracer: MeshInstance3D = null
	for c in parent.get_children():
		if c.name.begins_with("Tracer") and not before.has(c.get_instance_id()):
			tracer = c
			_made.append(c)
	_t._check(tracer != null and absf(tracer.global_basis.z.length() - 40.0) < 0.01 \
		and absf(float((tracer.material_override as ShaderMaterial).get_shader_parameter("length_m")) - 40.0) < 0.01,
		"gunplay: a tracer is one quad the round's length")


func _switch(city: Node3D) -> void:
	var was := GunplayFeel.enabled
	GunplayFeel.enabled = false
	var f0 := int(GunplayFeel.stats["flashes"])
	var t0 := int(GunplayFeel.stats["tracers"])
	var parent := WeaponFX.fx_parent(city)
	var before := {}
	for c in parent.get_children():
		before[c.get_instance_id()] = true
	WeaponFX.flash(city, Vector3(0, 2, 0))
	WeaponFX.tracer(city, Vector3(0, 2, 0), Vector3(0, 2, -20), Color(1, 0.8, 0.4))
	_t._check(int(GunplayFeel.stats["flashes"]) == f0 and int(GunplayFeel.stats["tracers"]) == t0,
		"gunplay: GUNPLAY_FEEL=0 hands WeaponFX back its old flash and tracer")
	var gun := AssaultRifle.new()
	gun.call("_recoil_kick")
	gun.call("_recoil_step", 0.05)
	_t._check(gun.recoil_local() == Transform3D(), "gunplay: and the old straight kick (no spring)")
	gun.free()
	GunplayFeel.enabled = was
	for c in parent.get_children():
		if not before.has(c.get_instance_id()):
			_made.append(c)
