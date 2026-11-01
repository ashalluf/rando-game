class_name CrowdFaces
extends RefCounted
## The crowd's faces up close (character.gdshader's face pass, docs/HANDOFF.md "The crowd's faces").
## Within `REACH` metres of the camera, on the region-masked crowd rigs: living eyes (the iris moved
## across the eyeball for saccades and eye contact, a blink painted down from the upper lid, the
## socket's shade, a sclera that is not paper), and the face's skin from a per-rig face map (blood
## under the cheeks, nose, lips and ears; the cavities under the eyes and in the creases; an oily
## T-zone; lips that are lips; finer pores and a broken-up sheen; light through skin only where it
## is thin). Nothing per person on the CPU: the timing is a hash of each instance's own scale in the
## shader, so the shared look materials stay shared.
##
## The data per rig comes from tools/crowd_faces/face_fit.gd (CrowdFaceTable + crowd_faces.png);
## a rig with no row keeps the pass off. CROWD_FACES=0 in the environment is the A/B.

const ATLAS := "res://assets/textures/crowd/crowd_faces.png"
## Metres from the camera the pass runs to (it fades out over the last quarter).
const REACH := 11.0

static var _on: int = -1


static func enabled() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("CROWD_FACES") == "0" else 1
	return _on == 1


## The table row for a body atlas (crowd_x_body.jpg -> "crowd_x"), or {}.
static func row_for(albedo: Texture2D) -> Dictionary:
	if albedo == null:
		return {}
	var key := albedo.resource_path.get_file().get_basename().trim_suffix("_body")
	return CrowdFaceTable.TABLE.get(key, {})


## Sets the face pass on a crowd look material made from `albedo` (Pedestrian.character_material).
## No rolls, so nothing a seed builds moves.
static func apply(mat: ShaderMaterial, albedo: Texture2D) -> void:
	if mat == null or not enabled() or not ResourceLoader.exists(ATLAS):
		return
	var row := row_for(albedo)
	if row.is_empty():
		return
	var tile: int = row.tile
	var cols := float(CrowdFaceTable.COLS)
	var rows := float(CrowdFaceTable.ROWS)
	var r: Array = row.rect
	var el: Array = row.eye_l
	var er: Array = row.eye_r
	var lid: Array = row.lid
	mat.set_shader_parameter("face_pass", 1.0)
	mat.set_shader_parameter("face_map", load(ATLAS))
	mat.set_shader_parameter("face_rect", Vector4(r[0], r[1], r[2], r[3]))
	mat.set_shader_parameter("face_tile", Vector4(float(tile % CrowdFaceTable.COLS) / cols, float(tile / CrowdFaceTable.COLS) / rows, 1.0 / cols, 1.0 / rows))
	mat.set_shader_parameter("eye_l_c", Vector4(el[0], el[1], 0.0, 0.0))
	mat.set_shader_parameter("eye_l_j", Vector4(el[2], el[3], el[4], el[5]))
	mat.set_shader_parameter("eye_r_c", Vector4(er[0], er[1], 0.0, 0.0))
	mat.set_shader_parameter("eye_r_j", Vector4(er[2], er[3], er[4], er[5]))
	mat.set_shader_parameter("lid_uv", Vector4(lid[0], lid[1], lid[2], lid[3]))
	mat.set_shader_parameter("face_reach", REACH)


## character.gdshader's face_h(), bit for bit as far as float32 lets it (tests only: the shader is
## what draws).
static func _h(n: float) -> float:
	var x := sin(n * 12.9898 + 4.1414) * 43758.5453
	return x - floor(x)


## character.gdshader's face_blink(): the upper lid's closure 0..1 at time t for a person's seed.
## The checks hold the shader's numbers (BLINK_*) to these.
const BLINK_SLOT := 3.7
const BLINK_CLOSE := 0.07
const BLINK_SHUT := 0.1
const BLINK_OPEN := 0.13
static func blink(seed: float, t: float) -> float:
	var slot := floorf(t / BLINK_SLOT)
	var ph := t - slot * BLINK_SLOT
	var h := _h(slot * 7.31 + seed * 91.7)
	var b := 0.0
	for k in 2:
		var start := 0.3 + h * 2.9 + float(k) * 0.34
		var dt := ph - start
		var c := 0.0
		if dt >= 0.0:
			if dt < BLINK_CLOSE:
				c = dt / BLINK_CLOSE
			elif dt < BLINK_SHUT:
				c = 1.0
			else:
				c = 1.0 - clampf((dt - BLINK_SHUT) / BLINK_OPEN, 0.0, 1.0)
		if k == 0 or h > 0.82:
			b = maxf(b, c)
	return b
