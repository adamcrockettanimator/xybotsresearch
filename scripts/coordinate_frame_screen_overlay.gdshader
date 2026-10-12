shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float overlay_opacity : hint_range(0.0, 1.0) = 0.58;

void fragment() {
	vec4 guide = texture(TEXTURE, UV);
	vec4 beneath = texture(screen_texture, SCREEN_UV);
	float strength = guide.a * overlay_opacity;
	vec3 screened = vec3(1.0) - (vec3(1.0) - beneath.rgb) * (vec3(1.0) - guide.rgb);
	// The screen copy's alpha can be zero for a rendered CanvasLayer even when
	// its RGB data is correct. Write an opaque composite so a later canvas pass
	// cannot discard the otherwise-valid guide pixels.
	COLOR = vec4(mix(beneath.rgb, screened, strength), 1.0);
}
