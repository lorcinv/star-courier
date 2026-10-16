shader_type canvas_item;
render_mode unshaded;

// Reconstructed texture-local presentation. No screen texture or autonomous
// clock: the presenter alone supplies actual paused camera motion.
uniform vec2 source_size_px = vec2(1280.0, 720.0);
uniform vec2 logical_size_px = vec2(1280.0, 720.0);
uniform vec2 scroll_px = vec2(0.0);
uniform vec2 blur_delta_px = vec2(0.0);
uniform bool repeat_x = false;
uniform bool terrain = false;
uniform float surface_y_px = 720.0;
uniform float saturation : hint_range(0.0, 1.0) = 1.0;
varying vec4 item_color;

void vertex() {
    item_color = COLOR;
}

vec2 raster_coordinate(vec2 logical_pixel) {
    vec2 pixel = logical_pixel + scroll_px;
    if (terrain) {
        // The authored bottom edge is registered to the actual saved surface.
        // The low silhouette remains decorative, never a collider or floor.
        pixel.y += source_size_px.y - surface_y_px;
    } else {
        // A single 1536x864 raster covers 1280x720 with symmetric overscan.
        // Clamping preserves one Earth at either extreme; no reflected copy.
        pixel += max(source_size_px - logical_size_px, vec2(0.0)) * 0.5;
    }
    pixel.x = repeat_x ? mod(pixel.x, source_size_px.x) : clamp(pixel.x, 0.0, source_size_px.x - 1.0);
    // Never repeat vertically. Terrain's opaque lower edge continues below
    // its saved ground reference, while its transparent upper edge stays clear.
    pixel.y = clamp(pixel.y, 0.0, source_size_px.y - 1.0);
    return (floor(pixel) + vec2(0.5)) / source_size_px;
}

void fragment() {
    vec2 at_px = UV * logical_size_px;
    vec4 paint = texture(TEXTURE, raster_coordinate(at_px));
    if (dot(blur_delta_px, blur_delta_px) > 0.01) {
        // Seven bounded premultiplied taps avoid dark transparent fringes.
        vec4 weighted = vec4(paint.rgb * paint.a, paint.a) * 0.4;
        for (int i = 1; i <= 6; i++) {
            vec4 tap = texture(TEXTURE, raster_coordinate(at_px + blur_delta_px * (float(i) / 6.0)));
            weighted += vec4(tap.rgb * tap.a, tap.a) * 0.1;
        }
        paint.a = weighted.a;
        paint.rgb = weighted.rgb / max(weighted.a, 0.00001);
    }
    float luminance = dot(paint.rgb, vec3(0.2126, 0.7152, 0.0722));
    paint.rgb = mix(vec3(luminance), paint.rgb, saturation);
    COLOR = paint * item_color;
}
