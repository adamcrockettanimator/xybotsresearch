shader_type canvas_item;
render_mode unshaded, blend_mix;

// Match the barrel's playfield-pixel sampling so the shifted silhouette
// remains registered with the visible sprite at every distance.
uniform float sprite_scale = 1.0;
uniform vec2 grid_origin = vec2(0.0);
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.30;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	if (UV.y * texture_size.y < texture_size.y - 10.0) {
		discard;
	}
	float scale = max(sprite_scale, 0.0001);
	vec2 texel = (floor(UV * texture_size * scale + grid_origin) + vec2(0.5) - grid_origin) / scale;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	float mask = texture(TEXTURE, texel / texture_size).a;
	// Black with alpha blending multiplies the destination by (1 - alpha),
	// preserving the actual floor color and leaving transparent texels alone.
	COLOR = vec4(0.0, 0.0, 0.0, mask * shadow_opacity);
}
