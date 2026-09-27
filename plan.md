I want to inspect the graphics construction of the 1987 Atari arcade game Xybots using MAME.

My purpose is technical research and education. I am developing an unrelated cowboy game, not a space game, and I do not want to copy or redistribute Xybots artwork. I specifically want to understand how its graphics are structured and assembled: tiles, sprites, palettes, tilemaps, sprite stacking, distance representations, perspective maze construction, and the turning effect.

I have never used an emulator before, so be extremely careful, explicit, and beginner-friendly.

## Overall goal

Help me create a local Xybots graphics-inspection workspace on Windows that:

1. Installs or configures an official current version of MAME.
2. Uses only a Xybots ROM set that I provide myself.
3. Verifies that the ROM set is valid before trying to run anything.
4. Launches Xybots correctly.
5. Gives me a simple way to open and use MAME's built-in graphics viewer.
6. Helps me inspect:

   * palettes
   * decoded graphics sets
   * playfield tiles
   * sprites / motion objects
   * character / UI tiles
   * tilemaps
7. Creates organized folders for screenshots and research notes.
8. Documents exactly what I should look for while inspecting the graphics.
9. Only after the visual inspection stage is working, investigates safe ways to export or reconstruct decoded graphics for study.
10. Never downloads, searches for, or provides copyrighted ROM files.

Do not skip directly to asset ripping. The first priority is understanding how the graphics are assembled.

---

# Current Plan: Xybots Maze Renderer Reverse Engineering for Godot

Status: active. User approved this plan; execute without using MAME focus unless explicitly warned/confirmed first.

Important user workflow rule:

- Before any step that needs the MAME window focused, warn the user and pause so they can wrap up what they are doing.
- Do not take keyboard focus unexpectedly.
- Do not drive MAME inputs until the user confirms it is okay to focus the MAME window.

## Objective

Reverse-engineer Xybots enough to describe a Godot-ready rendering model for an original game:

```text
grid/player state
-> visible corridor pieces
-> ordered playfield/sprite composition
-> forward and turn transition animation rules
```

The goal is not to copy Xybots artwork or make a byte-perfect ROM editor. The goal is an evidence-based behavioral spec for how a similar perspective maze system can be built with original assets.

## Reference Models Already Studied

Reference screenshots and images are stored in:

```text
D:\Godot\xybotsResearch\analysis\first_person_dungeon_video_refs
```

Lessons to preserve:

- First-person dungeon renderers can use a top-down grid as source of truth.
- A view can be resolved through fixed visibility slots rather than continuous 3D geometry.
- Direction-relative lookup tables map `player_position + facing + slot` to a map cell.
- A render list is built from visible slots.
- Draw order is far-to-near.
- Pixel-art renderers can preauthor slot-specific wall/floor pieces instead of transforming generic geometry at runtime.
- Heroine Dusk is a useful simpler model: 12 visible positions, explicit visibility cone, and far-to-near draw order.

## Xybots Differences To Keep In Mind

Xybots should not be treated as a direct clone of the reference dungeon renderers:

- Xybots is pixel art, not vector graphics.
- Xybots is third-person, so player, enemies, pickups, and projectiles must register to the same pseudo-3D corridor system.
- Turning is animated, for example turning from north to west.
- Forward movement has a small in-between visual frame.
- Side-to-side movement appears not to use the same in-between treatment as forward movement.
- Xybots' perspective/camera appears slightly higher than the reference first-person dungeon examples.

## Existing Data

Use existing captures before recording more:

- `D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\wall_turn_recordings\session_0008` through `session_0017` have matched playfield PNG and tile JSON counts.
- `session_0016` has 749 matched frames and is likely useful for a first pass.
- Earlier sessions may still be useful but contain old naming/count issues from the previous `_mame_####` output convention.
- Live motion-object capture CSVs exist in `D:\Godot\xybotsResearch\exports\live_mob_capture`.

Do not assume more capture is needed until the existing sessions have been classified.

## Milestones

### Milestone 1: Inventory and classify existing captures

Actions:

- Summarize each wall-turn session: frame count, JSON count, naming format, duration.
- Detect frames where playfield tile JSON changes.
- Group contiguous change ranges into likely actions.
- Identify candidate sequences for idle, forward movement, turning, and side movement.

