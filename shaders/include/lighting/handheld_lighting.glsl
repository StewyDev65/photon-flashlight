#ifndef INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#ifdef FLASHLIGHT_SHADOWS
#include "/include/utility/random.glsl"
#include "/include/utility/space_conversion.glsl"
#endif

// SSBO must be at global scope — Iris transformer rejects buffer blocks inside #ifdef
layout(std430, binding = 1) buffer OtherFlashlightBuffer {
    float data[40];
} fl_other;

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

// Flashlight origin in view space — tune all three values here.
// +X = right,  +Y = up,  -Z = forward (OpenGL convention)
#define FL_HAND_OFFSET vec3(FL_OFFSET_X, FL_OFFSET_Y, FL_OFFSET_Z)

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

#ifdef FLASHLIGHT_MULTIPLAYER

vec3 get_other_flashlights_lighting(vec3 scene_pos, vec3 normal, float ao) {
    vec3 total = vec3(0.0);

    float outer_cutoff = 1.0 - (1.0 - 0.866) * FLASHLIGHT_RADIUS;
    float inner_cutoff = 1.0 - (1.0 - 0.978) * FLASHLIGHT_RADIUS;
    outer_cutoff = clamp(outer_cutoff, 0.0, 0.999);
    inner_cutoff = clamp(inner_cutoff, outer_cutoff + 0.001, 1.0);

    for (int i = 0; i < 4; i++) {
        int base  = i * 10;
        float act = fl_other.data[base + 9];
        if (act < 0.001) continue;

        // Player eye is stored in scene space (world - cameraPos, computed each frame in Java)
        vec3 player_pos = vec3(fl_other.data[base],     fl_other.data[base + 1], fl_other.data[base + 2]);
        vec3 look       = normalize(vec3(fl_other.data[base + 3], fl_other.data[base + 4], fl_other.data[base + 5]));
        vec3 col        = vec3(fl_other.data[base + 6], fl_other.data[base + 7], fl_other.data[base + 8]);

        // Fragment relative to this player's eye
        vec3  pos      = scene_pos - player_pos;
        float dist_sq  = dot(pos, pos);
        float dist     = sqrt(dist_sq);
        vec3  frag_dir = pos * rcp(max(dist, 1e-5));

        float cos_theta = dot(look, frag_dir);
        float cone = smoothstep(outer_cutoff, inner_cutoff, cos_theta);
        if (cone < 1e-4) continue;

        float hotspot = 1.0 + 0.5 * smoothstep(inner_cutoff, 1.0, cos_theta);

        float scaled_dist_sq = dist_sq * rcp(FLASHLIGHT_DISTANCE * FLASHLIGHT_DISTANCE);
        float falloff = lift(rcp(scaled_dist_sq + 1.0), 1.2);
        falloff *= mix(ao, 1.0, falloff * falloff);

        float NdotL = max0(dot(normal, -frag_dir));

        total += col * blocklight_scale * cone * hotspot * falloff * NdotL * FLASHLIGHT_INTENSITY * act;
    }

    return total;
}
#endif // FLASHLIGHT_MULTIPLAYER

#ifdef FLASHLIGHT_SHADOWS

