class_name CacheTrim
## Static mesh caches that grow with the places visited (a street's name blades, a beach rider's
## suit, ...) keep every entry for the session, though a chunk that streamed out took its last
## user with it. trim() drops the entries nothing but the cache holds any more: a mesh still drawn
## somewhere has another reference (its MeshInstance3D / MultiMesh), so it stays, and an entry
## dropped is rebuilt the same way, from the same key, the next time it is asked for - the cache
## only ever saves time, never changes an answer (docs/HANDOFF.md, the perf-audit-3 section).
## An Array value counts as unused when every element is; a cache must then hand out copies made
## by copy() (a caller holding the cache's own array would not show in the elements' counts, and
## nor would one holding Array.duplicate()'s, which shares the elements copy-on-write).
## CACHE_TRIM=0 in the environment keeps everything (the A/B).

static var enabled := OS.get_environment("CACHE_TRIM") != "0"
## Entries dropped so far, for the checks and the memory probe.
static var dropped := 0


## Drops every entry of `cache` whose value is a RefCounted (or an Array of them) referenced by
## nothing but `cache` itself, plus `extra` other references each may legitimately have (another
## cache keying on it). Returns how many went.
static func trim(cache: Dictionary, extra: int = 0) -> int:
	if not enabled:
		return 0
	# What "held by the dictionary alone" reads as through these very calls: GDScript's
	# temporaries add their own references, so the number is measured, not assumed.
	# Built entry by entry, as a cache is (a literal [RefCounted.new()] keeps one more reference).
	var probe := {}
	probe["v"] = RefCounted.new()
	var list: Array = []
	list.append(RefCounted.new())
	probe["a"] = list
	var base_v := _refs(probe["v"])
	var base_a := _elem_refs(probe["a"])
	var gone := 0
	for k in cache.keys():
		var unused := false
		var t := typeof(cache[k])
		if t == TYPE_OBJECT and cache[k] is RefCounted:
			unused = _refs(cache[k]) <= base_v + extra
		elif t == TYPE_ARRAY and not (cache[k] as Array).is_empty():
			var r := _elem_refs(cache[k])
			unused = r >= 0 and r <= base_a + extra
		if unused:
			cache.erase(k)
			gone += 1
	dropped += gone
	return gone


static func _refs(v: Variant) -> int:
	return (v as RefCounted).get_reference_count()


## The highest reference count among an Array's elements, -1 if one is not a RefCounted.
static func _elem_refs(a: Array) -> int:
	var most := 0
	for e in a:
		if not (e is RefCounted):
			return -1
		most = maxi(most, (e as RefCounted).get_reference_count())
	return most


## A copy of `a` that holds its own reference to every element (unlike duplicate()).
static func copy(a: Array) -> Array:
	var out: Array = []
	out.resize(a.size())
	for i in a.size():
		out[i] = a[i]
	return out
