extends RefCounted
## The gate, third pass (docs/HANDOFF.md "The gate, third pass"): the reset puts back a static
## pointer to the city's own node that a second instance took or nulled, and the shards' deal gives
## every part to exactly one share with the table the gate was refreshed from.


func run(t, city: Node3D) -> void:
	var reset = t._reset
	if reset == null:
		t._check(false, "gate speed 3: the smoke test has its reset")
		return
	# A singleton pointer: StreetSounds._inst nulled (a second city's StreetSounds leaving), then
	# pointed at a node outside the city (one still queued for deletion).
	var own: Node = StreetSounds._inst
	var held: bool = own != null and is_instance_valid(own) and city.is_ancestor_of(own)
	t._check(held, "gate speed 3: the reset knows the city's StreetSounds (the snapshot's pointer)")
	if held:
		StreetSounds._inst = null
		reset.light()
		var back_from_null: bool = StreetSounds._inst == own
		var stray := StreetSounds.new()
		StreetSounds._inst = stray
		reset.light()
		var back_from_stray: bool = StreetSounds._inst == own
		stray.free()
		StreetSounds._inst = own
		t._check(back_from_null and back_from_stray,
			"gate speed 3: the reset puts a nulled or stray singleton pointer back on the city's node (null %s, stray %s)" % [back_from_null, back_from_stray])
	# The deal: every part in exactly one share, for 2 and 3 shards.
	var all: Array = t.all_parts()
	var ok := true
	for n in [2, 3]:
		var seen := {}
		for share: Array in t.shard_plan(n):
			for part in share:
				ok = ok and not seen.has(part)
				seen[part] = true
		ok = ok and seen.size() == all.size()
	t._check(ok, "gate speed 3: the deal gives every one of the %d parts to exactly one share" % all.size())
	# Every part but a handful of brand-new files has a measured cost (the table is fresh).
	var missing := 0
	for part in all:
		if not (t.get_script().PART_COST as Dictionary).has(part):
			missing += 1
	var table: Dictionary = t.get_script().PART_COST
	t._check(table.has("room") and table.has("city_crowd") and float(missing) < all.size() * 0.25,
		"gate speed 3: PART_COST has the room, the city parts and most files (%d of %d dealt at the default)" % [missing, all.size()])
