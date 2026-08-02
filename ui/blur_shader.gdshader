shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 10.0) = 3.0;
uniform float dim_amount : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 pixel_size = 1.0 / vec2(textureSize(screen_texture, 0));
	vec4 color = vec4(0.0);

	// 5x5 高斯模糊采样
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 offset = vec2(float(x), float(y)) * pixel_size * blur_amount;
			color += textureLod(screen_texture, SCREEN_UV + offset, 0.0);
		}
	}
	color /= 25.0;

	// 叠加暗色遮罩
	color.rgb *= (1.0 - dim_amount);
	color.a = 1.0;

	COLOR = color;
}
