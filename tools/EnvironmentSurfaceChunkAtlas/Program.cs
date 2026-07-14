using System.Drawing;
using System.Drawing.Imaging;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

if (!OperatingSystem.IsWindows())
    throw new PlatformNotSupportedException("This tool uses System.Drawing for the local Windows research workflow.");

var projectRoot = args.Length > 0 ? Path.GetFullPath(args[0]) : Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."));
var atlasWidth = args.Length > 1 ? int.Parse(args[1]) : 2048;
var padding = args.Length > 2 ? int.Parse(args[2]) : 2;
var minimumArea = args.Length > 3 ? int.Parse(args[3]) : 48;

var analysisRoot = Path.Combine(projectRoot, "analysis", "wall_reconstruction");
var outRoot = Path.Combine(analysisRoot, "environment_surface_chunk_atlas");
var chunkRoot = Path.Combine(outRoot, "chunks");
var atlasPath = Path.Combine(outRoot, "environment_surface_chunks_atlas.png");
var jsonPath = Path.Combine(outRoot, "environment_surface_chunks_atlas.json");
var csvPath = Path.Combine(outRoot, "environment_surface_chunks_atlas.csv");
var summaryPath = Path.Combine(outRoot, "environment_surface_chunk_summary.csv");
var readmePath = Path.Combine(outRoot, "README.md");

if (Directory.Exists(outRoot))
    Directory.Delete(outRoot, true);
Directory.CreateDirectory(chunkRoot);

var sources = new List<SourceImage>();
var turnRoot = Path.Combine(analysisRoot, "turn_recordings");
if (Directory.Exists(turnRoot))
{
    sources.AddRange(
        Directory.EnumerateFiles(turnRoot, "key_*.png", SearchOption.AllDirectories)
            .OrderBy(p => p, StringComparer.OrdinalIgnoreCase)
            .Select(p => new SourceImage(p, "turn_keyframe")));
}
var settledRoot = Path.Combine(analysisRoot, "unique_corridor_views");
if (Directory.Exists(settledRoot))
{
    sources.AddRange(
        Directory.EnumerateFiles(settledRoot, "*.png", SearchOption.TopDirectoryOnly)
            .OrderBy(p => p, StringComparer.OrdinalIgnoreCase)
            .Select(p => new SourceImage(p, "settled_corridor_view")));
}

var chunks = new List<ChunkRecord>();
var seen = new Dictionary<string, ChunkRecord>(StringComparer.Ordinal);

foreach (var source in sources)
{
    using var sourceBitmap = new Bitmap(source.Path);
    var cropRect = source.Kind == "turn_keyframe"
        ? new Rectangle(0, 96, 176, 144)
        : new Rectangle(0, 0, 176, 120);
    if (cropRect.Right > sourceBitmap.Width || cropRect.Bottom > sourceBitmap.Height)
        continue;

    using var cropBitmap = sourceBitmap.Clone(cropRect, PixelFormat.Format32bppArgb);
    var image = PixelImage.FromBitmap(cropBitmap);

    foreach (var kind in new[] { "ceiling", "floor", "wall" })
    {
        var mask = BuildMask(image, kind);
        var components = FindComponents(mask, image.Width, image.Height, minimumArea);
        var componentNumber = 0;
        foreach (var component in components)
        {
            componentNumber++;
            using var chunkBitmap = MakeChunkBitmap(image, mask, component);
            var hash = HashBitmap(chunkBitmap);
            if (seen.TryGetValue(hash, out var existing))
            {
                existing.source_count++;
                continue;
            }

            var index = chunks.Count + 1;
            var chunkName = $"{kind}_{index:D4}.png";
            var chunkPath = Path.Combine(chunkRoot, chunkName);
            chunkBitmap.Save(chunkPath, ImageFormat.Png);

            var record = new ChunkRecord
            {
                index = index,
                name = Path.GetFileNameWithoutExtension(chunkName),
                type = kind,
                width = chunkBitmap.Width,
                height = chunkBitmap.Height,
                atlas_x = 0,
                atlas_y = 0,
                atlas_w = chunkBitmap.Width,
                atlas_h = chunkBitmap.Height,
                source_kind = source.Kind,
                source = Rel(projectRoot, source.Path),
                source_crop_x = cropRect.X,
                source_crop_y = cropRect.Y,
                source_component = componentNumber,
                source_x = cropRect.X + component.X,
                source_y = cropRect.Y + component.Y,
                source_w = component.Width,
                source_h = component.Height,
                area = component.Area,
                source_count = 1,
                hash = hash,
                image = Rel(projectRoot, chunkPath),
            };
            chunks.Add(record);
            seen.Add(hash, record);
        }
    }
}

