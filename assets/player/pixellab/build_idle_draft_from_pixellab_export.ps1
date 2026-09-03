# Build a row-major draft PNG (256x320, 8 cols x 5 rows of 32x64 cells - same
# canvas as preview_player.png) from a raw PixelLab export folder that only
# has Idle/rotations/<dir>.png (64x64) per direction - no walk animation
# frames. Only row0 (cols0-3 = south/west/east/north idle) gets filled; the
# rest of the canvas stays transparent, so the file stays directly comparable/
# overlay-able with preview_player.png and other drafts.
#
# Usage: powershell -File build_idle_draft_from_pixellab_export.ps1 -SourceDir <path> -OutPath <path>
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

Add-Type -AssemblyName System.Drawing

$IdleColMap = @{ "south" = 0; "west" = 1; "east" = 2; "north" = 3 }
$Dirs = @("south", "west", "east", "north")
$CellW = 32
$CellH = 64
$IdleCropRect = New-Object System.Drawing.Rectangle 16, 0, 32, 64

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
}

$g.Dispose()

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

Write-Host "Built idle-only draft -> $OutPath"
