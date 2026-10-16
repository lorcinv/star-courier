shader_type canvas_item;
render_mode unshaded;

// Samples only this background's authored texture. No screen texture, TIME,
// ship, hazards, particles, receiver or HUD can enter this sampling path.
uniform vec2 source_size_px = vec2(1280.0, 720.0);
uniform vec2 logical_size_px = vec2(1280.0, 720.0);
uniform vec2 scroll_px = vec2(0.0);
uniform vec2 blur_delta_px = vec2(0.0);
uniform bool repeat_vertical = true;
uniform vec4 distance_color : source_color = vec4(0.04, 0.09, 0.20, 1.0);
uniform float distance_mix : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_color;

void vertex() {
    item_color = COLOR;
}

vec3 painted_uv(vec2 at_px) {
    float visible = 1.0;
    if (!repeat_vertical && (at_px.y < 0.0 || at_px.y >= source_size_px.y)) {
        visible = 0.0;
    }
    // Mirror pairs adjoin edge-to-identical-edge in either travel direction.
    // Sampling across the boundary also keeps speed blur seamless.
    vec2 period = source_size_px * 2.0;
    vec2 mirrored = mod(at_px, period);
    mirrored = min(mirrored, period - mirrored);
    vec2 uv = clamp(mirrored, vec2(0.5), source_size_px - vec2(0.5)) / source_size_px;
    return vec3(uv, visible);
}

void fragment() {
    vec2 at_px = UV * logical_size_px + scroll_px;
    vec3 sample_at = painted_uv(at_px);
    vec4 paint = texture(TEXTURE, sample_at.xy);
    paint.a *= sample_at.z;
    // Preserve crisp nearest pixels at low speed. Seven bounded samples only
    // when enabled; signed blur direction follows the actual horizontal speed.
    if (dot(blur_delta_px, blur_delta_px) > 0.01) {
        vec4 weighted = vec4(paint.rgb * paint.a, paint.a) * 0.4;
        for (int i = 1; i <= 6; i++) {
            sample_at = painted_uv(at_px + blur_delta_px * (float(i) / 6.0));
            vec4 tap = texture(TEXTURE, sample_at.xy);
            tap.a *= sample_at.z;
            weighted += vec4(tap.rgb * tap.a, tap.a) * 0.1;
        }
        paint.a = weighted.a;
        paint.rgb = weighted.rgb / max(weighted.a, 0.00001);
    }
    paint.rgb = mix(paint.rgb, distance_color.rgb, distance_mix);
    COLOR = paint * item_color;
}
