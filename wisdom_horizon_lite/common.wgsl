// Wisdom Shaders V3 (Build 3300) by bobcao3, ported to Horizon's shader API (WGSL).
// Licensed under the Apache License 2.0 (LICENSE.txt). Modified: translated from GLSL,
// restructured into Horizon's stages; see README.md for the full list of changes.
//
// Shared by every stage: Wisdom's time-of-day colours (calcCommons), its noise, the
// atmosphere and 2D clouds, the exposure and the AgX / ACES tonemap.

override exposure_mul: f32 = 1.0;
override agx_tonemap: bool = true;
// Horizon port option: how much the moonlight and the night's ambient light are raised over
// Wisdom's own (1), which many found too dark to play in.
override night_brightness: f32 = 3.0;

const PI: f32 = 3.14159265;
const TAU: f32 = 6.2831853;

// [[materials]] ids from horizon-shaders.toml.
const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;

const SKY_RGB: vec3<f32> = vec3<f32>(0.1502, 0.4056, 1.0);
const EXPOSURE: f32 = 1.4;
const OCTAVE_C: mat2x2<f32> = mat2x2<f32>(1.4, 1.2, -1.2, 1.4);

struct Commons {
    sun: vec3<f32>,
    ambient: vec3<f32>,
    ext_shadow: f32,
    cloud_coverage: f32,
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn luminance(c: vec3<f32>) -> f32 {
    return luma(c);
}

fn bad_weather() -> f32 {
    return max(frame.rain, frame.thunder);
}

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn to_display(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn in_overworld() -> bool {
    return frame.dimension == 0;
}

// calcCommons: the sun and ambient colours, blended by the time of day (Wisdom's
// worldTime and Horizon's day_time share their origin: 0 is sunrise).
fn commons() -> Commons {
    let t = fract(frame.day_time) * 24000.0;
    let sunrise = (clamp(t, 23000.0, 24000.0) - 23000.0) / 1000.0 + (1.0 - clamp(t, 0.0, 2000.0) / 2000.0);
    let noon = clamp(t, 0.0, 2000.0) / 2000.0 - (clamp(t, 10000.0, 12000.0) - 10000.0) / 2000.0;
    let sunset = (clamp(t, 10000.0, 12000.0) - 10000.0) / 2000.0 - (clamp(t, 12500.0, 12750.0) - 12500.0) / 250.0;
    let midnight = (clamp(t, 12500.0, 12750.0) - 12500.0) / 250.0 - (clamp(t, 23000.0, 24000.0) - 23000.0) / 1000.0;

    // Wisdom varies the coverage with the moon phase (0.1 to 0.4); its middle here.
    let coverage = mix(0.25, 0.7, max(frame.rain, frame.wetness));

    var sun = vec3<f32>(0.9243, 0.4, 0.0913) * 2.22 * sunrise
        + vec3<f32>(1.2311, 1.0, 0.8286) * 3.3 * noon
        + vec3<f32>(0.9943, 0.419, 0.0945) * 2.6 * sunset
        + vec3<f32>(0.34, 0.5, 0.6) * 0.2 * night_brightness * midnight;
    sun *= 1.0 - coverage;

    let ext = clamp((t - 12350.0) / 100.0, 0.0, 1.0) - clamp((t - 13050.0) / 100.0, 0.0, 1.0)
        + clamp((t - 22800.0) / 200.0, 0.0, 1.0) - clamp((t - 23400.0) / 200.0, 0.0, 1.0);

    var ambient = vec3<f32>(0.543, 0.772, 0.786) * 0.27 * sunrise
        + vec3<f32>(0.686, 0.702, 0.73) * 0.34 * noon
        + vec3<f32>(0.543, 0.772, 0.747) * 0.26 * sunset
        + vec3<f32>(0.06, 0.088, 0.117) * 0.1 * night_brightness * midnight;

    // The Nether and the End have no sun; a flat light of their own colour instead.
    if frame.dimension == -1 {
        sun = vec3<f32>(0.0);
        ambient = vec3<f32>(0.32, 0.17, 0.11);
    } else if frame.dimension == 1 {
        sun = vec3<f32>(0.0);
        ambient = vec3<f32>(0.20, 0.17, 0.28);
    }
    return Commons(sun, ambient, clamp(ext, 0.0, 1.0), coverage);
}

// Wisdom's noise: smooth value noise in -1..1.
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.2031);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(-2.0) * f + 3.0);
    return 2.0 * mix(
        mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y) - 1.0;
}

