# Combat VFX performance follow-up

The current projectile trails, procedural muzzle smoke, wall-impact dust,
splinters, and blood effects are deliberately CPU-simulated shared-world
effects. Each local camera then independently projects, visibility-tests, and
draws the active effects.

This preserves split-screen consistency and wall occlusion, but sustained
gunfights may create a measurable frame-time cost. The previous stationary
projectile trail was the densest emitter; it has now been replaced by a short
attached tracer, leaving wall splinters and muzzle-smoke cards as the main
configurable VFX costs.

Before changing visual density or moving effects to GPU particles, profile a
quiet scene and sustained one-, two-, and four-player gunfights. The existing
coordinate runtime CSV automatically records per-viewport render CPU/GPU time,
shared frame-setup CPU time, and average live counts for projectiles, trails,
muzzle smoke, wall dust, debris, and blood. Use those results to choose the
first optimization target; likely candidates are trail emission/visibility
batching, then muzzle-smoke cards. The editor Profiler remains the tool for a
call-stack breakdown, but it does not export into this runtime CSV.

The CSV also records per-view CPU render-pass timings for muzzle smoke, the
combined projectile effect, its stationary grey trail smoke, its moving
red/orange/yellow head and tail pixels, wall dust, blood, and debris. The
`avg_vfx_trail_smoke_ms` and `avg_vfx_projectile_hot_ms` columns make a
firing-past test actionable without conflating the two projectile paths.

## October 2026 optimization pass

The long-lived projectile smoke-particle trail was replaced with a short,
attached Xiaolin-Wu-rasterized tracer. It has a one-pixel head and
coverage-weighted tail, so shots no longer create a growing stationary-particle
list. The runtime CSV records it under `avg_vfx_projectile_hot_ms`; while this
attached tracer is active, `avg_vfx_trail_smoke_ms` should remain zero.

CPU-projected muzzle smoke, wall dust, and splinters retain shared world
simulation for split-screen consistency. Their expensive per-camera projection,
visibility, material, and sprite updates are cached until each deliberately
stepped visible frame changes. Wall-splinter color sampling is also cached per
impact and viewport.

Wall splinters now use closest-joined-player distance LOD. The controls live
together at the top of `xybots_character_controller.gd`:

- `WALL_DEBRIS_LOD_DISTANCE_CELLS`
- `WALL_DEBRIS_NEAR_COUNT_MIN/MAX` and `WALL_DEBRIS_FAR_COUNT_MIN/MAX`
- `WALL_DEBRIS_NEAR_BOUNCE_COUNT_MIN/MAX` and `WALL_DEBRIS_FAR_BOUNCE_COUNT_MIN/MAX`
- `WALL_DEBRIS_NEAR_VISUAL_FPS` and `WALL_DEBRIS_FAR_VISUAL_FPS`
- `WALL_DEBRIS_NEAR_GROUND_FADE_SECONDS` and `WALL_DEBRIS_FAR_GROUND_FADE_SECONDS`
- `WALL_DEBRIS_AWAY_SPEED_MIN/MAX`

By default, impacts farther than three cells from every joined player spawn
only two to four chunks, skip bounce motion, update at 8 FPS, and disappear
when they settle. Close impacts spawn eight to ten chunks, retain one bounce,
update at 14 FPS, and linger briefly after landing.

Muzzle smoke exposes `MUZZLE_SMOKE_PARTICLE_COUNT`, lifetime, card variant,
and `MUZZLE_SMOKE_CARD_SCALE_MIN/MAX` controls beside its other constants. In
the most recent two-player firing capture, roughly 22.5 live puffs cost about
1.0 ms per viewing camera on average (2.07 ms peak). The attached projectile
tracer averaged about 0.41 ms, while wall splinters remained the largest
configurable VFX pass at about 2.06 ms average (3.66 ms peak), making their
LOD the next targeted safeguard.
