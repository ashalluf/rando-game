class_name RcMayhem
extends RefCounted
## The mayhem reference camera's fixes (fleet wave 5, rc2-mayhem; docs/HANDOFF.md "The mayhem
## refcam"): a staged combat moment on Wilshire at 18:00 (tools/refcams/cameras_w5.json, staged
## by tools/refcams/mayhem_stage.gd) judged as an action-game screenshot. RC_MAYHEM=0 is the A/B.
##
##  (The fireball's own look is the explosions-4 session's: see the HANDOFF section for what this
##  camera found in it.)
##  - THE POLICE POOL (police_wash.gdshader `rc_soft`): a soft falloff, not a disc of flat red.
##  - THE MUZZLE FLASH'S LIGHT (GunplayFeel's main light): a 9 m omni at 7 energy lit a flat salmon
##    disc on the road round the shooter, clipped to its range; a flash is a small source, so it
##    now lights a few metres, falling off steeply (`muzzle_range`, `muzzle_attenuation`).
##  - A BURNING CAR'S LIGHT (CarDamage's fire light): 11 m at attenuation 1.4 stood as a flat red
##    disc on the road under a car on fire, cut at its range; inverse-square now, reaching further
##    and a little stronger close in, so it fades out long before its range (`fire_*`).

static var enabled: bool = OS.get_environment("RC_MAYHEM") != "0"



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


## A burning car's flickering light (CarDamage, made when the fire starts).
static var fire_range: float = 14.0
static var fire_attenuation: float = 2.0
static var fire_gain: float = 1.6


static func dress_fire_light(damage: Node, light: OmniLight3D) -> void:
	if not enabled or light == null:
		return
	light.omni_range = fire_range
	light.omni_attenuation = fire_attenuation
	if damage != null and not damage.has_meta("rc_fire"):
		damage.set_meta("rc_fire", true)
		damage.set("fire_light_energy", float(damage.get("fire_light_energy")) * fire_gain)
