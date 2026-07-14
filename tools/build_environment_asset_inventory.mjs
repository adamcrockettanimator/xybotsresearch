import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const analysisRoot = join(projectRoot, "analysis", "wall_reconstruction");
const outPath = join(analysisRoot, "environment_art_asset_inventory.xlsx");
const scratch = join(projectRoot, ".tmp_environment_asset_inventory_xlsx");

function ensureDir(path) {
  mkdirSync(path, { recursive: true });
}

function xmlEscape(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const next = text[i + 1];
    if (quoted) {
      if (ch === '"' && next === '"') {
        cell += '"';
        i++;
      } else if (ch === '"') {
        quoted = false;
      } else {
        cell += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ",") {
      row.push(cell);
      cell = "";
    } else if (ch === "\n") {
      row.push(cell.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += ch;
    }
  }
  if (cell.length || row.length) {
    row.push(cell.replace(/\r$/, ""));
    rows.push(row);
  }
  const headers = rows.shift() ?? [];
  return rows.filter((r) => r.length && r.some((c) => c !== "")).map((r) => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? ""])));
}

function readCsv(path) {
  return existsSync(path) ? parseCsv(readFileSync(path, "utf8")) : [];
}

function countUnique(rows, key) {
  return new Set(rows.map((row) => row[key]).filter(Boolean)).size;
}

function cellRef(row, col) {
  let n = col + 1;
  let letters = "";
  while (n > 0) {
    const r = (n - 1) % 26;
    letters = String.fromCharCode(65 + r) + letters;
    n = Math.floor((n - 1) / 26);
  }
  return `${letters}${row + 1}`;
}

function cellXml(value, row, col, style = 0) {
  const ref = cellRef(row, col);
  if (typeof value === "number" && Number.isFinite(value))
    return `<c r="${ref}"${style ? ` s="${style}"` : ""}><v>${value}</v></c>`;
  return `<c r="${ref}" t="inlineStr"${style ? ` s="${style}"` : ""}><is><t>${xmlEscape(value)}</t></is></c>`;
}

function worksheetXml(sheet) {
  const maxCols = Math.max(...sheet.rows.map((r) => r.length), 1);
  const cols = Array.from({ length: maxCols }, (_, i) => {
    const width = sheet.widths?.[i] ?? 18;
    return `<col min="${i + 1}" max="${i + 1}" width="${width}" customWidth="1"/>`;
  }).join("");
  const rows = sheet.rows.map((row, r) => {
    const isTitle = r === 0;
    const isHeader = r === 2 || (sheet.headerRows ?? []).includes(r);
    const style = isTitle ? 1 : isHeader ? 2 : 0;
    const cells = row.map((value, c) => cellXml(value, r, c, style)).join("");
    return `<row r="${r + 1}"${isTitle ? ' ht="24" customHeight="1"' : ""}>${cells}</row>`;
  }).join("");
  const freeze = sheet.freezeRows
    ? `<sheetViews><sheetView workbookViewId="0"><pane ySplit="${sheet.freezeRows}" topLeftCell="A${sheet.freezeRows + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>`
    : `<sheetViews><sheetView workbookViewId="0"/></sheetViews>`;
  const autoFilter = sheet.autoFilter ? `<autoFilter ref="${sheet.autoFilter}"/>` : "";
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
${freeze}
<cols>${cols}</cols>
<sheetData>${rows}</sheetData>
${autoFilter}
</worksheet>`;
}

function writeWorkbook(sheets) {
  rmSync(scratch, { recursive: true, force: true });
  ensureDir(join(scratch, "_rels"));
  ensureDir(join(scratch, "xl", "_rels"));
  ensureDir(join(scratch, "xl", "worksheets"));

  writeFileSync(join(scratch, "[Content_Types].xml"), `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("\n")}
