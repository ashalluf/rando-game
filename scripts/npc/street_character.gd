class_name StreetCharacter
extends StreetVendor
## A costumed street character on the walk of fame (StarBoulevard): somebody in an ORIGINAL
## costume - never a copyrighted character - standing on the stars for the tourists' photos.
## StreetVendor's life (stands at their spot, idles, folds their arms, talks to whoever stops,
## runs from gunfire and walks back), a crowd rig like anyone (shot, knocked, ragdolled, a crime).
##
## The costume is the rig's own body repainted (the character shader's garment split, or a
## painted-metal material over everything for the living statues) plus pieces built here in code,
## round the rig's own head from CrowdHatTable's measurements (CrowdHat.head_for(), the head frame
## FireHelmet uses) or hung off the upper spine like the crowd's backpack.

enum Piece { NONE, CAPE, COWBOY_HAT, ROBOT_HELMET, TIARA, ANTENNAE }

## name, top and bottom (HSV) or "metal" (a painted-metal colour over the whole body), skin tint,
## the pieces, the cape colour. Every one invented.
const COSTUMES := [
	{"name": "THE GILDED STATUE", "metal": Color(0.80, 0.58, 0.20), "pieces": [Piece.NONE]},
	{"name": "UNIT 7 THE CHROME ROBOT", "metal": Color(0.74, 0.76, 0.80), "pieces": [Piece.ROBOT_HELMET]},
	{"name": "CAPTAIN COMET", "top": Vector3(0.50, 0.80, 0.55), "bottom": Vector3(0.07, 0.90, 0.85),
		"pieces": [Piece.CAPE], "cape": Color(0.92, 0.38, 0.06)},
	{"name": "THE RODEO RANGER", "top": Vector3(0.02, 0.70, 0.55), "bottom": Vector3(0.60, 0.35, 0.30),
		"pieces": [Piece.COWBOY_HAT]},
	{"name": "MADAME SPOTLIGHT", "top": Vector3(0.98, 0.85, 0.62), "bottom": Vector3(0.98, 0.85, 0.50),
		"pieces": [Piece.TIARA, Piece.CAPE], "cape": Color(0.95, 0.94, 0.90)},
	{"name": "THE VISITOR", "top": Vector3(0.60, 0.04, 0.85), "bottom": Vector3(0.60, 0.04, 0.80),
		"skin": Color(0.55, 1.0, 0.50), "pieces": [Piece.ANTENNAE]},
	{"name": "THE MIDNIGHT AVENGER", "top": Vector3(0.75, 0.55, 0.20), "bottom": Vector3(0.70, 0.20, 0.08),
		"pieces": [Piece.CAPE], "cape": Color(0.30, 0.06, 0.45)},
]

const DRAW_DISTANCE := 70.0

var costume: int = 0

static var _metal: Dictionary = {}
static var _paint: Dictionary = {}
static var _piece_meshes: Dictionary = {}
static var _piece_mat: StandardMaterial3D
static var _cape_mat: StandardMaterial3D


func _ready() -> void:
	super()
	add_to_group("street_character")


