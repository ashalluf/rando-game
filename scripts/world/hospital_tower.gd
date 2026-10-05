class_name HospitalTower
extends Building
## A hospital's podium and bed tower as a Building (Hospital, HospitalBuild): the same facade
## shader (interior mapping, lit rooms at night, the stone base course), the same merged meshes,
## collision and occluder rules, and the far tiers' coded boxes for free (FarBuilding.boxes() on
## it, like any planned building). What differs is the massing and the style: two parts given by
## the campus layout - the podium filling its rect, the tower slab on it - in light panels with
## RIBBON windows (the horizontal window bands a modern bed tower has), no storefront (the lobby,
## the ER entrance and their canopies are HospitalBuild's own geometry against the podium), lit
## rooms most of the night (wards never sleep) and no roof plant on the tower, whose roof is the
## helipad.

## Set before generate(): the podium (x, y, z size) and the tower (size, and its centre's offset
## on the podium in x / z), all in the building's space (origin at the podium's foot centre).
var podium_size: Vector3 = Vector3(40.0, 13.2, 40.0)
var tower_size: Vector3 = Vector3(30.0, 30.0, 18.0)
var tower_offset: Vector2 = Vector2.ZERO


func _init() -> void:
	allow_storefront = false
	finish_options.assign([Finish.PANELS])
	lit_ratio_range = Vector2(0.55, 0.78)
	weathering_range = Vector2(0.1, 0.35)
	balcony_chance = 0.0
	bay_chance = 0.0
	chamfer_chance = 0.0
	canopy_chance = 0.0
	podium_lot = false
	collision_layer = 1
	collision_mask = 0


func _layout_parts() -> void:
	_add_part(podium_size, Vector2.ZERO, 0.0)
	_add_part(Vector3(tower_size.x, tower_size.y, tower_size.z), tower_offset, podium_size.y)


func _pick_window_style() -> WindowStyle:
	# The roll is still made, so the style's rolls after it are what they would be.
	_rng.randf()
	return WindowStyle.RIBBON


## The plant goes on the podium's roof only: the tower's is the helipad (HospitalBuild). Marking
## the tower as a podium part for the pass is what Building skips.
func _build_roof_props() -> void:
	if parts.size() < 2:
		super._build_roof_props()
		return
	var tower: Dictionary = parts[1]
	tower["podium"] = 1
	super._build_roof_props()
	tower.erase("podium")
