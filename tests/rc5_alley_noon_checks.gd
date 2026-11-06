extends RefCounted
## The alley at noon (AlleyNoon, refcam alley_noon), for tests/smoke_test.gd. Loaded at run time,
## not named there, so it compiles after the autoloads.
##
## Checks: the props AlleyNoon rebuilds (the cart, the mattress, the stoop) are written in
## IndustrialKit's form - every triangle wound clockwise to its outward normal, inside the old
## footprint, on the ground and in front of the wall - and with it off AlleyKit's old boxes come back;
## the refcam's chunk (block 28,-4) places the same props either way (no rng moved); the ground's
## shared material carries day_dry and the shader keeps the day terms behind it and lamp_factor.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := AlleyNoon.enabled
	AlleyNoon.enabled = true
	_props()
	_ground()
	_chunk(city)
	AlleyNoon.enabled = was


## The props in their local frame (x along the wall, y up, z out of it).
func _props() -> void:
	var cart := _write(AlleyKit.cart.bind(AlleyKit.CART_PAINT[0], Color(0.06, 0.06, 0.07)))
	_check_mesh(cart, "the moulded cart", AABB(Vector3(-0.42, -0.01, -0.5), Vector3(0.84, 1.06, 0.97)), AABB(Vector3(-0.42, -0.01, -0.5), Vector3(0.84, 0.33, 0.35)))
	_t._check(int(cart.tris) > 150, "the cart is moulded (%d triangles, the old box cart ~60)" % int(cart.tris))
	var mat := _write(AlleyKit.mattress.bind(Color(0.78, 0.76, 0.7)))
	_check_mesh(mat, "the quilted mattress", AABB(Vector3(-0.75, -0.03, 0.0), Vector3(1.5, 1.97, 0.75)))
	_t._check(int(mat.tris) >= AlleyNoon.QUILT_X * AlleyNoon.QUILT_Y * 4, "the mattress's face is quilted (%d triangles)" % int(mat.tris))
	var door := _write(AlleyKit.back_door.bind(AlleyKit.DOOR_PAINT[0], "", true))
	var stoop_dark := true
	var cols: PackedColorArray = door.arrays[Mesh.ARRAY_COLOR]
	for c in cols:
		if int(floor(c.a * 32.0)) == IndustrialKit.K_CONCRETE:
			stoop_dark = stoop_dark and c.r < 0.65
	_t._check(stoop_dark, "the back door's stoop is worn concrete, not the old 0.72 white")
	AlleyNoon.enabled = false
	var old_cart := _write(AlleyKit.cart.bind(AlleyKit.CART_PAINT[0], Color(0.06, 0.06, 0.07)))
	var old_mat := _write(AlleyKit.mattress.bind(Color(0.78, 0.76, 0.7)))
	_t._check(int(old_cart.tris) < int(cart.tris) and int(old_mat.tris) == 10, "ALLEY_NOON=0 draws AlleyKit's old cart and mattress")
	AlleyNoon.enabled = true


## Writes a prop at the origin into a fresh SurfaceTool: its arrays and triangle count.
func _write(build: Callable) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t0 := IndustrialKit.tris
	IndustrialKit.place(st, Transform3D(), Color.WHITE, build.bind(st))
	var arrays := st.commit_to_arrays()
	return {"arrays": arrays, "tris": IndustrialKit.tris - t0}


## (The wheels are IndustrialKit.cyl's, which winds its caps its own way: `skip` leaves out the
## triangles inside it.)
func _check_mesh(m: Dictionary, what: String, box: AABB, skip: AABB = AABB()) -> void:
	var verts: PackedVector3Array = m.arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = m.arrays[Mesh.ARRAY_NORMAL]
	var inside := verts.size() > 0
	var wound := 0
	for i in verts.size():
		inside = inside and box.grow(0.001).has_point(verts[i])
	var total := 0
	for i in range(0, verts.size() - 2, 3):
		if skip.size != Vector3.ZERO and skip.has_point(verts[i]) and skip.has_point(verts[i + 1]) and skip.has_point(verts[i + 2]):
			continue
		total += 1
		var g := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
		# Godot's front faces are clockwise to the viewer: the stored normal opposes the CCW cross.
		if g.length_squared() < 1e-12 or g.dot(norms[i]) <= 0.0:
			wound += 1
	_t._check(inside, "%s stands inside its footprint, on the ground, off the wall" % what)
	_t._check(wound == total, "%s: every triangle faces its normal (%d of %d)" % [what, wound, total])


func _ground() -> void:
	_t._check(float(Alleys.ground_material().get_shader_parameter("day_dry")) > 0.5, "the alley ground's shared material dries its water by day")
	var src := FileAccess.get_file_as_string("res://shaders/alley_ground.gdshader")
	_t._check(src.contains("uniform float day_dry = 0.0;") and src.contains("float dry = day_dry * (1.0 - clamp(lamp_factor, 0.0, 1.0));")
		and src.contains("if (day_w > 0.001 && pool > 0.01)"), "the day terms sit behind day_dry and fall to 0 as lamp_factor reaches 1 (the night as it was)")


## The refcam's chunk: the same props either way.
func _chunk(city: Node3D) -> void:
	var plan: CityPlan = city.plan
	var k: Vector2i = plan.block_index_at(Vector2(3052.0, -671.0))
	_t._check(not Alleys.spec(plan, k.x, k.y).is_empty(), "the alley_noon refcam's block %d,%d has a service alley" % [k.x, k.y])
	var a: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	a.build()
	var on_props: Dictionary = a.get_meta("alley_props", {})
	_free(a)
	AlleyNoon.enabled = false
	var b: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	b.build()
	var off_props: Dictionary = b.get_meta("alley_props", {})
	# The cook takes crowd room, which the first build may have used up: not a placed prop.
	on_props.erase("cook")
	off_props.erase("cook")
	_free(b)
	AlleyNoon.enabled = true
	_t._check(on_props.size() > 0 and on_props.has("cart") and on_props == off_props, "the refcam's alley places the same props with AlleyNoon on and off (%s)" % str(on_props))


## A built chunk and the parked cars it put under the city root (the flake rules).
func _free(chunk: CityChunk) -> void:
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and car is Node:
			(car as Node).free()
	chunk.free()
