# shots/web-bonfire

The beach bonfire flames on the web (fleet wave 8, `web-bonfire`). Browser stills are Chromium
1243 (full) at 960x540; "SwiftShader" is the harness's default software WebGL, "ANGLE GL" is the
same export through ANGLE on desktop GL (Mesa llvmpipe, `ANGLE=gl` on webshot.js), the stand-in
for a real GPU browser.

- 01_room_swiftshader_bonfire_flames_missing.jpg - fx_room `bonfire=bare+nosmoke,bare&fires=1&rowoff=1&night=1`
  on SwiftShader: car engine fire (left) and tree crown fire (right) draw, the two bonfires' flames do not.
- 02_room_angle_gl_bonfire_flames_draw.jpg - the same page through ANGLE GL: all four fires draw.
- 03_room_native_opengl3_reference.jpg - the same room natively (opengl3, web materials).
- 04_native_vs_swiftshader_depth_test_off.jpg - the bonfire flames with their depth test off:
  native (left) and SwiftShader (right) identical, so SwiftShader is depth-rejecting them.
- 05_flames_lifted_native_top_swiftshader_bottom.jpg - flames lifted 1 m / 3 m: they move natively,
  SwiftShader's small orange cone stays at the base (it is not the flames).
- 06_city_beach_night_swiftshader_before.jpg - the `beach_night` bookmark on SwiftShader: no flames.
- 07_city_beach_night_angle_gl_after.jpg - the same bookmark through ANGLE GL: flames over the ring.
- 08_city_bonfire_closeup_swiftshader_left_gl_right.jpg - the ring enlarged, SwiftShader | ANGLE GL.
- 09_city_santa_ana_brush_fire_angle_gl.jpg - the `santa_ana` bookmark through ANGLE GL: the brush fire.
