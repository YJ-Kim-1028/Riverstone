shader_type canvas_item;

// horror_events.md "NPC 사망 - 초상화 회색 처리". 새 그림 에셋 없이 기존
// 초상화 텍스처를 런타임에 흑백으로 바꾸는 용도(NPCManager.get_dead_portrait_material()).
void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float gray = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(gray), tex_color.a);
}
