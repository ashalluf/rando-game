class_name Cars3
extends RefCounted
## The third wave of everyday bodies (tools/make_cars_3.py): a compact EV hatch, a mid-size
## luxury sedan, a boxy compact SUV, a full-size crew-cab work truck with a ladder rack and a
## 2-door sports coupe. They are ordinary Vehicles (BodyType EV_HATCH .. COUPE, appended), rolled by
## random_car() through Vehicle.ROLL_MAP: each takes the END of an older type's range and leaves its
## start where it was, and the rows they took carry the type that had them before as a third entry,
## which `CARS_3=0` (the A/B) hands back - so with the switch off every roll lands where it landed
## before this wave, bit for bit. Original designs and invented badges (a chevron), no real names.

## `CARS_3=0` in the environment: no new body is rolled (the rows fall back to their old owners).
static var enabled: bool = OS.get_environment("CARS_3") != "0"

const TYPES := [Vehicle.BodyType.EV_HATCH, Vehicle.BodyType.LUX_SEDAN, Vehicle.BodyType.COMPACT_SUV,
		Vehicle.BodyType.WORK_TRUCK, Vehicle.BodyType.COUPE]

## A work truck's look rolls a fleet job this often (Vehicle.random_car(), off the look seed).
const WORK_FLEET_SHARE := 0.55
## Fleet paints: white, a utility yellow, an off-white and a contractor's grey.
const WORK_FLEET_PAINTS := [Color(0.93, 0.93, 0.92), Color(0.88, 0.66, 0.08), Color(0.86, 0.85, 0.80),
		Color(0.36, 0.38, 0.40)]

## Vehicle._dims() for the five (tools/make_cars_3.py prints length, width, the WHEEL_POSE row and
## ride / road; "road" is where the physics wheels meet the road in body space, CONTACT in
## car_shot.gd, and traffic stands the car on it). lamp_y / tail_y are the lamps' model z + road.
const DIMS := {
	Vehicle.BodyType.EV_HATCH: {"length": 4.363, "width": 1.835, "lamp_y": 0.516, "tail_y": 0.79, "chassis_h": 0.7,
			"cabin": Vector2(-1.0, 2.3), "cabin_h": 0.7, "wheel_z": 1.315, "wheel_front": 1.270, "wheel_rear": 1.360,
			"track": 1.54, "tyre_r": 0.343, "ride": -0.153, "road": -0.170},
	Vehicle.BodyType.LUX_SEDAN: {"length": 5.199, "width": 1.868, "lamp_y": 0.455, "tail_y": 0.778, "chassis_h": 0.7,
			"cabin": Vector2(-1.2, 2.4), "cabin_h": 0.7, "wheel_z": 1.535, "wheel_front": 1.609, "wheel_rear": 1.461,
			"track": 1.62, "tyre_r": 0.34, "ride": -0.158, "road": -0.177},
	Vehicle.BodyType.COMPACT_SUV: {"length": 4.869, "width": 1.95, "lamp_y": 0.738, "tail_y": 0.97, "chassis_h": 0.8,
			"cabin": Vector2(-1.2, 3.0), "cabin_h": 0.85, "wheel_z": 1.35, "wheel_front": 1.460, "wheel_rear": 1.242,
			"track": 1.60, "tyre_r": 0.336, "ride": -0.154, "road": -0.173},
	Vehicle.BodyType.WORK_TRUCK: {"length": 6.257, "width": 2.03, "lamp_y": 0.88, "tail_y": 0.96, "chassis_h": 0.8,
			"cabin": Vector2(-1.4, 1.8), "cabin_h": 0.75, "wheel_z": 1.80, "wheel_front": 2.076, "wheel_rear": 1.534,
			"track": 1.72, "tyre_r": 0.37, "ride": -0.185, "road": -0.206},
	Vehicle.BodyType.COUPE: {"length": 4.732, "width": 1.904, "lamp_y": 0.445, "tail_y": 0.78, "chassis_h": 0.65,
			"cabin": Vector2(-0.9, 2.1), "cabin_h": 0.6, "wheel_z": 1.415, "wheel_front": 1.472, "wheel_rear": 1.358,
			"track": 1.62, "tyre_r": 0.34, "ride": -0.158, "road": -0.177},
}


static func is_cars_3(type: int) -> bool:
	return TYPES.has(type)


## The body a ROLL_MAP row hands out: its own, or with the switch off the type that had the slice
## before this wave (the row's third entry).
static func row_type(row: Array) -> int:
	if row.size() > 2 and not enabled:
		return int(row[2])
	return int(row[1])
