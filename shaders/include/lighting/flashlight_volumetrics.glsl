#if !defined INCLUDE_LIGHTING_FLASHLIGHT_VOLUMETRICS
#define INCLUDE_LIGHTING_FLASHLIGHT_VOLUMETRICS

layout(std430, binding = 1) buffer OtherFlashlightVolBuffer {
    float data[40];
} fl_other_vol;

uniform float flashlight_active;
uniform float flashlight_color_r;
uniform float flashlight_color_g;
uniform float flashlight_color_b;
uniform vec3  flashlight_look_dir;

uniform vec3 relativeEyePosition;

#ifdef FLASHLIGHT

// Flashlight origin in view space — tune all three values here.
// +X = right,  +Y = up,  -Z = forward (OpenGL convention)
#define FL_HAND_OFFSET vec3(FL_OFFSET_X, FL_OFFSET_Y, FL_OFFSET_Z)

#endif

float fl_vol_hash(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// frag_dir : normalized world-space direction from camera to fragment
// max_dist : distance to the surface (or large value for sky)
vec3 get_flashlight_volumetrics(vec3 frag_dir, float max_dist, float sky_exposure) {
    if (flashlight_active < 0.001) return vec3(0.0);

    vec3  fl_col = vec3(flashlight_color_r, flashlight_color_g, flashlight_color_b);
    vec3  look   = normalize(flashlight_look_dir);

    // Cone parameters — must mirror handheld_lighting.glsl
    float outer = clamp(1.0 - (1.0 - 0.866) * FLASHLIGHT_RADIUS, 0.0, 0.999);
    float inner = clamp(1.0 - (1.0 - 0.978) * FLASHLIGHT_RADIUS, outer + 0.001, 1.0);

    // Flashlight world-space origin at player hand
    vec3 fl_right_w = normalize(cross(look, vec3(0.0, 1.0, 0.0)));
    vec3 fl_up_w    = normalize(cross(fl_right_w, look));
    vec3 hand_offset_world = fl_right_w *  FL_HAND_OFFSET.x
    + fl_up_w    *  FL_HAND_OFFSET.y
    + look       * -FL_HAND_OFFSET.z;
    vec3 fl_origin = (cameraPosition - relativeEyePosition) + hand_offset_world;

    // March from fl_origin toward the fragment — cone is then constant for all
    // samples (parallel beam), eliminating the ghost beam artifact
    vec3 frag_world  = cameraPosition + frag_dir * min(max_dist, 12.0 * FLASHLIGHT_DISTANCE);
    vec3 fl_to_frag  = frag_world - fl_origin;
    float fl_march_dist = length(fl_to_frag);
    vec3 fl_dir      = fl_to_frag / max(fl_march_dist, 1e-5);

    // Cone computed once — constant since we march in a fixed direction from fl_origin
    float cos_ray = dot(look, fl_dir);
    float cone    = smoothstep(outer, inner, cos_ray);
    if (cone < 0.001) return vec3(0.0);

    // Don't render volumetrics on the hand model itself
    float self_depth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).x;
    if (self_depth < hand_depth) return vec3(0.0);

    float march_dist = min(fl_march_dist, 12.0 * FLASHLIGHT_DISTANCE);
    float step_size  = march_dist / float(FLASHLIGHT_VOL_STEPS);

    vec3 result = vec3(0.0);

    for (int i = 0; i < FLASHLIGHT_VOL_STEPS; i++) {
        float t = (float(i) + 0.5) * step_size;

        // t IS the axial distance since we march from fl_origin
        float scaled_t = t / FLASHLIGHT_DISTANCE;
        float falloff  = 1.0 / (scaled_t * scaled_t * 0.5 + 1.0);

        // ─── Per-step shadow: single depth test projected from flashlight source ──
        float vol_shadow = 1.0;
        #ifdef FLASHLIGHT_SHADOWS
        {
            vec3 fl_fwd   = normalize(flashlight_look_dir);
            vec3 fl_right = normalize(cross(fl_fwd, vec3(0.0, 1.0, 0.0)));
            vec3 fl_up    = normalize(cross(fl_right, fl_fwd));

            vec3 hand_offset = fl_right *  FL_HAND_OFFSET.x
                    + fl_up    *  FL_HAND_OFFSET.y
                    + fl_fwd   * -FL_HAND_OFFSET.z;

            vec3 fl_source_view = scene_to_view_space(-relativeEyePosition + hand_offset);

            vec3 step_view = scene_to_view_space((fl_origin - cameraPosition) + fl_dir * t);

            // Sample the midpoint between source and step so we catch blockers
            // that are between the flashlight and the scattering point
            vec3 mid_view   = fl_source_view + 0.6 * (step_view - fl_source_view);
            vec3 mid_screen = view_to_screen_space(mid_view, true);

            if (clamp01(mid_screen) == mid_screen) {
                float scene_depth = texelFetch(
                depthtex1,
                ivec2(mid_screen.xy * view_res * taau_render_scale),
                0
                ).x;

                if (scene_depth < 1.0 - 1e-5 && scene_depth != 0.0
                && scene_depth >= hand_depth) {
                    float z_mid    = screen_to_view_space_depth(gbufferProjectionInverse, mid_screen.z);
                    float z_sample = screen_to_view_space_depth(gbufferProjectionInverse, scene_depth);
                    const float z_tol = 8.0;

                    if (scene_depth < mid_screen.z
                    && abs(z_tol - (z_mid - z_sample)) < z_tol) {
                        vol_shadow = 0.0;
                    }
                }
            }
        }
        #endif
        // ─────────────────────────────────────────────────────────────────────────

        result += fl_col * (cone * falloff * vol_shadow * 0.004 * FLASHLIGHT_INTENSITY * step_size);

        // --- Dust particle ---
        vec3 sample_world = fl_origin + fl_dir * t;
        vec3 cell  = floor(sample_world);
        float base = fl_vol_hash(cell);

        // Density threshold — underground 2x, outside 1/10
        float sky_density_mult  = mix(1.0, 0.1, sky_exposure);
        float density_threshold = 1.0 - FLASHLIGHT_PARTICLE_DENSITY * 0.033;

        float coarse        = fl_vol_hash(floor(sample_world * 0.33) + vec3(4.1, 7.7, 2.3));
        float cluster_zone  = smoothstep(0.3, 0.7, coarse);
        float cluster_delta = 0.06 * FLASHLIGHT_PARTICLE_CLUSTERING;
        float cell_threshold = density_threshold
            - cluster_delta * cluster_zone
            + cluster_delta * (1.0 - cluster_zone);

        // Gate 1: density + clustering
        if (base > clamp(cell_threshold, 0.0, 1.0)) {

            // Gate 2: independent sky probability, no clamping issues
            float sky_gate = fl_vol_hash(cell + vec3(3.3, 8.1, 1.7));
            if (sky_gate < sky_density_mult) {

                float life_seed  = fl_vol_hash(cell + vec3(7.3, 2.1, 5.9));
                float drift_seed = fl_vol_hash(cell + vec3(1.1, 4.4, 3.3));

                float life_t = fract(life_seed + frameTimeCounter * 0.08);
                float life   = smoothstep(0.0, 0.15, life_t)
                             * smoothstep(1.0, 0.85, life_t);

                if (life > 0.01) {
                    float drift_t = frameTimeCounter * 0.36 + drift_seed * 6.28;
                    vec3 p_world  = cell + 0.5 + vec3(
                        (fl_vol_hash(cell + 0.1) - 0.5) * 0.5,
                        sin(drift_t) * 0.10,
                        (fl_vol_hash(cell + 0.3) - 0.5) * 0.5
                    );

                    float p_proj = dot(p_world - cameraPosition, frag_dir);

                    if (p_proj > 0.1 && p_proj < max_dist) {
                        vec3 closest  = cameraPosition + frag_dir * p_proj;
                        vec3 perp_vec = p_world - closest;

                        vec3 right = normalize(cross(frag_dir, vec3(0.0, 1.0, 0.0)));
                        vec3 up    = normalize(cross(right, frag_dir));

                        float perp = max(abs(dot(perp_vec, right)),
                                         abs(dot(perp_vec, up)));

                        float pixel_threshold = max(p_proj * 0.005, 0.008);

                        if (perp < pixel_threshold) {
                            vec3  p_dir  = normalize(p_world - cameraPosition);
                            float p_cos  = dot(look, p_dir);
                            float p_cone = smoothstep(outer, inner, p_cos);

                            float p_scaled = p_proj / FLASHLIGHT_DISTANCE;
                            float p_fall   = 1.0 / (p_scaled * p_scaled * 0.5 + 1.0);

                            result += fl_col
                                * (p_cone * p_fall * life * 0.10 * FLASHLIGHT_INTENSITY * vol_shadow);
                        }
                    }
                }
            }
        }
    }

    return result * flashlight_active;
}