Deliverable:

- Update `analysis\turning_research.md` with a session inventory and likely action labels.

Status:

- Complete for existing clean sessions `session_0008` through `session_0017`.
- Older sessions `session_0001`, `session_0002`, and `session_0005` were also sampled visually because they show more varied wall/corner states.

### Milestone 2: Determine forward movement method

Questions:

- Does the forward in-between frame use separate in-between tiles?
- Does tilemap RAM shift/scroll?
- Does the playfield redraw to an intermediate state?
- Are there scaling-like sprite effects, or is everything tile replacement?

Actions:

- Compare per-frame tile JSON around a likely forward step.
- Compare playfield PNG differences frame-by-frame.
- Track whether the same tile codes move, whether new tile codes appear, or whether screen positions shift.

Deliverable:

- A confirmed/likely/unknown explanation in `analysis\maze_construction.md` and `analysis\turning_research.md`.

Status:

- Strong evidence recorded in `analysis\maze_construction.md` and `analysis\turning_research.md`.
- Current conclusion: forward in-between movement is fixed-screen-cell playfield tile replacement using authored intermediate tile phases. Whole-image scaling and global scrolling are unlikely as the main mechanism.

### Milestone 3: Determine turn animation method

Questions:

- Does a turn use unique transition tiles?
- Does it redraw the tilemap each frame?
- Does it scroll or shift a larger playfield?
- Does it use sprite-like overlays or motion objects?

Actions:

- Analyze a clean left or right turn sequence from existing recordings.
- Compare tile code sets and screen positions frame-by-frame.
- Check whether turn frames can be represented as slot-specific transition art.

Deliverable:

- A frame analysis table in `analysis\turning_research.md`.

Status:

- Complete for the playfield layer.
- Controlled captures `session_0032` and `session_0033` confirm left/right turns use authored playfield tile phases in fixed screen-space cells.
- Left and right turns use the same major tile phases in opposite order.

### Milestone 4: Determine side movement behavior

Questions:

- Does side movement update instantly relative to forward movement?
- Does side movement have no in-between frame, fewer frames, or a different animation path?

Actions:

- Identify or capture a side movement sequence.
- Compare against forward movement tile changes.

Deliverable:

- A direct comparison: forward vs side movement.

Status:

- Complete for the playfield layer.
- Manual captures `session_0038` and `session_0039` confirm strafe movement uses a much smaller side-band tile update than forward/backward movement.
- Manual captures `session_0036` and `session_0037` confirm forward/backward use broad corridor/floor phase replacement, with backward using the broad phases in reverse order.

### Milestone 5: Map Xybots visible corridor slots

Questions:

- What is Xybots' equivalent of the visibility cone?
- How many corridor cells/depths are represented?
- Which screen regions correspond to wall faces, side walls, floor bands, doors, and openings?

Actions:

- Use stable frames from captures to mark repeated wall/floor tile groups.
- Build a tentative slot map analogous to the 21-slot and 12-slot reference systems.
- Separate playfield tiles from motion objects and UI.

Deliverable:

- A Godot-oriented slot diagram in markdown, with evidence references.

Status:

- Partially complete conceptually in `analysis\maze_construction.md`.
- Still needs a formal slot diagram after turn and side movement are classified.

### Milestone 6: Motion object registration

Questions:

- How are the player, enemies, pickups, and projectiles positioned relative to corridor depth?
- Are distance changes represented by alternate sprites, hardware scaling, position changes, or stacked sprite parts?

Actions:

- Correlate playfield frame numbers with existing live motion-object captures where possible.
- If existing data is insufficient, plan a clean capture later.

Deliverable:

- Notes in `analysis\sprite_structure.md` or a new Godot renderer spec section.

Status:

- Partially complete.
- Source confirms motion objects are separate from the playfield and priority-merged before alpha/HUD.
- Existing live capture confirms active runtime objects commonly use 4-tile and 8-tile heights with varied priorities.
- Exact actor identity and corridor-depth registration still need targeted analysis.

### Milestone 7: Controlled scripted captures only if needed

Only after analyzing existing sessions, record clean labeled sequences if gaps remain:

