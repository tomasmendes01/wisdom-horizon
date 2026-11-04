// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: bloom,
// vignette and anti-aliasing as Horizon post passes (Wisdom's TAA is not possible there).
// Reads the `bloom` target the bloom pass wrote, softened with a few more taps.
fn bloom_at(uv: vec2<f32>) -> vec3<f32> {
    let px = 2.0 / vec2<f32>(textureDimensions(bloom));
    var sum = vec3<f32>(0.0);
    for (var i = 0; i < 8; i++) {
        let a = f32(i) * 0.785398;
        sum += textureSampleLevel(bloom, linear_sampler, uv + vec2<f32>(cos(a), sin(a)) * px * 4.0, 0.0).rgb;
    }
    let center = textureSampleLevel(bloom, linear_sampler, uv, 0.0).rgb;
    return (sum / 8.0) * 0.75 + center * 0.25;
}
