# Wisdom Shaders V3 — Horizon port

An unofficial port of **Wisdom Shaders V3 (Build 3300)** by bobcao3
(https://github.com/bobcao3/Wisdom-Shaders) to the Horizon client's own shader API
(schema 1, API 0.1). Wisdom Shaders is licensed under the Apache License 2.0
(LICENSE.txt); so is this port. Not an official Wisdom Shaders release.

Ported to Horizon by tomasmendes01 (in-game name: **iLoong**).

## What was ported (translated from GLSL to WGSL)

- `calcCommons`: the sunrise / noon / sunset / midnight sun and ambient colours, the
  transition shadow fade and the cloud coverage.
- `Lighting.glsl.frag`: the lightmap falloff and simulated GI, Oren-Nayar diffuse, GGX
  specular with Schlick-roughness Fresnel, the subsurface term for plants, and the
  jittered 3x3 shadow kernel.
- `Atomosphere.glsl.frag`: `calc_atmosphere`, `calc_clouds` (2D clouds), the sun and
  moon discs, and the height fog of composite3.
- `Utilities.glsl.frag`: the exposure curve and the AgX tonemap with its LUT (and the
  ACES fallback).
- Waving foliage, bloom and the vignette.

## What changed

- Horizon has no deferred G-buffers: the lighting runs per surface in the material
  stage, and the fog and sky are drawn there and in the sky stage.
- Shadows use Horizon's shadow map and comparison sampler (PCF) instead of Wisdom's
  variance shadow maps; water and stained glass tint the light through
  `shadow_color`.
- Vanilla's face shading is taken out of the vertex colour (Wisdom runs with
  `oldLighting=false`).
- The cloud coverage uses its average instead of following the moon phase; the
  exposure has no scene-average term; there is no SSAO, SSR, volumetric clouds,
  god rays, caustics or TAA (Horizon can't do TAA; FXAA instead).
- Water: refraction, depth colour, mirror reflections and a sun glint, written for
  Horizon's translucent pass.
- At the render-distance edge the terrain fades into the sky, and vanilla's fog is
  kept under water, in lava, while blind and outside the Overworld.

The **Lite** pack follows Wisdom's LITE profile: a smaller shadow map, single-tap
shadows, no cloud shadows, no water mirror, no bloom and no FXAA.

## Changes since 1.1.0

- Night: the sky and fog no longer turn black when rain hides the stars, rain streaks stay faint
  in the dark, and a "Night brightness" option raises the moonlight and night ambient light
  (3x Wisdom's by default).
- Rain: lighter fog in the rain ("Rain fog", 0.5 by default; 1 is Wisdom's), the water gets the
  same fog as the land, and the sun's glint on water fades under rain clouds.
- Water: its top stays flat (the waves are in the normals, as in Wisdom), and the mirror Horizon
  draws with vanilla's light is brought to this pack's light.
- Mobs, items, chests and particles: Horizon draws them with vanilla's light, so a post pass
  relights them by how this pack's light compares with vanilla's on the terrain in view, eased
  over time ("Light mobs and chests", with a diagnostic view). Water is told apart by a mark in
  its colour's low bits and by its flat top.
- Held light sources light the terrain when Horizon's Dynamic lights extra is on, coloured by the
  manifest's [[lights]].
- Glowing blocks show their own colour instead of burning out to white at night ("Glowing
  blocks"), with extra bloom around them in the full pack ("Glow bloom").
- The far edge of the loaded terrain blends into the sky ("Horizon haze"), which hides the band a
  server's shorter view distance leaves.