## The costume goes on after the rig is made (Pedestrian._add_model picks and prepares it).
func _add_model() -> bool:
	if not super():
		return false
	var c: Dictionary = COSTUMES[clampi(costume, 0, COSTUMES.size() - 1)]
	var inst: Node3D = null
	for mi: MeshInstance3D in _meshes:
		if not is_instance_valid(mi):
			continue
		if inst == null:
			inst = _rig_root(mi)
		if is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi.mesh else null
		if c.has("metal"):
			mi.material_override = metal_material(c.metal)
		elif src and src.albedo_texture:
			var m := paint_material(src.albedo_texture, costume)
			if m:
				mi.material_override = m
	if inst == null:
		return true
	var pieces: Array = c.pieces
	var covers_head := c.has("metal") or pieces.has(Piece.COWBOY_HAT) or pieces.has(Piece.ROBOT_HELMET)
	if covers_head:
		for node in inst.find_children("Hair*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).visible = false
			node.set_meta("under_hat", true)
	for p: int in pieces:
		match p:
			Piece.CAPE:
				_hang(inst, "Spine02", cape_mesh(), cape_material(c.get("cape", Color.WHITE)))
			Piece.COWBOY_HAT, Piece.ROBOT_HELMET, Piece.TIARA, Piece.ANTENNAE:
				_on_head(inst, p)
	return true


## No crowd hat or backpack: the costume is the accessory.
func _add_accessory(_inst: Node3D) -> void:
	pass


func _rig_root(mi: Node) -> Node3D:
	var n: Node = mi
	while n != null and n.get_parent() != _visual:
		n = n.get_parent()
	return n as Node3D


## A painted-metal body (the living statues): the whole rig one colour, a little worn.
static func metal_material(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _metal.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.75
		m.roughness = 0.38
		_metal[key] = m
	return _metal[key]


## The rig's own body, its top and trousers repainted the costume's colours.
func paint_material(albedo: Texture2D, which: int) -> ShaderMaterial:
	var key := "%d_%d" % [albedo.get_instance_id(), which]
	if _paint.has(key):
		return _paint[key]
	var base := character_material(albedo, 1)
	if base == null:
		return null
	var c: Dictionary = COSTUMES[which]
	var mat := base.duplicate() as ShaderMaterial
	var top: Vector3 = c.get("top", Vector3(0.0, 0.0, 0.5))
	var low: Vector3 = c.get("bottom", top)
	mat.set_shader_parameter("cloth_hue", top.x)
	mat.set_shader_parameter("cloth_sat", top.y)
	mat.set_shader_parameter("cloth_value", top.z)
	mat.set_shader_parameter("cloth_strength", 0.97)
	mat.set_shader_parameter("pants_hue", low.x)
	mat.set_shader_parameter("pants_sat", low.y)
	mat.set_shader_parameter("pants_value", low.z)
	mat.set_shader_parameter("pants_strength", 0.97)
	mat.set_shader_parameter("cloth_roughness", 0.55)
	mat.set_shader_parameter("cloth_shade_keep", 0.55)
	if c.has("skin"):
		mat.set_shader_parameter("skin_tint", c.skin)
	_paint[key] = mat
	return mat


## Hangs `mesh` (built level in metres about the bone, the rig facing +Z) off `bone`.
func _hang(inst: Node3D, bone: String, mesh: Mesh, mat: Material) -> void:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var idx := skel.find_bone(bone)
	if idx < 0:
		return
	var unit := 1.0 / maxf(CrowdHat._unit(inst, skel), 1e-6)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = bone
	var mi := MeshInstance3D.new()
	mi.name = "Costume"
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = DRAW_DISTANCE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var pose := skel.get_bone_global_pose(idx)
	mi.transform = pose.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit), pose.origin)
	att.add_child(mi)


## Puts a head piece on, built in the head frame from this rig's measurements.
func _on_head(inst: Node3D, piece: int) -> void:
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var hb := skel.find_bone("Head")
	if hb < 0:
		return
	var unit := CrowdHat._unit(inst, skel)
	var rest := skel.get_bone_global_rest(hb)
	var att := BoneAttachment3D.new()
	att.name = "CostumeHead"
	skel.add_child(att)
	att.bone_name = "Head"
	var mi := MeshInstance3D.new()
	mi.name = "Costume"
	mi.mesh = head_piece(_model_path, piece)
	mi.material_override = piece_material()
	mi.visibility_range_end = DRAW_DISTANCE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE / maxf(unit, 1e-6)), rest.origin)
	att.add_child(mi)


static func piece_material() -> StandardMaterial3D:
	if _piece_mat == null:
		_piece_mat = StandardMaterial3D.new()
		_piece_mat.vertex_color_use_as_albedo = true
		_piece_mat.vertex_color_is_srgb = true
		_piece_mat.roughness = 0.5
		_piece_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _piece_mat


