param(
    [string]$RomZip = "D:\MAME\roms\xybots.zip",
    [string]$OutputRoot = "D:\Godot\xybotsResearch\exports",
    [int]$Scale = 3
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $RomZip)) {
    Write-Host "ROM zip not found: $RomZip"
    exit 2
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$source = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;

public static class XybotsSpriteExporter
{
    struct LoadEntry
    {
        public string Name;
        public int Offset;
        public LoadEntry(string name, int offset) { Name = name; Offset = offset; }
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

    static readonly LoadEntry[] TileLoads = new LoadEntry[] {
        new LoadEntry("136054-2102.12l", 0x000000),
        new LoadEntry("136054-2102.12l", 0x008000),
        new LoadEntry("136054-2103.11l", 0x010000),
        new LoadEntry("136054-2117.8l",  0x030000)
    };

    static readonly LoadEntry[] CharLoads = new LoadEntry[] {
        new LoadEntry("136054-1101.5c", 0x000000)
    };

    static readonly Color[] DebugPalette = new Color[] {
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

    public static void Export(string romZip, string outputRoot, int scale)
    {
        string spriteDir = Path.Combine(outputRoot, "sprites");
        string reconstructedDir = Path.Combine(outputRoot, "reconstructed_sprites");
        string tileDir = Path.Combine(outputRoot, "tiles");
        string charDir = Path.Combine(outputRoot, "chars");
        Directory.CreateDirectory(spriteDir);
        Directory.CreateDirectory(reconstructedDir);
        Directory.CreateDirectory(tileDir);
        Directory.CreateDirectory(charDir);

        byte[] sprites = LoadRegion(romZip, 0x80000, SpriteLoads);
        int spriteTileCount = sprites.Length / 32;

        WriteReadme(spriteDir, romZip, spriteTileCount);
        WriteSheet(Path.Combine(spriteDir, "xybots_sprites_raw_8x8_tiles.png"), Path.Combine(spriteDir, "xybots_sprites_raw_8x8_tiles.csv"), sprites, spriteTileCount, 1, 1, scale, 64);
        WriteSheet(Path.Combine(spriteDir, "xybots_sprites_vertical_2_tiles_step2.png"), Path.Combine(spriteDir, "xybots_sprites_vertical_2_tiles_step2.csv"), sprites, spriteTileCount, 2, 2, scale, 64);
        WriteSheet(Path.Combine(spriteDir, "xybots_sprites_vertical_4_tiles_step4.png"), Path.Combine(spriteDir, "xybots_sprites_vertical_4_tiles_step4.csv"), sprites, spriteTileCount, 4, 4, scale, 64);
        WriteSheet(Path.Combine(spriteDir, "xybots_sprites_vertical_8_tiles_step8.png"), Path.Combine(spriteDir, "xybots_sprites_vertical_8_tiles_step8.csv"), sprites, spriteTileCount, 8, 8, scale, 64);

        WriteAssemblyReadme(reconstructedDir, romZip);
        WriteAssemblySheet(Path.Combine(reconstructedDir, "xybots_sprite_candidates_2x4_colmajor.png"), Path.Combine(reconstructedDir, "xybots_sprite_candidates_2x4_colmajor.csv"), sprites, spriteTileCount, 2, 4, true, scale, 32);
        WriteAssemblySheet(Path.Combine(reconstructedDir, "xybots_sprite_candidates_2x8_colmajor.png"), Path.Combine(reconstructedDir, "xybots_sprite_candidates_2x8_colmajor.csv"), sprites, spriteTileCount, 2, 8, true, scale, 32);
        WriteAssemblySheet(Path.Combine(reconstructedDir, "xybots_sprite_candidates_3x4_colmajor.png"), Path.Combine(reconstructedDir, "xybots_sprite_candidates_3x4_colmajor.csv"), sprites, spriteTileCount, 3, 4, true, scale, 32);
        WriteAssemblySheet(Path.Combine(reconstructedDir, "xybots_sprite_candidates_3x8_colmajor.png"), Path.Combine(reconstructedDir, "xybots_sprite_candidates_3x8_colmajor.csv"), sprites, spriteTileCount, 3, 8, true, scale, 32);
        WriteAssemblySheet(Path.Combine(reconstructedDir, "xybots_sprite_candidates_4x4_colmajor.png"), Path.Combine(reconstructedDir, "xybots_sprite_candidates_4x4_colmajor.csv"), sprites, spriteTileCount, 4, 4, true, scale, 32);
        WriteAssemblySheet(Path.Combine(reconstructedDir, "xybots_sprite_candidates_4x8_colmajor.png"), Path.Combine(reconstructedDir, "xybots_sprite_candidates_4x8_colmajor.csv"), sprites, spriteTileCount, 4, 8, true, scale, 32);
        WriteAssemblySheet(Path.Combine(reconstructedDir, "xybots_sprite_candidates_4x4_rowmajor.png"), Path.Combine(reconstructedDir, "xybots_sprite_candidates_4x4_rowmajor.csv"), sprites, spriteTileCount, 4, 4, false, scale, 32);

        byte[] tiles = LoadRegion(romZip, 0x40000, TileLoads);
        int playfieldTileCount = tiles.Length / 32;
        WriteTileReadme(tileDir, romZip, playfieldTileCount);
        WriteSheet(Path.Combine(tileDir, "xybots_playfield_raw_8x8_tiles.png"), Path.Combine(tileDir, "xybots_playfield_raw_8x8_tiles.csv"), tiles, playfieldTileCount, 1, 1, scale, 64);
        WriteAssemblySheet(Path.Combine(tileDir, "xybots_playfield_candidates_2x2_rowmajor.png"), Path.Combine(tileDir, "xybots_playfield_candidates_2x2_rowmajor.csv"), tiles, playfieldTileCount, 2, 2, false, scale, 32);
        WriteAssemblySheet(Path.Combine(tileDir, "xybots_playfield_candidates_4x4_rowmajor.png"), Path.Combine(tileDir, "xybots_playfield_candidates_4x4_rowmajor.csv"), tiles, playfieldTileCount, 4, 4, false, scale, 32);
        WriteAssemblySheet(Path.Combine(tileDir, "xybots_playfield_candidates_8x4_rowmajor.png"), Path.Combine(tileDir, "xybots_playfield_candidates_8x4_rowmajor.csv"), tiles, playfieldTileCount, 8, 4, false, scale, 16);

        byte[] chars = LoadRegion(romZip, 0x02000, CharLoads);
        int charTileCount = chars.Length / 16;
        WriteCharsSheet(Path.Combine(charDir, "xybots_chars_raw_8x8_2bpp.png"), Path.Combine(charDir, "xybots_chars_raw_8x8_2bpp.csv"), chars, charTileCount, scale, 32);
    }

    static byte[] LoadRegion(string romZip, int regionSize, LoadEntry[] loads)
    {
        byte[] region = new byte[regionSize];

        using (ZipArchive zip = ZipFile.OpenRead(romZip))
        {
            foreach (LoadEntry load in loads)
            {
                ZipArchiveEntry entry = zip.GetEntry(load.Name);
                if (entry == null)
                    throw new Exception("Missing ROM entry: " + load.Name);

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

    static void WriteAssemblySheet(string pngPath, string csvPath, byte[] region, int tileCount, int groupWidth, int groupHeight, bool columnMajor, int scale, int columns)
    {
        int step = groupWidth * groupHeight;
        int groups = Math.Max(0, tileCount / step);
        int rows = (groups + columns - 1) / columns;
        int imageW = 8 * groupWidth * scale;
        int imageH = 8 * groupHeight * scale;
        int cellW = Math.Max(imageW + 10, 72);
        int cellH = imageH + 16;

        using (Bitmap bitmap = new Bitmap(columns * cellW, rows * cellH, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bitmap))
        using (Font font = new Font(FontFamily.GenericMonospace, 8.0f))
        using (Brush textBrush = new SolidBrush(Color.White))
        using (Pen gridPen = new Pen(Color.FromArgb(80, 255, 255, 255)))
        using (StreamWriter csv = new StreamWriter(csvPath))
        {
            g.Clear(Color.FromArgb(255, 18, 18, 28));
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
            csv.WriteLine("cell,base_tile_hex,base_tile_dec,width_tiles,height_tiles,order,note");

            for (int i = 0; i < groups; i++)
            {
                int baseTile = i * step;
                int col = i % columns;
                int row = i / columns;
                int x0 = col * cellW;
                int y0 = row * cellH;
                int drawX = x0 + (cellW - imageW) / 2;
                int drawY = y0 + 2;

                DrawAssembly(bitmap, region, baseTile, groupWidth, groupHeight, columnMajor, drawX, drawY, scale);
                g.DrawRectangle(gridPen, drawX, drawY, imageW, imageH);
                g.DrawString(baseTile.ToString("X4"), font, textBrush, x0 + 2, y0 + imageH + 2);
                csv.WriteLine(String.Format("{0},{1},{2},{3},{4},{5},candidate reconstruction from consecutive tile codes", i, baseTile.ToString("X4"), baseTile, groupWidth, groupHeight, columnMajor ? "column-major" : "row-major"));
            }

            bitmap.Save(pngPath, ImageFormat.Png);
        }
    }

    static void DrawAssembly(Bitmap bitmap, byte[] region, int baseTile, int groupWidth, int groupHeight, bool columnMajor, int x0, int y0, int scale)
    {
        for (int gy = 0; gy < groupHeight; gy++)
        {
            for (int gx = 0; gx < groupWidth; gx++)
            {
                int offset = columnMajor ? (gx * groupHeight + gy) : (gy * groupWidth + gx);
                DrawTile(bitmap, region, baseTile + offset, x0 + gx * 8 * scale, y0 + gy * 8 * scale, scale);
            }
        }
    }

    static void WriteSheet(string pngPath, string csvPath, byte[] region, int tileCount, int groupHeight, int step, int scale, int columns)
    {
        int groups = Math.Max(0, ((tileCount - groupHeight) / step) + 1);
        int rows = (groups + columns - 1) / columns;
        int imageW = 8 * scale;
        int imageH = 8 * groupHeight * scale;
        int cellW = Math.Max(imageW + 8, 58);
        int cellH = imageH + 16;

        using (Bitmap bitmap = new Bitmap(columns * cellW, rows * cellH, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bitmap))
        using (Font font = new Font(FontFamily.GenericMonospace, 8.0f))
        using (Brush textBrush = new SolidBrush(Color.White))
        using (Pen gridPen = new Pen(Color.FromArgb(80, 255, 255, 255)))
        using (StreamWriter csv = new StreamWriter(csvPath))
        {
            g.Clear(Color.FromArgb(255, 18, 18, 28));
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
            csv.WriteLine("cell,base_tile_hex,base_tile_dec,height_tiles,step,note");

            for (int i = 0; i < groups; i++)
            {
                int baseTile = i * step;
                int col = i % columns;
                int row = i / columns;
                int x0 = col * cellW;
                int y0 = row * cellH;
                int drawX = x0 + (cellW - imageW) / 2;
                int drawY = y0 + 2;

                DrawVerticalGroup(bitmap, region, baseTile, groupHeight, drawX, drawY, scale);
                g.DrawRectangle(gridPen, drawX, drawY, imageW, imageH);
                g.DrawString(baseTile.ToString("X4"), font, textBrush, x0 + 2, y0 + imageH + 2);
                csv.WriteLine(String.Format("{0},{1},{2},{3},{4},consecutive 8x8 tiles stacked vertically", i, baseTile.ToString("X4"), baseTile, groupHeight, step));
            }

            bitmap.Save(pngPath, ImageFormat.Png);
        }
    }

    static void DrawVerticalGroup(Bitmap bitmap, byte[] region, int baseTile, int groupHeight, int x0, int y0, int scale)
    {
        for (int t = 0; t < groupHeight; t++)
        {
            DrawTile(bitmap, region, baseTile + t, x0, y0 + (t * 8 * scale), scale);
        }
    }

    static void DrawTile(Bitmap bitmap, byte[] region, int tileIndex, int x0, int y0, int scale)
    {
        int offset = tileIndex * 32;
        if (offset < 0 || offset + 31 >= region.Length)
            return;

        for (int y = 0; y < 8; y++)
        {
            for (int x = 0; x < 8; x++)
            {
                byte packed = region[offset + y * 4 + x / 2];
                int pen = ((x & 1) == 0) ? ((packed >> 4) & 0x0f) : (packed & 0x0f);
                Color color = DebugPalette[pen];

                for (int sy = 0; sy < scale; sy++)
                    for (int sx = 0; sx < scale; sx++)
                        bitmap.SetPixel(x0 + x * scale + sx, y0 + y * scale + sy, color);
            }
        }
    }

    static void WriteCharsSheet(string pngPath, string csvPath, byte[] region, int tileCount, int scale, int columns)
    {
        int rows = (tileCount + columns - 1) / columns;
        int imageW = 8 * scale;
        int imageH = 8 * scale;
        int cellW = Math.Max(imageW + 8, 58);
        int cellH = imageH + 16;
        Color[] charPalette = new Color[] {
            Color.FromArgb(0, 0, 0, 0),
            Color.FromArgb(255, 96, 96, 96),
            Color.FromArgb(255, 176, 176, 176),
            Color.FromArgb(255, 255, 255, 255)
        };

        using (Bitmap bitmap = new Bitmap(columns * cellW, rows * cellH, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bitmap))
        using (Font font = new Font(FontFamily.GenericMonospace, 8.0f))
        using (Brush textBrush = new SolidBrush(Color.White))
        using (StreamWriter csv = new StreamWriter(csvPath))
        {
            g.Clear(Color.FromArgb(255, 18, 18, 28));
            csv.WriteLine("cell,tile_hex,tile_dec,note");

            for (int tile = 0; tile < tileCount; tile++)
            {
                int col = tile % columns;
                int row = tile / columns;
                int x0 = col * cellW + (cellW - imageW) / 2;
                int y0 = row * cellH + 2;
                DrawCharTile(bitmap, region, tile, x0, y0, scale, charPalette);
                g.DrawString(tile.ToString("X4"), font, textBrush, col * cellW + 2, row * cellH + imageH + 2);
                csv.WriteLine(String.Format("{0},{1},{2},8x8 2bpp char tile", tile, tile.ToString("X4"), tile));
            }

            bitmap.Save(pngPath, ImageFormat.Png);
        }
    }

    static void DrawCharTile(Bitmap bitmap, byte[] region, int tileIndex, int x0, int y0, int scale, Color[] palette)
    {
        int offset = tileIndex * 16;
        if (offset < 0 || offset + 15 >= region.Length)
            return;

        for (int y = 0; y < 8; y++)
        {
            byte plane0 = region[offset + y * 2 + 0];
            byte plane1 = region[offset + y * 2 + 1];
            for (int x = 0; x < 8; x++)
            {
                int shift = 7 - x;
                int pen = ((plane0 >> shift) & 1) | (((plane1 >> shift) & 1) << 1);
                Color color = palette[pen];

                for (int sy = 0; sy < scale; sy++)
                    for (int sx = 0; sx < scale; sx++)
                        bitmap.SetPixel(x0 + x * scale + sx, y0 + y * scale + sy, color);
            }
        }
    }

    static void WriteReadme(string outputDir, string romZip, int tileCount)
    {
        string readme = @"# Xybots Private Sprite Exports

These PNG files are private research reference material derived from the local ROM set. Do not redistribute them.

What these are:

- `xybots_sprites_raw_8x8_tiles.png`: decoded 8x8 sprite chunks in ROM/code order.
- `xybots_sprites_vertical_2_tiles_step2.png`: consecutive 8x8 chunks stacked as 2-tile-tall strips.
- `xybots_sprites_vertical_4_tiles_step4.png`: consecutive chunks stacked as 4-tile-tall strips.
- `xybots_sprites_vertical_8_tiles_step8.png`: consecutive chunks stacked as 8-tile-tall strips.

Important limits:

- These are not final runtime palettes. The colors are a debug palette chosen to make pixel indices visible.
- Pen/index 0 is transparent.
- The vertical sheets are reconstruction aids. MAME source confirms motion objects have a height-in-tiles field, but the exact live object list comes from game RAM during play.
- Use the CSV next to each PNG to map each contact-sheet cell back to a base tile index.

Source basis:

- MAME 0.288 `src/mame/atari/xybots.cpp`
- `GFXDECODE_ENTRY( ""sprites"", 0, gfx_8x8x4_packed_msb, 256, 48 )`
- Motion-object config includes code index, color, position, horizontal flip, priority, and height in tiles.

ROM source:
" + romZip + @"

Decoded tile capacity:
" + tileCount.ToString() + @"
";
        File.WriteAllText(Path.Combine(outputDir, "README.md"), readme);
    }

    static void WriteAssemblyReadme(string outputDir, string romZip)
    {
        string readme = @"# Xybots Reconstructed Sprite Candidates

These sheets are private research reference material. Do not redistribute them.

The game does not store finished Photoshop-style character sprites. MAME source shows 8x8 4bpp sprite chunks plus Atari motion objects with a height-in-tiles field. Larger visible characters are likely built from several vertical motion-object strips.

These images assemble consecutive sprite tile codes into likely blocks:

- `colmajor`: each column is a vertical strip, matching the motion-object height idea.
- `rowmajor`: ordinary reading order, included as a comparison/control.

Treat each block as a candidate, not a confirmed runtime sprite, until matched against gameplay screenshots or live motion-object RAM.

ROM source:
" + romZip + @"
";
        File.WriteAllText(Path.Combine(outputDir, "README.md"), readme);
    }

    static void WriteTileReadme(string outputDir, string romZip, int tileCount)
    {
        string readme = @"# Xybots Playfield Tile Exports

These sheets are private research reference material. Do not redistribute them.

What these are:

- `xybots_playfield_raw_8x8_tiles.png`: decoded playfield chunks.
- `xybots_playfield_candidates_*`: simple consecutive-tile block reconstructions to help spot larger wall, door, floor, title, and maze pieces.

Important limit:

The real live tilemaps are RAM grids of tile codes, colors, and flip bits. These sheets reconstruct graphics chunks, but they do not dump the live tilemap RAM. Use MAME's F4 tilemap viewer and screenshots for live map evidence.

ROM source:
" + romZip + @"

Decoded tile capacity:
" + tileCount.ToString() + @"
";
        File.WriteAllText(Path.Combine(outputDir, "README.md"), readme);
    }
}
"@

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -TypeDefinition $source -ReferencedAssemblies "System.Drawing.dll", "System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll"

[XybotsSpriteExporter]::Export($RomZip, $OutputRoot, $Scale)

Write-Host "Exported graphics research PNGs to:"
Write-Host "  $OutputRoot"