var packedChunks = chunks
    .OrderBy(c => c.type, StringComparer.Ordinal)
    .ThenBy(c => c.height)
    .ThenBy(c => c.width)
    .ThenBy(c => c.index)
    .ToList();

var x = padding;
var y = padding;
var rowHeight = 0;
foreach (var chunk in packedChunks)
{
    if (x + chunk.width + padding > atlasWidth)
    {
        x = padding;
        y += rowHeight + padding;
        rowHeight = 0;
    }
    chunk.atlas_x = x;
    chunk.atlas_y = y;
    x += chunk.width + padding;
    rowHeight = Math.Max(rowHeight, chunk.height);
}
var atlasHeight = Math.Max(1, y + rowHeight + padding);

using (var atlas = new Bitmap(atlasWidth, atlasHeight, PixelFormat.Format32bppArgb))
using (var g = Graphics.FromImage(atlas))
{
    g.Clear(Color.Transparent);
    g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceOver;
    g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
    foreach (var chunk in packedChunks)
    {
        using var chunkBitmap = new Bitmap(Path.Combine(projectRoot, chunk.image.Replace('/', Path.DirectorySeparatorChar)));
        g.DrawImage(chunkBitmap, chunk.atlas_x, chunk.atlas_y, chunk.width, chunk.height);
    }
    atlas.Save(atlasPath, ImageFormat.Png);
}

var typeSummary = packedChunks
    .GroupBy(c => c.type)
    .OrderBy(g => g.Key, StringComparer.Ordinal)
    .Select(g => new { type = g.Key, count = g.Count() })
    .ToList();

var json = new
{
    atlas = Rel(projectRoot, atlasPath),
    width = atlasWidth,
    height = atlasHeight,
    padding,
    source_images_scanned = sources.Count,
    unique_chunks = packedChunks.Count,
    chunk_types = typeSummary,
    chunks = packedChunks,
};
File.WriteAllText(jsonPath, JsonSerializer.Serialize(json, new JsonSerializerOptions { WriteIndented = true }));

var csv = new StringBuilder();
csv.AppendLine("index,name,type,width,height,atlas_x,atlas_y,atlas_w,atlas_h,source_kind,source,source_crop_x,source_crop_y,source_component,source_x,source_y,source_w,source_h,area,source_count,hash,image");
foreach (var chunk in packedChunks)
{
    csv.AppendLine(string.Join(",", new[]
    {
        chunk.index.ToString(),
        Q(chunk.name),
        chunk.type,
        chunk.width.ToString(),
        chunk.height.ToString(),
        chunk.atlas_x.ToString(),
        chunk.atlas_y.ToString(),
        chunk.atlas_w.ToString(),
        chunk.atlas_h.ToString(),
        chunk.source_kind,
        Q(chunk.source),
        chunk.source_crop_x.ToString(),
        chunk.source_crop_y.ToString(),
        chunk.source_component.ToString(),
        chunk.source_x.ToString(),
        chunk.source_y.ToString(),
        chunk.source_w.ToString(),
        chunk.source_h.ToString(),
        chunk.area.ToString(),
        chunk.source_count.ToString(),
        chunk.hash,
        Q(chunk.image),
    }));
}
File.WriteAllText(csvPath, csv.ToString());

