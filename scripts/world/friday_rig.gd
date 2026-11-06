class_name FridayRig
extends Node3D
## A FULL chunk's stadium lights on a game night (FridayLights.standard()): the standards'
## spotlights, whose energy follows DayNight.lamp_now on a slow tick (none by day; hidden below
## MEDIUM, where DayNight's lamp_scale is 0, and the light pools carry it), and the blooms over
## their lenses (one mesh, built once the chunk's standards are all in).

## [lens centre, facing (unit, flat), aim point] per standard (chunk space = true world).
var banks: Array = []
var spots: Array = []
var _bloom: MeshInstance3D = null
var _built := 0
var _timer := 0.0
var _dn: Node = null


func _process(delta: float) -> void:
	if banks.size() != _built:
		_built = banks.size()
		if _bloom == null:
			_bloom = MeshInstance3D.new()
			_bloom.name = "FridayBloom"
			_bloom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_bloom.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			add_child(_bloom)
		_bloom.mesh = FridayLights.bank_mesh(banks)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.4
	var level := smoothstep(0.05, 0.6, DayNight.lamp_now)
	var scale := 1.0
	if _dn == null or not is_instance_valid(_dn):
		var root := get_tree().current_scene if is_inside_tree() else null
		_dn = root.get_node_or_null("DayNight") if root else null
	if _dn and _dn.get("lamp_scale") != null:
		scale = float(_dn.get("lamp_scale"))
	var energy := FridayLights.SPOT_ENERGY * level * scale
	for s: SpotLight3D in spots:
		if is_instance_valid(s):
			s.light_energy = energy
			s.visible = energy > 0.01
