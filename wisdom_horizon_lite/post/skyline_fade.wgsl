// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Horizon port addition:
// where the loaded terrain ends (a server's view distance can be shorter than the render distance
// the shader knows), its last chunks stood out against the sky as a hard band. Distant terrain
// just under the sky blends into the sky above it over a few pixels, whatever the distance it
// ends at; nearby trees and hills against the sky are left alone.
override skyline_fade: bool = true;

fn skyline(uv: vec2<f32>, color: vec3<f32>) -> vec3<f32> {
    if !skyline_fade || !in_overworld() || frame.eye_in != 0u {
        return color;
    }
    let depth = depth_at(uv);
    if depth == 0.0 {
        return color;
    }
    let far_k = smoothstep(64.0, 160.0, length(view_position(uv, depth))) * 0.7;
    if far_k <= 0.0 {
        return color;
    }
    let step = 2.0 * max(frame.resolution.y / 720.0, 1.0) / frame.resolution.y;
    for (var i = 1; i <= 10; i++) {
        let up = uv - vec2<f32>(0.0, f32(i) * step);
        if up.y < 0.0 {
            break;
        }
        if depth_at(up) == 0.0 {
            let sky = textureSampleLevel(scene_color, linear_sampler, up, 0.0).rgb;
            let k = 1.0 - f32(i) / 11.0;
            return mix(color, sky, k * k * far_k);
        }
    }
    return color;
}
