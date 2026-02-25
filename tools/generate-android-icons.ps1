param(
    [string]$ProjectDir = "NoRKN.Android"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function New-RoundedPath {
    param(
        [System.Drawing.RectangleF]$Rect,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2

    $arc = New-Object System.Drawing.RectangleF($Rect.X, $Rect.Y, $d, $d)
    $path.AddArc($arc, 180, 90)
    $arc.X = $Rect.Right - $d
    $path.AddArc($arc, 270, 90)
    $arc.Y = $Rect.Bottom - $d
    $path.AddArc($arc, 0, 90)
    $arc.X = $Rect.Left
    $path.AddArc($arc, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-NoRknIcon {
    param(
        [int]$PixelSize,
        [string]$OutPath
    )

    $bmp = New-Object System.Drawing.Bitmap($PixelSize, $PixelSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.Clear([System.Drawing.Color]::Transparent)

            $bounds = New-Object System.Drawing.RectangleF(0, 0, ($PixelSize - 1), ($PixelSize - 1))
            $r = [Math]::Max(2.0, $PixelSize * 0.30)
            $bgPath = New-RoundedPath -Rect $bounds -Radius $r
            try {
                $red = [System.Drawing.Color]::FromArgb(211, 47, 47)
                $redBrush = New-Object System.Drawing.SolidBrush($red)
                try {
                    $g.FillPath($redBrush, $bgPath)
                } finally {
                    $redBrush.Dispose()
                }
            } finally {
                $bgPath.Dispose()
            }

            $circleMargin = $PixelSize * 0.125
            $circleRect = New-Object System.Drawing.RectangleF(
                $circleMargin,
                $circleMargin,
                ($PixelSize - ($circleMargin * 2)),
                ($PixelSize - ($circleMargin * 2))
            )
            $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            try {
                $g.FillEllipse($whiteBrush, $circleRect)
            } finally {
                $whiteBrush.Dispose()
            }

            $iconMargin = $PixelSize * 0.175
            $iconRect = New-Object System.Drawing.RectangleF(
                $iconMargin,
                $iconMargin,
                ($PixelSize - ($iconMargin * 2)),
                ($PixelSize - ($iconMargin * 2))
            )
            $sx = $iconRect.Width / 1024.0
            $sy = $iconRect.Height / 1024.0

            function P {
                param([float]$x, [float]$y, [System.Drawing.RectangleF]$rect, [double]$sxp, [double]$syp)
                return New-Object System.Drawing.PointF(($rect.Left + ($x * $sxp)), ($rect.Top + ($y * $syp)))
            }

            $p1 = @(
                (P 765.748 167.568 $iconRect $sx $sy),
                (P 598.331 0.151 $iconRect $sx $sy),
                (P 425.5 0 $iconRect $sx $sy),
                (P 0 425.5 $iconRect $sx $sy),
                (P 0 598.5 $iconRect $sx $sy),
                (P 167.4 765.915 $iconRect $sx $sy),
                (P 295.753 637.563 $iconRect $sx $sy),
                (P 170.191 512 $iconRect $sx $sy),
                (P 512 170.191 $iconRect $sx $sy),
                (P 637.563 295.753 $iconRect $sx $sy)
            )

            $p2 = @(
                (P 512.9 339.5 $iconRect $sx $sy),
                (P 685.9 512.5 $iconRect $sx $sy),
                (P 512.5 685.9 $iconRect $sx $sy),
                (P 339.5 512.9 $iconRect $sx $sy)
            )

            $p3 = @(
                (P 258.252 856.432 $iconRect $sx $sy),
                (P 425.669 1023.85 $iconRect $sx $sy),
                (P 598.499 1024.02 $iconRect $sx $sy),
                (P 1024.02 598.5 $iconRect $sx $sy),
                (P 1024.02 425.5 $iconRect $sx $sy),
                (P 856.6 258.085 $iconRect $sx $sy),
                (P 728.247 386.437 $iconRect $sx $sy),
                (P 853.809 512 $iconRect $sx $sy),
                (P 512 853.809 $iconRect $sx $sy),
                (P 386.437 728.247 $iconRect $sx $sy)
            )

            $blackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
            try {
                $g.FillPolygon($blackBrush, $p1)
                $g.FillPolygon($blackBrush, $p2)
                $g.FillPolygon($blackBrush, $p3)
            } finally {
                $blackBrush.Dispose()
            }

            $outDir = Split-Path -Path $OutPath -Parent
            if (-not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir | Out-Null
            }
            $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $g.Dispose()
        }
    } finally {
        $bmp.Dispose()
    }
}

$densities = @(
    [pscustomobject]@{ Folder = "mipmap-mdpi"; Pixels = 48  },
    [pscustomobject]@{ Folder = "mipmap-hdpi"; Pixels = 72  },
    [pscustomobject]@{ Folder = "mipmap-xhdpi"; Pixels = 96  },
    [pscustomobject]@{ Folder = "mipmap-xxhdpi"; Pixels = 144 },
    [pscustomobject]@{ Folder = "mipmap-xxxhdpi"; Pixels = 192 }
)

foreach ($d in $densities) {
    $folder = Join-Path $ProjectDir ("Resources\" + $d.Folder)
    Draw-NoRknIcon -PixelSize ([int]$d.Pixels) -OutPath (Join-Path $folder "ic_launcher.png")
    Draw-NoRknIcon -PixelSize ([int]$d.Pixels) -OutPath (Join-Path $folder "ic_launcher_round.png")
}

Write-Host "Android icons generated from NoRKN logo."
