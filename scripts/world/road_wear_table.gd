class_name RoadWearTable
extends RefCounted
## Written by tools/make_road_wear.py: the 25 road wear stamps in its atlas, in cell order
## (index = row * GRID + column). [name, size in metres (u across the road, v along it),
## deepest point below the road (m), flags]. Do not edit by hand: change the generator.

const GRID := 5
const STAMP_PX := 400
const ATLAS_PX := 2048
const HEIGHT_RANGE := 0.120
const DEEP := 1
const ALIGN := 2
const CONCRETE := 4
const POOLS := 8
const SURFACE := 16
const KERB := 32

const STAMPS := [
	["pothole_shallow", Vector2(1.00, 1.00), 0.040, 9],
	["pothole_deep", Vector2(1.20, 1.20), 0.110, 9],
	["pothole_gravel", Vector2(1.10, 1.10), 0.030, 1],
	["pothole_water", Vector2(1.60, 1.60), 0.090, 9],
	["pothole_cluster", Vector2(2.40, 2.40), 0.060, 9],
	["alligator", Vector2(2.50, 3.50), 0.033, 10],
	["block_crack", Vector2(6.00, 6.00), 0.012, 0],
	["crack_long", Vector2(0.80, 6.00), 0.015, 2],
	["crack_trans", Vector2(3.50, 0.80), 0.015, 2],
	["tar_snake", Vector2(1.00, 6.00), 0.000, 2],
	["tar_network", Vector2(5.00, 5.00), 0.000, 0],
	["ravelling", Vector2(2.50, 2.50), 0.013, 0],
	["patch_raised", Vector2(1.80, 2.40), 0.010, 0],
	["patch_sunken", Vector2(1.60, 2.00), 0.028, 8],
	["sawcut_patch", Vector2(2.40, 3.00), 0.010, 2],
	["trench_strip", Vector2(1.00, 8.00), 0.016, 10],
	["rut_polish", Vector2(0.90, 8.00), 0.018, 10],
	["edge_break", Vector2(1.40, 5.00), 0.066, 43],
	["shoving", Vector2(3.00, 2.50), 0.012, 10],
	["oil_drips", Vector2(1.80, 3.00), 0.000, 16],
	["burnout", Vector2(2.50, 4.00), 0.000, 16],
	["paint_ghost", Vector2(0.60, 4.00), 0.002, 18],
	["bleeding", Vector2(0.90, 5.00), 0.000, 18],
	["concrete_spall", Vector2(2.00, 2.00), 0.030, 12],
	["concrete_crack", Vector2(2.00, 2.00), 0.013, 4],
]
