// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: rain
// and snow lit by Wisdom's ambient and torch light, tonemapped like the rest.
fn weather(input: WeatherInput) -> vec4<f32> {
    let c = commons();
    let torch = vec3<f32>(0.2435, 0.0921, 0.01053) * 3.0;
    let light = c.ambient * 0.4 * (-1.333 / (3.0 * pow(input.light.y, 3.0) + 1.0) + 1.333) * 2.0
        + c.sun * 0.15 * input.light.y
        + torch * max(0.0, exp(-(1.0 - input.light.x) * 5.0) - exp(-5.0));
    var lit = tonemap(to_linear(input.color.rgb) * light * get_exposure(c) * 2.0);
    // Never darker than a faint grey streak, and fainter the darker it is, so rain at night
    // doesn't cover the screen in dark lines (Horizon port change).
    lit = max(lit, input.color.rgb * 0.18);
    let visibility = mix(0.25, 1.0, smoothstep(0.05, 0.35, luma(lit)));
    return vec4<f32>(lit, input.color.a * select(0.5, 0.8, input.snow) * visibility);
}
