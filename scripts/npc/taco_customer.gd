class_name TacoCustomer
extends StreetVendor
## Somebody waiting at a taco truck's window at night (TacoTruckNight's regulars, fleet wave 8 rc5
## `taco_truck_night`): stood at one of the truck's queue spots facing it, looking up at the
## window or the menu board, now and then talking to the one beside them, some texting while they
## wait. A StreetVendor that is not in the truck: shot, knocked, scared off and walking back to
## their spot like a cart vendor does (StreetVendor._work), in the crowd cap and the "pedestrian"
## group like anyone.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## Where the window is (in the parent chunk's space), set by StreetVendors.spawn_vendor.
var window_at := Vector3.INF
## Share of the regulars who text while they wait.
@export var texting_share: float = 0.35


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	if absi(hash([seed_value, "taco_text"])) % 1000 < int(texting_share * 1000.0):
		_carry = CrowdLife.Carry.TEXT


var _tbeat: float = 0.0


## Nobody's vendor: no customer of their own to talk to.
func _customer() -> Node3D:
	return null


func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok:
		return
	_tbeat -= delta
	if _tbeat > 0.0:
		return
	_tbeat = _life.randf_range(2.5, 7.0)
	if _one_shot_left > 0.0:
		return
	var r := _life.randf()
	var parent := get_parent() as Node3D
	if window_at != Vector3.INF and parent != null and r < 0.65:
		_life_look = parent.to_global(window_at + Vector3(0.0, _life.randf_range(-0.2, 0.5), 0.0))
	else:
		_life_look = Vector3.INF
	if _carry == CrowdLife.Carry.TEXT:
		_life_base = CrowdLife.IDLE
	else:
		_life_base = CrowdLife.TALK if r > 0.8 else (CrowdLife.FOLD if r > 0.65 else CrowdLife.IDLE)
	_life_clip = _life_base
