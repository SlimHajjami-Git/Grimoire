shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Sphère de flash d'impact : cœur plein + rim fresnel lumineux.
// On la fait grossir et s'effacer par tween → boule d'énergie qui éclate.

uniform vec3 color : source_color = vec3(1.0, 0.6, 0.2);
uniform float intensity = 2.2;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - facing, 2.5);
	float core = facing * 0.5;
	ALBEDO = color * intensity;
	ALPHA = clamp(fres + core, 0.0, 1.0);
}