var summaryCsv = new StringBuilder();
summaryCsv.AppendLine("type,count,min_width,max_width,min_height,max_height,total_area");
foreach (var group in packedChunks.GroupBy(c => c.type).OrderBy(g => g.Key, StringComparer.Ordinal))
{
    summaryCsv.AppendLine($"{group.Key},{group.Count()},{group.Min(c => c.width)},{group.Max(c => c.width)},{group.Min(c => c.height)},{group.Max(c => c.height)},{group.Sum(c => c.area)}");
}
File.WriteAllText(summaryPath, summaryCsv.ToString());

File.WriteAllText(readmePath,
    $"""
    # Environment Surface Chunk Atlas

    This atlas is generated from the Xybots environment analysis frames:

    - selected every-frame turn keyframes
    - settled unique corridor view captures

    Unlike `environment_chunk_atlas`, this pass tries to split the images into
    surface-like chunks. It classifies pixels as:

    - `ceiling` - upper brown/gray ceiling and trim pieces
    - `floor` - lower tan/orange floor perspective pieces
    - `wall` - blue/gray wall pieces and vertical side structures

    Dark outline pixels adjacent to each surface are retained so chunks keep the
    arcade pixel-art edges. Black void pixels are treated as empty background.

    Files:

    - `environment_surface_chunks_atlas.png` - packed atlas image
    - `environment_surface_chunks_atlas.json` - atlas rectangles and source references
    - `environment_surface_chunks_atlas.csv` - spreadsheet-friendly atlas rectangles
    - `environment_surface_chunk_summary.csv` - count and size summary by surface type
    - `chunks/` - individual deduped PNG chunks

    Current source images scanned: {sources.Count}
    Current unique chunks: {packedChunks.Count}

    Chunk counts:
    {string.Join(Environment.NewLine, typeSummary.Select(t => $"- {t.type}: {t.count}"))}

    This is an automated estimate of the amount of reusable wall/floor/ceiling art
    needed for corridor navigation. It is intentionally conservative: similar
    chunks that differ by even a few pixels remain separate until reviewed by hand.
    """);

Console.WriteLine($"Sources scanned: {sources.Count}");
Console.WriteLine($"Unique chunks: {packedChunks.Count}");
foreach (var entry in typeSummary)
    Console.WriteLine($"  {entry.type}: {entry.count}");
Console.WriteLine($"Atlas: {atlasPath}");

static string Rel(string root, string path)
{
    var rel = Path.GetRelativePath(root, path);
    return rel.Replace(Path.DirectorySeparatorChar, '/');
}

static string Q(string value) => $"\"{value.Replace("\"", "\"\"")}\"";

static bool IsVoid(Pixel p) => p.A == 0 || (p.R <= 12 && p.G <= 12 && p.B <= 18);

static bool IsFloorSeed(Pixel p, int y, int height)
{
    if (IsVoid(p)) return false;
    var lowerEnough = y >= height * 0.38;
    var tan = p.R >= 155 && p.G >= 95 && p.G <= 205 && p.B <= 140;
    var orange = p.R >= 185 && p.G >= 105 && p.B <= 115;
    return lowerEnough && (tan || orange);
}

static bool IsCeilingSeed(Pixel p, int y, int height)
{
    if (IsVoid(p)) return false;
    var upperEnough = y <= height * 0.36;
    var brown = p.R >= 70 && p.R <= 185 && p.G >= 45 && p.G <= 145 && p.B <= 105;
    var darkTrim = p.R >= 25 && p.R <= 95 && p.G >= 25 && p.G <= 95 && p.B >= 30 && p.B <= 115;
    return upperEnough && (brown || darkTrim);
}