</Types>`);
  writeFileSync(join(scratch, "_rels", ".rels"), `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`);
  writeFileSync(join(scratch, "xl", "workbook.xml"), `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>${sheets.map((s, i) => `<sheet name="${xmlEscape(s.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets>
</workbook>`);
  writeFileSync(join(scratch, "xl", "_rels", "workbook.xml.rels"), `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("\n")}
<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`);
  writeFileSync(join(scratch, "xl", "styles.xml"), `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="3"><font/><font><b/><sz val="14"/></font><font><b/><color rgb="FFFFFFFF"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF24445C"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFill="1" applyFont="1"/></cellXfs>
</styleSheet>`);
  sheets.forEach((sheet, i) => writeFileSync(join(scratch, "xl", "worksheets", `sheet${i + 1}.xml`), worksheetXml(sheet)));
  rmSync(outPath, { force: true });
  execFileSync("powershell", ["-NoProfile", "-Command", `Compress-Archive -Path '${scratch}\\*' -DestinationPath '${outPath}' -Force`], { stdio: "inherit" });
  rmSync(scratch, { recursive: true, force: true });
}

const corridorViews = readCsv(join(analysisRoot, "corridor_views.csv"));
const zones = readCsv(join(analysisRoot, "zone_candidates.csv"));
const sessions = readCsv(join(analysisRoot, "turn_recordings", "wall_turn_recording_sessions.csv"));

const zoneCounts = ["left_wall", "right_wall", "center_back", "floor"].map((zone) => ({
  zone,
  candidates: zones.filter((r) => r.zone === zone).length,
  unique: countUnique(zones.filter((r) => r.zone === zone), "hash"),
}));

const totals = {
  corridorViews: corridorViews.length,
  turnRawFrames: sessions.reduce((sum, s) => sum + Number(s.raw_frames || 0), 0),
  turnKeyframes: sessions.reduce((sum, s) => sum + Number(s.consecutive_keyframes || 0), 0),
  selectedTurnFrames: sessions.reduce((sum, s) => sum + Number(s.selected_keyframes || 0), 0),
  uniqueSessionStates: sessions.reduce((sum, s) => sum + Number(s.unique_visible_tile_states || 0), 0),
};