- `forward_one_tile_only`
- `turn_left_only`
- `turn_right_only`
- `strafe_left_only`
- `strafe_right_only`

Before any scripted capture:

- Warn the user that MAME window focus is required.
- Wait for explicit confirmation.
- Launch MAME with capture and cheats enabled.
- Send simple deterministic keyboard inputs.
- Stop recording and document the resulting session number immediately.

Deliverable:

- Short, labeled, clean sessions using the current Premiere-friendly naming convention.

### Milestone 8: Godot renderer spec

Final deliverable:

```text
Xybots-inspired maze renderer spec
```

It should include:

- grid state representation
- player cell and facing
- visible slot resolver
- draw order
- wall/floor/passage/door piece categories
- forward movement transition
- turn transition
- side movement behavior
- sprite/object depth registration
- confirmed facts vs hypotheses vs unknowns

## Stop Conditions

Pause and ask the user before:

- focusing or driving the MAME window
- recording new MAME sessions
- changing capture instrumentation
- making broad code changes to the MAME driver
- starting a Godot implementation

Do not begin reverse engineering until the user reads this plan and says to continue.

---

# Important safety and workflow rules

## Do not obtain ROM files

Do not:

* search the web for Xybots ROM downloads
* download Xybots ROMs
* suggest ROM piracy sites
* bundle ROM data into the project
* modify or redistribute the ROM data

Assume that I will provide a legally obtained file myself.

The expected filename will probably be:

```text
xybots.zip
```

The project should work around that user-provided file.

If the ROM is missing, tell me exactly where to place it and stop that part of the workflow gracefully.

---

## Use official MAME

Use the official current Windows x64 MAME release.

Before installing anything:

1. Check whether MAME is already installed.
2. Search likely locations such as:

   * `E:\MAME`
   * `C:\MAME`
   * the current project directory
3. Check whether `mame.exe` exists.
4. If MAME is already present, inspect its version.
5. Only propose downloading a new copy if needed.

Prefer:

```text
E:\MAME
```

as the installation folder.

Do not use:

* RetroArch
* MAME cores
* MAMEUI forks
* unofficial preconfigured ROM packages
* random emulator bundles

Use the official MAME build.

---

# Working style

I want you to actively inspect my system and build the tools, not merely give me a generic tutorial.

Before making changes:

1. Inspect the current directory.
2. Inspect whether MAME is already installed.
3. Inspect whether a research folder already exists.
4. Show me a concise summary of what you found.

Then proceed with the safest logical next step.

Do not delete or overwrite existing files without checking them first.

Prefer creating small readable scripts rather than asking me to repeatedly type long commands.

I use Windows.

PowerShell is preferred for system setup and launch scripts.

Python is fine for image processing or analysis tools.

Use clear comments throughout all scripts.

---

# Desired workspace

Create a research workspace similar to:

```text
E:\XybotsResearch\
│
├── README.md
│
├── NOTES.md
│
├── mame\
│   ├── launch_xybots.ps1
│   ├── verify_xybots.ps1
│   ├── open_mame_folder.ps1
│   └── controls.md
│
├── screenshots\
│   ├── palettes\
│   ├── tiles\
│   ├── sprites\
│   ├── chars\
│   ├── tilemaps\
│   └── gameplay\
│
├── analysis\
│   ├── graphics_inventory.md
│   ├── maze_construction.md
│   ├── sprite_structure.md
│   ├── palette_notes.md
│   └── turning_research.md
│
├── tools\
│
└── exports\
```

Do not put copyrighted ROM data inside the research workspace.

The ROM should remain in MAME's normal ROM directory.

For example:

```text
E:\MAME\roms\xybots.zip
```

---

# Phase 1: Verify MAME

Determine whether MAME is already installed.

If it is installed:

1. Find `mame.exe`.
2. Record the full path.
3. Run the appropriate version command.
4. Record the MAME version in `README.md`.
5. Verify that the executable works.

If MAME is not installed:

1. Identify the official current Windows x64 MAME release.
2. Tell me exactly what will be downloaded and from where.
3. Use only the official MAME project source.
4. Install or extract it to:

```text
E:\MAME
```

when possible.

Do not download anything from unofficial emulator mirrors.