static func cape_material(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _paint.has("cape_" + key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.62
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.rim_enabled = true
		m.rim = 0.25
		_paint["cape_" + key] = m
	return _paint["cape_" + key]


## The cape: from the shoulders down the back to the knees, flaring and falling in soft folds,
## in the upper spine's frame (the back is -Z), two-sided.
static func cape_mesh() -> Mesh:
	if _piece_meshes.has("cape"):
		return _piece_meshes.cape
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 10
	var rows := 10
	var grid: Array = []
	for j in rows + 1:
		var t := float(j) / rows
		var row: Array[Vector3] = []
		for i in cols + 1:
			var s := float(i) / cols * 2.0 - 1.0
			var half := lerpf(0.21, 0.40, t)
			var x := s * half
			var y := lerpf(0.16, -1.02, t)
			# Behind the back, falling away from it, folds deepening toward the hem.
			var z := -lerpf(0.13, 0.26, t) - 0.05 * (1.0 - s * s) * t - 0.025 * t * sin(s * PI * 3.0)
			# Round the shoulders at the top.
			z += 0.06 * (s * s) * (1.0 - t) * (1.0 - t)
			row.append(Vector3(x, y, z))
		grid.append(row)
	for j in rows:
		for i in cols:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j + 1][i]
			for v: Vector3 in [a, b, c, a, c, d]:
				st.set_uv(Vector2(float(i) / cols, float(j) / rows))
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	_piece_meshes.cape = mesh
	return mesh


## A head piece for `rig`, in the head frame (metres; origin the Head bone's rest; +Z the face).
static func head_piece(rig: String, piece: int) -> Mesh:
	var key := "%s|%d" % [rig.get_file(), piece]
	if _piece_meshes.has(key):
		return _piece_meshes[key]
	var h := CrowdHat.head_for(rig)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rx := h.radius(PI * 0.5, 0.1) + 0.012
	var rz := (h.radius(0.0, 0.1) + h.radius(PI, 0.1)) * 0.5 + 0.012
	var cx := h.c.x
	var cz := h.c.z
	match piece:
		Piece.COWBOY_HAT:
			var felt := Color(0.36, 0.22, 0.12)
			var band := Color(0.10, 0.07, 0.05)
			var y0 := h.eye_y + 0.045
			# Crown: an ellipse rising and pinched at the front (the creases), a dented top.
			var prof := [[1.0, 0.0], [1.0, 0.025], [0.97, 0.06], [0.93, 0.11], [0.80, 0.135], [0.0, 0.12]]
			_ellipse_lathe(st, Vector3(cx, y0, cz), rx, rz, prof, 20, felt, band)
			# Brim: a ring curling up at the sides.
			var segs := 28
			for k in segs:
				var a0 := float(k) / segs * TAU
				var a1 := float(k + 1) / segs * TAU
				var pts: Array[Vector3] = []
				for a: float in [a0, a1]:
					var ix := sin(a) * rx
					var iz := cos(a) * rz
					var curl := 0.045 * pow(absf(sin(a)), 2.0)
					var w := 0.10 + 0.02 * absf(cos(a))
					pts.append(Vector3(cx + ix, y0 + 0.004, cz + iz))
					pts.append(Vector3(cx + sin(a) * (rx + w), y0 + 0.004 + curl - 0.012 * absf(cos(a)), cz + cos(a) * (rz + w)))
				for v: Vector3 in [pts[0], pts[1], pts[3], pts[0], pts[3], pts[2]]:
					st.set_color(felt)
					st.add_vertex(v)
				for v: Vector3 in [pts[0], pts[3], pts[1], pts[0], pts[2], pts[3]]:
					st.set_color(felt.darkened(0.25))
					st.add_vertex(v - Vector3(0, 0.006, 0))
		Piece.ROBOT_HELMET:
			var steel := Color(0.70, 0.72, 0.76)
			var y0 := h.eye_y - 0.17
			var y1 := h.top + 0.05
			var hx := rx + 0.045
			var hz := rz + 0.05
			BroadwayStreet._box(st, Vector3(cx, (y0 + y1) * 0.5, cz), Vector3(hx * 2.0, y1 - y0, hz * 2.0), steel)
			# The visor: a dark band at eye level with a cyan strip in it, ear bolts, an antenna.
			BroadwayStreet._box(st, Vector3(cx, h.eye_y, cz + hz + 0.004), Vector3(hx * 1.6, 0.07, 0.01), Color(0.03, 0.04, 0.05))
			BroadwayStreet._box(st, Vector3(cx, h.eye_y, cz + hz + 0.01), Vector3(hx * 1.3, 0.014, 0.006), Color(0.2, 0.95, 1.0))
			BroadwayStreet._box(st, Vector3(cx, h.eye_y - 0.09, cz + hz + 0.004), Vector3(hx * 0.9, 0.04, 0.01), Color(0.25, 0.26, 0.28))
			for sx: float in [-1.0, 1.0]:
				var bolt := Vector3(cx + sx * (hx + 0.012), h.eye_y - 0.01, cz)
				BroadwayStreet._box(st, bolt, Vector3(0.025, 0.06, 0.06), Color(0.85, 0.2, 0.15))
			BroadwayStreet.lathe(st, [Vector2(0.008, 0.0), Vector2(0.008, 0.12), Vector2(0.025, 0.13), Vector2(0.025, 0.16), Vector2(0.0, 0.17)], 8, Color(0.85, 0.2, 0.15), Vector3(cx, y1, cz))
		Piece.TIARA:
			var gold := Color(0.85, 0.66, 0.25)
			var n := 13
			for k in n:
				var th := lerpf(-1.25, 1.25, float(k) / (n - 1))
				var ph := 0.62
				var p := h.c + CrowdHat.Head.dir(th, ph) * (h.radius(th, ph) + h.hair(th, ph) + 0.012)
				var tall := 0.03 + 0.035 * exp(-pow(th / 0.35, 2.0)) + (0.012 if k % 2 == 0 else 0.0)
				BroadwayStreet._box(st, p + Vector3(0, tall * 0.5, 0), Vector3(0.022, tall, 0.012), gold, Basis(Vector3.UP, th))
				if k == n / 2:
					BroadwayStreet._box(st, p + Vector3(0, tall + 0.012, 0.004), Vector3(0.022, 0.022, 0.022), Color(0.85, 0.15, 0.30), Basis(Vector3.UP, th) * Basis(Vector3.FORWARD, PI * 0.25))
		Piece.ANTENNAE:
			var green := Color(0.35, 0.85, 0.25)
			for sx: float in [-1.0, 1.0]:
				var base := h.c + CrowdHat.Head.dir(sx * 1.2, 0.95) * (h.radius(sx * 1.2, 0.95) + h.hair(sx * 1.2, 0.95))
				var tip := base + Vector3(sx * 0.07, 0.17, 0.02)
				var d := tip - base
				var b := Basis(Quaternion(Vector3.UP, d.normalized()))
				BroadwayStreet._box(st, (base + tip) * 0.5, Vector3(0.008, d.length(), 0.008), Color(0.15, 0.15, 0.16), b)
				BroadwayStreet.lathe(st, [Vector2(0.0, -0.025), Vector2(0.018, -0.018), Vector2(0.025, 0.0), Vector2(0.018, 0.018), Vector2(0.0, 0.025)], 10, green, tip)
			# The headband the stalks stand on.
			for k in 16:
				var th := float(k) / 16.0 * TAU
				var p := h.c + CrowdHat.Head.dir(th, 0.55) * (h.radius(th, 0.55) + h.hair(th, 0.55) + 0.006)
				BroadwayStreet._box(st, p, Vector3(0.045, 0.016, 0.008), Color(0.12, 0.12, 0.13), Basis(Vector3.UP, th))
	st.generate_normals()
	var mesh := st.commit()
	_piece_meshes[key] = mesh
	return mesh


## A surface of revolution on an ellipse (radii rx, rz) round `c`: `prof` is [scale, y] pairs from
## the band up; the first two rows take `band`.
static func _ellipse_lathe(st: SurfaceTool, c: Vector3, rx: float, rz: float, prof: Array, segs: int, col: Color, band: Color) -> void:
	for j in prof.size() - 1:
		var p0: Array = prof[j]
		var p1: Array = prof[j + 1]
		var cc := band if j == 0 else col
		for k in segs:
			var a0 := float(k) / segs * TAU
			var a1 := float(k + 1) / segs * TAU
			# The front crease: the crown pinched in at the front of the top rows.
			var v := []
			for pr: Array in [p0, p1]:
				for a: float in [a0, a1]:
					var pinch := 1.0 - 0.18 * float(pr[1]) / 0.135 * maxf(cos(a), 0.0) * absf(sin(a * 1.0)) * 2.0
					var s: float = float(pr[0]) * clampf(pinch, 0.7, 1.0)
					v.append(c + Vector3(sin(a) * rx * s, float(pr[1]), cos(a) * rz * s))
			for q: Vector3 in [v[0], v[2], v[3], v[0], v[3], v[1]]:
				st.set_color(cc)
				st.add_vertex(q)
