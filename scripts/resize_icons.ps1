Add-Type -AssemblyName System.Drawing

$src = "C:\Users\evert\.gemini\antigravity\brain\069e2bdc-7ad8-4331-9b68-08e36b707f08\realtracks_logo_icon_1791921050405.jpg"
$baseDir = "C:\Users\evert\.gemini\antigravity\scratch\realtracks"

$sizes = @{
    "android\app\src\main\res\mipmap-mdpi\ic_launcher.png" = 48
    "android\app\src\main\res\mipmap-hdpi\ic_launcher.png" = 72
    "android\app\src\main\res\mipmap-xhdpi\ic_launcher.png" = 96
    "android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png" = 144
    "android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png" = 192
    "web\icons\Icon-192.png" = 192
    "web\icons\Icon-512.png" = 512
    "web\favicon.png" = 64
}

$original = [System.Drawing.Image]::FromFile($src)

foreach ($key in $sizes.Keys) {
    $size = $sizes[$key]
    $dest = Join-Path $baseDir $key
    $destDir = Split-Path $dest -Parent
    if (!(Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($original, 0, 0, $size, $size)
    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
    Write-Output "Created $dest ($size x $size)"
}

$original.Dispose()
Write-Output "All icons generated successfully!"
