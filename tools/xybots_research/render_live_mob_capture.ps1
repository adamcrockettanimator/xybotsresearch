param(
    [string]$CaptureCsv = "",
    [string]$RomZip = "D:\MAME\roms\xybots.zip",
    [string]$OutputDir = "D:\Godot\xybotsResearch\exports\live_mob_render",
    [int]$Scale = 4
)

$ErrorActionPreference = "Stop"

if (-not $CaptureCsv) {
    $CaptureCsv = Get-ChildItem -LiteralPath "D:\Godot\xybotsResearch\exports\live_mob_capture" -Filter "mob_capture_*.csv" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-Path -LiteralPath $CaptureCsv)) {
    Write-Host "Capture CSV not found: $CaptureCsv"
    exit 2
}

if (-not (Test-Path -LiteralPath $RomZip)) {
    Write-Host "ROM zip not found: $RomZip"
    exit 3
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$source = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;

public static class XybotsLiveMobRenderer
{
    struct LoadEntry
    {
        public string Name;
        public int Offset;
        public LoadEntry(string name, int offset) { Name = name; Offset = offset; }
    }

    class MobRow
    {
        public int Frame;
        public int Entry;
        public int Code;
        public int X;
        public int Y;
        public int Height;
        public int Color;
        public int Priority;
        public bool HFlip;
    }

    static readonly LoadEntry[] SpriteLoads = new LoadEntry[] {
        new LoadEntry("136054-1105.2e",  0x000000),
        new LoadEntry("136054-1106.2ef", 0x010000),
        new LoadEntry("136054-1107.2f",  0x020000),
        new LoadEntry("136054-1108.2fj", 0x030000),
        new LoadEntry("136054-1109.2jk", 0x040000),
        new LoadEntry("136054-1110.2k",  0x050000),
        new LoadEntry("136054-1111.2l",  0x060000)
    };

    static readonly Color[] Palette = new Color[] {
        Color.FromArgb(0, 0, 0, 0),
        Color.FromArgb(255, 0, 255, 0),
        Color.FromArgb(255, 32, 56, 72),
        Color.FromArgb(255, 0, 0, 96),
        Color.FromArgb(255, 32, 32, 128),
        Color.FromArgb(255, 72, 72, 176),
        Color.FromArgb(255, 96, 0, 96),
        Color.FromArgb(255, 176, 32, 104),
        Color.FromArgb(255, 88, 88, 88),
        Color.FromArgb(255, 152, 152, 152),
        Color.FromArgb(255, 192, 192, 192),
        Color.FromArgb(255, 176, 64, 64),
        Color.FromArgb(255, 255, 168, 80),
        Color.FromArgb(255, 232, 208, 88),
        Color.FromArgb(255, 232, 128, 136),
        Color.FromArgb(255, 232, 232, 232)
    };

    public static void Render(string captureCsv, string romZip, string outputDir, int scale)
    {
        Directory.CreateDirectory(outputDir);
        byte[] sprites = LoadSpriteRegion(romZip);
        List<MobRow> active = ReadActiveRows(captureCsv);

        WriteReadme(outputDir, captureCsv, active);
        WriteUniqueStripSheet(Path.Combine(outputDir, "live_unique_motion_object_strips.png"), Path.Combine(outputDir, "live_unique_motion_object_strips.csv"), sprites, active, scale);
        WriteFrameCompositeSheet(Path.Combine(outputDir, "live_frame_composites.png"), Path.Combine(outputDir, "live_frame_composites.csv"), sprites, active, scale);
    }

    static byte[] LoadSpriteRegion(string romZip)
    {
        byte[] region = new byte[0x80000];
        using (ZipArchive zip = ZipFile.OpenRead(romZip))
        {
            foreach (LoadEntry load in SpriteLoads)
            {
                ZipArchiveEntry entry = zip.GetEntry(load.Name);
                if (entry == null)
                    throw new Exception("Missing sprite ROM entry: " + load.Name);
                using (Stream input = entry.Open())
                using (MemoryStream ms = new MemoryStream())
                {
                    input.CopyTo(ms);
                    byte[] data = ms.ToArray();
                    Array.Copy(data, 0, region, load.Offset, data.Length);
                }
            }
        }
        return region;
    }

    static List<MobRow> ReadActiveRows(string csvPath)
    {
        List<MobRow> rows = new List<MobRow>();
        bool first = true;
        foreach (string line in File.ReadLines(csvPath))
        {
            if (first) { first = false; continue; }
            if (String.IsNullOrWhiteSpace(line)) continue;
            string[] p = line.Split(',');
            if (p.Length < 18 || p[2] != "1") continue;

            rows.Add(new MobRow {
                Frame = Int32.Parse(p[0], CultureInfo.InvariantCulture),
                Entry = Int32.Parse(p[1], CultureInfo.InvariantCulture),
                Code = Int32.Parse(p[8], CultureInfo.InvariantCulture),
                X = Int32.Parse(p[11], CultureInfo.InvariantCulture),
                Y = Int32.Parse(p[13], CultureInfo.InvariantCulture),
                Height = Int32.Parse(p[15], CultureInfo.InvariantCulture),
                Color = Int32.Parse(p[16], CultureInfo.InvariantCulture),
                Priority = Int32.Parse(p[17], CultureInfo.InvariantCulture),
                HFlip = p.Length > 18 && p[18] == "1"
            });
        }
        return rows;
    }

    static void WriteUniqueStripSheet(string pngPath, string csvPath, byte[] sprites, List<MobRow> active, int scale)
    {
        var unique = active
            .GroupBy(r => String.Format("{0:X4}_{1}_{2}_{3}_{4}", r.Code, r.Height, r.Color, r.Priority, r.HFlip ? 1 : 0))
            .Select(g => new { Row = g.First(), Count = g.Count(), FirstFrame = g.Min(x => x.Frame), LastFrame = g.Max(x => x.Frame) })
            .OrderByDescending(g => g.Count)
            .ThenBy(g => g.Row.Code)
            .ToList();

        int columns = 16;
        int maxH = Math.Max(1, unique.Max(g => g.Row.Height));
        int imageW = 8 * scale;
        int imageH = maxH * 8 * scale;
        int cellW = 86;
        int cellH = imageH + 34;
        int rows = (unique.Count + columns - 1) / columns;

        using (Bitmap bitmap = new Bitmap(columns * cellW, rows * cellH, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bitmap))
        using (Font font = new Font(FontFamily.GenericMonospace, 8.0f))
        using (Brush textBrush = new SolidBrush(Color.White))
        using (Pen gridPen = new Pen(Color.FromArgb(80, 255, 255, 255)))
        using (StreamWriter csv = new StreamWriter(csvPath))
        {
            g.Clear(Color.FromArgb(255, 18, 18, 28));
            csv.WriteLine("cell,count,first_frame,last_frame,code_hex,code_dec,height_tiles,color,priority,hflip");
            for (int i = 0; i < unique.Count; i++)
            {
                var item = unique[i];
                int col = i % columns;
                int row = i / columns;
                int x0 = col * cellW;
                int y0 = row * cellH;
                int drawX = x0 + (cellW - imageW) / 2;
                int drawY = y0 + 2;
                DrawStrip(bitmap, sprites, item.Row.Code, item.Row.Height, item.Row.HFlip, drawX, drawY, scale);
                g.DrawRectangle(gridPen, drawX, drawY, imageW, item.Row.Height * 8 * scale);
                g.DrawString(String.Format("{0:X4} h{1}", item.Row.Code, item.Row.Height), font, textBrush, x0 + 2, y0 + imageH + 2);
                g.DrawString(String.Format("c{0} p{1} x{2}", item.Row.Color, item.Row.Priority, item.Count), font, textBrush, x0 + 2, y0 + imageH + 16);
                csv.WriteLine(String.Format("{0},{1},{2},{3},{4:X4},{4},{5},{6},{7},{8}", i, item.Count, item.FirstFrame, item.LastFrame, item.Row.Code, item.Row.Height, item.Row.Color, item.Row.Priority, item.Row.HFlip ? 1 : 0));
            }
            bitmap.Save(pngPath, ImageFormat.Png);
        }
    }

    static void WriteFrameCompositeSheet(string pngPath, string csvPath, byte[] sprites, List<MobRow> active, int scale)
    {
        var frames = active
            .GroupBy(r => r.Frame)
            .OrderBy(g => g.Key)
            .Take(48)
            .ToList();

        int viewW = 384;
        int viewH = 256;
        int cellW = viewW * scale;
        int cellH = viewH * scale + 18;
        int columns = 2;
        int rows = (frames.Count + columns - 1) / columns;

        using (Bitmap bitmap = new Bitmap(columns * cellW, rows * cellH, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bitmap))
        using (Font font = new Font(FontFamily.GenericMonospace, 8.0f))
        using (Brush textBrush = new SolidBrush(Color.White))
        using (Pen borderPen = new Pen(Color.FromArgb(120, 255, 255, 255)))
        using (StreamWriter csv = new StreamWriter(csvPath))
        {
            g.Clear(Color.FromArgb(255, 10, 10, 14));
            csv.WriteLine("sheet_cell,frame,active_entries,note");

            for (int i = 0; i < frames.Count; i++)
            {
                var frame = frames[i];
                int col = i % columns;
                int row = i / columns;
                int baseX = col * cellW;
                int baseY = row * cellH;

                using (Bitmap cell = new Bitmap(viewW * scale, viewH * scale, PixelFormat.Format32bppArgb))
                {
                    using (Graphics cg = Graphics.FromImage(cell))
                        cg.Clear(Color.FromArgb(255, 24, 24, 30));

                    foreach (MobRow r in frame.OrderBy(x => x.Priority).ThenBy(x => x.Entry))
                    {
                        int x = r.X;
                        int y = -r.Y - (r.Height * 8);
                        if (x < -32 || x > viewW + 32 || y < -80 || y > viewH + 32)
                            continue;
                        DrawStrip(cell, sprites, r.Code, r.Height, r.HFlip, x * scale, y * scale, scale);
                    }

                    g.DrawImageUnscaled(cell, baseX, baseY);
                }

                g.DrawRectangle(borderPen, baseX, baseY, viewW * scale - 1, viewH * scale - 1);
                g.DrawString(String.Format("frame {0} entries {1}", frame.Key, frame.Count()), font, textBrush, baseX + 4, baseY + viewH * scale + 2);
                csv.WriteLine(String.Format("{0},{1},{2},approximate sprite-only composite using captured X/Y", i, frame.Key, frame.Count()));
            }
            bitmap.Save(pngPath, ImageFormat.Png);
        }
    }

    static void DrawStrip(Bitmap bitmap, byte[] sprites, int code, int height, bool hflip, int x0, int y0, int scale)
    {
        for (int i = 0; i < height; i++)
            DrawTile(bitmap, sprites, code + i, hflip, x0, y0 + i * 8 * scale, scale);
    }

    static void DrawTile(Bitmap bitmap, byte[] sprites, int tileIndex, bool hflip, int x0, int y0, int scale)
    {
        int offset = tileIndex * 32;
        if (offset < 0 || offset + 31 >= sprites.Length)
            return;

        for (int y = 0; y < 8; y++)
        {
            for (int x = 0; x < 8; x++)
            {
                int srcX = hflip ? (7 - x) : x;
                byte packed = sprites[offset + y * 4 + srcX / 2];
                int pen = ((srcX & 1) == 0) ? ((packed >> 4) & 0x0f) : (packed & 0x0f);
                if (pen == 0) continue;
                Color color = Palette[pen];
                for (int sy = 0; sy < scale; sy++)
                    for (int sx = 0; sx < scale; sx++)
                    {
                        int px = x0 + x * scale + sx;
                        int py = y0 + y * scale + sy;
                        if ((uint)px < (uint)bitmap.Width && (uint)py < (uint)bitmap.Height)
                            bitmap.SetPixel(px, py, color);
                    }
            }
        }
    }

    static void WriteReadme(string outputDir, string captureCsv, List<MobRow> active)
    {
        int first = active.Count == 0 ? 0 : active.Min(r => r.Frame);
        int last = active.Count == 0 ? 0 : active.Max(r => r.Frame);
        int unique = active.GroupBy(r => String.Format("{0}_{1}_{2}_{3}_{4}", r.Code, r.Height, r.Color, r.Priority, r.HFlip)).Count();
        string readme = @"# Live Xybots Motion-Object Renders

Private research reference. Do not redistribute.

These images are rendered from live MAME motion-object RAM capture plus the local sprite ROM region.

Important:

- The accurate Xybots motion-object unit is a vertical 8-pixel-wide strip.
- Height comes from the live height field plus one.
- Codes increment downward through the strip, confirmed by MAME's Atari motion-object helper.
- Colors are still a debug palette, not the exact final in-game palette.
- `live_unique_motion_object_strips.png` is the most reliable reconstruction sheet.
- `live_frame_composites.png` is an approximate sprite-only placement view for sampled frames.

Capture CSV:
" + captureCsv + @"

Active rows:
" + active.Count + @"

Frame range:
" + first + @"-" + last + @"

Unique strip variants:
" + unique + @"
";
        File.WriteAllText(Path.Combine(outputDir, "README.md"), readme);
    }
}
"@

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -TypeDefinition $source -ReferencedAssemblies "System.Drawing.dll", "System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll"

[XybotsLiveMobRenderer]::Render($CaptureCsv, $RomZip, $OutputDir, $Scale)

Write-Host "Rendered live motion-object images to:"
Write-Host "  $OutputDir"
