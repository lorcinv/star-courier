shader_type canvas_item;

// Omit only the original raster pixels replaced by registered imagegen art.
// The surrounding source texture, tint, transform and alpha stay unchanged.
uniform vec4 source_cutout_px = vec4(0.0);

void fragment() {
	vec2 source_px = UV / TEXTURE_PIXEL_SIZE;
	if (source_px.x >= source_cutout_px.x && source_px.y >= source_cutout_px.y
		&& source_px.x < source_cutout_px.z && source_px.y < source_cutout_px.w) {
		discard;
	}
}
