// Wisdom Shaders V3 by bobcao3 (Apache License 2.0), ported to Horizon. Modified: the
// deferred lighting of composite2 and the fog of composite3, done per surface in
// Horizon's material stage (forward shading), with Horizon's shadow map and samplers.
override shadow_filter: bool = true;
override cloud_shadow: bool = true;
override water_reflections: bool = true;
override held_lights: bool = true;
// Horizon port option: how bright glowing blocks are (1 shows their texture's own colour).
override emissive_brightness: f32 = 1.0;
// The option of post/entity_light.wgsl: water is marked for it only while it is on.
override relight_entities: bool = true;

const TORCH_COLOR: vec3<f32> = vec3<f32>(0.2435, 0.0921, 0.01053) * 3.0;

// --- Lighting.glsl.frag -------------------------------------------------------

fn positive(a: f32) -> f32 {
    return max(0.0000001, a);
}

fn mclightmap_attenuation(lm: f32) -> f32 {
    let falloff = 5.0;
    return max(0.0, exp(-(1.0 - lm) * falloff) - exp(-falloff));
}

fn mclightmap_simulated_gi(ld: f32) -> f32 {
    return 0.4 * (-1.333 / (3.0 * pow(ld, 3.0) + 1.0) + 1.333) * 2.0;
}

fn oren_diffuse(v: vec3<f32>, l: vec3<f32>, n: vec3<f32>, r: f32, ndl: f32, ndv: f32) -> f32 {
    let t = max(ndl, ndv);
    let g = max(0.0, dot(v - n * ndv, l - n * ndl));
    let c = g / t - g * t;
    let a = 0.285 / (r + 0.57) + 0.5;
    let b = 0.45 * r / (r + 0.09);
    return positive(ndl) * (b * c + a);
}

fn fresnel_schlick_roughness(cos_theta: f32, f0: vec3<f32>, roughness: f32) -> vec3<f32> {
    return f0 + (max(vec3<f32>(1.0 - roughness), f0) - f0) * pow(1.0 - cos_theta, 5.0);
}

fn geometry_schlick_ggx(ndv: f32, k: f32) -> f32 {
    return ndv / (ndv * (1.0 - k) + k);
}

fn distribution_ggx(n: vec3<f32>, h: vec3<f32>, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let ndh = positive(dot(n, h));
    var denom = ndh * ndh * (a2 - 1.0) + 1.0;
    denom = PI * denom * denom;
    return a2 / denom;
}

// light_calc_PBR: Oren-Nayar diffuse, GGX specular and light through thin surfaces.
fn light_calc_pbr(color: vec3<f32>, attenuation: f32, l: vec3<f32>, n: vec3<f32>, nvpos: vec3<f32>,
    albedo: vec3<f32>, roughness: f32, metalic: f32, thickness: f32) -> vec3<f32> {
    let ndv = positive(dot(n, -nvpos));
    let ndl = positive(dot(n, l));
    let oren = oren_diffuse(-nvpos, l, n, roughness, ndl, ndv);
    var att = max(0.0, attenuation * oren);
    att += 0.9 * attenuation * (1.0 - att) * max(0.0, pow(1.0 - thickness, 3.0) * (0.5 + 0.5 * dot(l, nvpos)));
    let radiance = att * color;

    let f0 = mix(vec3<f32>(0.01), albedo, metalic);
    let h = normalize(l - nvpos);
    let ndf = distribution_ggx(n, h, roughness);
    let g = geometry_schlick_ggx(ndv, roughness) * geometry_schlick_ggx(ndl, roughness);
    let f = fresnel_schlick_roughness(positive(dot(h, -nvpos)), f0, roughness);
    let kd = max(vec3<f32>(0.0), vec3<f32>(1.0) - f) * (1.0 - metalic);
    let specular = ndf * g * f / (4.0 * ndv * ndl + 0.001);
    return (kd / PI * albedo + specular) * radiance;
}