// animationOffset: a velocity integrated around an hour-long circle, so motion stays
// continuous when the time wraps (Horizon's frame.time wraps every hour too).
fn animation_offset(velocity: vec2<f32>) -> vec2<f32> {
    let period = 3600.0;
    let phase = frame.time * (TAU / period);
    let radius = period / TAU;
    let s = sin(phase);
    let c = cos(phase);
    return radius * vec2<f32>(velocity.x * s + velocity.y * (c - 1.0), velocity.x * (1.0 - c) + velocity.y * s);
}

fn mist_color(c: Commons) -> vec3<f32> {
    return (vec3<f32>(0.6) + SKY_RGB * 0.5) * (luma(c.sun) * 0.1);
}

// calc_atmosphere: the sky's colour toward `v` (unit), at the point `sphere` (HDR, linear).
fn calc_atmosphere(sphere: vec3<f32>, v: vec3<f32>, c: Commons) -> vec3<f32> {
    let h = pow(max(normalize(sphere).y, 0.0), 2.0);
    var at = SKY_RGB;
    at = mix(at, vec3<f32>(0.7), max(0.0, c.cloud_coverage));
    at *= 1.0 - (0.5 - frame.rain * 0.3) * h;

    let h2 = pow(max(0.0, 1.0 - h * 1.4), 2.0);
    at += h2 * mist_color(c) * clamp(length(sphere) / 512.0, 0.0, 1.0) * 3.5;

    let vds = max(dot(v, frame.light_direction), 0.0) * (1.0 - c.ext_shadow);
    let k = max(frame.light_direction.y * 2.0 + 1.0, 0.01);
    at = mix(at, c.sun + c.ambient, smoothstep(0.1, 1.0, h2 * pow(vds, k)));
    // Wisdom's multiplier is 0 at night, which turns the sky and the fog black once rain
    // hides the stars: keep a dim moonlit floor (Horizon port change).
    at *= max(0.008 * night_brightness, luma(c.ambient) * 1.2 - 0.02);

    at += c.sun * 0.009 * vds * (0.7 + c.cloud_coverage);
    at += c.sun * 0.015 * pow(vds, 8.0) * (0.7 + c.cloud_coverage);
    at += c.sun * 0.22 * pow(vds, 30.0) * (0.7 + c.cloud_coverage);
    at += SKY_RGB * 0.003;
    return at;
}

// calc_clouds: Wisdom's flat cloud layer (rgb its colour, a its cover).
fn calc_clouds(sphere: vec3<f32>, cam: vec3<f32>, dot_s: f32, c: Commons) -> vec4<f32> {
    if sphere.y < 0.0 {
        return vec4<f32>(0.0);
    }
    var p = sphere / max(sphere.y, 0.001) * 768.0;
    p += noise((p.xz + cam.xz) * 0.001 + animation_offset(vec2<f32>(0.0025))) * 200.0 / sphere.y;
    var uv = p.xz + cam.xz;
    uv += animation_offset(vec2<f32>(2.5, 0.0));
    uv *= 0.002;
    uv.y *= 0.75;
    var n = noise(uv * vec2<f32>(0.5, 1.0)) * 0.5;
    uv += vec2<f32>(n * 0.5, 0.3) * OCTAVE_C;
    uv *= 3.0;
    n += noise(uv) * 0.25;
    uv += vec2<f32>(n * 0.9, 0.2) * OCTAVE_C + animation_offset(vec2<f32>(0.025, 0.0)) + vec2<f32>(0.0, 0.2);
    uv *= 3.01;
    n += noise(uv) * 0.105;
    uv += vec2<f32>(n * 0.4, 0.1) * OCTAVE_C + animation_offset(vec2<f32>(0.0075, 0.0)) + vec2<f32>(0.0, 0.1);
    uv *= 3.02;
    n += noise(uv) * 0.0625;
    n = smoothstep(0.0, 1.0, n + c.cloud_coverage);
    n *= smoothstep(0.0, 140.0, sphere.y);
    let col = mist_color(c) + pow(dot_s, 3.0) * (1.0 - n) * c.sun * 0.3 * (1.0 - c.ext_shadow);
    return vec4<f32>(col, 0.5 * n);
}