static bool IsWallSeed(Pixel p)
{
    if (IsVoid(p)) return false;
    var blue = p.B >= 95 && p.B > p.R + 15;
    var coolGray = Math.Abs(p.R - p.G) <= 30 && Math.Abs(p.G - p.B) <= 45 && p.B >= 55 && p.R <= 150;
    var purpleShadow = p.B >= 65 && p.R >= 45 && p.R <= 125 && p.G <= 95;
    return blue || coolGray || purpleShadow;
}

static bool[] BuildMask(PixelImage image, string kind)
{
    var seed = new bool[image.Pixels.Length];
    var mask = new bool[image.Pixels.Length];
    for (var y = 0; y < image.Height; y++)
    {
        for (var x = 0; x < image.Width; x++)
        {
            var idx = y * image.Width + x;
            var p = image.Pixels[idx];
            seed[idx] = kind switch
            {
                "floor" => IsFloorSeed(p, y, image.Height),
                "ceiling" => IsCeilingSeed(p, y, image.Height),
                _ => IsWallSeed(p) && !IsFloorSeed(p, y, image.Height) && !IsCeilingSeed(p, y, image.Height),
            };
            mask[idx] = seed[idx];
        }
    }

    for (var pass = 0; pass < 2; pass++)
    {
        var next = (bool[])mask.Clone();
        for (var y = 0; y < image.Height; y++)
        {
            for (var x = 0; x < image.Width; x++)
            {
                var idx = y * image.Width + x;
                if (mask[idx]) continue;
                var p = image.Pixels[idx];
                if (IsVoid(p)) continue;
                var darkInk = p.R <= 45 && p.G <= 55 && p.B <= 75;
                if (!darkInk) continue;

                var near = false;
                for (var dy = -1; dy <= 1 && !near; dy++)
                for (var dx = -1; dx <= 1 && !near; dx++)
                {
                    if (dx == 0 && dy == 0) continue;
                    var nx = x + dx;
                    var ny = y + dy;
                    if (nx < 0 || ny < 0 || nx >= image.Width || ny >= image.Height) continue;
                    if (mask[ny * image.Width + nx]) near = true;
                }
                if (near) next[idx] = true;
            }
        }
        mask = next;
    }
    return mask;
}

static List<Component> FindComponents(bool[] mask, int width, int height, int minimumArea)
{
    var visited = new bool[mask.Length];
    var components = new List<Component>();
    var qx = new int[mask.Length];
    var qy = new int[mask.Length];
    var dxs = new[] { -1, 1, 0, 0 };
    var dys = new[] { 0, 0, -1, 1 };

    for (var sy = 0; sy < height; sy++)
    {
        for (var sx = 0; sx < width; sx++)
        {
            var start = sy * width + sx;
            if (visited[start] || !mask[start]) continue;
            visited[start] = true;
            var head = 0;
            var tail = 0;
            qx[tail] = sx;
            qy[tail] = sy;
            tail++;

            var minX = sx;
            var maxX = sx;
            var minY = sy;
            var maxY = sy;
            var area = 0;

            while (head < tail)
            {
                var x = qx[head];
                var y = qy[head];
                head++;
                area++;
                minX = Math.Min(minX, x);
                maxX = Math.Max(maxX, x);
                minY = Math.Min(minY, y);
                maxY = Math.Max(maxY, y);

                for (var i = 0; i < 4; i++)
                {
                    var nx = x + dxs[i];
                    var ny = y + dys[i];
                    if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
                    var n = ny * width + nx;
                    if (visited[n] || !mask[n]) continue;
                    visited[n] = true;
                    qx[tail] = nx;
                    qy[tail] = ny;
                    tail++;
                }
            }

            if (area >= minimumArea)
                components.Add(new Component(minX, minY, maxX - minX + 1, maxY - minY + 1, area));
        }
    }
    return components.OrderBy(c => c.Y).ThenBy(c => c.X).ToList();
}

