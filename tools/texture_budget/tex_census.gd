extends RefCounted
## Texture census: every texture the scene holds, what it costs in video memory, and the
## renderer's own total. Called by tools/glshot/still_shot.gd with TEX_REPORT=1 (after the GEO
## line), so it measures the exact bookmark frame:
##
##   TEX_REPORT=1 OUT=a.png xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/glshot/still_shot.gd \
##     --resolution 960x540 -- --spawn=2359.4,880,0,12,2 --hour=12 --nohud --quality=0
##
## Prints `TEXMEM renderer=<MB> textures=<MB> buffers=<MB> video=<MB>` (RenderingServer's
## counters: textures includes the render targets, shadow atlas and every texture made in code)
## and `TEXSUM found=<n> est=<MB>` for the textures it could reach from the scene - materials
## on meshes, MultiMeshes, overrides, decals, particles, CanvasItems, the environment's sky and
## the global shader parameters - then TEX_TOP (default 40) `TEX <MB> <w>x<h> <format> mips=<n>
## <path or code-made name>` rows, biggest first, and `TEXDIR` totals per folder. TEX_ALL=1
## lists every one. Estimates are width x height x the format's bits per pixel (x 4/3 with
## mipmaps); a texture the scene no longer references (a cache) only shows in the totals.

const BPP := {
	Image.FORMAT_L8: 8, Image.FORMAT_LA8: 16, Image.FORMAT_R8: 8, Image.FORMAT_RG8: 16,
	Image.FORMAT_RGB8: 32, Image.FORMAT_RGBA8: 32, Image.FORMAT_RGBA4444: 16,
	Image.FORMAT_RGB565: 16, Image.FORMAT_RF: 32, Image.FORMAT_RGF: 64, Image.FORMAT_RGBF: 128,
	Image.FORMAT_RGBAF: 128, Image.FORMAT_RH: 16, Image.FORMAT_RGH: 32, Image.FORMAT_RGBH: 64,
	Image.FORMAT_RGBAH: 64, Image.FORMAT_RGBE9995: 32,
	Image.FORMAT_DXT1: 4, Image.FORMAT_DXT3: 8, Image.FORMAT_DXT5: 8,
	Image.FORMAT_RGTC_R: 4, Image.FORMAT_RGTC_RG: 8, Image.FORMAT_BPTC_RGBA: 8,
	Image.FORMAT_BPTC_RGBF: 8, Image.FORMAT_BPTC_RGBFU: 8,
	Image.FORMAT_ETC: 4, Image.FORMAT_ETC2_R11: 4, Image.FORMAT_ETC2_R11S: 4,
	Image.FORMAT_ETC2_RG11: 8, Image.FORMAT_ETC2_RG11S: 8, Image.FORMAT_ETC2_RGB8: 4,
	Image.FORMAT_ETC2_RGBA8: 8, Image.FORMAT_ETC2_RGB8A1: 4, Image.FORMAT_ASTC_4x4: 8,
	Image.FORMAT_ASTC_8x8: 2,
}
const FORMAT_NAMES := {
	Image.FORMAT_L8: "L8", Image.FORMAT_LA8: "LA8", Image.FORMAT_R8: "R8", Image.FORMAT_RG8: "RG8",
	Image.FORMAT_RGB8: "RGB8", Image.FORMAT_RGBA8: "RGBA8", Image.FORMAT_RF: "RF",
	Image.FORMAT_RGF: "RGF", Image.FORMAT_RGBAF: "RGBAF", Image.FORMAT_RH: "RH",
	Image.FORMAT_RGH: "RGH", Image.FORMAT_RGBAH: "RGBAH", Image.FORMAT_DXT1: "DXT1",
	Image.FORMAT_DXT3: "DXT3", Image.FORMAT_DXT5: "DXT5", Image.FORMAT_RGTC_R: "RGTC_R",
	Image.FORMAT_RGTC_RG: "RGTC_RG", Image.FORMAT_BPTC_RGBA: "BPTC", Image.FORMAT_ETC2_RGB8: "ETC2",
	Image.FORMAT_ETC2_RGBA8: "ETC2A", Image.FORMAT_ETC2_RG11: "ETC2_RG11",
	Image.FORMAT_ASTC_4x4: "ASTC4",
}

