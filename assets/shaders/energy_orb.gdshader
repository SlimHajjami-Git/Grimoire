shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Noyau de sort animé : bruit qui défile (le feu monte), passé dans un
// dégradé chaud→froid, + halo fresnel sur les bords. Tinté par élément via
// les 3 couleurs de palette → marche pour feu, glace, foudre, etc.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 color_hot : source_color = vec3(1.0, 0.95, 0.6);
uniform vec3 color_mid : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 color_cool : source_color = vec3(0.7, 0.1, 0.02);
uniform float speed = 1.4;
uniform float intensity = 1.7;

void fragment() {
	vec2 uv1 = UV + vec2(0.0, -TIME * speed);
	vec2 uv2 = UV * 1.8 + vec2(TIME * speed * 0.35, -TIME * speed * 0.8);
	float n = texture(noise_tex, uv1).r * 0.6 + texture(noise_tex, uv2).r * 0.4;

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);

	vec3 col = mix(color_cool, color_mid, smoothstep(0.2, 0.55, n));
	col = mix(col, color_hot, smoothstep(0.55, 0.9, n + fres * 0.3));

	float alpha = smoothstep(0.12, 0.5, n + fres * 0.45);
	ALBEDO = col * intensity;
	ALPHA = alpha;
}
