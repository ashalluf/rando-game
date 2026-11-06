class_name Motels
extends RefCounted
## Googie motor court motels (rc5-googie-motel, 2026-11-06; docs/HANDOFF.md "The Googie motel at
## 21:00"). BoulevardSigns stands a Googie motel pole sign at the front corner of some midtown
## surface car parks - and until now the car park stayed a car park: a motel sign with no motel.
## Now the lot whose corner the sign stands on is the motel it advertises: a two-storey L of rooms
## round a parking court open to the boulevard (the back wing, and a side wing on a wide lot), an
## open walkway on cantilevered slabs with a steel railing and a stair, a door, a curtained
## window, a wall AC sleeve and a sconce per room, a neon line under the fascia, the office in the
## front corner with a glass front, a stone wall and a swept roof, its OFFICE in neon; the court's
## stalls nose-in to the doors with the guests' cars in most of them (fuller when the sign says NO
## VACANCY), light pools under the walkways.
##
## Claimed in CityChunk._build_lot() just before the surface car park (the pad roll and every
## claim before it are made; the lot stays a "parking" lot for everything that reads the plan).
## Pure: the plan is BoulevardSigns.plan_poles() (hashes) and the lot; every roll here is a hash
## of seed + lot. FULL chunks build the motel (MotelKit, one mesh on shaders/motel.gdshader, box
## collision); LOD chunks and the far city get the wings and the office as lod_boxes over the
## lot's asphalt. MOTELS=0 in the environment is the A/B: the car park again.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("MOTELS") != "0"

## The room bay and storey (shaders/motel.gdshader's ROOM_W / STOREY: change both).
const ROOM_W := 4.0
const STOREY := 2.95
## The open walkway in front of the rooms, and the parapet over the top storey.
const WALK := 1.7
const PARAPET := 0.55
## A stall in front of each room and the aisle behind the stalls (m).
const STALL_D := 5.3
const AISLE := 6.0
## The office's footprint (m) and height.
const OFFICE := Vector2(6.2, 6.0)
const OFFICE_H := 3.6
## How full the court is: the sign's NO VACANCY lit, or not.
const FILL_FULL := 0.92
const FILL := 0.68
## Wall, trim and neon colourways (sRGB): [stucco, trim / doors, fascia accent, neon].
const LOOKS := [
	[Color(0.93, 0.9, 0.82), Color(0.13, 0.42, 0.45), Color(0.9, 0.42, 0.2), Color(0.1, 0.95, 0.85)],
	[Color(0.95, 0.88, 0.78), Color(0.62, 0.16, 0.14), Color(0.13, 0.36, 0.5), Color(1.0, 0.25, 0.45)],
	[Color(0.88, 0.9, 0.86), Color(0.2, 0.28, 0.4), Color(0.95, 0.72, 0.18), Color(0.25, 0.55, 1.0)],
	[Color(0.96, 0.82, 0.7), Color(0.16, 0.32, 0.22), Color(0.94, 0.94, 0.9), Color(1.0, 0.45, 0.12)],
	[Color(0.9, 0.86, 0.9), Color(0.36, 0.2, 0.38), Color(0.22, 0.55, 0.52), Color(0.95, 0.2, 0.9)],
]

static var _poles: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The Googie pole sign that stands at lot `lot`'s front corner, or {}.
static func pole_for(plan: CityPlan, ix: int, iz: int, lot: Dictionary) -> Dictionary:
	if not enabled or plan == null or not lot.get("parking", false):
		return {}
	var key := Vector3i(plan.seed, ix, iz)
	if not _poles.has(key):
		var found: Array = []
		for p: Dictionary in BoulevardSigns.plan_poles(plan, ix, iz):
			if int(p.kind) == BoulevardSigns.Pole.MOTEL and String(p.get("src", "")) == "park":
				found.append(p)
		if _poles.size() > 4096:
			_poles.clear()
		_poles[key] = found
	for p: Dictionary in _poles[key]:
		if int((p.id as Array)[0]) == int(lot.seed):
			return p
	return {}


static func claims(plan: CityPlan, ix: int, iz: int, lot: Dictionary) -> bool:
	return not pole_for(plan, ix, iz, lot).is_empty()


