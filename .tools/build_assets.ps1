param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$IconSource = 'C:\Users\bl4ut\.gemini\antigravity\brain\f5b70e6f-c4f5-4029-8847-64e2166e4e5a\ulo_icon_1794694103079.jpg',
    [string]$BannerSource = 'C:\Users\bl4ut\.gemini\antigravity\brain\f5b70e6f-c4f5-4029-8847-64e2166e4e5a\ulo_banner_1794694121568.jpg'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-ResizedBitmap {
    param(
        [System.Drawing.Image]$SourceImage,
        [int]$Width,
        [int]$Height
    )

    $dest = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($dest)
    try {
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($SourceImage, 0, 0, $Width, $Height)
    }
    finally {
        $graphics.Dispose()
    }
    return $dest
}

function Write-UncompressedTga32 {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$OutputPath
    )

    $width = $Bitmap.Width
    $height = $Bitmap.Height

    $header = New-Object byte[] 18
    $header[2] = 2 # Uncompressed true-color image
    $header[12] = [byte]($width -band 0xFF)
    $header[13] = [byte](($width -shr 8) -band 0xFF)
    $header[14] = [byte]($height -band 0xFF)
    $header[15] = [byte](($height -shr 8) -band 0xFF)
    $header[16] = 32   # 32-bit BGRA
    $header[17] = 0x08 # 8-bit alpha, bottom-left origin

    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $bmpData = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = [Math]::Abs($bmpData.Stride)
        $rawSize = $stride * $height
        $rawBytes = New-Object byte[] $rawSize
        [System.Runtime.InteropServices.Marshal]::Copy($bmpData.Scan0, $rawBytes, 0, $rawSize)

        $dir = Split-Path -Parent $OutputPath
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $fs = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        try {
            $fs.Write($header, 0, $header.Length)
            $rowBytes = $width * 4
            # Write bottom-up rows (origin = bottom-left)
            for ($y = $height - 1; $y -ge 0; $y--) {
                $offset = $y * $stride
                $fs.Write($rawBytes, $offset, $rowBytes)
            }
        }
        finally {
            $fs.Dispose()
        }
    }
    finally {
        $Bitmap.UnlockBits($bmpData)
    }
}

$imagesDir = Join-Path $RepoRoot 'Images'
$mediaDir = Join-Path $RepoRoot 'ULO\Media'
New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null

$logoOut = Join-Path $imagesDir 'Logo.png'
$bannerOut = Join-Path $imagesDir 'Banner.png'

if (Test-Path $IconSource) {
    $srcIcon = [System.Drawing.Image]::FromFile($IconSource)
    try {
        $logoBmp = New-ResizedBitmap -SourceImage $srcIcon -Width 512 -Height 512
        try {
            $logoBmp.Save($logoOut, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $logoBmp.Dispose()
        }
    }
    finally {
        $srcIcon.Dispose()
    }
}
elseif (-not (Test-Path $logoOut)) {
    throw "Icon source not found at '$IconSource' and fallback '$logoOut' does not exist."
}

if (Test-Path $BannerSource) {
    $srcBanner = [System.Drawing.Image]::FromFile($BannerSource)
    try {
        $targetWidth = [Math]::Min(1280, $srcBanner.Width)
        $targetHeight = [int][Math]::Round($srcBanner.Height * ($targetWidth / [double]$srcBanner.Width))
        $bannerBmp = New-ResizedBitmap -SourceImage $srcBanner -Width $targetWidth -Height $targetHeight
        try {
            $bannerBmp.Save($bannerOut, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bannerBmp.Dispose()
        }
    }
    finally {
        $srcBanner.Dispose()
    }
}
elseif (-not (Test-Path $bannerOut)) {
    throw "Banner source not found at '$BannerSource' and fallback '$bannerOut' does not exist."
}

# Build ULOIcon.tga (64x64) and ULOMinimap.tga (64x64 circular alpha mask, radius 30px)
$logoImg = [System.Drawing.Image]::FromFile($logoOut)
try {
    $icon64 = New-ResizedBitmap -SourceImage $logoImg -Width 64 -Height 64
    try {
        Write-UncompressedTga32 -Bitmap $icon64 -OutputPath (Join-Path $mediaDir 'ULOIcon.tga')
    }
    finally {
        $icon64.Dispose()
    }

    $minimap64 = New-ResizedBitmap -SourceImage $logoImg -Width 64 -Height 64
    try {
        $cx = 31.5
        $cy = 31.5
        $radius = 30.0
        for ($y = 0; $y -lt 64; $y++) {
            for ($x = 0; $x -lt 64; $x++) {
                $dx = $x - $cx
                $dy = $y - $cy
                $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
                $px = $minimap64.GetPixel($x, $y)
                if ($dist -gt ($radius + 0.5)) {
                    $minimap64.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
                }
                elseif ($dist -gt ($radius - 0.5)) {
                    $fade = ($radius + 0.5) - $dist
                    $alpha = [int][Math]::Max(0, [Math]::Min(255, [Math]::Round($px.A * $fade)))
                    $minimap64.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $px.R, $px.G, $px.B))
                }
            }
        }
        Write-UncompressedTga32 -Bitmap $minimap64 -OutputPath (Join-Path $mediaDir 'ULOMinimap.tga')
    }
    finally {
        $minimap64.Dispose()
    }
}
finally {
    $logoImg.Dispose()
}

# Build ULOHudBg.tga (256x64 dark obsidian panel with 2px bronze/gold border)
$hudW = 256
$hudH = 64
$hudBmp = New-Object System.Drawing.Bitmap($hudW, $hudH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
try {
    $g = [System.Drawing.Graphics]::FromImage($hudBmp)
    try {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $hudW, $hudH)
        $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect,
            [System.Drawing.Color]::FromArgb(236, 14, 18, 30),
            [System.Drawing.Color]::FromArgb(242, 8, 10, 18),
            [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
        )
        try {
            $g.FillRectangle($bgBrush, $rect)
        }
        finally {
            $bgBrush.Dispose()
        }

        # Outer 1px bronze/gold border (#C89B3C)
        $outerPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 200, 155, 60), 1)
        try {
            $g.DrawRectangle($outerPen, 0, 0, $hudW - 1, $hudH - 1)
        }
        finally {
            $outerPen.Dispose()
        }

        # Inner 1px muted bronze border (#7A5B22)
        $innerPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 122, 91, 34), 1)
        try {
            $g.DrawRectangle($innerPen, 1, 1, $hudW - 3, $hudH - 3)
        }
        finally {
            $innerPen.Dispose()
        }

        # Subtle arcane cyan inner hairline highlight
        $accentPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(72, 0, 204, 255), 1)
        try {
            $g.DrawLine($accentPen, 3, 2, $hudW - 4, 2)
        }
        finally {
            $accentPen.Dispose()
        }
    }
    finally {
        $g.Dispose()
    }
    Write-UncompressedTga32 -Bitmap $hudBmp -OutputPath (Join-Path $mediaDir 'ULOHudBg.tga')
}
finally {
    $hudBmp.Dispose()
}

Write-Output "Assets built successfully:"
Get-Item $logoOut, $bannerOut, (Join-Path $mediaDir 'ULOIcon.tga'), (Join-Path $mediaDir 'ULOMinimap.tga'), (Join-Path $mediaDir 'ULOHudBg.tga') |
    Select-Object FullName, Length