const assetRows = [
  ["ENV-001", "Screen Frame", "Static HUD/status frame", "Top scoreboard panels and unchanged upper UI framing", "Visible in all playfield captures", 1, "1", "High", "Keep separate from corridor plates", "Needed before gameplay mockup", "Identified", "HUD is alpha/playfield art, not part of the lower corridor system."],
  ["ENV-002", "Screen Frame", "Black action void / right-side clear area", "Empty play space to the right of the corridor crop", "All corridor captures show a large black area to the right", 1, "1", "High", "Single reusable rectangle or background layer", "Used by all plates/templates", "Identified", "Useful if corridor art is cropped to the active wall area."],
  ["ENV-010", "Full Plate", "Settled corridor view plates", "Fastest accurate Godot prototype for settled maze views", "unique_corridor_views/", totals.corridorViews, "52 observed", "High", "Use captured/tight plates first; replace later with components", "Needs logical map-state labeling", "Ready to sort", "These are deduped from one-shot captures and include maze state variants."],
  ["ENV-011", "Full Plate", "Turn transition plates/templates", "Animated first-person turn states between settled facings", "turn_recordings/session_*/keyframes/", totals.turnKeyframes, "388 within-session keyframes before global dedupe", "High", "Use sampled keyframes for review, then consolidate duplicates", "Needs left/right turn sequence tagging", "Needs curation", "The F10 recorder confirms intermediate tilemap states during turns."],
  ["ENV-012", "Full Plate", "Forward movement transition plates/templates", "Animated step or move-forward transition states", "Some turn sessions include motion/position changes", "Unknown", "Capture-specific", "Medium", "Separate by controlled movement recordings", "Needs controlled forward/back capture", "Unknown", "Current sessions were focused on turns, not clean movement-only timing."],
  ["ENV-020", "Wall Component", "Left wall plane variants", "Reusable left side perspective wall blocks", "zone_candidates left_wall", zoneCounts.find((z) => z.zone === "left_wall")?.unique ?? "", "15-25 prototype, 46 observed rough hashes", "High", "Manually consolidate from zone candidates", "Depends on tile cleanup and duplicate review", "Needs curation", "Rough hashes overcount because panels include openings and transition states."],
  ["ENV-021", "Wall Component", "Right wall plane variants", "Reusable right side perspective wall blocks", "zone_candidates right_wall", zoneCounts.find((z) => z.zone === "right_wall")?.unique ?? "", "12-20 prototype, 33 observed rough hashes", "High", "Manually consolidate from zone candidates", "Pair with left wall mirrored/unique cases", "Needs curation", "Right side often includes doorway edge/black void interactions."],
  ["ENV-022", "Wall Component", "Center/back wall and far opening panels", "Dead ends, far wall, forward passage opening, distant doors", "zone_candidates center_back", zoneCounts.find((z) => z.zone === "center_back")?.unique ?? "", "15-25 prototype, 42 observed rough hashes", "High", "Extract from center/back candidates", "Needed for straight/dead-end/corner state templates", "Needs curation", "This is the main logical state indicator for what lies ahead."],
  ["ENV-023", "Wall Component", "Floor perspective panels", "Tan floor plane, diagonal seams, distance cues", "zone_candidates floor", zoneCounts.find((z) => z.zone === "floor")?.unique ?? "", "15-25 prototype, 51 observed rough hashes", "High", "Extract repeated floor seam families", "Must align to wall edge templates", "Needs curation", "Floor variants are high because perspective seams shift during transitions."],
  ["ENV-024", "Trim Component", "Ceiling / upper trim strips", "Brown/gray top corridor strip and perspective ceiling edge", "Visible across corridor crops", "Observed, not separately counted", "8-15", "High", "Slice from cropped keyframes and settled plates", "Aligns with left/right wall and center panels", "Needs extraction", "Likely reusable across many corridor states."],
  ["ENV-025", "Trim Component", "Vertical columns / doorway side rails", "Dark gray vertical borders at near and far wall edges", "Repeated in turn contact sheets", "Observed, not separately counted", "6-12", "High", "Extract as modular edge pieces", "Needed for door/opening templates", "Needs extraction", "These are strong anchors for reconstructing turns."],
  ["ENV-026", "Opening Component", "Left side passage opening pieces", "Indicates a possible left turn or side hallway", "Turn contact sheets and side-wall views", "Observed", "8-16", "High", "Group by distance: near/mid/far", "Requires map-state labeling", "Needs curation", "Distinct from simple wall plane because it exposes black passage space."],
  ["ENV-027", "Opening Component", "Right side passage opening pieces", "Indicates a possible right turn or side hallway", "Turn contact sheets and side-wall views", "Observed", "8-16", "High", "Group by distance: near/mid/far", "Requires map-state labeling", "Needs curation", "Likely asymmetric because screen composition leaves large black action space."],
  ["ENV-028", "Opening Component", "Forward doorway / gate / end-panel details", "Far door, dead-end panel, and passage blockers", "center/back candidates", "Observed", "8-16", "Medium", "Crop from center/back panels", "Depends on identifying room/door states", "Needs curation", "May include animated/open variants if encountered."],
  ["ENV-029", "Detail Component", "Wall pattern decals", "Blue wall glyph-like blocks that sell the Xybots wall material", "All wall crops", "Observed", "10-25", "Medium", "Tile-level cleanup from wall sheets", "Useful if moving from plates to modular renderer", "Needs extraction", "These may be embedded in larger wall panels for prototype."],
  ["ENV-030", "Detail Component", "Floor seam/line tiles", "Diagonal floor lines and distance grid", "floor candidates", "Observed", "8-20", "Medium", "Extract line families by perspective row", "Must match floor panels", "Needs extraction", "Could be baked into floor panels for the first Godot pass."],
  ["ENV-031", "Tile System", "Raw 8x8 environment tile atlas", "Reusable source tile sheet for manual/automated reconstruction", "playfield wall tile exports", "Exists as working files", "1 cleaned atlas plus source metadata", "High", "Keep clean 1x transparent tile atlas", "Basis for component reconstruction", "In progress", "Equivalent to the sprite raw 8x8 sheet workflow."],
  ["ENV-040", "Template", "Straight corridor template", "Logical arrangement for forward hallway", "settled plates/contact sheets", "Observed", "1 template with variants", "High", "Build as plate first, then component layout", "Needs map-state mapping", "Needed", "Core movement view."],
  ["ENV-041", "Template", "Dead end template", "Logical arrangement for blocked forward path", "settled plates/contact sheets", "Observed", "1 template with variants", "High", "Build as plate first, then component layout", "Needs map-state mapping", "Needed", "Core maze state."],
  ["ENV-042", "Template", "Left opening / left turn template", "Logical arrangement for a side opening on the left", "turn sheets and side openings", "Observed", "1 template with near/mid/far variants", "High", "Label from turn captures", "Needs controlled map-state annotation", "Needed", "Needed for navigation feedback."],
  ["ENV-043", "Template", "Right opening / right turn template", "Logical arrangement for a side opening on the right", "turn sheets and side openings", "Observed", "1 template with near/mid/far variants", "High", "Label from turn captures", "Needs controlled map-state annotation", "Needed", "Needed for navigation feedback."],
  ["ENV-044", "Template", "T-junction / intersection template", "Multiple possible branches visible in one view", "Some captured plates may include these", "Unconfirmed", "1-3 templates", "Medium", "Find in contact sheets or run controlled captures", "Needs explicit capture route", "Needs verification", "Do not overbuild until confirmed."],
  ["ENV-045", "Template", "Left turn animation sequence", "Facing change through intermediate tilemap states", "session_0005 contact sheet", "Observed", "10-30 curated frames per direction", "High", "Select/dedupe turn keyframes into animation states", "Need direction labels", "Needs curation", "Use frame timing from mame_frame deltas."],
  ["ENV-046", "Template", "Right turn animation sequence", "Facing change through intermediate tilemap states", "session_0005 contact sheet", "Observed", "10-30 curated frames per direction", "High", "Select/dedupe turn keyframes into animation states", "Need direction labels", "Needs curation", "Likely not a simple mirror because composition and map state differ."],
  ["ENV-047", "Template", "Move forward animation sequence", "Transition from one grid cell to the next", "Not isolated in current data", "Unknown", "10-30 frames after controlled capture", "Medium", "Run F10 during a straight step only", "Needs new controlled capture", "Not started", "This will determine whether movement can use plate switching or needs interpolated templates."],
  ["ENV-050", "Metadata", "Tilemap state definitions", "Data mapping logical view state to plate/template/components", "playfield_tiles.json and keyframe CSVs", "Many", "One JSON/CSV table", "High", "Generate from curated frame list", "Depends on art curation", "Needed", "This is the bridge from captured art to Godot runtime."],
];

