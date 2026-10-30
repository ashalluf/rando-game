class_name RefineryFar
extends Node3D
## The refinery as the far city sees it (Refinery): one far piece per block of the site - the plant
## at `detail` false (no rails, ladders, small pipes; fewer sides), its lamps, flames and steam -
## built once at load with the far landmarks (CityStreamer._build_far_landmarks()) and always
## present, so the tank farm, the stacks and the city of lights read from the freeway, the hills
## and the night aerial. A FULL chunk of the site builds its block in detail and leaves a
## RefineryCover, which hides that block's far piece while the chunk is shown (polled a few times a
## second). LOD chunks of the site lay only the ground, so the far piece stands on it.
##
## A child of the streamer (a Node3D under the scene root), placed at -world_offset like the far
## landmarks, so origin shifts carry it; its pieces are in true world coordinates.

var _pieces: Dictionary = {}
var _tick: float = 0.0


static func attach(streamer: Node3D, plan: CityPlan) -> RefineryFar:
	var lay := Refinery.layout(plan)
	if lay.is_empty():
		return null
	var far := RefineryFar.new()
	far.name = "RefineryFar"
	far.position = -WorldState.world_offset
	streamer.add_child(far)
	far.build(plan, lay)
	return far


func build(plan: CityPlan, lay: Dictionary) -> void:
	var s: Dictionary = lay.site
	var gy := func(p: Vector2) -> float: return plan.macro.relief_at(p) if plan.macro else 0.0
	for bx in range(int(s.ix0) - 1, int(s.ix1) + 1):
		for bz in range(int(s.iz0) - 1, int(s.iz1) + 1):
			var area := plan.owned_rect(bx, bz)
			if not area.intersects(lay.rect):
				continue
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_smooth_group(-1)
			var lights: Array = []
			var flames: Array = []
			var plumes: Array = []
			Refinery.write(lay, area, st, false, gy, lights, flames, plumes)
			var piece := Node3D.new()
			piece.name = "Piece_%d_%d" % [bx, bz]
			var mesh := st.commit()
			if mesh.get_surface_count() > 0:
				var mi := MeshInstance3D.new()
				mi.name = "Plant"
				mi.mesh = mesh
				mi.material_override = RefineryKit.material()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				piece.add_child(mi)
			Refinery.add_lights(piece, lights, "Lights")
			Refinery.add_fx(piece, flames, plumes)
			if piece.get_child_count() == 0:
				piece.free()
				continue
			add_child(piece)
			_pieces[Vector2i(bx, bz)] = piece


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	for k: Vector2i in _pieces:
		(_pieces[k] as Node3D).visible = not RefineryCover.covered(k)


func piece_count() -> int:
	return _pieces.size()