---

# Phase 2: Create a ROM verification tool

Create:

```text
E:\XybotsResearch\mame\verify_xybots.ps1
```

The script should:

1. Find the MAME executable.
2. Check for:

```text
E:\MAME\roms\xybots.zip
```

3. Clearly report whether the ROM file exists.
4. If it exists, use MAME's audit/verification functionality to check the `xybots` set.
5. Capture the result in a readable log file.
6. Explain errors in plain English.

The script must not:

* unzip the ROM automatically
* modify the ROM
* download missing ROM files
* substitute random files

The output should clearly distinguish:

```text
MAME FOUND
ROM FILE FOUND
ROM AUDIT PASSED
```

from:

```text
MAME NOT FOUND
ROM FILE NOT FOUND
ROM AUDIT FAILED
```

If the audit fails, preserve the exact MAME error output for later analysis.

---

# Phase 3: Create a simple launcher

Create:

```text
E:\XybotsResearch\mame\launch_xybots.ps1
```

The script should:

1. Locate `mame.exe`.
2. Confirm `xybots.zip` exists.
3. Optionally run a quick audit first.
4. Launch:

```text
mame.exe xybots
```

using the correct working directory.
5. Print a short reminder before launch:

```text
Xybots research controls:

F4      Open graphics viewer
Enter   Cycle palette / graphics / tilemap views
[ ]     Change graphics set
Arrow keys / Page Up / Page Down   Navigate
Left / Right   Change palette
F12     Save screenshot
Esc     Exit MAME
```

Do not use complicated command-line options unless they are needed.

The ordinary MAME interface should remain available.

---

# Phase 4: Document MAME controls

Create:

```text
E:\XybotsResearch\mame\controls.md
```

Include beginner-friendly instructions for:

## Starting the game

Explain:

* how to run the launcher
* how to start from the MAME interface
* what to do if MAME says the ROM is missing
* what to do if the game fails its audit

## Basic gameplay controls

Include likely defaults such as:

```text
5       Insert coin
1       Start player 1
Esc     Exit
```

Make clear that Xybots used unusual arcade controls and that playing the game is secondary to graphics research.

## Graphics viewer

Explain carefully:

```text
F4
```

opens the internal viewer.

Explain how to cycle through:

```text
Palette
Graphics
Tilemap
```

Explain the navigation controls.

Do not assume I already know what terms such as tilemap, palette bank, graphics set, or sprite bank mean. Give each one a one-paragraph explanation.

---

# Phase 5: Prepare the screenshot workflow

Determine where MAME saves screenshots by default.

Verify the actual path rather than guessing.

Then create a system for moving or copying selected research screenshots into:

```text
E:\XybotsResearch\screenshots\
```

Do not move every screenshot automatically unless there is a reliable way to classify it.

At minimum, create folders for:

```text
palettes
tiles
sprites
chars
tilemaps
gameplay
```

Create a helper script such as:

```text
collect_latest_screenshot.ps1
```

The helper can:

1. Find the newest MAME screenshot.
2. Ask or accept a category.
3. Copy the screenshot into the corresponding research folder.
4. Preserve the original.
5. Give the copied file a timestamped filename.

For example:

```text
tiles_2026-07-05_001.png
sprites_2026-07-05_001.png
tilemap_2026-07-05_001.png
```

Never overwrite an earlier screenshot.

---

# Phase 6: Create the Xybots inspection guide

Create:

```text
E:\XybotsResearch\analysis\graphics_inventory.md
```

This should act as a field guide while I use the F4 graphics viewer.

We already have reason to expect three major decoded graphics categories:

```text
tiles
sprites
chars
```

The known structure is approximately:

```text
tiles      8x8, 4 bits per pixel
sprites    8x8, 4 bits per pixel
chars      8x8, 2 bits per pixel
```

Do not blindly assume the MAME viewer labels them with those exact names.

Instead, help me identify them by content.

For each graphics set, create sections for:

```text
Viewer set number:
Likely role:
First tile index:
Last tile index:
Useful palette numbers:
Visual patterns:
Likely in-game usage:
Questions:
Screenshots:
```

---

# Phase 7: Research the playfield tile graphics

The most important area is the main environment graphics.

