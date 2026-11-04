// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: bloom,
// vignette and anti-aliasing as Horizon post passes (Wisdom's TAA is not possible there).
// Smooths jagged edges (Horizon's own anti-aliasing is off while a pack draws the frame):
// where the brightness changes sharply, blend along the edge instead of across it.
override fxaa: bool = true;

fn luma_at(uv: vec2<f32>) -> f32 {
    return luminance(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb);
}

fn post(input: PostInput) -> vec4<f32> {
    if !fxaa {
        return input.color;
    }
    let px = 1.0 / vec2<f32>(textureDimensions(previous));
    let m = luminance(input.color.rgb);
    let n = luma_at(input.uv + vec2<f32>(0.0, -px.y));
    let s = luma_at(input.uv + vec2<f32>(0.0, px.y));
    let e = luma_at(input.uv + vec2<f32>(px.x, 0.0));
    let w = luma_at(input.uv + vec2<f32>(-px.x, 0.0));
    let hi = max(m, max(max(n, s), max(e, w)));
    let lo = min(m, min(min(n, s), min(e, w)));
    let range = hi - lo;
    if range < max(0.04, hi * 0.15) {
        return input.color;
    }
    // Along the edge: perpendicular to the brightness gradient.
    let dir = normalize(vec2<f32>(-(s - n), e - w) + vec2<f32>(1e-5));
    let a = textureSampleLevel(previous, linear_sampler, input.uv + dir * px * 0.5, 0.0).rgb;
    let b = textureSampleLevel(previous, linear_sampler, input.uv - dir * px * 0.5, 0.0).rgb;
    let c = textureSampleLevel(previous, linear_sampler, input.uv + dir * px * 1.75, 0.0).rgb;
    let d = textureSampleLevel(previous, linear_sampler, input.uv - dir * px * 1.75, 0.0).rgb;
    let near = (a + b) * 0.5;
    var smoothed = (a + b + c + d) * 0.25;
    // A wide sample that strays out of the local range crossed another edge: keep the near one.
    let sl = luminance(smoothed);
    if sl < lo || sl > hi {
        smoothed = near;
    }
    let amount = clamp(range * 2.0, 0.0, 1.0);
    return vec4<f32>(mix(input.color.rgb, smoothed, amount), input.color.a);
}
