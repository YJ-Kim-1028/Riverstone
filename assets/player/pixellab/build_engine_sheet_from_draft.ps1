# Convert an already-complete row-major draft (256x320, 8 cols x 5 rows of 32x64
# cells, body/skin already baked in - e.g. preview_player_<style>_with_skin.png)
# directly into the engine-facing column-major sheet (1152x64, [south west east
# north] groups x [idle + 8 walk]) - no separate body compositing needed, unlike
# recomposite_hairstyle.ps1 which overlays a hair-only draft onto a canonical body.
#
# Usage: powershell -File build_engine_sheet_from_draft.ps1 -DraftPath <path> -OutPath <path>
param(
    [Parameter(Mandatory = $true)]
    [string]$DraftPath,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

Add-Type -AssemblyName System.Drawing

$IdleColMap = @{ "south" = 0; "west" = 1; "east" = 2; "north" = 3 }
$WalkRowMap = @{ "west" = 1; "east" = 2; "south" = 3; "north" = 4 }
$GroupOrder = @("south", "west", "east", "north")
$CellW = 32
$CellH = 64

if (Test-Path $OutPath) {
    $backupPath = $OutPath -replace '\.png$', '_old.png'
    Copy-Item $OutPath $backupPath -Force
    Write-Host "Backed up existing $OutPath -> $backupPath"
}

$draft = [System.Drawing.Bitmap]::new((Resolve-Path $DraftPath).Path)
$out = New-Object System.Drawing.Bitmap ($CellW * 9 * 4), $CellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($out)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

for ($gi = 0; $gi -lt $GroupOrder.Count; $gi++) {
    $dir = $GroupOrder[$gi]
    $groupX = $gi * 9 * $CellW

    $idleRect = New-Object System.Drawing.Rectangle ($IdleColMap[$dir] * $CellW), 0, $CellW, $CellH
    $idleCell = $draft.Clone($idleRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g.DrawImageUnscaled($idleCell, $groupX, 0)
    $idleCell.Dispose()

    $walkRow = $WalkRowMap[$dir]
    for ($k = 0; $k -lt 8; $k++) {
        $walkRect = New-Object System.Drawing.Rectangle ($k * $CellW), ($walkRow * $CellH), $CellW, $CellH
        $walkCell = $draft.Clone($walkRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g.DrawImageUnscaled($walkCell, $groupX + (1 + $k) * $CellW, 0)
        $walkCell.Dispose()
    }
}

$g.Dispose()
$out.Save((Join-Path (Get-Location) $OutPath), [System.Drawing.Imaging.ImageFormat]::Png)
$out.Dispose()
$draft.Dispose()

Write-Host "Built engine sheet -> $OutPath"