static Bitmap MakeChunkBitmap(PixelImage source, bool[] mask, Component component)
{
    var bitmap = new Bitmap(component.Width, component.Height, PixelFormat.Format32bppArgb);
    var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    var bytes = new byte[data.Stride * data.Height];
    for (var y = 0; y < component.Height; y++)
    {
        for (var x = 0; x < component.Width; x++)
        {
            var sx = component.X + x;
            var sy = component.Y + y;
            var srcIdx = sy * source.Width + sx;
            var dstIdx = y * data.Stride + x * 4;
            if (!mask[srcIdx])
            {
                bytes[dstIdx + 3] = 0;
                continue;
            }
            var p = source.Pixels[srcIdx];
            bytes[dstIdx] = p.B;
            bytes[dstIdx + 1] = p.G;
            bytes[dstIdx + 2] = p.R;
            bytes[dstIdx + 3] = p.A;
        }
    }
    System.Runtime.InteropServices.Marshal.Copy(bytes, 0, data.Scan0, bytes.Length);
    bitmap.UnlockBits(data);
    return bitmap;
}

static string HashBitmap(Bitmap bitmap)
{
    var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    try
    {
        var bytes = new byte[data.Stride * data.Height + 8];
        BitConverter.GetBytes(bitmap.Width).CopyTo(bytes, 0);
        BitConverter.GetBytes(bitmap.Height).CopyTo(bytes, 4);
        System.Runtime.InteropServices.Marshal.Copy(data.Scan0, bytes, 8, data.Stride * data.Height);
        return Convert.ToHexString(SHA1.HashData(bytes)).ToLowerInvariant();
    }
    finally
    {
        bitmap.UnlockBits(data);
    }
}

readonly record struct SourceImage(string Path, string Kind);
readonly record struct Component(int X, int Y, int Width, int Height, int Area);
readonly record struct Pixel(byte R, byte G, byte B, byte A);

sealed class PixelImage
{
    public required int Width { get; init; }
    public required int Height { get; init; }
    public required Pixel[] Pixels { get; init; }

    public static PixelImage FromBitmap(Bitmap bitmap)
    {
        var clone = bitmap.PixelFormat == PixelFormat.Format32bppArgb
            ? bitmap
            : bitmap.Clone(new Rectangle(0, 0, bitmap.Width, bitmap.Height), PixelFormat.Format32bppArgb);
        var disposeClone = !ReferenceEquals(clone, bitmap);
        try
        {
            var data = clone.LockBits(new Rectangle(0, 0, clone.Width, clone.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                var bytes = new byte[data.Stride * data.Height];
                System.Runtime.InteropServices.Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
                var pixels = new Pixel[clone.Width * clone.Height];
                for (var y = 0; y < clone.Height; y++)
                {
                    for (var x = 0; x < clone.Width; x++)
                    {
                        var idx = y * data.Stride + x * 4;
                        pixels[y * clone.Width + x] = new Pixel(bytes[idx + 2], bytes[idx + 1], bytes[idx], bytes[idx + 3]);
                    }
                }
                return new PixelImage { Width = clone.Width, Height = clone.Height, Pixels = pixels };
            }
            finally
            {
                clone.UnlockBits(data);
            }
        }
        finally
        {
            if (disposeClone) clone.Dispose();
        }
    }
}

sealed class ChunkRecord
{
    public int index { get; set; }
    public string name { get; set; } = "";
    public string type { get; set; } = "";
    public int width { get; set; }
    public int height { get; set; }
    public int atlas_x { get; set; }
    public int atlas_y { get; set; }
    public int atlas_w { get; set; }
    public int atlas_h { get; set; }
    public string source_kind { get; set; } = "";
    public string source { get; set; } = "";
    public int source_crop_x { get; set; }
    public int source_crop_y { get; set; }
    public int source_component { get; set; }
    public int source_x { get; set; }
    public int source_y { get; set; }
    public int source_w { get; set; }
    public int source_h { get; set; }
    public int area { get; set; }
    public int source_count { get; set; }
    public string hash { get; set; } = "";
    public string image { get; set; } = "";
}
