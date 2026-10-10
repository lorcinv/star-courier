shader_type canvas_item;
render_mode unshaded;

// Each material reads its own generated layer only. There is no screen sampler
// and no clock: ship, hazards and HUD can never enter this texture-local blur.
uniform vec2 source_size_px = vec2(1280.0, 640.0);
uniform vec2 logical_size_px = vec2(1280.0, 720.0);
uniform vec2 scroll_px = vec2(0.0);
uniform vec2 blur_delta_px = vec2(0.0);
uniform bool repeat_x = true;
uniform bool repeat_y = true;
uniform bool clamp_y = false;
varying vec4 item_color;

void vertex() {
    item_color = COLOR;
}

vec3 ordinary_sample_coordinate(vec2 pixel) {
    float visible = 1.0;
    if (!repeat_y && !clamp_y && (pixel.y < 0.0 || pixel.y >= source_size_px.y)) {
        visible = 0.0;
    }
    // Ordinary modulo retains left-to-right architecture and star orientation.
    // Source derivatives have measured matching edges. No reflected period.
    pixel.x = repeat_x ? mod(pixel.x, source_size_px.x) : clamp(pixel.x, 0.0, source_size_px.x - 1.0);
    pixel.y = repeat_y ? mod(pixel.y, source_size_px.y) : clamp(pixel.y, 0.0, source_size_px.y - 1.0);
    return vec3((floor(pixel) + vec2(0.5)) / source_size_px, visible);
}

void fragment() {
    vec2 at_px = UV * logical_size_px + scroll_px;
    vec3 sample_at = ordinary_sample_coordinate(at_px);
    vec4 paint = texture(TEXTURE, sample_at.xy);
    paint.a *= sample_at.z;
    if (dot(blur_delta_px, blur_delta_px) > 0.01) {
        // Seven bounded taps, premultiplied to avoid dark transparent fringes.
        // A signed two-dimensional vector also smears during pure ascent.
        vec4 weighted = vec4(paint.rgb * paint.a, paint.a) * 0.4;
        for (int i = 1; i <= 6; i++) {
            sample_at = ordinary_sample_coordinate(at_px + blur_delta_px * (float(i) / 6.0));
            vec4 tap = texture(TEXTURE, sample_at.xy);
            tap.a *= sample_at.z;
            weighted += vec4(tap.rgb * tap.a, tap.a) * 0.1;
        }
        paint.a = weighted.a;
        paint.rgb = weighted.rgb / max(weighted.a, 0.00001);
    }
    COLOR = paint * item_color;
}
