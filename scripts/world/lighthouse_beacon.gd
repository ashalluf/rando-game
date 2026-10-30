class_name LighthouseBeacon
extends Node3D
## Turns a lighthouse's lens (Lighthouses.LIGHTS): this node is the rotor, its children - the lens
## barrel, the drawn beams, the far point light and (near copies on Forward+ with volumetric fog)
## the SpotLight3Ds - are laid along its local +X and turn with it. Everything the shaders need is
## in the node's own transform (lighthouse_lamp.gdshader and lighthouse_lens.gdshader read the
## beam axis off MODEL_MATRIX), so there is no per-frame uniform and the near and far copies of a
## light, built apart, turn in step: the angle is worked out from the real clock, never ticked.
## Paused (the pause menu, photo mode) it holds where it is, as everything else does.

## Seconds a full turn takes, and the start angle (turns).
@export var period: float = 20.0
@export var phase: float = 0.0
## The beams' drawn shafts and the spots (hidden by day, they cost nothing then).
var beams: Array[Node3D] = []
var spots: Array[SpotLight3D] = []
## Spot energy and volumetric energy at full night.
var spot_energy: float = 18.0
var spot_fog: float = 6.0

## A clock only the tests and stills move (LIGHTHOUSE_T=seconds in the environment holds it).
static var hold_t: float = -1.0
static var _hold_read: bool = false


static func clock() -> float:
	if not _hold_read:
		_hold_read = true
		var e := OS.get_environment("LIGHTHOUSE_T")
		if e != "":
			hold_t = float(e)
	if hold_t >= 0.0:
		return hold_t
	return float(Time.get_ticks_msec()) / 1000.0


## The rotor's yaw (radians) at clock `t`: clockwise seen from above, as real lenses turn.
static func angle_at(t: float, turn_period: float, turn_phase: float) -> float:
	return -TAU * fposmod(t / turn_period + turn_phase, 1.0)


func _ready() -> void:
	_turn()


func _process(_delta: float) -> void:
	_turn()


func _turn() -> void:
	rotation = Vector3(0.0, angle_at(clock(), period, phase), 0.0)
	var lamp := DayNight.lamp_now
	var dark := lamp > 0.02
	for b in beams:
		if is_instance_valid(b) and b.visible != dark:
			b.visible = dark
	for s in spots:
		if is_instance_valid(s):
			s.visible = dark
			s.light_energy = spot_energy * lamp
			s.light_volumetric_fog_energy = spot_fog