var _seen := {} # Texture rid -> row
var _mats := {}


static func report(root: Node, label: String = "TEX") -> Dictionary:
	var c = load("res://tools/texture_budget/tex_census.gd").new()
	return c._run(root, label)


static func estimate(tex: Texture) -> int:
	var w := 0
	var h := 0
	var layers := 1
	var fmt := -1
	var mips := false
	if tex is Texture2D:
		w = (tex as Texture2D).get_width()
		h = (tex as Texture2D).get_height()
		fmt = (tex as Texture2D).get_format() if tex.has_method("get_format") else -1
		mips = _mipped(tex)
	elif tex is Texture3D:
		w = (tex as Texture3D).get_width()
		h = (tex as Texture3D).get_height()
		layers = (tex as Texture3D).get_depth()
		fmt = (tex as Texture3D).get_format()
		mips = (tex as Texture3D).has_mipmaps()
	elif tex is TextureLayered:
		w = (tex as TextureLayered).get_width()
		h = (tex as TextureLayered).get_height()
		layers = (tex as TextureLayered).get_layers()
		fmt = (tex as TextureLayered).get_format()
		mips = (tex as TextureLayered).has_mipmaps()
	var bits: int = int(BPP.get(fmt, 32))
	var bytes := float(w) * h * layers * bits / 8.0
	if mips:
		bytes *= 4.0 / 3.0
	return int(bytes)


## CompressedTexture2D.has_mipmaps() reads false even when the file carries mipmaps (it is not
## overridden); the imported .ctex does say, and so does the image it decodes to.
static func _mipped(tex: Texture2D) -> bool:
	if tex.has_mipmaps():
		return true
	if tex is CompressedTexture2D and tex.resource_path != "":
		var key := tex.resource_path
		if _MIP_CACHE.has(key):
			return _MIP_CACHE[key]
		var img := tex.get_image()
		var m := img != null and img.has_mipmaps()
		_MIP_CACHE[key] = m
		return m
	return false


static var _MIP_CACHE := {}


func _run(root: Node, label: String) -> Dictionary:
	for n in root.find_children("*", "", true, false):
		_node(n)
	_node(root)
	for name in RenderingServer.global_shader_parameter_get_list():
		var v = RenderingServer.global_shader_parameter_get(name)
		if v is Texture:
			_tex(v, "global:" + String(name))
	var rows: Array = _seen.values()
	rows.sort_custom(func(a, b): return a.bytes > b.bytes)
	var total := 0
	var dirs := {}
	for r in rows:
		total += r.bytes
		var d: String = r.path.get_base_dir() if r.path.begins_with("res://") else "(code) " + r.owner.get_slice(":", 0)
		dirs[d] = int(dirs.get(d, 0)) + r.bytes
	var mb := 1.0 / 1048576.0
	print("%sMEM renderer textures=%.1f MB buffers=%.1f MB video=%.1f MB" % [label,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) * mb,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) * mb,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) * mb])
	print("%sSUM found=%d est=%.1f MB materials=%d" % [label, rows.size(), total * mb, _mats.size()])
	var top := int(OS.get_environment("TEX_TOP")) if OS.get_environment("TEX_TOP") != "" else 40
	if OS.get_environment("TEX_ALL") == "1":
		top = rows.size()
	for i in mini(top, rows.size()):
		var r = rows[i]
		print("%s %.2f %dx%d %s mips=%s %s" % [label, r.bytes * mb, r.w, r.h, r.fmt, r.mips,
			r.path if r.path != "" else "(code) " + r.owner])
	var dk := dirs.keys()
	dk.sort_custom(func(a, b): return dirs[a] > dirs[b])
	for d in dk:
		print("%sDIR %.1f MB %s" % [label, dirs[d] * mb, d])
	return {"found": rows.size(), "est": total, "renderer": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}


