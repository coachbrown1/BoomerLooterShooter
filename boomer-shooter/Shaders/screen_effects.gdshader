shader_type canvas_item;

// --- Saturation/Brightness/Contrast ---
uniform float saturation : hint_range(0.0, 3.0, 0.01) = 1.3;
uniform float brightness : hint_range(0.0, 2.0, 0.01) = 0.95;
uniform float contrast   : hint_range(0.0, 3.0, 0.01) = 1.1;

// --- Vignette ---
uniform float vignette_strength : hint_range(0.0, 2.0, 0.01) = 0.35;
uniform float vignette_radius   : hint_range(0.0, 1.5, 0.01) = 0.75;

// --- Chromatic Aberration ---
uniform float chromatic_aberration_strength : hint_range(0.0, 5.0, 0.01) = 0.5;

// --- Color Tint (dungeon mood) ---
uniform vec3 color_tint : source_color = vec3(1.0, 0.97, 0.92);

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    vec2 uv_dist = SCREEN_UV - 0.5;
    float dist = length(uv_dist);
    vec2 offset = uv_dist * (dist * chromatic_aberration_strength * 0.02);

    // Sample channels with offset
    float r = texture(screen_texture, SCREEN_UV - offset).r;
    float g = texture(screen_texture, SCREEN_UV).g;
    float b = texture(screen_texture, SCREEN_UV + offset).b;
    
    vec3 col = vec3(r, g, b);
    float alpha = texture(screen_texture, SCREEN_UV).a;

    // 1. Brightness
    col *= brightness;

    // 2. Contrast (pivot around 0.5)
    col = (col - 0.5) * contrast + 0.5;

    // 3. Saturation
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(lum), col, saturation);

    // 4. Warm color tint
    col *= color_tint;

    // 5. Vignette
    vec2 uv = UV * 2.0 - 1.0;
    float vign = length(uv) / vignette_radius;
    vign = clamp(vign, 0.0, 1.0);
    vign = pow(vign, 2.5) * vignette_strength;
    col = mix(col, vec3(0.0), vign);

    // Clamp final output
    col = clamp(col, vec3(0.0), vec3(1.0));

    COLOR = vec4(col, alpha);
}