#ifdef FLASHLIGHT_MULTIPLAYER

vec3 get_other_flashlight_volumetrics(vec3 frag_dir, float max_dist) {
    vec3 total = vec3(0.0);

    float outer = clamp(1.0 - (1.0 - 0.866) * FLASHLIGHT_RADIUS, 0.0, 0.999);
    float inner = clamp(1.0 - (1.0 - 0.978) * FLASHLIGHT_RADIUS, outer + 0.001, 1.0);

    float march_dist = min(max_dist, 12.0 * FLASHLIGHT_DISTANCE);
    float step_size  = march_dist / float(FLASHLIGHT_VOL_STEPS);

    for (int s = 0; s < FLASHLIGHT_VOL_STEPS; s++) {
        float t = (float(s) + 0.5) * step_size;
        vec3 sample_world = cameraPosition + frag_dir * t;

        for (int pi = 0; pi < 4; pi++) {
            int   base   = pi * 10;
            float pl_active = fl_other_vol.data[base + 9];
            if (pl_active < 0.001) continue;

            vec3 player_world = vec3(
                fl_other_vol.data[base],
                fl_other_vol.data[base + 1],
                fl_other_vol.data[base + 2]
            ) + cameraPosition;

            vec3 look = normalize(vec3(
                fl_other_vol.data[base + 3],
                fl_other_vol.data[base + 4],
                fl_other_vol.data[base + 5]
            ));
            vec3 col = vec3(
                fl_other_vol.data[base + 6],
                fl_other_vol.data[base + 7],
                fl_other_vol.data[base + 8]
            );

            vec3  to_sample  = sample_world - player_world;
            float dist       = length(to_sample);
            vec3  sample_dir = to_sample / max(dist, 1e-5);

            float cos_ray = dot(look, sample_dir);
            float cone    = smoothstep(outer, inner, cos_ray);
            if (cone < 0.001) continue;

            float scaled = dist / FLASHLIGHT_DISTANCE;
            float falloff = 1.0 / (scaled * scaled * 0.5 + 1.0);

            total += col * (cone * falloff * 0.004 * FLASHLIGHT_INTENSITY * step_size * pl_active);
        }
    }

    return total;
}
#endif // FLASHLIGHT_MULTIPLAYER

#endif // INCLUDE_LIGHTING_FLASHLIGHT_VOLUMETRICS