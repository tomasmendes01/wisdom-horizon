// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: bloom,
// vignette and anti-aliasing as Horizon post passes (Wisdom's TAA is not possible there).
// Bloom, an underwater tint, and the colour grade: contrast, saturation and a vignette.
override bloom_strength: f32 = 0.3;
override contrast: f32 = 1.0;
override saturation: f32 = 1.0;
override vignette: bool = true;

fn post(input: PostInput) -> vec4<f32> {
    let scene = skyline(input.uv, textureSampleLevel(scene_color, linear_sampler, input.uv, 0.0).rgb);
    // This frame's light ratio for mobs and items, eased over time (post/ratio_update.wgsl).
    let eased = textureLoad(light_ratio, vec2<i32>(0), 0);
    var ratio = eased.r;
    if eased.g < 0.5 {
        ratio = frame_light_ratio();
    }
    var c = to_linear(relight(input.uv, scene, ratio));
    c += bloom_at(input.uv) * bloom_strength;

    // Under water: blue-green and a little murky.
    c = mix(c, c * vec3<f32>(0.35, 0.75, 0.85), frame.in_water * 0.7);

    var d = to_display(c);
    d = (d - 0.5) * contrast + 0.5;
    let grey = luminance(d);
    d = mix(vec3<f32>(grey), d, saturation * (1.0 - bad_weather() * 0.25));

    if vignette {
        let aspect = frame.resolution.x / frame.resolution.y;
        let off = (input.uv - 0.5) * vec2<f32>(aspect, 1.0);
        let r = length(off) / length(vec2<f32>(aspect, 1.0) * 0.5);
        d *= 1.0 - smoothstep(0.6, 1.15, r) * 0.28;
    }
    if relight_entities && relight_debug && input.uv.x < 0.06 && input.uv.y < 0.06 {
        d = vec3<f32>(clamp(ratio / 1.5, 0.0, 1.0));
    }
    return vec4<f32>(clamp(d, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
}