func _tex(t, owner: String) -> void:
	if not (t is Texture):
		return
	var tex := t as Texture
	var rid := tex.get_rid()
	if _seen.has(rid):
		return
	var w := 0
	var h := 0
	var fmt := -1
	var mips := false
	if tex is Texture2D:
		w = tex.get_width()
		h = tex.get_height()
		fmt = tex.get_format() if tex.has_method("get_format") else -1
		mips = _mipped(tex)
	elif tex is Texture3D or tex is TextureLayered:
		w = tex.get_width()
		h = tex.get_height()
		fmt = tex.get_format()
		mips = tex.has_mipmaps()
	_seen[rid] = {"bytes": estimate(tex), "w": w, "h": h, "fmt": FORMAT_NAMES.get(fmt, str(fmt)),
		"mips": mips, "path": tex.resource_path if not tex.resource_path.contains("::") else "",
		"owner": owner if not tex.resource_path.contains("::") or owner != "" else tex.resource_path}
	if tex.resource_path.contains("::") and _seen[rid].path == "":
		_seen[rid].owner = owner + " (" + tex.resource_path.get_file() + ")"


func _mat(m, owner: String) -> void:
	if m == null or not (m is Material) or _mats.has(m):
		return
	_mats[m] = true
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh:
			for u in sh.get_shader_uniform_list():
				_tex((m as ShaderMaterial).get_shader_parameter(u.name), owner + ":" + sh.resource_path.get_file())
	else:
		for p in m.get_property_list():
			if p.type == TYPE_OBJECT:
				var v = m.get(p.name)
				if v is Texture:
					_tex(v, owner + ":" + p.name)
				elif v is Material:
					_mat(v, owner)
	_mat(m.next_pass, owner)


func _mesh(mesh, owner: String) -> void:
	if mesh == null or not (mesh is Mesh):
		return
	for s in mesh.get_surface_count():
		_mat(mesh.surface_get_material(s), owner)


func _node(n: Node) -> void:
	var owner := n.name
	if n is GeometryInstance3D:
		_mat((n as GeometryInstance3D).material_override, owner)
		_mat((n as GeometryInstance3D).material_overlay, owner)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_mesh(mi.mesh, owner)
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				_mat(mi.get_surface_override_material(s), owner)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm:
			_mesh(mm.mesh, owner)
	elif n is CPUParticles3D:
		_mesh((n as CPUParticles3D).mesh, owner)
	elif n is GPUParticles3D:
		var gp := n as GPUParticles3D
		_mat(gp.process_material, owner)
		for i in gp.draw_passes:
			_mesh(gp.get_draw_pass_mesh(i), owner)
	elif n is Decal:
		for k in [Decal.TEXTURE_ALBEDO, Decal.TEXTURE_NORMAL, Decal.TEXTURE_ORM, Decal.TEXTURE_EMISSION]:
			_tex((n as Decal).get_texture(k), owner + ":decal")
	elif n is Light3D:
		_tex((n as Light3D).light_projector, owner + ":projector")
	elif n is WorldEnvironment:
		var env := (n as WorldEnvironment).environment
		if env:
			if env.sky:
				_mat(env.sky.sky_material, owner + ":sky")
			_tex(env.adjustment_color_correction, owner + ":lut")
	elif n is Camera3D and (n as Camera3D).environment:
		var env2 := (n as Camera3D).environment
		if env2.sky:
			_mat(env2.sky.sky_material, owner + ":sky")
	if n is CanvasItem:
		_mat((n as CanvasItem).material, owner)
		for p in ["texture", "texture_normal", "texture_progress", "texture_under", "texture_over"]:
			if p in n:
				_tex(n.get(p), owner)
	if n is Sprite3D or n is AnimatedSprite3D:
		if "texture" in n:
			_tex(n.get("texture"), owner)