// light_fetch_shadow: rgb the light let through (tinted under water and stained glass),
// a how much is in shadow (0 lit, 1 dark). Wisdom's jittered 3x3 kernel, with Horizon's
// comparison sampler in place of the depth reads.
fn fetch_shadow(position: vec3<f32>, normal: vec3<f32>, screen: vec2<f32>, c: Commons) -> vec4<f32> {
    if frame.has_shadow == 0u {
        return vec4<f32>(1.0, 1.0, 1.0, 0.0);
    }
    let texel = max(frame.shadow_center_texel, 0.01);
    let p = shadow_position(position + normal * texel * 0.6);
    if any(p.xy <= vec2<f32>(0.0)) || any(p.xy >= vec2<f32>(1.0)) || p.z >= 1.0 {
        return vec4<f32>(1.0, 1.0, 1.0, 0.0);
    }
    var lit = 0.0;
    var clear = 0.0;
    if shadow_filter {
        let n = pixel_noise(screen * frame.resolution);
        for (var i = -1; i < 2; i++) {
            for (var j = -1; j < 2; j++) {
                let jitter = fract(n + f32(i * j) * 0.17) * (1.0 + c.cloud_coverage * 2.0) * 0.7 + 0.3;
                let o = vec2<f32>(f32(i), f32(j)) * jitter * 0.001;
                lit += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + o, p.z);
                clear += textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy + o, p.z);
            }
        }
        lit /= 9.0;
        clear /= 9.0;
    } else {
        lit = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z);
        clear = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy, p.z);
    }
    // Light that reached the surface through water or glass takes its colour.
    let through = max(lit - clear, 0.0);
    var tint = vec3<f32>(1.0);
    if through > 0.0 {
        let size = vec2<f32>(textureDimensions(shadow_color));
        let s = textureLoad(shadow_color, vec2<i32>(clamp(p.xy * size, vec2<f32>(0.0), size - 1.0)), 0);
        tint = select(to_linear(s.rgb), to_linear(s.rgb) * vec3<f32>(0.6, 0.85, 0.9), s.a >= 1.0);
    }
    let light = (vec3<f32>(clear) + through * tint) / max(lit, 1e-4);
    return vec4<f32>(light, 1.0 - lit);
}

// --- composite3: calc_fog_height ----------------------------------------------

// Horizon port option: how much rain thickens the fog, from Wisdom's own (1) to none (0).
override rain_fog: f32 = 0.5;

// Where Wisdom's fog is full: 512 blocks scaled by the cloud cover, of which rain's share is
// scaled by rain_fog (clear skies keep Wisdom's 0.25 cover).
fn fog_end(c: Commons) -> f32 {
    let cover = 0.25 + (c.cloud_coverage - 0.25) * rain_fog;
    return 512.0 * (1.0 - cover);
}

fn fog_height(position: vec3<f32>, start: f32, end: f32, color: vec3<f32>, fog: vec3<f32>) -> vec3<f32> {
    var k = 1.0 - clamp((end - length(position)) / (end - start), 0.0, 1.0);
    k *= clamp((end - position.y) / (end - start), 0.0, 1.0);
    k = pow(k, (1.0 - frame.rain * rain_fog) * 0.5 + 0.5);
    return mix(color, fog, k);
}

// Wisdom's fog, then the sky itself at the edge of the render distance (hides the
// border), and vanilla's fog under water, in lava, blind, and outside the Overworld.
fn finish(hdr: vec3<f32>, position: vec3<f32>, c: Commons, alpha: f32) -> Surface {
    var color = hdr;
    let dir = normalize(position);
    if in_overworld() && frame.eye_in == 0u {
        color = fog_height(position, 0.0, fog_end(c), color, calc_atmosphere(position, dir, c));
        let edge = smoothstep(frame.render_distance * 0.8, frame.render_distance * 0.98, length(position.xz));
        color = mix(color, sky_color(dir, c, false), edge);
    }
    var out = tonemap(max(color, vec3<f32>(0.0)) * get_exposure(c));
    let vanilla_fog = !in_overworld() || frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0;
    if vanilla_fog {
        let f = smoothstep(frame.fog_start, max(frame.fog_end, frame.fog_start + 0.01), length(position));
        out = mix(out, frame.fog_color, f);
    }
    return Surface(vec4<f32>(out, alpha));
}

