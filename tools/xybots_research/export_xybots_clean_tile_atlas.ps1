param(
    [string]$RomZip = "D:\MAME\roms\xybots.zip",
    [string]$OutputPath = "D:\Godot\xybotsResearch\exports\sprites\xybots_sprites_raw_8x8_tiles_clean_1x.png",
    [int]$Columns = 64
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $RomZip)) {
    throw "ROM zip not found: $RomZip"
}

$outputDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$source = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;

public static class XybotsCleanTileAtlas
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

    public static void Export(string romZip, string outputPath, int columns)
    {
        byte[] sprites = LoadRegion(romZip, 0x80000, SpriteLoads);
        int tileCount = sprites.Length / 32;
        int rows = (tileCount + columns - 1) / columns;

        using (Bitmap bitmap = new Bitmap(columns * 8, rows * 8, PixelFormat.Format32bppArgb))
        {
            for (int tile = 0; tile < tileCount; tile++)
            {
                int x0 = (tile % columns) * 8;
                int y0 = (tile / columns) * 8;
                DrawTile(bitmap, sprites, tile, x0, y0);
            }

            bitmap.Save(outputPath, ImageFormat.Png);
        }
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

    static void DrawTile(Bitmap bitmap, byte[] region, int tileIndex, int x0, int y0)
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
                bitmap.SetPixel(x0 + x, y0 + y, DebugPalette[pen]);
            }
        }
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies "System.Drawing", "System.IO.Compression", "System.IO.Compression.FileSystem"
[XybotsCleanTileAtlas]::Export($RomZip, $OutputPath, $Columns)
Write-Output $OutputPath
