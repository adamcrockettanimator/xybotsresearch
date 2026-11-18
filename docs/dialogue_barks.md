# Enemy bark catalog

The editable catalog lists the approved Zach, Adam, Rowan and Devin recordings. The Google Sheet has one tab per actor. The checked-in `assets/Audio/Dialog/bark_catalog.csv` is the local copy used to build the game. Original WAV files in `Audio/Dialog/Dialog clips - review` are never edited by the catalog builder.

## Editing a recording

Each row represents one original recording. Add one or more tags separated by spaces, for example:

| actor | file | tags | weight | repeatable | min_enemies | max_enemies |
| --- | --- | --- | ---: | --- | ---: | ---: |
| zach | 0107 - dammit!.wav | `#hit #reload` | 0.5 | yes | | |

- `tags` describes the situations where the recording makes sense. An empty cell leaves a recording unassigned. `#hitReact`, `#reloading`, and `#postkill` are accepted aliases for `#hit`, `#reload`, and `#victory`.
- `weight` changes relative frequency: 1 is normal, 2 is twice the weight of an equally long line, 0.5 is half, and 0 disables the line. The game also favors short recordings, particularly during combat. Longer lines can still play.
- `repeatable` is `yes` for short exclamations that can recur during a round; use `no` for lines that shouldn't repeat. Non-repeatable lines use shared round history across the actors.
- `min_enemies` and `max_enemies` are optional. Blank preserves the original per-event rule when known; otherwise the builder applies safe group-language and flank/charge limits. Use `max_enemies` of 1 for a last-outlaw line. Do not use a group line with `min_enemies` of 1.
- `actor` and `file` identify the original recording; keep them unchanged. `duration_seconds` comes from the WAV and informs the length preference. `matching` describes the initial automatic match, not whether a clip is approved.
- Keep every row. To exclude a recording, clear its tags or set its weight to 0. The validator catches missing rows, missing files, invalid tags and invalid weights before replacing the game bank.

Supported tags: `#hearing`, `#shot`, `#ally_fall`, `#attacking`, `#reply_attack`, `#charge`, `#flank`, `#flee`, `#hiding`, `#hit`, `#hit_player`, `#investigate`, `#death`, `#victory`, `#lost_contact`, `#player_cover`, `#player_reload`, `#player_roll`, `#player_spotted`, `#combat`, `#first_sighting`, `#kill_player`, `#reload`, `#search`, `#cover`, and `#taunt`. `#player_spotted` is for seeing the player again after at least one second out of sight; `#first_sighting` is for the first sighting by that enemy. Use `#reply_attack` only for the scripted response to "Take that!". Use `#victory` for a line suitable near the dead player; `#taunt` is a combat taunt.

A tag makes a clip eligible; game events and priorities decide when to request it. A recording may have several tags. Some 384 approved recordings have no automatically inferred tag and remain silent until tagged; being unassigned is not a rejection of the take.

## Applying edits

You can edit the Google Sheet and ask Codex to apply it. For a manual workflow, download the sheet as an Excel workbook, then from the game project folder run:

```powershell
python tools/apply_bark_catalog.py --check --xlsx "C:\path\to\downloaded.xlsx"
python tools/apply_bark_catalog.py --xlsx "C:\path\to\downloaded.xlsx"
```

The first command only validates. The second saves a backup of the old local CSV, updates the CSV and game JSON, makes normalized game copies of newly tagged recordings, and updates the web export list. Godot needs to import any new assets; restart the running game to load changes. You can edit the local CSV directly instead and run the same commands without `--xlsx`.

The generated JSON is game-facing. For example, a multi-tagged clip appears in both event lists, with a record like:

```json
{
  "path": "res://assets/Audio/Dialog/Barks/zach/reaction_0107.wav",
  "id": "dammit",
  "source": "0107 - dammit!.wav",
  "weight": 0.5,
  "repeatable": true,
  "min_enemies": 1,
  "max_enemies": 999,
  "duration_seconds": 0.8
}
```

The real duration in the generated file comes from the catalog; this example illustrates the structure. WAV metadata can carry text in some tools, but Godot's import and the editing workflow do not reliably expose custom game tags from those chunks, so tags live outside the original WAVs.

## Reaction priorities

Hit and death reactions are immediate and can overlap another character. First sight and the killer's reaction are also mandatory, but wait if the same actor is already delivering a higher-priority hit or death. Tactical and combat callouts use a short, ranked queue; the event can expire if the situation changes. Initial hearing and investigation lines are suppressed once combat has begun. A last enemy's death has a gentler length penalty so a longer line can occasionally play.

On a clear-the-map loss, survivors approach the body without shooting and take turns using `#victory` lines near it. The scene stays visible until Start, X, or the touch Continue control skips directly into a fresh round.
