// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Horizon port addition:
// the light ratio mobs and items are relit by (post/entity_light.wgsl), eased over about half a
// second so it doesn't flicker as the terrain in view changes. r: the ratio, g: 1 once set.
fn post(input: PostInput) -> vec4<f32> {
    let now = frame_light_ratio();
    let previous = textureLoad(light_ratio_prev, vec2<i32>(0), 0);
    var ratio = now;
    if previous.g > 0.5 && frame.delta_time > 0.0 {
        ratio = mix(previous.r, now, 1.0 - exp(-frame.delta_time / 0.5));
    }
    return vec4<f32>(ratio, 1.0, 0.0, 1.0);
}
