// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: waving
// foliage (WAVING_FOILAGE) and water swell as Horizon's vertex stage.
// Leaves sway, small plants bend at the top, and water rolls gently. The same movement is
// used for the shadow map, so shadows move with the plants.
override waving_plants: bool = true;

fn vertex(input: VertexInput) -> vec3<f32> {
    var p = input.position;
    if !waving_plants {
        return p;
    }
    let w = p + frame.camera_position;
    let t = frame.time;
    let wind = 0.7 + 0.3 * sin(t * 0.37) + bad_weather() * 0.9;

    if input.material == MAT_LEAVES {
        let sway = vec3<f32>(
            sin(t * 1.7 + w.x * 0.9 + w.y * 0.6),
            sin(t * 2.3 + w.z * 0.7 + w.x * 0.3) * 0.4,
            sin(t * 1.3 + w.z * 0.8 + w.y * 0.5),
        );
        p += sway * 0.03 * wind;
    } else if input.material == MAT_PLANT {
        // Only the top of the sprite moves (uv.y 0 is its top edge), so plants stay rooted.
        let top = 1.0 - clamp(input.uv.y, 0.0, 1.0);
        let bend = vec2<f32>(sin(t * 2.0 + w.x * 0.8 + w.z * 0.4), sin(t * 1.6 + w.z * 0.9 + w.x * 0.2));
        p.x += bend.x * 0.08 * top * wind;
        p.z += bend.y * 0.08 * top * wind;
    } else if input.fluid == 1u && input.face == 1u {
        // The top of a fluid: a slow swell, kept just under its resting height.
        let swell = sin(t * 1.4 + w.x * 0.7 + w.z * 0.5) + sin(t * 1.1 - w.z * 0.9 + w.x * 0.3);
        p.y += swell * 0.012 - 0.025;
    }
    return p;
}