While inspecting the tile graphics, specifically look for:

* wall faces
* diagonal wall edges
* perspective lines
* floor tiles
* ceiling pieces
* doors
* wall terminals
* repeated horizontal strips
* repeated vertical strips
* mirrored shapes
* near / medium / far versions of similar shapes
* turn-transition graphics
* corner pieces
* T-junction pieces
* intersections
* dead ends
* decorative overlays

The key research question is:

> Does Xybots store large finished perspective views, or does it assemble the viewport from many small reusable graphics tiles?

Assume the answer must come from evidence.

Do not invent a conclusion.

Record:

* tile numbers
* groups of adjacent tiles
* repeating sequences
* likely multi-tile assemblies
* screenshots showing the evidence

Look especially for groups where neighboring graphics combine into a larger shape.

For example:

```text
tile N
tile N+1
tile N+2
tile N+3
```

may be parts of a single larger visual structure.

Create notes about suspected groupings.

---

# Phase 8: Research sprite and motion-object structure

Inspect the sprite graphics carefully.

Look for:

* player character pieces
* robots
* projectiles
* doors
* pickups
* effects
* upper-body sections
* lower-body sections
* vertical strips
* repeated character views
* apparent distance levels
* alternate facing directions

The major questions are:

1. Are complete objects stored as single images?
2. Are large objects built from multiple 8x8 chunks?
3. Are chunks stacked vertically?
4. Are multiple nearby tile numbers pieces of the same object?
5. Are there explicit near, medium, and far versions?
6. Does apparent scaling come from hardware scaling, alternate graphics, tile stacking, or a combination?
7. How many directional views exist?
8. Are mirrored graphics stored separately or generated by hardware?

Create:

```text
E:\XybotsResearch\analysis\sprite_structure.md
```

Use tables where useful.

Suggested fields:

```text
Tile range
Suspected object
Width in tiles
Height in tiles
Direction
Distance level
Palette
Confidence
Evidence screenshot
Notes
```

Use confidence labels:

```text
Confirmed
Strong hypothesis
Weak hypothesis
Unknown
```

Never represent a hypothesis as fact.

---

# Phase 9: Research palette behavior

Create:

```text
E:\XybotsResearch\analysis\palette_notes.md
```

While viewing graphics, test multiple palette selections.

Record cases where:

* meaningless graphics suddenly become recognizable
* one graphics set clearly expects a certain palette range
* the same tile produces multiple visual roles with different palettes
* colors appear to be team, enemy, lighting, or environment variations

Explain that pixel indices and final displayed colors can be separate.

Record:

```text
Graphics set
Tile range
Useful palette
Observed result
Screenshot
```

---

# Phase 10: Research the live tilemap

Use MAME's tilemap viewer.

This is especially important.

Create:

```text
E:\XybotsResearch\analysis\maze_construction.md
```

Look for evidence of:

* the complete playfield map
* the first-person viewport
* offscreen areas
* hidden tiles
* repeated patterns
* map regions larger than the visible screen
* perspective wall assembly
* parts of the viewport built from multiple adjacent 8x8 tiles

The Xybots playfield is expected to use a tilemap roughly structured around:

```text
64 x 32 tiles
8 x 8 pixels per tile
```

Verify what MAME actually shows.

Do not assume the visible first-person maze is represented in the most obvious way.

The tilemap viewer may show:

* the logical map
* the visible playfield
* screen-oriented tile data
* intermediate rendering data

Document what is actually observed.

---

# Phase 11: Investigate the turning effect

Create:

```text
E:\XybotsResearch\analysis\turning_research.md
```

This is one of the most important parts of the project.

Xybots allows visible turning between maze directions.

I want to determine how that visual effect is built.

Research it using:

1. normal gameplay
2. frame advance if useful
3. screenshots
4. tilemap viewer
5. graphics viewer
6. source-code inspection
7. emulator debugger only if genuinely necessary

Do not jump straight into the debugger.

Start visually.

Capture the turning animation frame by frame if possible.

For every frame, investigate:

* which walls move
* which edges stretch
* whether the image is sliding
* whether graphics are being replaced
* whether different perspective tiles appear
* whether the turn uses discrete animation frames
* whether hardware scrolling is involved
* whether tilemap content changes
* whether sprites overlay the playfield
* whether the apparent rotation is actually a sequence of 2D transformations

