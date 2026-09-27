#[versions]

prepare = "#define MODE_PREPARE";
tile_x = "#define MODE_TILE_X";
tile_y = "#define MODE_TILE_Y";
neighbor = "#define MODE_NEIGHBOR";
gather = "#define MODE_GATHER";

#[compute]

#version 450

#VERSION_DEFINES

// Per-pixel motion blur (MotionBlurEffect, scripts/util/motion_blur_effect.gd). Forward+ only:
// a CompositorEffect at POST_TRANSPARENT, so it runs on the HDR frame at the internal resolution,
// before TAA / FSR 2.2 and before the tonemapper. The reconstruction filter is McGuire et al.
// 2012, "A Reconstruction Filter for Plausible Motion Blur", with the tile and neighbour maxima
// and the sample alternation of Guertin et al. 2014:
//   prepare   the engine's velocity (UV units a frame) -> a blur radius in pixels at a FIXED
//             exposure (so 20 fps and 60 fps blur alike), soft threshold, clamp; linear depth;
//             and a copy of the colour to gather from
//   tile_x/y  the longest radius in each tile x tile block (tile = the longest radius)
//   neighbor  the longest of each tile's 3 x 3 neighbours, so blur reaches past a silhouette
//   gather    taps along the neighbourhood's velocity (and the pixel's own), weighted by depth
//             and by whether each tap's blur really covers this pixel
// Traps: with FSR 2.2 the engine writes velocity only for MOVING objects and clears the rest to
// (-1, -1) (FSR derives the camera motion itself); the sky writes none at all. Both are rebuilt
// here from depth and the camera's reprojection. Depth is reverse-Z, 0 at the far plane.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
	mat4 reprojection; // this frame's NDC (x, y, depth) -> last frame's clip position
	vec2 size; // internal resolution in pixels
	float scale; // one frame's displacement in pixels -> blur length in pixels
	float threshold; // pixels of blur length dropped before any blur shows
	float max_radius; // pixels, half the longest blur
	float depth_a; // linear distance = depth_b / (depth + depth_a) for the reverse-Z buffer
	float depth_b;
	float soft_z; // depth difference, relative, over which two taps count as one surface
	float samples; // taps per pixel
	float frame; // frame counter, moves the noise so TAA integrates it
	float camera_valid; // 1 when last frame's camera is known (no cut)
	float tile; // tile size in pixels
	float debug; // 1 paints each pixel's blur (red / green = x / y, blue = the tile's) instead
	float pad0;
	float pad1;
	float pad2;
}
params;

#ifdef MODE_PREPARE

layout(set = 0, binding = 0) uniform sampler2D depth_buffer;
layout(rg16f, set = 0, binding = 1) uniform restrict readonly image2D velocity_buffer;
layout(rgba16f, set = 0, binding = 2) uniform restrict readonly image2D color_image;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D blur_image;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D color_copy;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(pos, ivec2(params.size)))) {
		return;
	}
	float depth = texelFetch(depth_buffer, pos, 0).x;
	vec2 velocity = imageLoad(velocity_buffer, pos).xy;
	vec2 uv = (vec2(pos) + 0.5) / params.size;
	// No velocity of its own: FSR's (-1, -1) marker, or the sky (depth 0). Take the camera's.
	if ((velocity.x <= -0.99 && velocity.y <= -0.99) || depth <= 0.0) {
		velocity = vec2(0.0);
		if (params.camera_valid > 0.5) {
			vec4 prev = params.reprojection * vec4(uv * 2.0 - 1.0, depth, 1.0);
			if (prev.w > 1e-6) {
				velocity = (prev.xy / prev.w) * 0.5 + 0.5 - uv;
			}
		}
	}
	vec2 streak = velocity * params.size * params.scale;
	float len = length(streak);
	// Soft threshold (the blur grows from zero past it, never pops in) and the cap.
	float keep = clamp(len - params.threshold, 0.0, 2.0 * params.max_radius);
	vec2 radius = len > 1e-3 ? streak * (0.5 * keep / len) : vec2(0.0);
	if (any(isnan(radius))) {
		radius = vec2(0.0);
	}
	float linear_depth = params.depth_b / (depth + params.depth_a);
	imageStore(blur_image, pos, vec4(radius, linear_depth, 0.0));
	imageStore(color_copy, pos, imageLoad(color_image, pos));
}

#endif

#ifdef MODE_TILE_X

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D blur_image;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D tile_x_image;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	int t = int(params.tile);
	ivec2 grid = ivec2((int(params.size.x) + t - 1) / t, int(params.size.y));
	if (any(greaterThanEqual(id, grid))) {
		return;
	}
	vec2 best = vec2(0.0);
	float best_len = 0.0;
	int x_end = min(id.x * t + t, int(params.size.x));
	for (int x = id.x * t; x < x_end; x++) {
		vec2 r = imageLoad(blur_image, ivec2(x, id.y)).xy;
		float l = dot(r, r);
		if (l > best_len) {
			best_len = l;
			best = r;
		}
	}
	imageStore(tile_x_image, id, vec4(best, 0.0, 0.0));
}

#endif

#ifdef MODE_TILE_Y

