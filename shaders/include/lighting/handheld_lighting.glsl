#ifndef INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#ifdef COLORED_LIGHTS
uniform sampler2D light_data_sampler;
#endif

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 get_handheld_light_color(int held_item_id, int held_item_light_value) {
#ifdef COLORED_LIGHTS
    bool is_emitter = 10032 <= held_item_id && held_item_id < 10064;

    if (is_emitter) {
        return texelFetch(
                   light_data_sampler,
                   ivec2(int(held_item_id) - 10032, 0),
                   0
        )
            .rgb;
    } else {
        return vec3(0.0);
    }
#else
    return (blocklight_color * blocklight_scale * rcp(15.0))
        * held_item_light_value;
#endif
}

float get_handheld_light_falloff(vec3 scene_pos, float ao) {
    float falloff = lift(rcp(dot(scene_pos, scene_pos) + 1.0), 1.2);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * HANDHELD_LIGHTING_INTENSITY;
}

vec3 get_handheld_lighting(vec3 scene_pos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scene_pos += relativeEyePosition;
#endif

    vec3 light_color = max(
        get_handheld_light_color(heldItemId, heldBlockLightValue),
        get_handheld_light_color(heldItemId2, heldBlockLightValue2)
    );

    float falloff = get_handheld_light_falloff(scene_pos, ao);

    return light_color * falloff;
}

#ifdef FLASHLIGHT

// Cosine of cone half-angles for the flashlight beam.
// Outer edge  (~30°): cos(30°) ≈ 0.866 — where beam fully fades out
// Inner hotspot (~12°): cos(12°) ≈ 0.978 — where the bright center begins

uniform float flashlight_active;
uniform float flashlight_color_r;
uniform float flashlight_color_g;
uniform float flashlight_color_b;
uniform vec3  flashlight_look_dir;

#ifdef IS_IRIS
uniform vec3 playerLookVector; // world-space head look direction (Iris exclusive)
#endif

vec3 get_flashlight_lighting(vec3 scene_pos, vec3 normal, float ao) {
#ifndef IS_IRIS
    return vec3(0.0);
#else
	// Wider radius = lower cosine threshold = bigger cone.
    // At FLASHLIGHT_RADIUS 1.0 these equal the original hardcoded values.
    float outer_cutoff = 1.0 - (1.0 - 0.866) * FLASHLIGHT_RADIUS;
    float inner_cutoff = 1.0 - (1.0 - 0.978) * FLASHLIGHT_RADIUS;
    outer_cutoff = clamp(outer_cutoff, 0.0, 0.999);
    inner_cutoff = clamp(inner_cutoff, outer_cutoff + 0.001, 1.0);
	
    // Both scene_pos and playerLookVector are in scene/world space — no transform needed
    vec3 pos = scene_pos + relativeEyePosition;

    float dist_sq = dot(pos, pos);
    float dist    = sqrt(dist_sq);
    vec3 frag_dir = pos * rcp(max(dist, 1e-5));

    // playerLookVector is world-aligned — use directly, no matrix needed
    float cos_theta = dot(normalize(flashlight_look_dir), frag_dir);

    float cone = smoothstep(outer_cutoff, inner_cutoff, cos_theta);
    if (cone < 1e-4) return vec3(0.0);

    float hotspot = 1.0 + 0.5 * smoothstep(inner_cutoff, 1.0, cos_theta);

    // Scale distance by FLASHLIGHT_DISTANCE — higher value = light reaches further
    float scaled_dist_sq = dist_sq * rcp(FLASHLIGHT_DISTANCE * FLASHLIGHT_DISTANCE);
    float falloff = lift(rcp(scaled_dist_sq + 1.0), 1.2);
    falloff *= mix(ao, 1.0, falloff * falloff);

    float NdotL = max0(dot(normal, -frag_dir));

    vec3 color = vec3(flashlight_color_r, flashlight_color_g, flashlight_color_b)
        * blocklight_scale;

    return color * cone * hotspot * falloff * NdotL * FLASHLIGHT_INTENSITY;
#endif
}

#endif // FLASHLIGHT

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
