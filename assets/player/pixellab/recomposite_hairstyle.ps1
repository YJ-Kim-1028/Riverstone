# Rebuild the engine-facing player_hd_<style>.png (1152x64, [south west east north]
# groups x [idle + 8 walk] columns) from a hand-edited hair-only draft
# basic_hair/<style>/preview_player_<style>.png (256x320, 8 cols x 5 rows of 32x64 cells:
# row0 = idle strip, cols 0-3 = south/west/east/north; row1..4 = west/east/south/north
# walk cycles), composited onto the canonical body frames.
#
# Usage: powershell -File recomposite_hairstyle.ps1 -Style bun
#        powershell -File recomposite_hairstyle.ps1 -Style bun -DraftFileName preview_player_bun_with_skin.png
# Run from the project root (uses relative paths).
param(
    [Parameter(Mandatory = $true)]
    [string]$Style,
    [string]$DraftFileName = ""
)

Add-Type -AssemblyName System.Drawing

$IdleColMap = @{ "south" = 0; "west" = 1; "east" = 2; "north" = 3 }
$WalkRowMap = @{ "west" = 1; "east" = 2; "south" = 3; "north" = 4 }
$GroupOrder = @("south", "west", "east", "north")
$CellW = 32
$CellH = 64

function Get-Cell {
    param([System.Drawing.Bitmap]$Bitmap, [int]$Col, [int]$Row)
    $rect = New-Object System.Drawing.Rectangle ($Col * $CellW), ($Row * $CellH), $CellW, $CellH
    return $Bitmap.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Composite-Cell {
    param([System.Drawing.Bitmap]$Body, [System.Drawing.Bitmap]$Hair)
    $canvas = New-Object System.Drawing.Bitmap $CellW, $CellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.DrawImageUnscaled($Body, 0, 0)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $g.DrawImageUnscaled($Hair, 0, 0)
    $g.Dispose()
    return $canvas
}

$draftFile = if ($DraftFileName -ne "") { $DraftFileName } else { "preview_player_$Style.png" }
$hairDraftPath = "assets/player/pixellab/basic_hair/$Style/$draftFile"
$outPath = "assets/player/pixellab/player_hd_$Style.png"
$backupPath = "assets/player/pixellab/player_hd_${Style}_old.png"

if (-not (Test-Path $hairDraftPath)) {
    Write-Error "Hair draft not found: $hairDraftPath"
    exit 1
}

if (Test-Path $outPath) {
    Copy-Item $outPath $backupPath -Force
    Write-Host "Backed up existing $outPath -> $backupPath"
}

$hairDraft = [System.Drawing.Bitmap]::new((Resolve-Path $hairDraftPath).Path)

# Load per-direction idle body (64x64 cropped to 32x64) and walk body (256x64, 8 frames of 32x64)
$idleBody = @{}
$walkBody = @{}
foreach ($dir in $GroupOrder) {
    $rawIdle = [System.Drawing.Bitmap]::new((Resolve-Path "assets/player/pixellab/body/$dir.png").Path)
    $idleCropRect = New-Object System.Drawing.Rectangle 16, 0, 32, 64
    $idleBody[$dir] = $rawIdle.Clone($idleCropRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rawIdle.Dispose()
    $walkBody[$dir] = [System.Drawing.Bitmap]::new((Resolve-Path "assets/player/pixellab/preview_walk_$dir.png").Path)
}

$out = New-Object System.Drawing.Bitmap (9 * $CellW * 4), $CellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$og = [System.Drawing.Graphics]::FromImage($out)
$og.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

for ($gi = 0; $gi -lt $GroupOrder.Count; $gi++) {
    $dir = $GroupOrder[$gi]
    $groupX = $gi * 9 * $CellW

    # col0: idle
    $hairIdleCell = Get-Cell -Bitmap $hairDraft -Col $IdleColMap[$dir] -Row 0
    $idleFrame = Composite-Cell -Body $idleBody[$dir] -Hair $hairIdleCell
    $og.DrawImageUnscaled($idleFrame, $groupX, 0)
    $hairIdleCell.Dispose()
    $idleFrame.Dispose()

    # col1..8: 8 walk frames
    $walkRow = $WalkRowMap[$dir]
    for ($k = 0; $k -lt 8; $k++) {
        $bodyFrame = $walkBody[$dir].Clone((New-Object System.Drawing.Rectangle ($k * $CellW), 0, $CellW, $CellH), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $hairCell = Get-Cell -Bitmap $hairDraft -Col $k -Row $walkRow
        $walkFrame = Composite-Cell -Body $bodyFrame -Hair $hairCell
        $og.DrawImageUnscaled($walkFrame, $groupX + (1 + $k) * $CellW, 0)
        $bodyFrame.Dispose()
        $hairCell.Dispose()
        $walkFrame.Dispose()
    }
}

$og.Dispose()
$out.Save((Join-Path (Get-Location) $outPath), [System.Drawing.Imaging.ImageFormat]::Png)
$out.Dispose()
$hairDraft.Dispose()
foreach ($dir in $GroupOrder) {
    $idleBody[$dir].Dispose()
    $walkBody[$dir].Dispose()
}

Write-Host "Rebuilt $outPath from $hairDraftPath"
