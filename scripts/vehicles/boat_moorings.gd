class_name BoatMoorings
extends RefCounted
## Where the player's boats wait (Boat): side-tied along the water side of the marina's east
## headwalk, in the aisle between its two southernmost main docks - the SALTRUNNER 24 bow north
## and the WAVEKITE astern of it - so the player walks down the gangway, along the headwalk and
## gets in. Worked out from the marina's plan (Marina.docks), pure; each boat's look is a hash of
## the seed. Built by the FULL chunk that owns the spot (MarinaBuild's last step, one line),
## owned like a parked car: under the city root, in the chunk's `_cars`, freed with the chunk
## unless the player drove it off. `BOATS=0` (Boat.enabled): none.

## The two boats' places: [kind, metres south (+z) of the aisle's middle, metres out
## from the headwalk's water edge to the hull's side].
const PLACES := [[BoatKit.Kind.SPEEDBOAT, -2.5, 0.45], [BoatKit.Kind.JETSKI, 6.5, 0.35]]


## The spots: [{"p": Vector2 (true world XZ), "yaw", "kind", "look"}], or [] with no marina.
static func spots(mr: Marina) -> Array:
	var out: Array = []
	if mr == null or not mr.ok or mr.docks.is_empty():
		return out
	var head: Dictionary = mr.docks[0]
	var x_root := (head.a as Vector2).x - Marina.HEAD_W * 0.5
	var mains: Array[float] = []
	for d: Dictionary in mr.docks:
		if d.kind == "main":
			mains.append((d.a as Vector2).y)
	mains.sort()
	var z_mid := 0.0
	if mains.size() >= 2:
		z_mid = (mains[mains.size() - 1] + mains[mains.size() - 2]) * 0.5
	else:
		z_mid = ((head.a as Vector2).y + (head.b as Vector2).y) * 0.5
	for pl: Array in PLACES:
		var k: int = pl[0]
		var beam: float = (BoatKit.SIZE[k] as Vector2).y
		var p := Vector2(x_root - float(pl[2]) - beam * 0.5, z_mid + float(pl[1]))
		if not mr.in_water(p):
			continue
		out.append({"p": p, "yaw": 0.0, "kind": k, "look": absi(hash([mr.seed_value, "boat", k]))})
	return out


## Builds the boats whose spot this FULL chunk owns.
static func build(c: CityChunk) -> void:
	if not Boat.enabled or c.capturing or c.level != CityChunk.Level.FULL:
		return
	var m: MacroMap = c.plan.macro
	if m == null or m.marina == null:
		return
	var own := c.owned_rect()
	var holder: Node = c.get_parent() if c.get_parent() else c
	for sp: Dictionary in spots(m.marina):
		var p: Vector2 = sp.p
		if not own.has_point(p):
			continue
		var b := Boat.new()
		b.name = "Boat_%d" % int(sp.kind)
		b.setup_boat(int(sp.kind), int(sp.look))
		var at := Vector3(p.x, Marina.WATER_Y, p.y)
		b.position = WorldState.to_local(at) if holder != c else at
		b.rotation.y = float(sp.yaw)
		holder.add_child(b)
		b.visible = c.visible
		c._cars.append(b)
