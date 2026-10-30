extends RefCounted
## Six more kinds of Los Angeles adult (tools/crowd: the tailored jacket and the tie, the tank top,
## wide-leg trousers, gym shorts) and the rigs that wear them, crowd_aa..af, for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
## Reads files and rig scenes only: nothing here leans on where an earlier check left the player,
## the weather or the crowd.

const NEW := ["crowd_aa", "crowd_ab", "crowd_ac", "crowd_ad", "crowd_ae", "crowd_af"]
## What each new rig was built to wear (crowd_config.json): a garment type, or a key one carries.
const WEARS := {"crowd_aa": ["tailored", "tie"], "crowd_ab": ["tailored", "skirt"], "crowd_ac": ["work"],
	"crowd_ad": ["knit", "over"], "crowd_ae": ["tank", "athletic"], "crowd_af": ["wide", "jacket"]}
const TYPES := ["tee", "trousers", "shirt", "jacket", "skirt", "dress", "vest", "scarf", "tailored", "tie"]
## The earlier rigs, in their places: appended after them, so no earlier MODELS index moves.
const BEFORE := 26

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var ped: Script = load("res://scripts/npc/pedestrian.gd")
	var models: Array = Array(ped.MODELS)
	var listed := models.size() >= BEFORE + NEW.size()
	for i in NEW.size():
		listed = listed and models.find("res://assets/models/%s.glb" % NEW[i]) == BEFORE + i
	listed = listed and models.find("res://assets/models/crowd_z.glb") == BEFORE - 1
	_t._check(listed, "crowd-variety: crowd_aa..af are Pedestrian.MODELS 26..31, after the twenty-six before them")
	var ab := Array(ped.VARIETY_MODELS) == models.slice(BEFORE, BEFORE + NEW.size())
	_t._check(ab, "crowd-variety: CROWD_VARIETY=0 leaves out exactly the six new rigs (Pedestrian.VARIETY_MODELS)")
	var table: Dictionary = load("res://scripts/npc/crowd_hat_table.gd").TABLE
	var rows := true
	var libs := true
	for n: String in NEW:
		rows = rows and table.has(n + ".glb")
		libs = libs and ResourceLoader.exists("res://assets/models/crowd_life/%s_life.res" % n) \
			and ResourceLoader.exists("res://assets/models/crowd_busk/%s_busk.res" % n)
	_t._check(rows, "crowd-variety: every new rig has a hat-table row (tools/crowd/hat_fit.gd)")
	_t._check(libs, "crowd-variety: every new rig has its life and busk clip libraries")
	_t._check(not NEW.any(func(n): return "res://assets/models/%s.glb" % n in ped.NO_HAT_MODELS),
		"crowd-variety: the new rigs all take the crowd's hats")
	# the config that built them: adults only, each in what it was built to wear, known garments
	var f := FileAccess.open("res://tools/crowd/crowd_config.json", FileAccess.READ)
	var cfg = JSON.parse_string(f.get_as_text()) if f else null
	var dressed := cfg is Dictionary
	var adults := dressed
	var seen := 0
	if dressed:
		for ch: Dictionary in cfg["characters"]:
			if not ch.get("name", "") in NEW:
				continue
			seen += 1
			adults = adults and float(ch.get("phenotype", {}).get("age", 0.0)) >= 0.44
			for key: String in WEARS[ch["name"]]:
				var has := false
				for g: Dictionary in ch.get("outfit", []):
					dressed = dressed and String(g.get("type", "")) in TYPES
					has = has or g.has(key) or String(g.get("type", "")) == key or String(g.get("style", "")) == key
				dressed = dressed and has
	_t._check(dressed and seen == NEW.size(), "crowd-variety: the six config rows wear the new garments (suit and tie, blazer and skirt, work shirt, cardigan over a shirt, tank and gym shorts, cropped jacket and wide trousers)")
	_t._check(adults, "crowd-variety: every new rig is an adult (no children in the crowd)")
	# the bodies: one masked body plus hair cards, a varied set of builds, inside the crowd's budget
	var worst := 0
	var bodies := true
	var heights: Array[float] = []
	for n: String in NEW:
		var scene: PackedScene = load("res://assets/models/%s.glb" % n)
		if scene == null:
			bodies = false
			continue
		var inst := scene.instantiate()
		var body_tris := 0
		var hair := false
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m == null:
				continue
			if (mi as MeshInstance3D).name.to_lower().contains("hair"):
				hair = true
				continue
			for s in m.get_surface_count():
				body_tris += m.surface_get_array_index_len(s) / 3
		var skel: Skeleton3D = null
		for k in inst.find_children("*", "Skeleton3D", true, false):
			skel = k
		if skel != null and skel.find_bone("Head") >= 0:
			heights.append(skel.get_bone_global_rest(skel.find_bone("Head")).origin.y)
		worst = maxi(worst, body_tris)
		bodies = bodies and body_tris > 4000 and hair
		inst.free()
	_t._check(bodies and worst <= 16500, "crowd-variety: the new bodies are real, with hair cards, at most 16.5k triangles (worst %d)" % worst)
	var spread := 0.0
	if heights.size() == NEW.size():
		spread = heights.max() - heights.min()
	_t._check(spread > 0.05, "crowd-variety: the six are of different heights (head rest heights spread %.1f rig units)" % spread)
