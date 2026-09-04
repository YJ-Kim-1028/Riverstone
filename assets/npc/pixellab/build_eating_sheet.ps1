# Builds a simple horizontal-strip eating sprite sheet (32x64 per frame,
# south-facing only) from a raw multi-frame PixelLab GIF export. Handles
# source canvases of any square size (each NPC's raw GIF export ended up a
# different size - 64x64, 84x84, 60x60 etc.) by centering a 32-wide crop
# horizontally and bottom-anchoring a 64-tall crop vertically (padding
# transparent space at the top if the source is shorter than 64) - matches
# how a standing/sitting character's feet are usually near the bottom of the
# raw canvas, same reasoning as the player pipeline's IdleCropRect.
#
# Usage: powershell -File build_eating_sheet.ps1 -SourceGif <path> -OutPath <path>
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceGif,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

Add-Type -AssemblyName System.Drawing

$CellW = 32
$CellH = 64

$gif = [System.Drawing.Image]::FromFile((Resolve-Path $SourceGif).Path)
$dim = New-Object System.Drawing.Imaging.FrameDimension($gif.FrameDimensionsList[0])
$frameCount = $gif.GetFrameCount($dim)

$out = New-Object System.Drawing.Bitmap ($CellW * $frameCount), $CellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($out)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

for ($f = 0; $f -lt $frameCount; $f++) {
    $gif.SelectActiveFrame($dim, $f)
    $frameBmp = New-Object System.Drawing.Bitmap $gif.Width, $gif.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $fg = [System.Drawing.Graphics]::FromImage($frameBmp)
    $fg.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $fg.DrawImageUnscaled($gif, 0, 0)
    $fg.Dispose()

    $srcW = $frameBmp.Width
    $srcH = $frameBmp.Height
    $cropX = [Math]::Max(0, [int](($srcW - $CellW) / 2))
    $cropW = [Math]::Min($CellW, $srcW)
    if ($srcH -gt $CellH) {
        # 64보다 큰 원본(지금까지 실제로는 84뿐)은 하단 정렬이 아니라 플레이어
        # 파이프라인의 WalkCropRect와 같은 y=10 고정 오프셋을 쓴다 - 벨제로
        # 실측해본 결과, 하단 정렬(84-64=20)은 모자 윗부분이 그 위(13~19행)에
        # 있어서 잘려나갔다(사용자 리포트, 2026-09-05 - "모자 위가 잘려서
        # 보여"). 정상 idle 시트는 캐릭터 윗부분이 프레임 2행 부근에서
        # 시작하는데, y=10으로 자르면 그것과 거의 같은 위치(13-10=3행 부근)에
        # 맞아떨어진다.
        $cropY = [Math]::Min(10, $srcH - $CellH)
        $cropH = $CellH
        $destY = 0
    } else {
        $cropY = 0
        $cropH = $srcH
        $destY = $CellH - $srcH
    }
    $cropRect = New-Object System.Drawing.Rectangle $cropX, $cropY, $cropW, $cropH
    $cropped = $frameBmp.Clone($cropRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $frameBmp.Dispose()

    $destX = $f * $CellW + [Math]::Max(0, [int](($CellW - $cropW) / 2))
    $g.DrawImageUnscaled($cropped, $destX, $destY)
    $cropped.Dispose()
}
$g.Dispose()
$gif.Dispose()

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

Write-Host "Built eating sheet ($frameCount frames) -> $OutPath"
