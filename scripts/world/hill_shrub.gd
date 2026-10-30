class_name HillShrub
extends RefCounted
## The hills' chaparral shrub, built in code (hill-ground-3): a ground-hugging mound of chamise
## and scrub oak, several stems out of the root crown and a dense, rounded head of small grey-green
## leaves all the way down to the ground. It replaces the Poly Haven searsia on the painted stands
## (CityChunk._plant_hills): that one is a sparse tree-like shrub on a leaf atlas that is three
## quarters black, so from twenty metres on every stand was a scatter of dark sprigs over the paint
## and the hills read as bare ground with soot on it.
##
## LaTrees' machinery does the work (its clusters, twigs and leaf sprigs, the emitter, the
## measured LOD ladder, the shadow twin, la_tree.gdshader); only the grower is ours, because
## LaTrees' broad crown starts a metre over its fork - a lollipop, not a mound. Built once per
## variant and cached; warmed on the loading screen with LaTrees (warm()).

const VARIANTS := 3
## Native height (metres, the leaves' top); instances are scaled to the planted height. The dome
## is grown to CROWN_TOP and its sprigs stand out over it to about this.
const HEIGHT := 2.8
const CROWN_TOP := 2.2
## Leaf colours (linear, LaTrees' vertex colours): the dusty grey-green of chamise and scrub oak
## in late summer, a little lighter than the painted stand (whose colour holds the shade between
## the bushes).
const LEAF := [Color(0.084, 0.102, 0.062), Color(0.132, 0.146, 0.092)]
const BARK := Color(0.26, 0.22, 0.18)

static var _cache := {}
static var _mat: ShaderMaterial = null


## Variant `v`'s mesh (the LOD ladder; its shadow twin is registered with PropFactory).
static func mesh(v: int) -> Mesh:
	v = posmod(v, VARIANTS)
	if _cache.has(v):
		return _cache[v]
	var data := _grow(v)
	var levels: Array = []
	for l in LaTrees.LEVELS.size():
		levels.append(LaTrees._emit(data, LaTrees.LEVELS[l]))
	var edges := LaTrees._edges(data)
	var m := LaTrees._ladder(levels, edges, 0)
	m.surface_set_material(0, material())
	m.set_meta("foliage_ladder", true)
	var tw := LaTrees._ladder(levels, edges, LaTrees.SHADOW_LEVEL)
	tw.surface_set_material(0, material())
	PropFactory._shadow_proxies[m] = tw
	_cache[v] = m
	return m


## The shared material: la_tree.gdshader with a stiff shrub's wind and a dull, dusty leaf.
static func material() -> ShaderMaterial:
	if _mat:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/la_tree.gdshader")
	_mat.set_shader_parameter("bend_scale", 0.004)
	_mat.set_shader_parameter("flutter", 0.012)
	_mat.set_shader_parameter("leaf_roughness", 0.82)
	_mat.set_shader_parameter("leaf_specular", 0.22)
	_mat.set_shader_parameter("translucency", 0.25)
	_mat.set_shader_parameter("underside", Vector3(1.2, 1.22, 1.15))
	return _mat


## Builds every variant (the loading screen) and returns the material.
static func warm() -> Array:
	for v in VARIANTS:
		mesh(v)
	return [material()]


## A mound: stems fanning out of the root crown, clusters filling a squat dome from 0.25 m up,
## pushed toward its shell (the inside of a real shrub is bare wood).
static func _grow(v: int) -> LaTrees.TreeData:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["hill_shrub", v])
	var d := LaTrees.TreeData.new()
	var cr := Vector2(1.55 + 0.15 * v, 1.05)
	var centre := Vector3(0.0, CROWN_TOP - cr.y, 0.0)
	d.crown = {"centre": centre, "radii": Vector3(cr.x, cr.y, cr.x)}
	var p := {"cluster_r": 0.46, "leaves": 14, "leaf_len": 0.3, "leaf_w": 0.2, "leaf_kind": LaTrees.L_SPRIG,
		"sprig": 0, "mode": "up", "leaf_segs": 1, "droop": 0.0, "cluster_style": 0}
	d.leaf_len = p.leaf_len
	d.cluster_r = p.cluster_r
	var pts: Array[Vector3] = []
	var tries := 0
	while pts.size() < 120 and tries < 4000:
		tries += 1
		var u := LaTrees._rand_unit(rng) * pow(rng.randf(), 0.3)
		var q := centre + Vector3(u.x * cr.x, u.y * cr.y, u.z * cr.x)
		# Lumpy: a few lobes bulge out, so the outline is not a perfect dome.
		var lobe := 1.0 + 0.12 * sin(atan2(q.z, q.x) * (3.0 + v) + float(v))
		if Vector2(q.x, q.z).length() > cr.x * lobe or q.y < 0.25:
			continue
		pts.append(q)
	# Stems: out of a root crown 0.3 m across, each to a point a third of the way out under the head.
	var stems := 5 + v
	var tops: Array[Vector3] = []
	for k in stems:
		var a := TAU * (float(k) + rng.randf_range(-0.3, 0.3)) / float(stems)
		var base := Vector3(cos(a), 0.0, sin(a)) * 0.15
		var top := Vector3(cos(a) * cr.x * 0.45, centre.y * rng.randf_range(0.8, 1.15), sin(a) * cr.x * 0.45)
		var line := LaTrees._bend(base, base.lerp(top, 0.5) + LaTrees._rand_unit(rng) * 0.12, top, 6)
		d.tubes.append(LaTrees._tube(line, LaTrees._taper(line, 0.045, 0.02, 0.3), LaTrees.B_OLIVE, BARK, 5))
		tops.append(top)
	for q in pts:
		var best := 0
		for k in stems:
			if q.distance_squared_to(tops[k]) < q.distance_squared_to(tops[best]):
				best = k
		var te := q - (q - centre).normalized() * 0.1
		var twig := LaTrees._bend(tops[best], tops[best].lerp(te, 0.5) + Vector3.UP * 0.1, te, 3)
		d.tubes.append(LaTrees._tube(twig, LaTrees._taper(twig, 0.016, 0.006), LaTrees.B_OLIVE, BARK, 3))
		d.clusters.append(LaTrees._cluster(p, rng, q, centre, cr, LaTrees.L_SPRIG, LEAF))
	return d
