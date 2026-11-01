class_name CarLodBlend
extends RefCounted
## The car's near body and far twin crossfade instead of swapping at one distance (wave 5,
## "lod-pops"; docs/HANDOFF.md "Popping while driving and flying").
##
## Every car drew its full model to Vehicle.body_far_distance (30 m; 60 for the big ones) and its
## ~8k-triangle far twin from there, cut over in one frame: the paint's lacquer, the lamps, the
## wheels and the trim all jumped on every car the camera passed. Godot's own range fade is an
## alpha blend, which on a body of many parts shows the car through itself
## (tools/lod_pops/car_pop_shot.gd), so this is a SCREEN-DOOR crossfade instead: across BAND
## metres round the swap both are drawn, opaque, and each pixel is taken by exactly one of them
## (shaders/lod_blend.gdshaderinc). The paint (shared by the near and far meshes, so the far one
## gets its own copy with the side flag), the cabin glass and the far twin's vertex-coloured parts
## carry the include; the near body's glTF materials (trim, tyres, lamps, chrome) are copies with
## StandardMaterial3D's OBJECT_DITHER fade, which is the same rule. TAA resolves the pattern into
## a dissolve on the Mac.
##
## Forward+ desktop only (where LodFade runs): StandardMaterial3D's distance fade is compiled out
## on the low-end Compatibility renderer, so there the trim would not follow the paint; the web
## keeps the hard swap. The first hit (CarDamage, which copies and swaps the paint) puts the hard
## swap back (revert()). CAR_LOD_BLEND=0 (or LOD_POPS=0) is the A/B.

## Off with CAR_LOD_BLEND=0.
static var enabled: bool = OS.get_environment("CAR_LOD_BLEND") != "0"
## Metres the crossfade spans, centred on the swap distance.
const BAND := 6.0
## Metres the hard ranges run past the band: a range is measured to the mesh's AABB centre, the
## fade to its origin.
const SLACK := 1.5

## Near glTF material (by instance id, and the band) -> its dithered copy, shared by every car.
static var _std: Dictionary = {}
## Band -> the far twin's dithered parts material.
static var _parts: Dictionary = {}
static var _parts_shader: Shader


static func supported() -> bool:
	return enabled and LodFade.enabled and (LodFade.force or LodFade.supported())


## Called at the end of Vehicle._add_body_model() with its near and far meshes.
static func apply(car: Node, near: Array[MeshInstance3D], far: Array[MeshInstance3D], at: float) -> void:
	if not supported() or near.is_empty() or far.is_empty() or at <= 0.0:
		return
	var lo := at - BAND * 0.5
	var hi := at + BAND * 0.5
	var blend_near := Vector3(lo, hi, 0.0)
	var blend_far := Vector3(lo, hi, 1.0)
	var undo: Array = []
	var far_copy := {}
	for m in near:
		if not is_instance_valid(m) or m.mesh == null or not is_equal_approx(m.visibility_range_end, at):
			continue
		m.visibility_range_end = hi + SLACK
		for si in m.mesh.get_surface_count():
			var cur := m.get_surface_override_material(si)
			var mat := cur if cur != null else m.mesh.surface_get_material(si)
			if mat is ShaderMaterial:
				if _blends(mat as ShaderMaterial):
					(mat as ShaderMaterial).set_shader_parameter("lod_blend", blend_near)
			elif mat is StandardMaterial3D:
				var key := "%d:%.1f" % [mat.get_instance_id(), at]
				if not _std.has(key):
					var d := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					d.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER
					d.distance_fade_min_distance = hi
					d.distance_fade_max_distance = lo
					_std[key] = d
				undo.append([m, si, cur])
				m.set_surface_override_material(si, _std[key])
	for m in far:
		if not is_instance_valid(m) or m.mesh == null or not is_equal_approx(m.visibility_range_begin, at):
			continue
		m.visibility_range_begin = lo - SLACK
		for si in m.mesh.get_surface_count():
			var cur := m.get_surface_override_material(si) as ShaderMaterial
			if cur == null:
				continue
			if _blends(cur):
				# The paint, which the far twin shares with the near body: its own copy, far side.
				if not far_copy.has(cur):
					var c := cur.duplicate() as ShaderMaterial
					c.set_shader_parameter("lod_blend", blend_far)
					far_copy[cur] = c
				undo.append([m, si, cur])
				m.set_surface_override_material(si, far_copy[cur])
			elif cur.shader != null and cur.shader.code == Vehicle.PARTS_SHADER:
				undo.append([m, si, cur])
				m.set_surface_override_material(si, _parts_material(lo, hi))
	car.set_meta("lod_blend", {"at": at, "near": near, "far": far, "undo": undo, "paints": far_copy.keys()})


