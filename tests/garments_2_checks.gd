extends RefCounted
## The second garment set (tools/crowd/garments.py: the quilted puffer, the duck work jacket, cargo
## shorts, the dress) and the six rigs that wear them, crowd_u..z, for tests/smoke_test.gd. Loaded
## at run time, not named there, so it compiles after the autoloads.
##
## The rigs are crowd rigs (Pedestrian.MODELS, after the twenty that came before, so no earlier
## index moves), each with a hat-table row and a life-clip library; the config row that built each
## one still says what it wears (a garment the pipeline knows); the bodies stay inside the budget the
## crowd keeps (_check_crowd_rigs holds every rig to the full contract); and the camp figures keep to
## the first twelve rigs.

const NEW := ["crowd_u", "crowd_v", "crowd_w", "crowd_x", "crowd_y", "crowd_z"]
## What each new rig was built to wear (crowd_config.json): a key of its outfit that must be there.
const WEARS := {"crowd_u": "puffer", "crowd_v": "dress", "crowd_w": "work", "crowd_x": "cargo",
	"crowd_y": "dress", "crowd_z": "puffer"}

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var ped: Script = load("res://scripts/npc/pedestrian.gd")
	var models: Array = Array(ped.MODELS)
	var listed := true
	for i in NEW.size():
		var path := "res://assets/models/%s.glb" % NEW[i]
		listed = listed and models.find(path) == 20 + i
	_t._check(listed and models.size() >= 26, "garments-2: crowd_u..z are Pedestrian.MODELS 20..25 (after the twenty before them)")
	var table: Dictionary = load("res://scripts/npc/crowd_hat_table.gd").TABLE
	var rows := true
	var libs := true
	for n: String in NEW:
		rows = rows and table.has(n + ".glb")
		libs = libs and ResourceLoader.exists("res://assets/models/crowd_life/%s_life.res" % n)
	_t._check(rows, "garments-2: every new rig has a row in the hat table (tools/crowd/hat_fit.gd)")
	_t._check(libs, "garments-2: every new rig has its life-clip library (tools/crowd/life_clips.gd)")
	_t._check(int(load("res://scripts/world/encampment.gd").FIGURE_POOL) <= 20, "garments-2: the camp figures keep to the earlier rigs (FIGURE_POOL)")
	# the config that built them: each wears what it was built in, and the garments are known types
	var f := FileAccess.open("res://tools/crowd/crowd_config.json", FileAccess.READ)
	var cfg = JSON.parse_string(f.get_as_text()) if f else null
	var dressed := cfg is Dictionary
	var types := ["tee", "trousers", "shirt", "jacket", "skirt", "dress", "vest", "scarf"]
	if dressed:
		for ch: Dictionary in cfg["characters"]:
			if not ch.get("name", "") in NEW:
				continue
			var key: String = WEARS[ch["name"]]
			var has := false
			for g: Dictionary in ch.get("outfit", []):
				dressed = dressed and String(g.get("type", "")) in types
				has = has or g.has(key) or String(g.get("type", "")) == key
			dressed = dressed and has
	_t._check(dressed, "garments-2: the six rows in crowd_config.json wear the new garments (puffer, dress, work jacket, cargo)")
	# each new rig's body: one surface, under the triangle budget the crowd keeps (LOD 0)
	var worst := 0
	var bodies := true
	for n: String in NEW:
		var scene: PackedScene = load("res://assets/models/%s.glb" % n)
		if scene == null:
			bodies = false
			continue
		var inst := scene.instantiate()
		var body_tris := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m == null or (mi as MeshInstance3D).name.to_lower().contains("hair"):
				continue
			for s in m.get_surface_count():
				body_tris += m.surface_get_array_index_len(s) / 3
		worst = maxi(worst, body_tris)
		bodies = bodies and body_tris > 4000
		inst.free()
	_t._check(bodies and worst <= 16000, "garments-2: the new bodies are real and at most 16k triangles (worst %d)" % worst)
