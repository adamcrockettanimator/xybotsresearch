param(
    [Parameter(Mandatory = $true)]
    [string]$InputDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputPsd,

    [int]$CanvasWidth = 4096,

    [int]$CanvasHeight = 4096
)

$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;

public static class LayeredPsdFromPngs
{
    private sealed class Layer
    {
        public string Name = "";
        public int Width;
        public int Height;
        public byte[] R = Array.Empty<byte>();
        public byte[] G = Array.Empty<byte>();
        public byte[] B = Array.Empty<byte>();
        public byte[] A = Array.Empty<byte>();
    }

    public static void Build(string inputDir, string outputPsd, int requestedCanvasW, int requestedCanvasH)
    {
        string[] files = Directory.GetFiles(inputDir, "*.png").OrderBy(p => Path.GetFileName(p), StringComparer.OrdinalIgnoreCase).ToArray();
        if (files.Length == 0)
            throw new InvalidOperationException("No PNG files found in " + inputDir);

        List<Layer> layers = new List<Layer>(files.Length);
        int canvasW = Math.Max(1, requestedCanvasW);
        int canvasH = Math.Max(1, requestedCanvasH);

        foreach (string file in files)
        {
            using (Bitmap original = new Bitmap(file))
            using (Bitmap bitmap = new Bitmap(original.Width, original.Height, PixelFormat.Format32bppArgb))
            using (Graphics g = Graphics.FromImage(bitmap))
            {
                g.Clear(Color.Transparent);
                g.DrawImageUnscaled(original, 0, 0);

                Layer layer = new Layer();
                layer.Name = Path.GetFileName(file);
                layer.Width = bitmap.Width;
                layer.Height = bitmap.Height;
                int pixels = bitmap.Width * bitmap.Height;
                layer.R = new byte[pixels];
                layer.G = new byte[pixels];
                layer.B = new byte[pixels];
                layer.A = new byte[pixels];

                BitmapData data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                try
                {
                    int stride = data.Stride;
                    byte[] row = new byte[Math.Abs(stride)];
                    for (int y = 0; y < bitmap.Height; y++)
                    {
                        IntPtr ptr = IntPtr.Add(data.Scan0, y * stride);
                        Marshal.Copy(ptr, row, 0, row.Length);
                        for (int x = 0; x < bitmap.Width; x++)
                        {
                            int src = x * 4;
                            int dst = y * bitmap.Width + x;
                            layer.B[dst] = row[src + 0];
                            layer.G[dst] = row[src + 1];
                            layer.R[dst] = row[src + 2];
                            layer.A[dst] = row[src + 3];
                        }
                    }
                }
                finally
                {
                    bitmap.UnlockBits(data);
                }

                canvasW = Math.Max(canvasW, layer.Width);
                canvasH = Math.Max(canvasH, layer.Height);
                layers.Add(layer);
            }
        }

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPsd)) ?? ".");

        using (FileStream fs = File.Create(outputPsd))
        using (BinaryWriter bw = new BinaryWriter(fs, Encoding.ASCII))
        {
            WriteHeader(bw, canvasW, canvasH);
            WriteU32(bw, 0); // color mode data
            WriteImageResources(bw);
            WriteLayerMaskSection(bw, layers);
            WriteCompositeImage(bw, canvasW, canvasH);
        }
    }

    private static void WriteHeader(BinaryWriter bw, int width, int height)
    {
        WriteAscii(bw, "8BPS");
        WriteU16(bw, 1);
        bw.Write(new byte[6]);
        WriteU16(bw, 4); // RGB + transparency
        WriteU32(bw, (uint)height);
        WriteU32(bw, (uint)width);
        WriteU16(bw, 8);
        WriteU16(bw, 3); // RGB
    }

    private static void WriteImageResources(BinaryWriter bw)
    {
        WriteU32(bw, 0);
    }

    private static void WriteLayerMaskSection(BinaryWriter bw, List<Layer> layers)
    {
        using (MemoryStream layerInfo = new MemoryStream())
        using (BinaryWriter li = new BinaryWriter(layerInfo, Encoding.ASCII))
        {
            if (layers.Count > short.MaxValue)
                throw new InvalidOperationException("PSD layer count limit exceeded. Use fewer than 32768 layers.");

            WriteI16(li, (short)layers.Count);

            foreach (Layer layer in layers.AsEnumerable().Reverse())
                WriteLayerRecord(li, layer);

            foreach (Layer layer in layers.AsEnumerable().Reverse())
                WriteLayerChannelImageData(li, layer);

            using (MemoryStream section = new MemoryStream())
            using (BinaryWriter sec = new BinaryWriter(section, Encoding.ASCII))
            {
                WriteU32(sec, (uint)layerInfo.Length);
                sec.Write(layerInfo.ToArray());
                WriteU32(sec, 0); // global layer mask info length

                WriteU32(bw, (uint)section.Length);
                bw.Write(section.ToArray());
            }
        }
    }

    private static void WriteLayerRecord(BinaryWriter bw, Layer layer)
    {
        WriteU32(bw, 0);
        WriteU32(bw, 0);
        WriteU32(bw, (uint)layer.Height);
        WriteU32(bw, (uint)layer.Width);

        WriteU16(bw, 4);
        WriteChannelInfo(bw, 0, layer.R.Length);
        WriteChannelInfo(bw, 1, layer.G.Length);
        WriteChannelInfo(bw, 2, layer.B.Length);
        WriteChannelInfo(bw, -1, layer.A.Length);

        WriteAscii(bw, "8BIM");
        WriteAscii(bw, "norm");
        bw.Write((byte)255); // opacity
        bw.Write((byte)0);   // clipping
        bw.Write((byte)8);   // transparency protected flag off, visible
        bw.Write((byte)0);   // filler

        using (MemoryStream extra = new MemoryStream())
        using (BinaryWriter ex = new BinaryWriter(extra, Encoding.ASCII))
        {
            WriteU32(ex, 0); // layer mask data
            WriteU32(ex, 0); // layer blending ranges
            WritePascalString(ex, layer.Name);

            WriteU32(bw, (uint)extra.Length);
            bw.Write(extra.ToArray());
        }
    }

    private static void WriteChannelInfo(BinaryWriter bw, short id, int byteCount)
    {
        WriteI16(bw, id);
        WriteU32(bw, (uint)(2 + byteCount)); // 2-byte compression marker + raw channel bytes
    }

    private static void WriteLayerChannelImageData(BinaryWriter bw, Layer layer)
    {
        WriteRawChannel(bw, layer.R);
        WriteRawChannel(bw, layer.G);
        WriteRawChannel(bw, layer.B);
        WriteRawChannel(bw, layer.A);
    }

    private static void WriteRawChannel(BinaryWriter bw, byte[] data)
    {
        WriteU16(bw, 0); // raw
        bw.Write(data);
    }

    private static void WriteCompositeImage(BinaryWriter bw, int width, int height)
    {
        WriteU16(bw, 0); // raw
        byte[] zeros = new byte[width * height];
        bw.Write(zeros);
        bw.Write(zeros);
        bw.Write(zeros);
        bw.Write(zeros);
    }

    private static void WritePascalString(BinaryWriter bw, string text)
    {
        byte[] bytes = Encoding.ASCII.GetBytes(text);
        int count = Math.Min(255, bytes.Length);
        bw.Write((byte)count);
        bw.Write(bytes, 0, count);
        int total = 1 + count;
        int pad = (4 - (total % 4)) % 4;
        if (pad > 0)
            bw.Write(new byte[pad]);
    }

    private static void WriteAscii(BinaryWriter bw, string value)
    {
        bw.Write(Encoding.ASCII.GetBytes(value));
    }

    private static void WriteU16(BinaryWriter bw, ushort value)
    {
        bw.Write(new byte[] { (byte)(value >> 8), (byte)value });
    }

    private static void WriteI16(BinaryWriter bw, short value)
    {
        WriteU16(bw, unchecked((ushort)value));
    }

    private static void WriteU32(BinaryWriter bw, uint value)
    {
        bw.Write(new byte[] { (byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value });
    }
}
"@

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $source
[LayeredPsdFromPngs]::Build($InputDir, $OutputPsd, $CanvasWidth, $CanvasHeight)
Write-Host "Wrote $OutputPsd"
