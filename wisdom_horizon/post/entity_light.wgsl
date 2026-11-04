// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Horizon port addition:
// mobs, dropped items, block entities (chests, signs...) and particles are drawn by Horizon with
// vanilla's lighting, which the native shader API doesn't let a pack change, so at night or in the
// rain they looked lit while the terrain around them was dark. The material stage stores, for each
// pixel of terrain, how much brighter or darker this pack's light is than vanilla's there
// (`set_surface`'s data). One factor for the whole frame, read from the terrain in front of the
// camera, relights everything else the same way, so a mob is never lit in patches.
override relight_entities: bool = true;
// Diagnostic view of the relighting: relit pixels magenta, water cyan, the frame's ratio as a
// grey square in the top-left corner (white = 1.5, mid grey = 0.75).
override relight_debug: bool = false;

// The material stage marks water's pixels in a checkerboard: every 8-bit channel 2 mod 4 on even
// pixels, 0 mod 4 on odd ones.
fn water_mark(texel: vec2<i32>) -> bool {
    let size = vec2<i32>(textureDimensions(scene_color));
    let t = clamp(texel, vec2<i32>(0), size - 1);
    let c = textureLoad(scene_color, t, 0).rgb;
    let v = vec3<u32>(round(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)) * 255.0));
    let expected = select(2u, 0u, ((t.x + t.y) & 1) == 1);
    return all((v & vec3<u32>(3u)) == vec3<u32>(expected));
}

// Water: the mark along a short horizontal run through the pixel, on both checkerboard colours
// (a mob's flat-coloured patch can only ever match one of them). Looking sideways lets a rain
// streak over water, which is thin and vertical and blends the mark away under it, still count
// as water, so the rain isn't darkened as if it were a mob.
fn is_water(uv: vec2<f32>) -> bool {
    let size = vec2<f32>(textureDimensions(scene_color));
    let t = vec2<i32>(uv * size);
    var even = 0;
    var odd = 0;
    for (var dx = -3; dx <= 3; dx++) {
        let p = t + vec2<i32>(dx, 0);
        if water_mark(p) {
            if ((p.x + p.y) & 1) == 1 {
                odd += 1;
            } else {
                even += 1;
            }
        }
    }
    return even + odd >= 3 && even >= 1 && odd >= 1;
}

// Water by its shape, whatever is drawn over it: rain writes no depth, so under a streak the depth
// is still the water's, and water's top lies flat (this pack doesn't wave it) at a height that is
// a ninth of a block (a source block's 8/9, a flowing column's levels).
fn on_water_plane(uv: vec2<f32>, depth: f32) -> bool {
    let px = 1.0 / frame.resolution;
    let rel = view_position(uv, depth);
    let tolerance = 0.002 + length(rel) * 0.0005;
    let y = rel.y + frame.camera_position.y;
    let r_uv = uv + vec2<f32>(px.x, 0.0);
    let d_uv = uv + vec2<f32>(0.0, px.y);
    let yr = view_position(r_uv, depth_at(r_uv)).y + frame.camera_position.y;
    let yd = view_position(d_uv, depth_at(d_uv)).y + frame.camera_position.y;
    if abs(y - yr) > tolerance || abs(y - yd) > tolerance {
        return false;
    }
    let ninth = fract(y * 9.0);
    return min(ninth, 1.0 - ninth) < tolerance * 9.0;
}

// How this pack's light compares with vanilla's this frame: the stored ratio averaged over the
// terrain in the lower middle of the screen (in front of and around the player).
fn frame_light_ratio() -> f32 {
    let size = vec2<f32>(textureDimensions(scene_surface));
    var sum = 0.0;
    var count = 0.0;
    for (var i = 0; i < 24; i++) {
        let uv = vec2<f32>(0.2 + f32(i % 6) * 0.12, 0.45 + f32(i / 6) * 0.13);
        let s = surface_at(vec2<i32>(uv * size));
        if s.present {
            sum += s.data;
            count += 1.0;
        }
    }
    if count > 0.0 {
        return sum / count;
    }
    // Only sky in view: dimmer at night and in the rain, like the terrain would be.
    return mix(0.3, 1.0, smoothstep(-0.08, 0.12, frame.sun_direction.y)) * (1.0 - 0.4 * bad_weather());
}

// `color` (display) relit with this frame's ratio, where it isn't the sky, terrain or water.
fn relight(uv: vec2<f32>, color: vec3<f32>, ratio: f32) -> vec3<f32> {
    if !relight_entities || depth_at(uv) == 0.0 {
        return color;
    }
    let size = vec2<f32>(textureDimensions(scene_surface));
    if surface_at(vec2<i32>(uv * size)).present {
        return color;
    }
    if is_water(uv) || on_water_plane(uv, depth_at(uv)) {
        // Diagnostic view: what is taken for water shows cyan.
        return select(color, mix(color, vec3<f32>(0.0, 1.0, 1.0), 0.6), relight_debug);
    }
    // Diagnostic view: what is relit (mobs, items, chests, particles) shows magenta.
    let relit = color * clamp(ratio, 0.05, 1.5);
    return select(relit, mix(relit, vec3<f32>(1.0, 0.0, 1.0), 0.6), relight_debug);
}
