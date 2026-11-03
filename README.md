# Wisdom Shaders V3 — Horizon port

An unofficial port of **Wisdom Shaders V3 (Build 3300)** by bobcao3
(https://github.com/bobcao3/Wisdom-Shaders) to the [Horizon](https://playhorizon.dev) client's
own shader API (WGSL, schema 1, API 0.1). Licensed under the Apache License 2.0, like the original.

- `wisdom_horizon/`: the full pack (registry id `wisdom_horizon`).
- `wisdom_horizon_lite/`: Wisdom's LITE profile (registry id `wisdom_horizon_lite`).

Each folder is a pack as Horizon reads it. Zip its contents (`horizon-shaders.toml` at the
root) as a `.hshader`, or drop the folder into `shaderpacks/`. Each folder's README lists what
was ported and what changed from the original.