// get_exposure (without the scene-average term): brighter in the dark, dimmer in the sun.
fn get_exposure(c: Commons) -> f32 {
    let eye = pow(frame.eye_light_smooth.y, 6.0) * luma(c.sun);
    return EXPOSURE * (1.8 - clamp(eye, 0.0, 1.2)) * exposure_mul;
}

fn agx_lut_sample(coord: vec3<f32>) -> vec3<f32> {
    let size = 33.0;
    let dims = vec2<f32>(1089.0, 33.0);
    let pos = clamp(coord, vec3<f32>(0.0), vec3<f32>(1.0)) * (size - 1.0);
    let b0 = floor(pos.b);
    let b1 = min(b0 + 1.0, size - 1.0);
    let uv0 = (vec2<f32>(b0 * size + pos.r, pos.g) + 0.5) / dims;
    let uv1 = (vec2<f32>(b1 * size + pos.r, pos.g) + 0.5) / dims;
    let a = textureSampleLevel(agx_lut, agx_lut_sampler, uv0, 0.0).rgb;
    let b = textureSampleLevel(agx_lut, agx_lut_sampler, uv1, 0.0).rgb;
    return mix(a, b, fract(pos.b));
}

// tonemap: HDR linear in, display out. AgX (Wisdom's default) or the ACES fit.
fn tonemap(hdr: vec3<f32>) -> vec3<f32> {
    if agx_tonemap {
        let to_2020 = mat3x3<f32>(
            vec3<f32>(0.6274, 0.0691, 0.0164),
            vec3<f32>(0.3293, 0.9195, 0.0880),
            vec3<f32>(0.0433, 0.0113, 0.8956));
        let inset = mat3x3<f32>(
            vec3<f32>(0.856627153315983, 0.137318972929847, 0.111898212999950),
            vec3<f32>(0.095121240538159, 0.761241990602591, 0.076799418603190),
            vec3<f32>(0.048251606145858, 0.101439036467562, 0.811302368396859));
        let min_ev = -12.4739311883324;
        let max_ev = 4.02606881166759;
        var c = to_2020 * hdr;
        c = inset * max(c, vec3<f32>(0.0));
        c = clamp((log2(max(c, vec3<f32>(1e-10))) - min_ev) / (max_ev - min_ev), vec3<f32>(0.0), vec3<f32>(1.0));
        return agx_lut_sample(c);
    }
    let a = 2.51;
    let b = 0.03;
    let cc = 2.43;
    let d = 0.59;
    let e = 0.14;
    let c = clamp((hdr * (a * hdr + b)) / (hdr * (cc * hdr + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
    return pow(c, vec3<f32>(0.7 / 2.2));
}

// A per-pixel jitter (stands in for Wisdom's bayer_4x4).
fn pixel_noise(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
}

// The sky along `dir`, as calc_sky_with_sun draws it (without the sun disk), HDR.
fn sky_color(dir: vec3<f32>, c: Commons, with_clouds: bool) -> vec3<f32> {
    let sphere = dir * 512.0 + vec3<f32>(0.0, frame.camera_position.y, 0.0);
    var sky = calc_atmosphere(sphere, dir, c);
    if with_clouds {
        let clouds = calc_clouds(dir * 512.0, frame.camera_position, max(dot(dir, frame.light_direction), 0.0), c);
        sky = mix(sky, clouds.rgb, clouds.a);
    }
    return sky;
}
