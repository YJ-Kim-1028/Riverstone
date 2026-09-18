# NPC의 걷기/정지 스프라이트 시트(npc_sprite.gd가 기대하는 레이아웃 - 방향
# 4개(DOWN/LEFT/RIGHT/UP=south/west/east/north 순서), 방향마다 [정지 1칸,
# 걷기 N칸])를 PixelLab 원본 재수출(Idle/rotations/<dir>.png=정지,
# Idle/animations/Walking/<dir>/frame_NNN.png=걷기)로부터 다시 조립한다.
# 지금까지는 이 조립을 스크립트 없이 수작업으로 했는데, 마린 재수출
# (2026-09-14 - "마린 이미지 바꿨는데 다시 임포트해줭 지금 예전거로 되어있다")
# 처럼 나중에 다른 NPC도 원본을 재수출하면 또 같은 수작업이 필요할 것 같아서
# 재사용 가능한 스크립트로 만들었다. 원본 캔버스 크기가 정지(64x64)와 걷기
# (84x84/88x88 등)가 서로 다른 문제는 build_eating_sheet.ps1이 이미 겪고
# 해결한 것과 완전히 같은 문제라 그 크롭 로직을 그대로 재사용한다(가로 32px
# 중앙 정렬 + 세로 64px, 원본이 64보다 크면 y=10 고정 오프셋 크롭, 64 이하면
# 하단 정렬) - "정상 idle 시트가 이미 이 규칙으로 만들어져 있다"는
# build_eating_sheet.ps1의 전제와 이번 작업이 서로를 검증해준다(정지 프레임
# 원본이 64x64=CellH와 정확히 같아서 y 크롭이 전혀 안 걸리는 것도 일치).
#
# Usage: powershell -File build_walking_sheet.ps1 -NpcDir <path to
#   assets/npc/pixellab/<npc_id>> -OutPath <path to assets/npc/sprite/<npc>Sprite.png>
param(
    [Parameter(Mandatory = $true)]
    [string]$NpcDir,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

Add-Type -AssemblyName System.Drawing

$CellW = 32
$CellH = 64
$Directions = @("south", "west", "east", "north")

function Get-CroppedCell($srcPath) {
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $srcPath).Path)
    $bmp = New-Object System.Drawing.Bitmap $img.Width, $img.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.DrawImageUnscaled($img, 0, 0)
    $g.Dispose()
    $img.Dispose()

    $srcW = $bmp.Width
    $srcH = $bmp.Height
    $cropX = [Math]::Max(0, [int](($srcW - $CellW) / 2))
    $cropW = [Math]::Min($CellW, $srcW)
    if ($srcH -gt $CellH) {
        $cropY = [Math]::Min(10, $srcH - $CellH)
        $cropH = $CellH
        $destY = 0
    } else {
        $cropY = 0
        $cropH = $srcH
        $destY = $CellH - $srcH
    }
    $cropRect = New-Object System.Drawing.Rectangle $cropX, $cropY, $cropW, $cropH
    $cropped = $bmp.Clone($cropRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.Dispose()
    return @{ Bitmap = $cropped; DestX = [Math]::Max(0, [int](($CellW - $cropW) / 2)); DestY = $destY }
}

# 방향마다 [정지 1장] + [Walking/<dir>/frame_*.png 전부, 오름차순]을 모은다.
$cellSources = @()
foreach ($dir in $Directions) {
    $cellSources += (Join-Path $NpcDir "Idle\rotations\$dir.png")
    $walkDir = Join-Path $NpcDir "Idle\animations\Walking\$dir"
    $walkFrames = Get-ChildItem -Path $walkDir -Filter "frame_*.png" | Sort-Object Name
    foreach ($f in $walkFrames) {
        $cellSources += $f.FullName
    }
}

$out = New-Object System.Drawing.Bitmap ($CellW * $cellSources.Count), $CellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($out)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

for ($i = 0; $i -lt $cellSources.Count; $i++) {
    $cell = Get-CroppedCell $cellSources[$i]
    $destX = $i * $CellW + $cell.DestX
    $g.DrawImageUnscaled($cell.Bitmap, $destX, $cell.DestY)
    $cell.Bitmap.Dispose()
}
$g.Dispose()

for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        $ms = New-Object System.IO.MemoryStream
        $out.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        [System.IO.File]::WriteAllBytes($OutPath, $ms.ToArray())
        $ms.Dispose()
        break
    } catch {
        if ($attempt -eq 5) { throw }
        Start-Sleep -Milliseconds 500
    }
}
$out.Dispose()

Write-Host "Built walking sheet ($($cellSources.Count) cells, $($Directions.Count) directions) -> $OutPath"
