// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: bloom,
// vignette and anti-aliasing as Horizon post passes (Wisdom's TAA is not possible there).
// The bright parts of the picture, blurred, at half size (the `bloom` target). The sky
// counts for less, so a clear day doesn't wash out. Glowing blocks (fire, lava, glowstone: the
// material stage stores how much a block glows) bloom more, by emissive_bloom.
override emissive_bloom: f32 = 0.8;
fn post(input: PostInput) -> vec4<f32> {
    let px = 1.0 / frame.resolution;
    let surface_size = vec2<f32>(textureDimensions(scene_surface));
    var sum = vec3<f32>(0.0);
    var weight = 0.0;
    for (var i = -2; i <= 2; i++) {
        for (var j = -2; j <= 2; j++) {
            let o = vec2<f32>(f32(i), f32(j));
            let uv = input.uv + o * px * 5.0;
            let c = to_linear(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
            let l = luminance(c);
            let glow = surface_at(vec2<i32>(uv * surface_size)).smoothness;
            // Capped, so a glowing block's halo spreads instead of piling up on the block itself.
            let bright = min(max(l - 0.45, 0.0) / max(l, 1e-4) + glow * emissive_bloom, 1.0);
            let sky = select(1.0, 0.3, depth_at(uv) == 0.0);
            let w = exp(-dot(o, o) * 0.18);
            sum += c * bright * sky * w;
            weight += w;
        }
    }
    return vec4<f32>(sum / weight, 1.0);
}
