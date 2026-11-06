shader_type spatial;
render_mode cull_disabled;

// A crashed car whose bonnet flew open (CrashBreakup): car_paint_damage.gdshader drawn from both
// sides, so the lifted bonnet's underside - single-sided skin, culled by the damage shader - is
// there, in bare primer grey rather than paint. Only such a car wears it.
#define CAR_DAMAGE
#define CAR_OPEN_PANEL
#include "res://shaders/car_paint.gdshaderinc"
