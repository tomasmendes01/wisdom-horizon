// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: the
// sky pass of composite2 (calc_sky_with_sun) as Horizon's sky stage, tonemapped here.
override clouds_2d: bool = true;

fn sky(input: SkyInput) -> vec4<f32> {
    if !in_overworld() {
        return input.color;
    }
    let c = commons();
    let dir = input.direction;
    var sky = calc_atmosphere(dir * 512.0 + vec3<f32>(0.0, frame.camera_position.y, 0.0), dir, c);

    // The sun and the moon: Wisdom draws both discs itself.
    let dot_s = dot(dir, frame.light_direction);
    let ground_cover = smoothstep(30.0, 60.0, dir.y * 512.0);
    sky += c.sun * smoothstep(0.9992, 0.9995, abs(dot_s)) * (1.0 - frame.rain) * 5.0 * ground_cover;

    if clouds_2d {
        let clouds = calc_clouds(dir * 512.0, frame.camera_position, max(dot_s, 0.0), c);
        sky = mix(sky, clouds.rgb, clouds.a);
    }

    var out = tonemap(max(sky, vec3<f32>(0.0)) * get_exposure(c));
    // Blindness, darkness and being under water or in lava keep vanilla's colour.
    let vanilla = max(max(frame.blindness, frame.darkness), max(frame.in_water, frame.in_lava));
    out = mix(out, input.color.rgb, vanilla);
    return vec4<f32>(out, input.color.a);
}
