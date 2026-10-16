shader_type canvas_item;
render_mode unshaded;

// Texture-local, clock-free raster sampling. Decoration never implies a floor.
// Only the presenter's actual camera sample supplies parallax. Horizontal wrap
// is explicit; vertical edges clamp, so climbing cannot repeat a floating island.
uniform vec2 source_size_px = vec2(1280.0, 720.0);
uniform vec2 logical_size_px = vec2(1280.0, 720.0);
uniform vec2 scroll_px = vec2(0.0);
uniform bool repeat_x = true;
uniform float overscan = 1.0;
uniform float pixel_grid_px = 2.0;
uniform float saturation : hint_range(0.0, 1.0) = 1.0;
// The generated receiver contains tool-matte residue at alpha 1/255. Its
// unchanged PNG is retained; only that invisible residue is discarded here.
// No alpha >= 2/255 pixel is removed. This is an explicit runtime rule.
uniform bool registered_cutout = false;
varying vec4 item_color;

void vertex() {
    item_color = COLOR;
}

void fragment() {
    if (registered_cutout) {
        vec4 paint = texture(TEXTURE, UV);
        if (paint.a <= 1.0 / 255.0 + 0.000001) {
            paint = vec4(0.0);
        }
        COLOR = paint * item_color;
    } else {
    float cover_scale = max(logical_size_px.x / source_size_px.x, logical_size_px.y / source_size_px.y) * overscan;
    vec2 view_span = logical_size_px / cover_scale;
    vec2 logical_pixel = floor(UV * logical_size_px / pixel_grid_px) * pixel_grid_px;
    vec2 sample_pixel = logical_pixel / cover_scale + (source_size_px - view_span) * 0.5 + scroll_px;
    sample_pixel.x = repeat_x ? mod(sample_pixel.x, source_size_px.x) : clamp(sample_pixel.x, 0.0, source_size_px.x - 1.0);
    sample_pixel.y = clamp(sample_pixel.y, 0.0, source_size_px.y - 1.0);
    vec2 raster_uv = (floor(sample_pixel) + vec2(0.5)) / source_size_px;
    vec4 paint = texture(TEXTURE, raster_uv);
    float luminance = dot(paint.rgb, vec3(0.2126, 0.7152, 0.0722));
    paint.rgb = mix(vec3(luminance), paint.rgb, saturation);
    COLOR = paint * item_color;
    }
}