Create a frame-analysis table:

```text
Frame
Camera orientation
Visible wall changes
Tile changes
Scrolling changes
Sprite changes
Hypothesis
Evidence
```

The final goal is to explain the turning illusion in a form that could be recreated with completely original cowboy-game artwork.

Do not copy Xybots graphics.

Extract the general rendering logic.

---

# Phase 12: Inspect the MAME Xybots driver source

Find the official MAME source code for the Xybots driver.

Use primary sources whenever possible.

Study the relevant implementation.

Look for:

* graphics layouts
* graphics decode definitions
* ROM regions
* playfield tilemap dimensions
* motion-object configuration
* sprite dimensions
* height fields
* flip flags
* tile code fields
* palette fields
* scrolling
* rendering order
* screen update logic

Create:

```text
E:\XybotsResearch\analysis\source_code_notes.md
```

For every important claim, include:

```text
Claim:
Source file:
Relevant function or structure:
Line or symbol:
What it means:
Confidence:
```

Separate:

```text
Directly confirmed by source
Inferred from source
Inferred from visual evidence
Unknown
```

Do not make things up.

---

# Phase 13: Optional decoded-graphics export

Do not begin this phase until:

* MAME runs successfully
* Xybots passes its audit
* the F4 graphics viewer works
* I have inspected at least the main graphics sets

Then investigate ways to export the decoded graphics for private study.

Preferred approaches, in order:

1. Existing official MAME functionality
2. MAME debugger commands
3. MAME Lua scripting
4. A small custom decoder based on the official graphics layout
5. External extraction tools only if their behavior is fully understood

The goal is to produce research images such as:

```text
tile_set_000.png
sprite_set_000.png
chars_set_000.png
```

or sprite sheets with:

* tile indices
* transparent backgrounds where appropriate
* configurable palette
* nearest-neighbor scaling
* no smoothing
* original pixel boundaries preserved

Do not redistribute the exported images.

Store any exported results only in:

```text
E:\XybotsResearch\exports
```

Create a clear note that these are copyrighted reference materials for private research.

---

# Phase 14: Build a sprite-sheet viewer if useful

Once decoded graphics can be exported, create a small local viewer if it would help.

A simple HTML, Python, or desktop tool is fine.

Desired features:

* open a sprite sheet
* zoom with nearest-neighbor rendering
* show tile grid
* show tile index under cursor
* choose tile width and height
* select a tile range
* change palette if the source format allows it
* mark groups of tiles
* add notes
* export a contact sheet for research

Do not overengineer this before the raw inspection workflow is useful.

---

# Final research goal

At the end, I want evidence-based answers to these questions:

1. How are Xybots maze walls stored?

2. How are the small graphics chunks assembled into the visible first-person maze?

3. Are walls represented by:

   * large pre-rendered images
   * 8x8 tiles
   * multiple tile layers
   * sprites
   * some combination?

4. How is the visible turning animation created?

5. What changes from frame to frame during a turn?

6. How are enemies and other objects constructed?

7. Are large sprites assembled from vertically stacked graphics?

8. Does the game use true sprite scaling hardware?

9. Does it use alternate graphics for different distances?

10. How does depth ordering work?

11. Which parts of the technique could be generalized into an original rendering system for a cowboy game?

The final explanation should clearly separate:

```text
Confirmed facts
Strong evidence
Reasonable hypotheses
Unknowns
```

---

# How to begin

Start now by:

1. Inspecting the current computer for MAME.
2. Checking:

   * `E:\MAME`
   * `C:\MAME`
   * the current working directory
3. Checking whether an `D:\Godot\xybotsResearch` workspace already exists.
4. Reporting what you find.
5. Creating the research workspace if safe.
6. Creating the first ROM verification and launcher scripts.
7. Do not attempt to locate or download a Xybots ROM.

Work incrementally.

After each meaningful stage:

* test what you created
* report the exact result
* update `README.md`
* preserve useful logs
* continue to the next stage when the previous one works

Be obsessive about evidence.

I care much more about understanding the technique correctly than reaching a quick conclusion.
