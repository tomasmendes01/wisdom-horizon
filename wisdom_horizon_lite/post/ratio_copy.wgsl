// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Horizon port addition:
// keeps last frame's light ratio (the `light_ratio` target, written later in the chain) for the
// next pass to ease toward this frame's value.
fn post(input: PostInput) -> vec4<f32> {
    return textureLoad(light_ratio, vec2<i32>(0), 0);
}