layout(rg16f, set = 0, binding = 0) uniform restrict readonly image2D tile_x_image;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D tile_image;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	int t = int(params.tile);
	ivec2 grid = (ivec2(params.size) + t - 1) / t;
	if (any(greaterThanEqual(id, grid))) {
		return;
	}
	vec2 best = vec2(0.0);
	float best_len = 0.0;
	int y_end = min(id.y * t + t, int(params.size.y));
	for (int y = id.y * t; y < y_end; y++) {
		vec2 r = imageLoad(tile_x_image, ivec2(id.x, y)).xy;
		float l = dot(r, r);
		if (l > best_len) {
			best_len = l;
			best = r;
		}
	}
	imageStore(tile_image, id, vec4(best, 0.0, 0.0));
}

#endif

#ifdef MODE_NEIGHBOR

layout(rg16f, set = 0, binding = 0) uniform restrict readonly image2D tile_image;
layout(rg16f, set = 0, binding = 1) uniform restrict writeonly image2D neighbor_image;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	int t = int(params.tile);
	ivec2 grid = (ivec2(params.size) + t - 1) / t;
	if (any(greaterThanEqual(id, grid))) {
		return;
	}
	vec2 best = vec2(0.0);
	float best_len = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 p = id + ivec2(x, y);
			if (any(lessThan(p, ivec2(0))) || any(greaterThanEqual(p, grid))) {
				continue;
			}
			vec2 r = imageLoad(tile_image, p).xy;
			// A diagonal neighbour only reaches this tile if it points at it (Jimenez 2014).
			if (x != 0 && y != 0 && dot(normalize(r + 1e-6), normalize(vec2(-x, -y))) < 0.707) {
				continue;
			}
			float l = dot(r, r);
			if (l > best_len) {
				best_len = l;
				best = r;
			}
		}
	}
	imageStore(neighbor_image, id, vec4(best, 0.0, 0.0));
}

#endif

#ifdef MODE_GATHER

layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_copy;
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D blur_image;
layout(rg16f, set = 0, binding = 2) uniform restrict readonly image2D neighbor_image;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D color_image;

// Interleaved gradient noise (Jimenez 2014), stepped per frame so TAA averages it away.
float ign(vec2 p) {
	p += 5.588238 * mod(params.frame, 64.0);
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float cone(float dist, float radius) {
	return clamp(1.0 - dist / radius, 0.0, 1.0);
}

float cylinder(float dist, float radius) {
	return 1.0 - smoothstep(0.95 * radius, 1.05 * radius, dist);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.size);
	if (any(greaterThanEqual(pos, size))) {
		return;
	}
	int t = int(params.tile);
	ivec2 grid = (size + t - 1) / t;
	float noise = ign(vec2(pos));
	// Jitter the tile lookup a little so tile edges do not show as a grid.
	vec2 wobble = (vec2(noise, ign(vec2(pos.y, pos.x) + 17.0)) - 0.5) * params.tile * 0.5;
	ivec2 tile = clamp(ivec2((vec2(pos) + wobble) / params.tile), ivec2(0), grid - 1);
	vec2 vn = imageLoad(neighbor_image, tile).xy;
	float vn_len = length(vn);
	if (params.debug > 0.5) {
		vec2 own = imageLoad(blur_image, pos).xy / params.max_radius;
		imageStore(color_image, pos, vec4(abs(own), vn_len / params.max_radius, 1.0));
		return;
	}
	if (vn_len < 0.5) {
		return; // nothing near here moves: the pixel stays exactly as rendered
	}
	vec4 cx = imageLoad(color_copy, pos);
	vec3 bx = imageLoad(blur_image, pos).xyz;
	vec2 vx = bx.xy;
	float zx = bx.z;
	float vx_len = max(length(vx), 0.5);
	// Half the taps follow the pixel's own motion when it has one of its own (Guertin 2014):
	// along the neighbourhood's alone, a spinning or zooming view blurs everything one way.
	vec2 vc = length(vx) >= 0.5 ? vx : vn;
	int count = int(params.samples);
	float weight = 1.0 / vx_len;
	vec3 sum = cx.rgb * weight;
	for (int i = 0; i < count; i++) {
		float tt = mix(-1.0, 1.0, (float(i) + noise + 0.5) / float(count));
		vec2 along = (i & 1) == 0 ? vn : vc;
		ivec2 ypos = clamp(ivec2(floor(vec2(pos) + 0.5 + along * tt)), ivec2(0), size - 1);
		if (ypos == pos) {
			continue;
		}
		vec3 by = imageLoad(blur_image, ypos).xyz;
		float zy = by.z;
		float vy_len = max(length(by.xy), 0.5);
		float dist = length(vec2(ypos - pos));
		float extent = max(params.soft_z * min(zx, zy), 0.05);
		float front = clamp(1.0 + (zx - zy) / extent, 0.0, 1.0); // the tap is in front of us
		float back = clamp(1.0 + (zy - zx) / extent, 0.0, 1.0); // the tap is behind us
		float alpha = front * cone(dist, vy_len) + back * cone(dist, vx_len)
				+ cylinder(dist, vy_len) * cylinder(dist, vx_len) * 2.0;
		weight += alpha;
		sum += alpha * imageLoad(color_copy, ypos).rgb;
	}
	imageStore(color_image, pos, vec4(sum / weight, cx.a));
}

#endif
