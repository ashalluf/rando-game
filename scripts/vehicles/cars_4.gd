class_name Cars4
extends RefCounted
## The fourth wave of everyday bodies (tools/make_cars_4.py, fleet wave 5 `car-variety-4`): a
## compact estate wagon, a 2-door muscle coupe, a big luxury SUV, a small kei-style city van and a
## 1970s full-size sedan. Ordinary Vehicles (BodyType WAGON .. CLASSIC, appended), rolled by
## random_car() through Vehicle.ROLL_MAP exactly like Cars3: each takes the END of an older type's
## range and leaves its start where it was; the rows they took carry the type that had them as a
## third entry and a 4 as a fourth (the wave), which `CARS_4=0` (the A/B) hands back - so with the
## switch off every roll lands where it landed before this wave, bit for bit. Original designs,
## invented badges, no real names.

## `CARS_4=0` in the environment: no new body is rolled (the rows fall back to their old owners).
static var enabled: bool = OS.get_environment("CARS_4") != "0"

## The wave's tag in a ROLL_MAP row (its fourth entry).
const WAVE := 4

const TYPES := [Vehicle.BodyType.WAGON, Vehicle.BodyType.MUSCLE, Vehicle.BodyType.LUX_SUV,
		Vehicle.BodyType.KEI_VAN, Vehicle.BodyType.CLASSIC]

## The 1970s sedan's paints: the decade's colours, as a cherished classic keeps them (gloss).
## Harvest gold, avocado, a chocolate brown, a burgundy, cream, a baby blue, a deep bronze.
const CLASSIC_PAINTS := [Color(0.72, 0.52, 0.14), Color(0.36, 0.40, 0.16), Color(0.24, 0.14, 0.08),
		Color(0.36, 0.05, 0.07), Color(0.86, 0.82, 0.68), Color(0.50, 0.66, 0.80), Color(0.42, 0.26, 0.12)]
## A city van is a work van more often than not: white, then a pale grey or a sky blue.
const KEI_FLEET_SHARE := 0.6
const KEI_FLEET_PAINTS := [Color(0.94, 0.94, 0.93), Color(0.94, 0.94, 0.93), Color(0.78, 0.80, 0.82),
		Color(0.62, 0.76, 0.86)]
## Muscle coupes come in loud paint more often than the street's greys.
const MUSCLE_LOUD_SHARE := 0.55
const MUSCLE_PAINTS := [Color(0.80, 0.30, 0.03), Color(0.62, 0.02, 0.03), Color(0.95, 0.72, 0.05),
		Color(0.05, 0.22, 0.55), Color(0.10, 0.36, 0.20), Color(0.02, 0.02, 0.025)]

## Vehicle._dims() for the five (tools/make_cars_4.py prints length, width, the WHEEL_POSE row and
## ride / road; "road" is where the physics wheels meet the road in body space, CONTACT in
## car_shot.gd, and traffic stands the car on it). lamp_y / tail_y are the lamps' model z + road.
const DIMS := {
	Vehicle.BodyType.WAGON: {"length": 4.903, "width": 1.836, "lamp_y": 0.48, "tail_y": 0.86, "chassis_h": 0.7,
			"cabin": Vector2(-1.4, 2.8), "cabin_h": 0.72, "wheel_z": 1.43, "wheel_front": 1.545, "wheel_rear": 1.325,
			"track": 1.54, "tyre_r": 0.343, "ride": -0.153, "road": -0.170},
	Vehicle.BodyType.MUSCLE: {"length": 4.742, "width": 1.960, "lamp_y": 0.38, "tail_y": 0.64, "chassis_h": 0.65,
			"cabin": Vector2(-0.9, 2.1), "cabin_h": 0.58, "wheel_z": 1.415, "wheel_front": 1.467, "wheel_rear": 1.363,
			"track": 1.64, "tyre_r": 0.34, "ride": -0.158, "road": -0.177},
	Vehicle.BodyType.LUX_SUV: {"length": 5.621, "width": 2.168, "lamp_y": 0.90, "tail_y": 1.11, "chassis_h": 0.85,
			"cabin": Vector2(-1.2, 3.4), "cabin_h": 0.9, "wheel_z": 1.595, "wheel_front": 1.715, "wheel_rear": 1.475,
			"track": 1.74, "tyre_r": 0.382, "ride": -0.193, "road": -0.215},
	Vehicle.BodyType.KEI_VAN: {"length": 3.627, "width": 1.528, "lamp_y": 0.52, "tail_y": 0.62, "chassis_h": 0.75,
			"cabin": Vector2(-1.4, 3.0), "cabin_h": 1.0, "wheel_z": 1.197, "wheel_front": 1.045, "wheel_rear": 1.349,
			"track": 1.26, "tyre_r": 0.316, "ride": -0.134, "road": -0.149},
	Vehicle.BodyType.CLASSIC: {"length": 5.698, "width": 1.90, "lamp_y": 0.435, "tail_y": 0.62, "chassis_h": 0.7,
			"cabin": Vector2(-1.2, 2.4), "cabin_h": 0.62, "wheel_z": 1.475, "wheel_front": 1.536, "wheel_rear": 1.414,
			"track": 1.49, "tyre_r": 0.329, "ride": -0.148, "road": -0.165},
}


static func is_cars_4(type: int) -> bool:
	return TYPES.has(type)


## The body a ROLL_MAP row hands out. A row this wave took ([end, type, old, WAVE]) goes back to
## its old owner under `CARS_4=0`; everything else is Cars3's rule (its own rows under `CARS_3=0`).
static func row_type(row: Array) -> int:
	if row.size() > 3 and int(row[3]) == WAVE:
		return int(row[2]) if not enabled else int(row[1])
	return Cars3.row_type(row)


## The paint a new body's look rolls (off the look seed only, after every rng call): the classic's
## decade palette always, the city van's fleet white most of the time, the muscle coupe's loud
## paint about half the time. Returns [color, finish] or [] to keep what random_car() rolled.
static func paint_for(type: int, look: int) -> Array:
	match type:
		Vehicle.BodyType.CLASSIC:
			return [CLASSIC_PAINTS[absi(hash([look, 41])) % CLASSIC_PAINTS.size()], Vehicle.Finish.GLOSS]
		Vehicle.BodyType.KEI_VAN:
			if float(absi(hash([look, 42])) % 1000) / 1000.0 < KEI_FLEET_SHARE:
				return [KEI_FLEET_PAINTS[absi(hash([look, 43])) % KEI_FLEET_PAINTS.size()], Vehicle.Finish.GLOSS]
		Vehicle.BodyType.MUSCLE:
			if float(absi(hash([look, 44])) % 1000) / 1000.0 < MUSCLE_LOUD_SHARE:
				return [MUSCLE_PAINTS[absi(hash([look, 45])) % MUSCLE_PAINTS.size()], Vehicle.Finish.GLOSS]
	return []
