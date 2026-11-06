class_name FilmNightLights
extends Node3D
## The HMIs' real lights at a film shoot (FilmShootNight): SpotLight3Ds, not in `lamp_light`
## (DayNight drives those as OmniLight3Ds), so this node sets their energy from DayNight.lamp_now
## on a 0.3 s tick, and hides them while it is light (a light at zero energy still costs every
## pixel it reaches).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

var spots: Array[SpotLight3D] = []
var _timer := 0.0


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	_apply()


func _apply() -> void:
	var level := SunsetReview.light_level(clampf(DayNight.lamp_now, 0.0, 1.0)) * FilmShootNight.HMI_GAIN
	for s in spots:
		if not is_instance_valid(s):
			continue
		s.light_energy = level
		s.visible = level > 0.01