const summaryRows = [
  ["Xybots Environment Art Asset Inventory", "", "", ""],
  ["Generated", new Date().toISOString().slice(0, 10), "", ""],
  ["Metric", "Value", "Meaning", "Source"],
  ["Settled unique corridor plates", totals.corridorViews, "Deduped one-shot lower corridor views", "analysis/wall_reconstruction/corridor_views.csv"],
  ["Turn raw frames captured", totals.turnRawFrames, "Every-frame playfield PNG/JSON frames across F10 sessions", "turn_recordings/wall_turn_recording_sessions.csv"],
  ["Turn consecutive keyframes", totals.turnKeyframes, "Within-session visible tilemap state changes, not globally deduped", "turn_recordings/session_*/keyframe_changes.csv"],
  ["Selected review turn frames", totals.selectedTurnFrames, "Sampled frames copied to keyframes folders/contact sheets", "turn_recordings/session_*/keyframes"],
  ["Lean component target", "40-60", "Minimum reusable wall/floor component set for prototype", "corridor_system_analysis.md"],
  ["Broad playable component target", "80-120", "Likely useful set after curation/dedupe", "corridor_system_analysis.md"],
  ["Close arcade reconstruction target", "150+", "True tile/component reconstruction with transition coverage", "corridor_system_analysis.md"],
  ["Recommended first implementation", "Full plates + curated turn sequences", "Fastest route to Godot feel while curation continues", "Derived from current captures"],
];

const inventoryRows = [
  ["ID", "Category", "Asset / Template", "Purpose", "Evidence", "Observed Count", "Suggested Count", "Priority", "Production Method", "Dependencies", "Status", "Notes"],
  ...assetRows,
];

