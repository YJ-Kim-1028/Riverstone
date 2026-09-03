# Makes skin/scalp-toned pixels transparent (leaves hair-colored pixels and
# near-black outline/shading intact) - for previewing a "hair only" version
# of a with_skin PixelLab export. Skin tone is detected by hue/saturation/
# lightness range (typical peach/tan/brown skin sits at hue ~5-45 deg), not a
# fixed color list, so it works across different base skin tones. Very dark
# pixels (lightness < 0.12) are always kept, since those are almost always
# hair strands/outline rather than skin.
#
# Usage: powershell -File strip_skin_tone.ps1 -InPath <path> -OutPath <path>
param(
    [Parameter(Mandatory = $true)]
    [string]$InPath,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

Add-Type -AssemblyName System.Drawing

$SkinHueMin = 5.0
$SkinHueMax = 45.0
$SkinSatMin = 0.03
$SkinSatMax = 0.65
$SkinLightMin = 0.12
$SkinLightMax = 0.98

$src = [System.Drawing.Bitmap]::new((Resolve-Path $InPath).Path)
$out = New-Object System.Drawing.Bitmap $src.Width, $src.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

for ($y = 0; $y -lt $src.Height; $y++) {
    for ($x = 0; $x -lt $src.Width; $x++) {
        $c = $src.GetPixel($x, $y)
        if ($c.A -eq 0) {
            continue
        }
        $hue = $c.GetHue()
        $sat = $c.GetSaturation()
        $light = $c.GetBrightness()
        $isSkin = ($hue -ge $SkinHueMin -and $hue -le $SkinHueMax) `
            -and ($sat -ge $SkinSatMin -and $sat -le $SkinSatMax) `
            -and ($light -ge $SkinLightMin -and $light -le $SkinLightMax)
        if (-not $isSkin) {
            $out.SetPixel($x, $y, $c)
        }
    }
}
$src.Dispose()

for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        $ms = New-Object System.IO.MemoryStream
        $out.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        [System.IO.File]::WriteAllBytes((Join-Path (Get-Location) $OutPath), $ms.ToArray())
        $ms.Dispose()
        break
    } catch {
        if ($attempt -eq 5) { throw }
        Start-Sleep -Milliseconds 500
    }
}
$out.Dispose()

Write-Host "Stripped skin tone -> $OutPath"
