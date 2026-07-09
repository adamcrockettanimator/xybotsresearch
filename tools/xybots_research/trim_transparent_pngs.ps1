param(
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [switch]$InPlace,

    [string]$OutputDir = "",

    [switch]$Backup
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $InputDir)) {
    throw "Input directory not found: $InputDir"
}

if (-not $InPlace -and -not $OutputDir) {
    $OutputDir = Join-Path $InputDir "trimmed"
}

if ($OutputDir) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$source = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

public static class TransparentPngTrimmer
{
    public static int Run(string inputDir, string outputDir, bool inPlace, bool backup)
    {
        string backupDir = Path.Combine(inputDir, "pretrim_backup");
        if (backup)
            Directory.CreateDirectory(backupDir);
        if (!inPlace)
            Directory.CreateDirectory(outputDir);

        int changed = 0;
        string[] files = Array.FindAll(
            Directory.GetFiles(inputDir, "*.png", SearchOption.TopDirectoryOnly),
            f => !Path.GetFileName(f).Contains(".tmp."));
        Array.Sort(files, StringComparer.OrdinalIgnoreCase);

        foreach (string file in files)
        {
            string target = inPlace ? file : Path.Combine(outputDir, Path.GetFileName(file));
            string temp = target + ".tmp.png";
            bool sizeChanged = false;

            byte[] inputBytes = File.ReadAllBytes(file);
            using (MemoryStream inputStream = new MemoryStream(inputBytes))
            using (Bitmap src = new Bitmap(inputStream))
            {
                Rectangle bounds = FindOpaqueBounds(src);
                int outW = Math.Max(1, bounds.Width);
                int outH = Math.Max(1, bounds.Height);

                sizeChanged = outW != src.Width || outH != src.Height;
                if (sizeChanged)
                    changed++;

                using (Bitmap dst = new Bitmap(outW, outH, PixelFormat.Format32bppArgb))
                {
                    for (int y = 0; y < outH; y++)
                        for (int x = 0; x < outW; x++)
                            dst.SetPixel(x, y, src.GetPixel(x + bounds.X, y + bounds.Y));

                    if (inPlace && backup && sizeChanged)
                        File.Copy(file, Path.Combine(backupDir, Path.GetFileName(file)), true);

                    dst.Save(temp, ImageFormat.Png);
                }
            }

            if (File.Exists(target))
                File.Delete(target);
            File.Move(temp, target);
        }

        return changed;
    }

    static Rectangle FindOpaqueBounds(Bitmap bitmap)
    {
        int minX = bitmap.Width;
        int minY = bitmap.Height;
        int maxX = -1;
        int maxY = -1;

        for (int y = 0; y < bitmap.Height; y++)
        {
            for (int x = 0; x < bitmap.Width; x++)
            {
                if (bitmap.GetPixel(x, y).A == 0)
                    continue;
                if (x < minX) minX = x;
                if (y < minY) minY = y;
                if (x > maxX) maxX = x;
                if (y > maxY) maxY = y;
            }
        }

        if (maxX < minX || maxY < minY)
            return new Rectangle(0, 0, 1, 1);

        return new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
    }
}
"@

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition $source -ReferencedAssemblies "System.Drawing.dll"

$changed = [TransparentPngTrimmer]::Run($InputDir, $OutputDir, [bool]$InPlace, [bool]$Backup)
Write-Host "Trimmed PNGs in: $InputDir"
if ($InPlace) {
    Write-Host "Mode: in-place"
    if ($Backup) {
        Write-Host "Changed-file backup: $(Join-Path $InputDir 'pretrim_backup')"
    }
} else {
    Write-Host "Output: $OutputDir"
}
Write-Host "Files with changed dimensions: $changed"
