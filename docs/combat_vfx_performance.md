# Combat VFX performance follow-up

The current projectile trails, procedural muzzle smoke, wall-impact dust,
splinters, and blood effects are deliberately CPU-simulated shared-world
effects. Each local camera then independently projects, visibility-tests, and
draws the active effects.

This preserves split-screen consistency and wall occlusion, but sustained
gunfights may create a measurable frame-time cost. The densest emitter is the
projectile trail: at its current 0.05-cell spacing, a shot can emit up to 120
trail particles per second before per-camera rendering work.

Before changing visual density or moving effects to GPU particles, profile a
quiet scene and sustained one-, two-, and four-player gunfights. Record CPU
frame time, render time, active effect counts, and the existing coordinate
runtime CSV. Use those results to choose the first optimization target; likely
candidates are trail emission/visibility batching, then muzzle-smoke cards.