// finish's fog for water, whose colour is already in display space: Wisdom's height fog and the
// sky at the render-distance edge, tonemapped, then vanilla's fog where finish uses it.
fn water_fog(display: vec3<f32>, position: vec3<f32>, c: Commons, exposure: f32) -> vec3<f32> {
    var out = display;
    let dir = normalize(position);
    if in_overworld() && frame.eye_in == 0u {
        let end = fog_end(c);
        var k = 1.0 - clamp((end - length(position)) / end, 0.0, 1.0);
        k *= clamp((end - position.y) / end, 0.0, 1.0);
        k = pow(k, (1.0 - frame.rain * rain_fog) * 0.5 + 0.5);
        out = mix(out, tonemap(max(calc_atmosphere(position, dir, c), vec3<f32>(0.0)) * exposure), k);
        let edge = smoothstep(frame.render_distance * 0.8, frame.render_distance * 0.98, length(position.xz));
        out = mix(out, tonemap(max(sky_color(dir, c, false), vec3<f32>(0.0)) * exposure), edge);
    }
    let vanilla_fog = !in_overworld() || frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0;
    if vanilla_fog {
        let f = smoothstep(frame.fog_start, max(frame.fog_end, frame.fog_start + 0.01), length(position));
        out = mix(out, frame.fog_color, f);
    }
    return out;
}

// Vanilla darkens block faces by direction; Wisdom runs with that off (oldLighting=false)
// and lights faces itself, so the shade is taken back out of the tint.
fn face_shade(n: vec3<f32>) -> f32 {
    let a = abs(n);
    if a.y > 0.99 {
        return select(0.5, 1.0, n.y > 0.0);
    }
    if a.z > 0.99 {
        return 0.8;
    }
    if a.x > 0.99 {
        return 0.6;
    }
    return 1.0;
}

// --- Water --------------------------------------------------------------------

fn position_at(screen: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return (frame.view_inverse * vec4<f32>(view.xyz / view.w, 0.0)).xyz;
}

fn water_normal(world: vec2<f32>) -> vec3<f32> {
    let e = 0.08;
    var h = vec3<f32>(0.0);
    for (var i = 0; i < 3; i++) {
        let s = f32(i);
        let scale = 0.9 * pow(1.9, s);
        let amp = 0.5 * pow(0.5, s);
        let q = world * scale + animation_offset(vec2<f32>(0.6, 0.35) * (1.0 + s * 0.45));
        h.x += noise(q) * amp;
        h.y += noise(q + vec2<f32>(e * scale, 0.0)) * amp;
        h.z += noise(q + vec2<f32>(0.0, e * scale)) * amp;
    }
    let strength = 0.09 + frame.rain * 0.1;
    return normalize(vec3<f32>((h.x - h.y) / e * strength, 1.0, (h.x - h.z) / e * strength));
}