## The motel's plan in its lot frame: u along the boulevard from the sign's end, v in from the
## street. Pure (the lot, the pole, hashes).
static func layout(plan: CityPlan, ix: int, iz: int, lot: Dictionary, p: Dictionary) -> Dictionary:
	var cell: Rect2 = Alleys.trim(plan, ix, iz, LotFill._cell(lot))
	var d: Vector2 = p.along
	var n: Vector2 = p.out
	var c := cell.get_center()
	var U := absf(d.x) * cell.size.x + absf(d.y) * cell.size.y
	var V := absf(n.x) * cell.size.x + absf(n.y) * cell.size.y
	var O := c - d * U * 0.5 - n * V * 0.5
	var sd := int(lot.seed)
	var look := absi(hash([plan.seed, sd, "motel_look"])) % LOOKS.size()
	var depth := clampf(V - (WALK + STALL_D + AISLE + 1.5), 5.6, 7.6)
	var storeys := 2 if V - depth >= WALK + STALL_D + AISLE - 0.5 and V >= 22.0 else 1
	var wings: Array = []
	var side := U >= 30.0
	var vf := V - 0.4 - depth
	var uf := U - 0.4 - depth
	# The back wing: its facade at v = vf, facing the street (-n), rooms along u; its body runs to
	# the lot's far end, its rooms stop at the side wing's walkway.
	var rooms_L := (uf - WALK - 0.5) if side else (U - 1.0)
	wings.append({"o": O + d * 0.5 + n * vf, "al": d, "out": -n, "L": U - 0.9, "rooms_L": rooms_L,
		"D": depth, "storeys": storeys, "stair": 1, "key": 0})
	var office_u0 := uf if side else U - 0.5 - OFFICE.x
	if side:
		# The side wing: its facade at u = uf, facing the sign's end (-d), rooms along v from the
		# back wing's facade to behind the office.
		var v0 := OFFICE.y + 1.5
		if vf - v0 >= ROOM_W * 2.0:
			wings.append({"o": O + d * uf + n * vf, "al": -n, "out": -d, "L": vf - v0, "rooms_L": vf - v0,
				"D": depth, "storeys": storeys, "stair": 0, "key": 1})
	var office := {"u0": office_u0, "u1": office_u0 + (depth if side else OFFICE.x), "v0": 1.0, "v1": 1.0 + OFFICE.y}
	return {"O": O, "d": d, "n": n, "U": U, "V": V, "wings": wings, "office": office, "look": look,
		"seed": sd, "full": (int(p.flags) & 1) == 1, "storeys": storeys, "cell": cell}


## Builds lot `lot` (the caller has made every roll before this), at every level.
static func build_lot(ch: CityChunk, lot: Dictionary) -> bool:
	var p := pole_for(ch.plan, ch.ix, ch.iz, lot)
	if p.is_empty():
		return false
	var L := layout(ch.plan, ch.ix, ch.iz, lot, p)
	var cell: Rect2 = L.cell
	LotFill._ground(ch, cell, "asphalt")
	ch.building_count += 1
	if ch.level != CityChunk.Level.FULL or ch.capturing:
		_far(ch, L)
		return true
	MotelKit.build(ch, L)
	return true


## LOD chunks and the far city: each wing and the office as one box in its stucco.
static func _far(ch: CityChunk, L: Dictionary) -> void:
	var look: Array = LOOKS[int(L.look)]
	var wall: Color = look[0]
	var sd := int(L.seed)
	var base := CityChunk.SIDEWALK_TOP
	for w: Dictionary in L.wings:
		var H := float(w.storeys) * STOREY + PARAPET
		var al: Vector2 = w.al
		var out: Vector2 = w.out
		var c2: Vector2 = (w.o as Vector2) + al * float(w.L) * 0.5 - out * float(w.D) * 0.5
		var x := Vector3(al.x, 0.0, al.y) * float(w.L)
		var z := Vector3(out.x, 0.0, out.y) * float(w.D)
		var xf := Transform3D(Basis(x, Vector3.UP * H, z), Vector3(c2.x, base + H * 0.5, c2.y))
		ch._batch.add("lod_box", PropFactory.unit_box(), xf, Color(wall.r, wall.g, wall.b, 1.0),
				Color(0.25, 0.55, float(sd % 997) / 997.0, 0.0))
		ch._add_lod_shape(Vector3(absf(x.x) + absf(z.x), H, absf(x.z) + absf(z.z)), Vector3(c2.x, base + H * 0.5 + ch._gy(c2.x, c2.y), c2.y))
	var of: Dictionary = L.office
	var O: Vector2 = L.O
	var d: Vector2 = L.d
	var n: Vector2 = L.n
	var oc := O + d * (float(of.u0) + float(of.u1)) * 0.5 + n * (float(of.v0) + float(of.v1)) * 0.5
	var ox := Vector3(d.x, 0.0, d.y) * (float(of.u1) - float(of.u0))
	var oz := Vector3(n.x, 0.0, n.y) * (float(of.v1) - float(of.v0))
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis(ox, Vector3.UP * OFFICE_H, oz), Vector3(oc.x, base + OFFICE_H * 0.5, oc.y)),
			Color(wall.r, wall.g, wall.b, 1.0), Color(0.0, 0.9, float((sd + 7) % 997) / 997.0, 0.0))
