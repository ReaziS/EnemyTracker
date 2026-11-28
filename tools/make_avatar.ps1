# Draws the CurseForge project avatar (400x400 PNG): the monogram "ET",
# a light E and a red T inside a thin red ring, on a dark background.
# Usage (Windows PowerShell): powershell -File tools/make_avatar.ps1 [out.png]
param([string]$Out = "docs/curseforge/avatar.png")

Add-Type -AssemblyName System.Drawing
$S = 400
function Rgb($r, $g, $b, $a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

$bmp = New-Object System.Drawing.Bitmap $S, $S
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.PixelOffsetMode = 'HighQuality'
$g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear((Rgb 17 19 24))

$font = New-Object System.Drawing.Font "Segoe UI Black", 210, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = 'Center'
$fmt.LineAlignment = 'Center'
$g.DrawString("E", $font, (New-Object System.Drawing.SolidBrush (Rgb 236 238 242)), (New-Object System.Drawing.RectangleF 22, 0, 220, 400), $fmt)
$g.DrawString("T", $font, (New-Object System.Drawing.SolidBrush (Rgb 228 56 56)), (New-Object System.Drawing.RectangleF 158, 0, 220, 400), $fmt)

# Thin ring around, like a scope.
$ring = New-Object System.Drawing.Pen (Rgb 228 56 56 90), 6
$g.DrawEllipse($ring, 24, 24, 352, 352)

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save((Join-Path (Get-Location) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "wrote $Out"
