import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, join, relative, resolve } from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const defaultCaptureRoot = resolve(projectRoot, "../../mame-src/snap/xybots_capture/wall_turn_recordings");
const defaultOutRoot = resolve(projectRoot, "analysis/wall_reconstruction/turn_recordings");
const captureRoot = resolve(process.argv[2] ?? defaultCaptureRoot);
const outRoot = resolve(process.argv[3] ?? defaultOutRoot);
const maxKeyframes = Number(process.argv[4] ?? 80);

function ensureDir(path) {
  mkdirSync(path, { recursive: true });
}

function hashText(text) {
  return createHash("sha1").update(text).digest("hex");
}

function frameNumberFromName(name) {
  const match = name.match(/frame_(\d+)_mame_(\d+)/);
  return {
    captureFrame: match ? Number(match[1]) : 0,
    mameFrame: match ? Number(match[2]) : 0,
  };
}

function visibleTileSignature(metadata) {
  const width = metadata.screen.width;
  const height = metadata.screen.height;
  const visible = metadata.tiles
    .filter((tile) => tile.screen_x >= 0 && tile.screen_x < width && tile.screen_y >= 0 && tile.screen_y < height)
    .sort((a, b) => (a.screen_y - b.screen_y) || (a.screen_x - b.screen_x));

  return {
    text: visible.map((tile) => `${tile.screen_x},${tile.screen_y},${tile.raw},${tile.code},${tile.color},${tile.flag}`).join("|"),
    tiles: visible,
  };
}

function diffTiles(prevTiles, nextTiles) {
  const count = Math.min(prevTiles.length, nextTiles.length);
  const rows = new Map();
  let changed = 0;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;

  for (let i = 0; i < count; i++) {
    const prev = prevTiles[i];
    const next = nextTiles[i];
    if (prev.raw === next.raw && prev.code === next.code && prev.color === next.color && prev.flag === next.flag)
      continue;

    changed++;
    minX = Math.min(minX, next.screen_x);
    minY = Math.min(minY, next.screen_y);
    maxX = Math.max(maxX, next.screen_x + 7);
    maxY = Math.max(maxY, next.screen_y + 7);
    const row = Math.floor(next.screen_y / 8);
    rows.set(row, (rows.get(row) ?? 0) + 1);
  }

  return {
    changed,
    bounds: changed ? { minX, minY, maxX, maxY } : null,
    rows: Array.from(rows.entries()).sort((a, b) => a[0] - b[0]),
  };
}

