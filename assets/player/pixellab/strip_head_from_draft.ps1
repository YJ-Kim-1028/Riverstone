# Makes rows 0..(CutoffY-1) of every 32x64 cell in a row-major draft (256x320,
# 8 cols x 5 rows) fully transparent - used to remove a baked-in head/face so
# an outfit draft becomes a pure below-the-neck overlay (matches the
# established head/collar boundary at y=24, verified on clothes/plain and
# clothes/plain2's silhouette).
#
# Usage: powershell -File strip_head_from_draft.ps1 -DraftPath <path> -CutoffY 24
param(
    [Parameter(Mandatory = $true)]
    [string]$DraftPath,
    [int]$CutoffY = 24
)

Add-Type -AssemblyName System.Drawing

$backupPath = $DraftPath -replace '\.png$', '_with_head.png'
Copy-Item $DraftPath $backupPath -Force
Write-Host "Backed up original (with head) -> $backupPath"

$rawImg = [System.Drawing.Bitmap]::new((Resolve-Path $DraftPath).Path)
$img = $rawImg.Clone([System.Drawing.Rectangle]::new(0, 0, $rawImg.Width, $rawImg.Height), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$rawImg.Dispose()
$CellH = 64
$rows = [Math]::Ceiling($img.Height / $CellH)

for ($r = 0; $r -lt $rows; $r++) {
    $cellTop = $r * $CellH
    for ($y = $cellTop; $y -lt ($cellTop + $CutoffY); $y++) {
        for ($x = 0; $x -lt $img.Width; $x++) {
            $img.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        }
    }
}

$outPath = Join-Path (Get-Location) $DraftPath
$stream = New-Object System.IO.MemoryStream
$img.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
$bytes = $stream.ToArray()
$stream.Dispose()
$img.Dispose()

# OneDrive can transiently lock the file right after Copy-Item syncs the
# backup - retry a few times instead of failing outright.
$attempt = 0
while ($true) {
    try {
        [System.IO.File]::WriteAllBytes($outPath, $bytes)
        break
    } catch {
        $attempt++
        if ($attempt -ge 5) { throw }
        Start-Sleep -Milliseconds 500
    }
}
Write-Host "Stripped head (rows 0-$($CutoffY-1) of each cell) -> $DraftPath"
