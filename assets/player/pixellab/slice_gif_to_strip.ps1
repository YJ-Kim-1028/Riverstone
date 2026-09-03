# Slice an animated GIF into its frames and lay them out side by side in one PNG strip.
# Optionally crops each frame to the actual in-engine region (default: the established
# WalkCropRect 26,10,32,64 used to turn 84x84 PixelLab walk-GIF frames into 32x64
# engine frames). Pass -NoCrop to keep the raw uncropped frame instead.
#
# Usage: powershell -File slice_gif_to_strip.ps1 -GifPath <path> -OutPath <path>
#        powershell -File slice_gif_to_strip.ps1 -GifPath <path> -OutPath <path> -NoCrop
param(
    [Parameter(Mandatory = $true)]
    [string]$GifPath,
    [Parameter(Mandatory = $true)]
    [string]$OutPath,
    [switch]$NoCrop,
    [int]$CropX = 26,
    [int]$CropY = 10,
    [int]$CropW = 32,
    [int]$CropH = 64
)

Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile((Resolve-Path $GifPath).Path)
$dim = New-Object System.Drawing.Imaging.FrameDimension($src.FrameDimensionsList[0])
$frameCount = $src.GetFrameCount($dim)

$rawW = $src.Width
$rawH = $src.Height

if ($NoCrop) {
    $outFrameW = $rawW
    $outFrameH = $rawH
} else {
    $outFrameW = $CropW
    $outFrameH = $CropH
}

$out = New-Object System.Drawing.Bitmap ($outFrameW * $frameCount), $outFrameH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($out)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

for ($i = 0; $i -lt $frameCount; $i++) {
    $src.SelectActiveFrame($dim, $i)
    $rawBmp = New-Object System.Drawing.Bitmap $rawW, $rawH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $fg = [System.Drawing.Graphics]::FromImage($rawBmp)
    $fg.DrawImageUnscaled($src, 0, 0)
    $fg.Dispose()

    if ($NoCrop) {
        $g.DrawImageUnscaled($rawBmp, $i * $outFrameW, 0)
    } else {
        $cropRect = New-Object System.Drawing.Rectangle $CropX, $CropY, $CropW, $CropH
        $cropped = $rawBmp.Clone($cropRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g.DrawImageUnscaled($cropped, $i * $outFrameW, 0)
        $cropped.Dispose()
    }
    $rawBmp.Dispose()
}

$g.Dispose()
$out.Save((Join-Path (Get-Location) $OutPath), [System.Drawing.Imaging.ImageFormat]::Png)
$out.Dispose()
$src.Dispose()

Write-Host "Sliced $frameCount frames -> $OutPath ($outFrameW x $outFrameH each, crop=$(-not $NoCrop))"
