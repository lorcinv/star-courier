shader_type spatial;
render_mode unshaded;
uniform vec4 base_color : source_color = vec4(0.9,0.8,0.4,1.0);
uniform float night_mix = 0.0;
uniform float emissive = 0.0;
uniform float atmosphere = 0.0;
void fragment() {
 float n=dot(normalize(NORMAL),normalize(vec3(-0.42,0.75,0.66)));
 vec3 shadow=mix(base_color.rgb,vec3(0.035,0.052,0.24),0.45);
 vec3 tone=n>0.64 ? base_color.rgb : (n>0.04 ? mix(shadow,base_color.rgb,0.68) : shadow);
 tone=mix(tone,tone*vec3(0.52,0.60,0.88),night_mix*(1.0-emissive));
 ALBEDO=mix(mix(tone,base_color.rgb,emissive*0.7),vec3(0.085,0.47,0.46),atmosphere);
}