// ─────────────────────────────────────────────────────────────────────────────
// get_flashlight_shadow — SSRT occlusion test for the player flashlight.
// ─────────────────────────────────────────────────────────────────────────────
float get_flashlight_shadow(vec3 scene_pos) {
    // Rebuild hand position in scene space using player orientation (same as get_flashlight_lighting)
    vec3 fl_fwd   = normalize(flashlight_look_dir);
    vec3 fl_right = normalize(cross(fl_fwd, vec3(0.0, 1.0, 0.0)));
    vec3 fl_up    = normalize(cross(fl_right, fl_fwd));

    vec3 hand_offset = fl_right *  FL_HAND_OFFSET.x
    + fl_up    *  FL_HAND_OFFSET.y
    + fl_fwd   * -FL_HAND_OFFSET.z;

    // Convert hand scene-space position to view space for the depth buffer raymarch
    vec3 fl_source_view = scene_to_view_space(-relativeEyePosition + hand_offset);

    // Fragment in view space
    vec3 frag_view = scene_to_view_space(scene_pos);

    // Temporal blue-noise dither — animates per frame to allow TAA to
    // smooth out the hard 0/1 result over time (same technique as SSRT sun).
    float dither = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b;
    dither = r1(frameCounter, dither);

    // Stop at 92 % of the ray to avoid the fragment shadowing itself.
    // The dither adds ±0.5 steps of jitter, so we need a safe margin.
    const float t_max       = 0.92;
    const float z_tolerance = 8.0; // assumed scene geometry thickness (blocks)
    // matches ssrt.glsl's value

    for (int i = 0; i < FLASHLIGHT_SHADOW_STEPS; i++) {
        // Distribute steps evenly from 0 → t_max, with temporal jitter
        float t = (float(i) + 0.5 + dither * 0.5)
        * (t_max / float(FLASHLIGHT_SHADOW_STEPS));

        // Lerp in view space along the flashlight-source → fragment ray
        vec3 sample_view   = fl_source_view + t * (frag_view - fl_source_view);

        // Project the view-space point to screen space [0,1]^3
        vec3 sample_screen = view_to_screen_space(sample_view, true);

        // Steps near t=0 (close to the source) project off-screen because the
        // source's XY offset is large relative to its small Z magnitude. Skip
        // them — the meaningful tests happen near the fragment end of the ray.
        if (clamp01(sample_screen) != sample_screen) continue;

        // Opaque depth at this screen position (depthtex1 = opaque-only, avoids
        // water/glass falsely blocking the beam)
        float scene_depth = texelFetch(
        depthtex1,
        ivec2(sample_screen.xy * view_res * taau_render_scale),
        0
        ).x;

        // Skip sky/void pixels
        if (scene_depth >= 1.0 - 1e-5 || scene_depth == 0.0) continue;

        // Convert screen-space Z values to view-space distances (positive, away
        // from camera) — same convention as ssrt.glsl
        float z_ray    = screen_to_view_space_depth(gbufferProjectionInverse, sample_screen.z);
        float z_sample = screen_to_view_space_depth(gbufferProjectionInverse, scene_depth);

        // Hit condition (verbatim from ssrt.glsl / DrDesten's depth tolerance):
        //   scene_depth < sample_screen.z → geometry in front of the ray
        //   abs(z_tolerance − (z_ray − z_sample)) < z_tolerance
        //     ↔  0 < z_ray − z_sample < 2 * z_tolerance
        //     = geometry is between 0 and 2*z_tolerance blocks behind the ray
        //       (the "slab" that avoids false hits through thin walls)
        bool hit = scene_depth < sample_screen.z
        && abs(z_tolerance - (z_ray - z_sample)) < z_tolerance;

        if (hit) return 0.0;
    }

    return 1.0;
}

#endif

vec3 get_flashlight_lighting(vec3 scene_pos, vec3 normal, float ao) {
#ifndef IS_IRIS
    return vec3(0.0);
#else
    float outer_cutoff = 1.0 - (1.0 - 0.866) * FLASHLIGHT_RADIUS;
    float inner_cutoff = 1.0 - (1.0 - 0.978) * FLASHLIGHT_RADIUS;
    outer_cutoff = clamp(outer_cutoff, 0.0, 0.999);
    inner_cutoff = clamp(inner_cutoff, outer_cutoff + 0.001, 1.0);

    // Build a coordinate frame from the player's look direction, not the camera
    vec3 fl_fwd   = normalize(flashlight_look_dir);
    vec3 fl_right = normalize(cross(fl_fwd, vec3(0.0, 1.0, 0.0)));
    vec3 fl_up    = normalize(cross(fl_right, fl_fwd));

    // Translate FL_HAND_OFFSET (X=right, Y=up, -Z=forward) into scene space
    // using the player's own orientation axes
    vec3 hand_offset = fl_right *  FL_HAND_OFFSET.x
    + fl_up    *  FL_HAND_OFFSET.y
    + fl_fwd   * -FL_HAND_OFFSET.z;

    // Player eye in scene space is -relativeEyePosition
    // (relativeEyePosition = cameraPos - eyePos, so eyePos in scene = -relativeEyePosition)
    vec3 light_origin = -relativeEyePosition + hand_offset;
    vec3 pos = scene_pos - light_origin;

    float dist_sq = dot(pos, pos);
    float dist    = sqrt(dist_sq);
    vec3 frag_dir = pos * rcp(max(dist, 1e-5));

    float cos_theta = dot(normalize(flashlight_look_dir), frag_dir);

    float cone = smoothstep(outer_cutoff, inner_cutoff, cos_theta);
    if (cone < 1e-4) return vec3(0.0);

    // ─── Flashlight shadow ────────────────────────────────────────────────
#if defined FLASHLIGHT_SHADOWS && defined IS_IRIS
    float fl_shadow = get_flashlight_shadow(scene_pos);
    if (fl_shadow < 0.5) return vec3(0.0);
#endif
    // ─────────────────────────────────────────────────────────────────────

    float hotspot = 1.0 + 0.5 * smoothstep(inner_cutoff, 1.0, cos_theta);

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