const countsRows = [
  ["Captured Counts", "", "", "", ""],
  ["", "", "", "", ""],
  ["Item", "Count", "Source", "Interpretation", "Caveat"],
  ["Unique settled corridor plates", totals.corridorViews, "corridor_views.csv", "Observed lower corridor plates", "May include partial/uncategorized states"],
  ...zoneCounts.map((z) => [`Unique rough ${z.zone} hashes`, z.unique, "zone_candidates.csv", "Candidate reusable component group", "Rough crop hashes overcount visual assets"]),
  ["Turn raw frames", totals.turnRawFrames, "wall_turn_recording_sessions.csv", "Every-frame playfield capture volume", "Not deduped globally"],
  ["Turn within-session keyframes", totals.turnKeyframes, "wall_turn_recording_sessions.csv", "Frames where visible tilemap changed", "Duplicates may exist across sessions"],
  ["Selected turn review frames", totals.selectedTurnFrames, "selected_keyframes.csv", "Frames copied for contact-sheet review", "Sampled when sessions are large"],
];

const sessionRows = [
  ["Session", "Raw Frames", "Unique Visible Tile States", "Consecutive Keyframes", "Selected Review Frames", "MAME Frame Range", "Review Sheet", "Notes"],
  ...sessions.map((s) => [
    s.session,
    Number(s.raw_frames),
    Number(s.unique_visible_tile_states),
    Number(s.consecutive_keyframes),
    Number(s.selected_keyframes),
    `${s.first_mame_frame}-${s.last_mame_frame}`,
    `analysis/wall_reconstruction/turn_recordings/${s.session}/${s.corridor_contact_sheet}`,
    s.session === "session_0005" ? "Largest turn exploration session; best first review target" : "",
  ]),
];

const checklistRows = [
  ["Task ID", "Asset Group", "Action", "Priority", "Status", "Output", "Notes"],
  ["TASK-001", "Full plates", "Label the 52 settled corridor plates by logical state", "High", "Next", "corridor_plate_index.csv", "Needed before Godot can choose a view from map state."],
  ["TASK-002", "Turns", "Split session_0005 keyframes into left-turn and right-turn sequences", "High", "Next", "turn_sequence_index.csv", "Use contact_sheet_corridor.png and mame_frame timing."],
  ["TASK-003", "Turns", "Cull duplicate/near-duplicate transition frames", "High", "Next", "curated_turn_frames/", "Keep enough frames for visual smoothness, not every raw state."],
  ["TASK-004", "Wall components", "Manually consolidate left/right wall candidates into reusable panels", "Medium", "Planned", "wall_component_sheet.psd/png", "Start from the repeated large wall planes."],
  ["TASK-005", "Floor", "Extract and group floor perspective panels/seams", "Medium", "Planned", "floor_component_sheet.psd/png", "Floor variants are common during turns."],
  ["TASK-006", "Template system", "Create a Godot data table for state -> plate/template mapping", "High", "Planned", "environment_view_states.json", "Can start with full plates, then later point to component layouts."],
  ["TASK-007", "Capture", "Run controlled forward-step F10 recording", "Medium", "Not Started", "forward_step_turn_recording/", "Needed to separate movement animation from turn animation."],
  ["TASK-008", "Verification", "Compare Godot view switching against MAME contact sheets", "Medium", "Not Started", "comparison sheet/screenshots", "Use 1x scale and nearest filtering."],
];

const sheets = [
  { name: "Summary", rows: summaryRows, widths: [34, 18, 58, 48], freezeRows: 3, autoFilter: "A3:D11", headerRows: [2] },
  { name: "Asset Inventory", rows: inventoryRows, widths: [12, 18, 34, 44, 38, 16, 24, 12, 36, 34, 16, 54], freezeRows: 1, autoFilter: `A1:L${inventoryRows.length}`, headerRows: [0] },
  { name: "Captured Counts", rows: countsRows, widths: [34, 14, 42, 46, 46], freezeRows: 3, autoFilter: `A3:E${countsRows.length}`, headerRows: [2] },
  { name: "Turn Sessions", rows: sessionRows, widths: [16, 14, 24, 22, 22, 18, 74, 48], freezeRows: 1, autoFilter: `A1:H${sessionRows.length}`, headerRows: [0] },
  { name: "Production Checklist", rows: checklistRows, widths: [14, 22, 52, 12, 16, 34, 56], freezeRows: 1, autoFilter: `A1:G${checklistRows.length}`, headerRows: [0] },
];

writeWorkbook(sheets);
console.log(outPath);
