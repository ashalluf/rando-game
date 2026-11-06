class_name HillGround3
extends RefCounted
## The hills' ground pass of fleet wave 3 (hill-ground-3, docs/HANDOFF.md "Hills without leopard
## spots, again"): the A/B switch and the numbers it puts back.
##
## What changed: the fine erosion orders (erosion.gdshaderinc, the 55 m and 27 m gullies the
## terrain and the horizon plane draw as shading) were 7 m deep with their cells half a stripe out
## of phase, so every gully was a braid of deep pits - under an afternoon sun the dark LEOPARD
## SPOTS over every slope. They are 3 m deep, nearly in phase (continuous rills). The chaparral
## stands are masses of the land (the patch octaves, the drainage, the rills: hill_rill_th())
## rather than of the shrub-scale noise, and the shrubs that stand on them read from 20-150 m.
## HILL_GROUND_3=0 in the environment puts every old number back on the materials (apply()) and
## in HillPlanting.

## Metres out to which a chunk's chaparral shrubs (HillShrub) are drawn: the task's 150 m, the
## painted stands carrying them on past it. (CityChunk.hill_brush_distance, 110, is the old searsia's.)
const SHRUB_DISTANCE := 160.0

static var enabled: bool = OS.get_environment("HILL_GROUND_3") != "0"

## The uniforms as they were before this pass (and their new values live in the shaders).
const OLD := {
	"erosion_jitter": 0.5, "erosion_branch": 1.6, "erosion_amp": 7.0, "far_erosion_amp": 7.0,
	"stand_patch_w": 0.2, "stand_mid_w": 0.1, "stand_bush_w": 0.4, "stand_fine_w": 0.3,
	"stand_bias": 0.35, "rill_brush": 0.0, "stand_gaps": 1.0,
}


## Puts the old numbers on a hill ground material (terrain, shells, the horizon plane) when the
## pass is off; nothing when it is on. A uniform the shader does not have is skipped.
static func apply(mat: ShaderMaterial) -> void:
	if enabled or mat == null or mat.shader == null:
		return
	var names := {}
	for u in mat.shader.get_shader_uniform_list(true):
		names[u.name] = true
	for k: String in OLD:
		if names.has(k):
			mat.set_shader_parameter(k, OLD[k])
