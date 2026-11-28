# Draws the CurseForge project avatar (400x400 PNG): a red target reticle
# with the addon's red flag in the middle, on a dark gradient.
# Usage (Windows PowerShell): powershell -File tools/make_avatar.ps1 [out.png]
param([string]$Out = "docs/curseforge/avatar.png")

Add-Type -AssemblyName System.Drawing
$S = 400
$bmp = New-Object System.Drawing.Bitmap $S, $S
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

function Rgb($r, $gg, $b, $a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $gg, $b) }

# Background: dark radial gradient.
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddEllipse(-120, -120, $S + 240, $S + 240)
$bg = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
$bg.CenterColor = Rgb 44 22 28
$bg.SurroundColors = @(Rgb 10 11 15)
$g.FillRectangle($bg, 0, 0, $S, $S)

$c = $S / 2
$red = Rgb 226 52 52
$dim = Rgb 226 52 52 70

# Faint radar rings and sweep.
$ringPen = New-Object System.Drawing.Pen $dim, 2
foreach ($r in 168, 120) { $g.DrawEllipse($ringPen, $c - $r, $c - $r, 2 * $r, 2 * $r) }
$sweep = New-Object System.Drawing.SolidBrush (Rgb 226 52 52 28)
$g.FillPie($sweep, $c - 168, $c - 168, 336, 336, -90, 60)

# Reticle: main ring with four ticks pointing inwards.
$pen = New-Object System.Drawing.Pen $red, 14
$r = 140
$g.DrawEllipse($pen, $c - $r, $c - $r, 2 * $r, 2 * $r)
$tick = New-Object System.Drawing.Pen $red, 14
$tick.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$tick.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($tick, $c, $c - 186, $c, $c - 104)
$g.DrawLine($tick, $c, $c + 186, $c, $c + 104)
$g.DrawLine($tick, $c - 186, $c, $c - 104, $c)
$g.DrawLine($tick, $c + 186, $c, $c + 104, $c)

# Blips: other players nearby.
$blip = New-Object System.Drawing.SolidBrush (Rgb 240 240 240 150)
foreach ($p in @(@(96, 118), @(300, 286), @(118, 300))) { $g.FillEllipse($blip, $p[0] - 7, $p[1] - 7, 14, 14) }

# Flag in the centre: pole and a waving red pennant.
$pole = New-Object System.Drawing.SolidBrush (Rgb 235 235 235)
$g.FillRectangle($pole, $c - 30, $c - 62, 10, 128)
$flag = New-Object System.Drawing.Drawing2D.GraphicsPath
$flag.AddBezier($c - 20, $c - 60, $c + 10, $c - 76, $c + 30, $c - 44, $c + 62, $c - 56)
$flag.AddLine($c + 62, $c - 56, $c + 62, $c + 4)
$flag.AddBezier($c + 62, $c + 4, $c + 30, $c + 16, $c + 10, $c - 16, $c - 20, $c)
$flag.CloseFigure()
$flagBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point ($c - 20), 0), (New-Object System.Drawing.Point ($c + 62), 0), (Rgb 255 70 70), (Rgb 170 24 30)
$g.FillPath($flagBrush, $flag)
$g.FillEllipse($pole, $c - 32, $c - 72, 14, 14)

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save((Join-Path (Get-Location) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "wrote $Out"
