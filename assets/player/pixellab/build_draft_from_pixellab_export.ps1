# Build a row-major draft PNG (256x320, 8 cols x 5 rows of 32x64 cells - same
# layout as preview_player.png / basic_hair drafts) from a raw PixelLab export
# folder that already has Idle/rotations/<dir>.png (64x64) and
# Idle/animations/Walking/<dir>/frame_00N.png (84x84, 8 frames) per direction.
# Row0 = idle strip (col0=south,col1=west,col2=east,col3=north).
# Row1..4 = west/east/south/north walk cycles (8 frames each).
#
# Usage: powershell -File build_draft_from_pixellab_export.ps1 -SourceDir <path> -OutPath <path>
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

Add-Type -AssemblyName System.Drawing

$IdleColMap = @{ "south" = 0; "west" = 1; "east" = 2; "north" = 3 }
$WalkRowMap = @{ "west" = 1; "east" = 2; "south" = 3; "north" = 4 }
$Dirs = @("south", "west", "east", "north")
$CellW = 32
$CellH = 64
$IdleCropRect = New-Object System.Drawing.Rectangle 16, 0, 32, 64
$WalkCropRect = New-Object System.Drawing.Rectangle 26, 10, 32, 64

$out = New-Object System.Drawing.Bitmap ($CellW * 8), ($CellH * 5), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($out)
$g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy

foreach ($dir in $Dirs) {
    $idlePath = Join-Path $SourceDir "Idle/rotations/$dir.png"
    $rawIdle = [System.Drawing.Bitmap]::new((Resolve-Path $idlePath).Path)
    $idleCell = $rawIdle.Clone($IdleCropRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rawIdle.Dispose()
    $g.DrawImageUnscaled($idleCell, $IdleColMap[$dir] * $CellW, 0)
    $idleCell.Dispose()

    $walkRow = $WalkRowMap[$dir]
    for ($k = 0; $k -lt 8; $k++) {
        $framePath = Join-Path $SourceDir ("Idle/animations/Walking/$dir/frame_{0:D3}.png" -f $k)
        $rawFrame = [System.Drawing.Bitmap]::new((Resolve-Path $framePath).Path)
        $walkCell = $rawFrame.Clone($WalkCropRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $rawFrame.Dispose()
        $g.DrawImageUnscaled($walkCell, $k * $CellW, $walkRow * $CellH)
        $walkCell.Dispose()
    }
}

$g.Dispose()
$out.Save((Join-Path (Get-Location) $OutPath), [System.Drawing.Imaging.ImageFormat]::Png)
$out.Dispose()

Write-Host "Built draft -> $OutPath"
