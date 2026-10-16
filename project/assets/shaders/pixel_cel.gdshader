shader_type spatial;
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled;

// Real lights and shadow maps drive the ramp. Emission supplies a deliberately
// cobalt fill only; it does not replace the directional/counter light pass.
uniform vec4 base_color : source_color = vec4(0.85, 0.70, 0.30, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform bool has_albedo_texture = false;
uniform float night_mix : hint_range(0.0, 1.0) = 0.0;
uniform float emissive : hint_range(0.0, 1.0) = 0.0;
uniform float atmosphere : hint_range(0.0, 1.0) = 0.0;
uniform float unlit_mix : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec3 authored_color = base_color.rgb;
    if (has_albedo_texture) {
        authored_color *= texture(albedo_texture, UV).rgb;
    }
    vec3 pigment = mix(authored_color, vec3(0.40, 0.69, 0.84), atmosphere);
    pigment *= mix(vec3(1.0), vec3(0.40, 0.49, 0.70), night_mix * (1.0 - emissive));
    vec3 fill = mix(pigment * vec3(0.26, 0.32, 0.53), vec3(0.026, 0.047, 0.12), 0.16);
    fill *= mix(1.0, 0.60, night_mix);
    ALBEDO = pigment * (1.0 - unlit_mix) * (1.0 - emissive * 0.88);
    EMISSION = mix(fill, pigment, max(unlit_mix, emissive));
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}

void light() {
    float facing = dot(normalize(NORMAL), normalize(LIGHT));
    float ramp = facing > 0.62 ? 0.74 : (facing > 0.12 ? 0.50 : (facing > -0.16 ? 0.20 : 0.0));
    // Directional shadows retain a firm pixel-art edge, local lamps use their
    // real distance falloff so the counter glows without lighting the city.
    float visibility = LIGHT_IS_DIRECTIONAL ? step(0.48, ATTENUATION) : ATTENUATION;
    float day_energy = LIGHT_IS_DIRECTIONAL ? mix(1.0, 0.25, night_mix) : 1.0;
    // Stylized max-light combination keeps broad pigment colors from clipping
    // white when a practical overlaps the sun. Shadows still come from geometry.
    vec3 contribution = min(ramp * visibility * day_energy * LIGHT_COLOR / PI, vec3(0.80));
    DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, contribution);
}