## Back to the hard swap (CarDamage is about to copy and swap the paint).
static func revert(car: Node) -> void:
	if not car.has_meta("lod_blend"):
		return
	var b: Dictionary = car.get_meta("lod_blend")
	car.remove_meta("lod_blend")
	var at: float = b.at
	for u: Array in b.undo:
		var m := u[0] as MeshInstance3D
		if is_instance_valid(m):
			m.set_surface_override_material(int(u[1]), u[2])
	var paints: Array = b.paints
	for m: MeshInstance3D in b.near:
		if not is_instance_valid(m):
			continue
		m.visibility_range_end = at
		for si in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(si) as ShaderMaterial
			if mat == null or not _blends(mat) or mat.get_shader_parameter("lod_blend") == Vector3.ZERO:
				continue
			if paints.has(mat):
				mat.set_shader_parameter("lod_blend", Vector3.ZERO)
			else:
				# Shared (the body type's cabin glass): this car's own copy, not fading.
				var own := mat.duplicate() as ShaderMaterial
				own.set_shader_parameter("lod_blend", Vector3.ZERO)
				m.set_surface_override_material(si, own)
		_twins(m)
	var glass_own = car.get("_glass_own")
	if glass_own is ShaderMaterial:
		(glass_own as ShaderMaterial).set_shader_parameter("lod_blend", Vector3.ZERO)
	for m: MeshInstance3D in b.far:
		if is_instance_valid(m):
			m.visibility_range_begin = at
			_twins(m)


## A body mesh's shadow twin (Vehicle._make_body_shadows) follows it.
static func _twins(m: MeshInstance3D) -> void:
	for t in m.get_children():
		if t is MeshInstance3D and String(t.name) == "Shadow":
			var tw := t as MeshInstance3D
			tw.visibility_range_begin = m.visibility_range_begin
			tw.visibility_range_end = m.visibility_range_end
			for si in m.mesh.get_surface_count():
				tw.set_surface_override_material(si, m.get_surface_override_material(si))


## Shaders carrying the include, by instance id (the uniform list is long to walk).
static var _has_uniform: Dictionary = {}


static func _blends(mat: ShaderMaterial) -> bool:
	var sh := mat.shader
	if sh == null:
		return false
	var id := sh.get_instance_id()
	if not _has_uniform.has(id):
		var found := false
		for u: Dictionary in sh.get_shader_uniform_list():
			if u.name == "lod_blend":
				found = true
				break
		_has_uniform[id] = found
	return _has_uniform[id]


static func _parts_material(lo: float, hi: float) -> ShaderMaterial:
	var key := "%.1f:%.1f" % [lo, hi]
	if _parts.has(key):
		return _parts[key]
	if _parts_shader == null:
		_parts_shader = Shader.new()
		_parts_shader.code = Vehicle.PARTS_SHADER.replace("void fragment() {",
			"#include \"res://shaders/lod_blend.gdshaderinc\"\nvoid fragment() {\n\tif (lod_blend_cut(FRAGCOORD.xy, VIEW_MATRIX, MODEL_MATRIX, IN_SHADOW_PASS)) {\n\t\tdiscard;\n\t}")
	var m := ShaderMaterial.new()
	m.shader = _parts_shader
	m.set_shader_parameter("lod_blend", Vector3(lo, hi, 1.0))
	_parts[key] = m
	return m
