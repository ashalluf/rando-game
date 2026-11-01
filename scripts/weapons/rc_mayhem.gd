class_name RcMayhem
extends RefCounted
## The mayhem reference camera's fixes (fleet wave 5, rc2-mayhem; docs/HANDOFF.md "The mayhem
## refcam"): a staged combat moment on Wilshire at 18:00 (tools/refcams/cameras_w5.json, staged
## by tools/refcams/mayhem_stage.gd) judged as an action-game screenshot. RC_MAYHEM=0 is the A/B.
##
##  - THE FIREBALL (blast_volume.gdshader `rc_look`): heat by depth into the ball, a sooty shell.
##  - THE POLICE POOL (police_wash.gdshader `rc_soft`): a soft falloff, not a disc of flat red.
##  - THE MUZZLE FLASH'S LIGHT (GunplayFeel's main light): a 9 m omni at 7 energy lit a flat salmon
##    disc on the road round the shooter, clipped to its range; a flash is a small source, so it
##    now lights a few metres, falling off steeply (`muzzle_range`, `muzzle_attenuation`).

static var enabled: bool = OS.get_environment("RC_MAYHEM") != "0"


## The volume material's look switch (Blast3.spawn_volume).
static func dress_volume(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc_look", 1.0 if enabled else 0.0)


## A cruiser's glow material (PoliceNightLook._make_glow).
static func dress_police(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc_soft", 1.0 if enabled else 0.0)


## The muzzle flash's light, out ahead of the muzzle (GunplayFeel._lights).
static var muzzle_range: float = 4.2
static var muzzle_attenuation: float = 2.2


static func dress_muzzle(light: OmniLight3D) -> void:
	if not enabled or light == null:
		return
	light.omni_range = minf(light.omni_range, muzzle_range)
	light.omni_attenuation = muzzle_attenuation
