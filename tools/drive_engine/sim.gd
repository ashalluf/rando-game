extends Node
func _ready():
	for c in DriveTrain.SPECS:
		var r := DriveTrain.simulate(c)
		var b := DriveTrain.simulate(c, 40.0, true)
		print("SIM %-13s 0-60 %5.2f 0-100 %5.2f top %5.1f km/h shifts %d | boost 0-100 %5.2f top %5.1f" % [c, r.t60, r.t100, r.top*3.6, r.shifts, b.t100, b.top*3.6])
	get_tree().quit()
