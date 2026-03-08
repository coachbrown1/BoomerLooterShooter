shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_disable;
uniform float outline_width : hint_range(0.0, 5.0, 1.0) = 1.0;
uniform bool enable_outline = true;
uniform bool billboard = true;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform float distance_fade_min : hint_range(0.0, 100.0, 1.0) = 15.0;
uniform float distance_fade_max : hint_range(0.0, 100.0, 1.0) = 30.0;
uniform float rim_steepness : hint_range(0.0, 10.0, 0.1) = 3.0;
uniform vec3 rim_color : source_color = vec3(1.0, 1.0, 1.0);

uniform sampler2D texture_emission : source_color, filter_nearest, repeat_disable;
uniform float emission_energy : hint_range(0.0, 10.0, 0.1) = 2.0;
uniform bool enable_emission = false;

varying float dist_to_cam;

void vertex() {
	if (billboard) {
		// Y-Billboard (Sprite3D BILLBOARD_FIXED_Y math)
		vec3 up_dir = vec3(0.0, 1.0, 0.0);
		vec3 cam_z = INV_VIEW_MATRIX[2].xyz;
		if (abs(dot(up_dir, cam_z)) > 0.99) {
			cam_z = INV_VIEW_MATRIX[1].xyz;
		}
		vec3 bb_x = normalize(cross(up_dir, cam_z));
		vec3 bb_z = normalize(cross(INV_VIEW_MATRIX[0].xyz, up_dir));
		
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(bb_x, 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(bb_z, 0.0),
			MODEL_MATRIX[3]);
		
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
			
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	
	// Pass distance to camera for fading
	dist_to_cam = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
    vec4 albedo_tex = texture(texture_albedo, UV);
    vec2 size = vec2(textureSize(texture_albedo, 0));
    vec2 px = vec2(1.0) / size;
    
    // Hard scissor the image alpha to clean up semi-transparent anti-aliasing edges 
    float alpha = albedo_tex.a > alpha_scissor_threshold ? 1.0 : 0.0;
    
    // Distance Fade Calculation
    float dist_alpha = clamp((distance_fade_max - dist_to_cam) / (distance_fade_max - distance_fade_min), 0.0, 1.0);
    
    if (enable_outline && alpha == 0.0) {
        float max_a = 0.0;
        // Check surrounding pixels up to outline_width
        for (float y = -ceil(outline_width); y <= ceil(outline_width); y += 1.0) {
            for (float x = -ceil(outline_width); x <= ceil(outline_width); x += 1.0) {
                if (x == 0.0 && y == 0.0) continue;
                
                // Manhattan distance check makes the outline "tighter" and more "pixel-perfect"
                if (abs(x) + abs(y) > outline_width) continue;
                
                vec2 offset = vec2(x, y) * px;
                float neighbor_a = texture(texture_albedo, UV + offset).a;
                if (neighbor_a > alpha_scissor_threshold) {
                    max_a = 1.0;
                    break;
                }
            }
            if (max_a > 0.0) break;
        }
        
        if (max_a > 0.0) {
            ALBEDO = outline_color.rgb;
            ALPHA = outline_color.a * dist_alpha;
        } else {
            ALBEDO = albedo_tex.rgb;
            ALPHA = 0.0;
        }
    } else {
        // Fresnel-like Rim Lighting (Pop effect for the sprite itself)
        // Since it's a quad, we use the dot product of the normal and view vector
        // In unshaded mode, we have to fake this.
        float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_steepness);
        vec3 final_color = mix(albedo_tex.rgb, rim_color, fresnel * 0.5);
        
        if (enable_emission) {
            vec4 emission_tex = texture(texture_emission, UV);
            // Add emissive color times the energy. Since we're unshaded, this acts like an HDR glow modifier.
            final_color += emission_tex.rgb * emission_tex.a * emission_energy;
        }
        
        ALBEDO = final_color;
        ALPHA = alpha;
    }
    
    // Discard fully transparent pixels so depth buffer remains clean
    if (ALPHA < 0.1) {
        discard;
    }
}