fn shade_water(input: MaterialInput, c: Commons) -> Surface {
    let world = input.position + frame.camera_position;
    var n = input.normal;
    if input.face == 1u {
        n = water_normal(world.xz);
        if dot(n, input.normal) < 0.0 {
            n = -n;
        }
    }
    let nvpos = normalize(input.position);
    let ndv = clamp(dot(n, -nvpos), 0.0, 1.0);
    let fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
    let sky_seen = smoothstep(0.3, 0.9, input.light.y);

    // What lies behind, already shaded and tonemapped by this pack: mix in display space.
    let size = vec2<f32>(textureDimensions(opaque_depth));
    let bent = clamp(input.screen + n.xz * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let texel = vec2<i32>(clamp(bent * size, vec2<f32>(0.0), size - 1.0));
    let behind_depth = textureLoad(opaque_depth, texel, 0);
    let behind = to_linear(textureLoad(opaque_color, texel, 0).rgb);
    var thickness = 24.0;
    if behind_depth > 0.0 {
        thickness = clamp(distance(position_at(bent, behind_depth), input.position), 0.0, 24.0);
    }
    let absorb = exp(-thickness * vec3<f32>(0.42, 0.11, 0.07));
    let exposure = get_exposure(c);
    let body_hdr = to_linear(input.albedo.rgb * input.tint.rgb)
        * (c.ambient * mclightmap_simulated_gi(input.light.y) + TORCH_COLOR * mclightmap_attenuation(input.light.x)) * 0.6;
    let body = to_linear(tonemap(body_hdr * exposure));
    let refracted = behind * absorb + body * (1.0 - absorb);

    let r = reflect(nvpos, n);
    var reflected = to_linear(tonemap(sky_color(r, c, true) * exposure)) * sky_seen;
    if water_reflections && frame.has_reflection == 1u {
        let m = textureSampleLevel(reflection, reflection_sampler, clamp(input.screen + n.xz * 0.03, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        // Horizon draws the mirror with vanilla's lighting: bring it to this pack's light, by how
        // the two compare for a grey surface lit as the water is (Horizon port change).
        reflected = mix(reflected, to_linear(m.rgb * mirror_light_ratio(input, c, exposure)), sky_seen * 0.85);
    }

    let shadow = fetch_shadow(input.position, input.normal, input.screen, c);
    let h = normalize(frame.light_direction - nvpos);
    // Rain clouds hide the sun: the glint fades with them (Horizon port change).
    let glint = pow(max(dot(n, h), 0.0), 300.0) * 6.0 * (1.0 - shadow.a) * (1.0 - c.ext_shadow)
        * (1.0 - 0.9 * bad_weather());
    let spec = to_linear(tonemap(c.sun * glint * exposure));

    var col = mix(refracted, reflected, fresnel) + spec;
    col = mix(col, refracted, frame.in_water);
    // The same fog as the terrain (finish), so water greys out in the rain like the land does.
    var out = water_fog(to_display(min(col, vec3<f32>(1.0))), input.position, c, exposure);
    // The mark only matters to the mobs' relighting, and it shows as a dither in dark water.
    if relight_entities {
        out = water_marker(out, input.screen);
    }
    return Surface(vec4<f32>(out, 1.0));
}

// How much brighter or darker this pack lights a grey surface than vanilla does, where `input` is
// (display-space luminance ratio), for pictures Horizon draws with vanilla's light.
fn mirror_light_ratio(input: MaterialInput, c: Commons, exposure: f32) -> f32 {
    let grey = 0.18;
    var light = c.ambient * mclightmap_simulated_gi(input.light.y) + TORCH_COLOR * mclightmap_attenuation(input.light.x);
    if in_overworld() {
        light += c.sun * (1.0 - c.ext_shadow) * 0.25 * pow(input.light.y, 4.0);
    }
    let ours = luma(tonemap(vec3<f32>(grey) * light * exposure));
    let vanilla = luma(vec3<f32>(pow(grey, 1.0 / 2.2)) * input.lightmap);
    return clamp(ours / max(vanilla, 0.004), 0.05, 1.5);
}

// Water's pixels carry a mark in the low bits of each 8-bit channel, in a checkerboard: 2 mod 4
// on even pixels, 0 mod 4 on odd ones (at most 3/255 off). No mob or item can match it over a
// patch of pixels, even where its texture is one flat colour, so post/entity_light.wgsl can
// leave water, and only water, out of the relighting of mobs and items.
fn water_marker(display: vec3<f32>, screen: vec2<f32>) -> vec3<f32> {
    let pixel = vec2<u32>(screen * frame.resolution);
    let base = select(2.0, 0.0, ((pixel.x + pixel.y) & 1u) == 1u);
    let v = floor(clamp(display, vec3<f32>(0.0), vec3<f32>(1.0)) * 255.0 / 4.0) * 4.0 + base;
    return min(v, vec3<f32>(252.0 + base)) / 255.0;
}

// --- The material -------------------------------------------------------------

fn material(input: MaterialInput) -> Surface {
    let c = commons();
    if input.fluid == 1u {
        return shade_water(input, c);
    }
    let foliage = input.material == MAT_LEAVES || input.material == MAT_PLANT;
    var tint = input.tint.rgb;
    if !foliage {
        tint /= face_shade(input.normal);
    }
    let albedo = to_linear(input.albedo.rgb * min(tint, vec3<f32>(1.0)));
    let n = input.normal;
    let nvpos = normalize(input.position);
    let sky = input.light.y;
    let block = input.light.x;

    // LabPBR maps when the resource packs have them; Wisdom's defaults otherwise.
    var roughness = 0.9999;
    var metalic = 0.0001;
    var emissive = smoothstep(0.3, 0.9, input.emission);
    if block_pbr_maps() {
        let spec = block_specular_map(input.uv);
        roughness = clamp(1.0 - spec.r, 0.0001, 0.9999);
        metalic = clamp(spec.g, 0.0001, 0.9999);
        if spec.a < 0.995 {
            emissive = max(emissive, spec.a);
        }
    }

    var color = vec3<f32>(0.0);
    if in_overworld() {
        let shadow = fetch_shadow(input.position, n, input.screen, c);
        var shade = shadow.a;
        if frame.eye_in == 1u {
            shade = max(shade, 1.0 - sky);
        }
        var attenuation = 1.0 - max(c.ext_shadow, shade);
        if cloud_shadow {
            let clouds = calc_clouds(frame.light_direction * 512.0, frame.camera_position + input.position, 0.0, c);
            attenuation *= max(0.0, 1.0 - clouds.a * 1.6);
        }
        // Thin plants let light through (Wisdom's subsurface term, by shadow thickness).
        let thickness = select(1.0, shade, foliage);
        color += light_calc_pbr(c.sun * shadow.rgb, attenuation, frame.light_direction, n, nvpos,
            albedo, roughness, metalic, thickness);
        color += mclightmap_simulated_gi(sky) * albedo * c.ambient;
    } else {
        color += albedo * c.ambient;
    }
    color += mclightmap_attenuation(block) * albedo * TORCH_COLOR;
    // Horizon port addition: held and dropped light sources (Horizon's dynamic lights, coloured by
    // the manifest's [[lights]]), on the same curve as Wisdom's torch light.
    if held_lights {
        let reach = max(input.colored_light.r, max(input.colored_light.g, input.colored_light.b));
        let tint = input.colored_light / max(reach, 1e-4);
        color += mclightmap_attenuation(reach) * albedo * tint * luma(TORCH_COLOR) * 3.0;
    }

    // Glowing blocks (fire, lava, glowstone, torches): Wisdom's emissive mix, but scaled against
    // the exposure so they show their own colour instead of burning out to white when the
    // night raises the exposure (Horizon port change).
    color = mix(color, albedo * (1.6 * emissive_brightness / get_exposure(c)), emissive);
    // Night vision: lift toward vanilla's lightmap.
    color = mix(color, albedo * to_linear(input.lightmap) * 1.5, frame.night_vision);

    let surface = finish(color, input.position, c, input.albedo.a * input.tint.a);
    // For the post pass that relights mobs, items and chests (post/entity_light.wgsl): how this
    // pack's light here compares with vanilla's.
    let vanilla = input.albedo.rgb * input.tint.rgb * input.lightmap;
    // smoothness carries how much the block glows (the bloom pass reads it); data the light ratio.
    set_surface(n, emissive, clamp(luma(surface.color.rgb) / max(luma(vanilla), 0.004), 0.0, 4.0));
    return surface;
}