function csvEscape(value) {
  const text = String(value ?? "");
  if (!/[",\n]/.test(text))
    return text;
  return `"${text.replaceAll('"', '""')}"`;
}

function writeCsv(path, rows) {
  if (!rows.length) {
    writeFileSync(path, "");
    return;
  }
  const headers = Object.keys(rows[0]);
  const lines = [headers.join(",")];
  for (const row of rows)
    lines.push(headers.map((header) => csvEscape(row[header])).join(","));
  writeFileSync(path, `${lines.join("\n")}\n`);
}

function selectEvenly(items, limit) {
  if (items.length <= limit)
    return items;
  const selected = [];
  for (let i = 0; i < limit; i++) {
    const index = Math.round((i * (items.length - 1)) / (limit - 1));
    selected.push(items[index]);
  }
  return selected;
}

function makeContactSheet(outDir, count, outputName = "contact_sheet.png", cropFilter = null) {
  if (!count)
		return false;
	const rows = Math.ceil(count / 5);
	const filters = [];
	if (cropFilter)
		filters.push(cropFilter);
	filters.push(`tile=5x${rows}:padding=8:margin=8:color=white`);
	try {
		execFileSync("ffmpeg", [
			"-y",
      "-hide_banner",
      "-loglevel",
      "error",
      "-framerate",
      "1",
			"-i",
			join(outDir, "keyframes/key_%04d.png"),
			"-vf",
			filters.join(","),
			join(outDir, outputName),
		], { stdio: "inherit" });
		return true;
	} catch {
    return false;
  }
}

function analyzeSession(sessionDir) {
  const sessionName = basename(sessionDir);
  const playfieldDir = join(sessionDir, "playfield");
  const tilesDir = join(sessionDir, "tiles");
  const pngs = existsSync(playfieldDir)
    ? readdirSync(playfieldDir).filter((name) => name.endsWith(".png")).sort()
    : [];

  const frames = [];
  for (const pngName of pngs) {
    const jsonName = pngName.replace(/\.png$/i, ".json");
    const jsonPath = join(tilesDir, jsonName);
    if (!existsSync(jsonPath))
      continue;

    const metadata = JSON.parse(readFileSync(jsonPath, "utf8"));
    const signature = visibleTileSignature(metadata);
    const tileHash = hashText(signature.text);
    const pngPath = join(playfieldDir, pngName);
    const pngHash = createHash("sha1").update(readFileSync(pngPath)).digest("hex");
    frames.push({
      ...frameNumberFromName(pngName),
      pngName,
      pngPath,
      jsonPath,
      pngHash,
      tileHash,
      tiles: signature.tiles,
    });
  }

  const outDir = join(outRoot, sessionName);
  const keyframeDir = join(outDir, "keyframes");
  rmSync(outDir, { recursive: true, force: true });
  ensureDir(keyframeDir);

  const keyframes = [];
  let prevHash = "";
  for (const frame of frames) {
    if (frame.tileHash !== prevHash) {
      keyframes.push(frame);
      prevHash = frame.tileHash;
    }
  }

  const changeRows = [];
  for (let i = 1; i < keyframes.length; i++) {
    const diff = diffTiles(keyframes[i - 1].tiles, keyframes[i].tiles);
    changeRows.push({
      from_capture_frame: keyframes[i - 1].captureFrame,
      to_capture_frame: keyframes[i].captureFrame,
      from_mame_frame: keyframes[i - 1].mameFrame,
      to_mame_frame: keyframes[i].mameFrame,
      changed_tiles: diff.changed,
      bounds: diff.bounds ? `${diff.bounds.minX},${diff.bounds.minY}-${diff.bounds.maxX},${diff.bounds.maxY}` : "",
      rows: diff.rows.map(([row, count]) => `${row}:${count}`).join(" "),
      image: `keyframes/${keyframes[i].pngName}`,
    });
  }

  const selected = selectEvenly(keyframes, maxKeyframes);
  const keyframeRows = selected.map((frame, index) => {
    const outputName = `key_${String(index + 1).padStart(4, "0")}.png`;
    copyFileSync(frame.pngPath, join(keyframeDir, outputName));
    return {
      key_index: index + 1,
      capture_frame: frame.captureFrame,
      mame_frame: frame.mameFrame,
      source_png: relative(projectRoot, frame.pngPath),
      review_png: `keyframes/${outputName}`,
      tile_hash: frame.tileHash,
      png_hash: frame.pngHash,
    };
  });

	writeCsv(join(outDir, "selected_keyframes.csv"), keyframeRows);
	writeCsv(join(outDir, "keyframe_changes.csv"), changeRows);
	const contactMade = makeContactSheet(outDir, selected.length);
	const corridorContactMade = makeContactSheet(outDir, selected.length, "contact_sheet_corridor.png", "crop=336:144:0:96");

  const uniqueTileHashes = new Set(frames.map((frame) => frame.tileHash));
  const uniquePngHashes = new Set(frames.map((frame) => frame.pngHash));
	const summary = {
		session: sessionName,
		raw_frames: frames.length,
    unique_visible_tile_states: uniqueTileHashes.size,
    unique_pngs: uniquePngHashes.size,
    consecutive_keyframes: keyframes.length,
		selected_keyframes: selected.length,
		contact_sheet: contactMade ? "contact_sheet.png" : "",
		corridor_contact_sheet: corridorContactMade ? "contact_sheet_corridor.png" : "",
		first_mame_frame: frames[0]?.mameFrame ?? "",
		last_mame_frame: frames.at(-1)?.mameFrame ?? "",
	};

  const readme = [
    `# ${sessionName}`,
    "",
    `Raw frames: ${summary.raw_frames}`,
    `Unique visible tile states: ${summary.unique_visible_tile_states}`,
    `Consecutive keyframes: ${summary.consecutive_keyframes}`,
    `Selected review keyframes: ${summary.selected_keyframes}`,
    "",
	    "Files:",
	    "- `contact_sheet.png` - sampled visible playfield states from this recording.",
	    "- `contact_sheet_corridor.png` - same samples cropped to the lower corridor/wall area.",
	    "- `selected_keyframes.csv` - sampled keyframe sources and hashes.",
    "- `keyframe_changes.csv` - tile changes between consecutive unique states.",
    "- `keyframes/` - copied review PNGs.",
    "",
    "Raw source frames remain under the MAME `snap/xybots_capture/wall_turn_recordings` folder.",
    "",
  ].join("\n");
  writeFileSync(join(outDir, "README.md"), readme);

  return summary;
}

if (!existsSync(captureRoot))
  throw new Error(`Capture root not found: ${captureRoot}`);

ensureDir(outRoot);
const sessions = readdirSync(captureRoot)
  .filter((name) => /^session_\d+$/.test(name))
  .sort()
  .map((name) => join(captureRoot, name));

const summaries = sessions.map(analyzeSession);
writeCsv(join(outRoot, "wall_turn_recording_sessions.csv"), summaries);

const markdown = [
  "# Wall Turn Recording Analysis",
  "",
  `Capture root: \`${captureRoot}\``,
  `Generated sessions: ${summaries.length}`,
  "",
	"| Session | Raw Frames | Unique Tile States | Keyframes | Selected | Contact Sheet |",
	"|---|---:|---:|---:|---:|---|",
	...summaries.map((summary) => `| ${summary.session} | ${summary.raw_frames} | ${summary.unique_visible_tile_states} | ${summary.consecutive_keyframes} | ${summary.selected_keyframes} | ${summary.corridor_contact_sheet ? `${summary.session}/${summary.corridor_contact_sheet}` : ""} |`),
  "",
  "Interpretation:",
  "- These recordings are playfield-only captures: sprites and HUD alpha are excluded.",
  "- `unique_visible_tile_states` changes when the visible playfield tilemap changes.",
  "- For turn reconstruction, start with the contact sheets, then inspect each session's `keyframe_changes.csv` to see which tile rows/regions changed.",
  "- Raw frame-by-frame data is intentionally left in MAME's `snap` folder to avoid bloating the Godot repo.",
  "",
].join("\n");
writeFileSync(join(outRoot, "wall_turn_recording_analysis.md"), markdown);

console.log(`Wrote ${summaries.length} session analyses to ${outRoot}`);
