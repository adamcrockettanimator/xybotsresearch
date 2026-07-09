param(
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [Parameter(Mandatory = $true)]
    [string]$BackgroundPath,

    [string]$OutputDir = "",

    [int]$Threshold = 24,

    [switch]$Trim
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $InputDir)) {
    throw "Input directory not found: $InputDir"
}

if (-not (Test-Path -LiteralPath $BackgroundPath)) {
    throw "Background plate not found: $BackgroundPath"
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $InputDir "masked"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$source = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

public static class BatchPlateMasker
{
    public static void Run(string inputDir, string backgroundPath, string outputDir, int threshold, bool trim)
    {
        Directory.CreateDirectory(outputDir);

        using (Bitmap bg = new Bitmap(backgroundPath))
        {
            string bgFull = Path.GetFullPath(backgroundPath);
            string[] files = Directory.GetFiles(inputDir, "*.png");
            Array.Sort(files, StringComparer.OrdinalIgnoreCase);

            int done = 0;
            foreach (string file in files)
            {
                if (String.Equals(Path.GetFullPath(file), bgFull, StringComparison.OrdinalIgnoreCase))
                    continue;

                string outPath = Path.Combine(outputDir, Path.GetFileNameWithoutExtension(file) + "_masked.png");
                MaskOne(file, bg, outPath, threshold, trim);
                done++;
                if ((done % 25) == 0)
                    Console.WriteLine("Masked " + done + " files");
            }

            Console.WriteLine("Masked " + done + " files to " + outputDir);
        }
    }

    static void MaskOne(string inputPath, Bitmap bg, string outputPath, int threshold, bool trim)
    {
        using (Bitmap src = new Bitmap(inputPath))
        {
            if (src.Width != bg.Width || src.Height != bg.Height)
                throw new Exception("Size mismatch: " + inputPath);

            bool[,] mask = new bool[src.Width, src.Height];
            int minX = src.Width, minY = src.Height, maxX = -1, maxY = -1;

            for (int y = 0; y < src.Height; y++)
            {
                for (int x = 0; x < src.Width; x++)
                {
                    Color a = src.GetPixel(x, y);
                    Color b = bg.GetPixel(x, y);
                    int diff = Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B);
                    bool keep = diff >= threshold;
                    mask[x, y] = keep;

                    if (keep)
                    {
                        if (x < minX) minX = x;
                        if (y < minY) minY = y;
                        if (x > maxX) maxX = x;
                        if (y > maxY) maxY = y;
                    }
                }
            }

            if (maxX < minX || maxY < minY)
            {
                minX = 0; minY = 0; maxX = 0; maxY = 0;
            }

            int outX = trim ? minX : 0;
            int outY = trim ? minY : 0;
            int outW = trim ? (maxX - minX + 1) : src.Width;
            int outH = trim ? (maxY - minY + 1) : src.Height;

            using (Bitmap dst = new Bitmap(outW, outH, PixelFormat.Format32bppArgb))
            {
                for (int y = 0; y < outH; y++)
                {
                    for (int x = 0; x < outW; x++)
                    {
                        int sx = x + outX;
                        int sy = y + outY;
                        if (mask[sx, sy])
                            dst.SetPixel(x, y, src.GetPixel(sx, sy));
                        else
                            dst.SetPixel(x, y, Color.FromArgb(0, 0, 0, 0));
                    }
                }

                dst.Save(outputPath, ImageFormat.Png);
            }
        }
    }
}
"@

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition $source -ReferencedAssemblies "System.Drawing.dll"

[BatchPlateMasker]::Run($InputDir, $BackgroundPath, $OutputDir, $Threshold, [bool]$Trim)
