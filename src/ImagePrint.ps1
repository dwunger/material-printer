param(
    [Parameter(Mandatory)]
    [string]$PrinterIp   # e.g. "10.32.40.30"
)

# 1) Locate pepe.png on the Desktop
$desktop   = [Environment]::GetFolderPath('Desktop')
$imagePath = Join-Path $desktop 'pepe.png'
if (-not (Test-Path $imagePath)) {
    Write-Error "Cannot find pepe.png on your Desktop: $imagePath"
    exit 1
}

# 2) Load drawing APIs
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::new($imagePath)
$w   = $bmp.Width
$h   = $bmp.Height

# 3) Build grayscale buffer
$gray = New-Object double[] ($w * $h)
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $c = $bmp.GetPixel($x, $y)
        $gray[$y * $w + $x] = $c.R * 0.3 + $c.G * 0.59 + $c.B * 0.11
    }
}

# 4) Floyd–Steinberg dithering
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $idx = $y * $w + $x
        $old = $gray[$idx]
        $new = if ($old -ge 128) { 255 } else { 0 }
        $err = $old - $new
        $gray[$idx] = $new

        if ($x + 1 -lt $w) {
            $gray[$y * $w + ($x + 1)] += $err * 7/16
        }
        if ($y + 1 -lt $h) {
            if ($x -gt 0) {
                $gray[($y + 1) * $w + ($x - 1)] += $err * 3/16
            }
            $gray[($y + 1) * $w + $x] += $err * 5/16
            if ($x + 1 -lt $w) {
                $gray[($y + 1) * $w + ($x + 1)] += $err * 1/16
            }
        }
    }
}

# 5) Pack into ZPL hex string
$bytesPerRow = [Math]::Ceiling($w / 8)
$hex         = ''
for ($y = 0; $y -lt $h; $y++) {
    for ($b = 0; $b -lt $bytesPerRow; $b++) {
        $val = 0
        for ($bit = 0; $bit -lt 8; $bit++) {
            $x = $b * 8 + $bit
            if ($x -lt $w -and $gray[$y * $w + $x] -lt 128) {
                $val = $val -bor (1 -shl (7 - $bit))
            }
        }
        $hex += '{0:X2}' -f $val
    }
}
$total = $bytesPerRow * $h
$zpl   = "^XA^FO10,10^GFA,$total,$total,$bytesPerRow,$hex^XZ"

# 6) Clean up Bitmap
$bmp.Dispose()

# 7) Send via raw TCP using reflection
$asm      = [Reflection.Assembly]::LoadWithPartialName('System')
$tcpType  = $asm.GetType('System.Net.Sockets.TcpClient')
$ctor     = $tcpType.GetConstructor([Type[]]@([string], [int]))
$client   = $ctor.Invoke(@($PrinterIp, 9100))

# get network stream
$getStr   = $tcpType.GetMethod('GetStream', [Type[]]@())
$stream   = $getStr.Invoke($client, @())

# write bytes
$bytes    = [System.Text.Encoding]::ASCII.GetBytes($zpl)
$write    = $stream.GetType().GetMethod('Write', [Type[]]@([byte[]], [int], [int]))
$write.Invoke($stream, @($bytes, 0, $bytes.Length))

# close stream & client (zero‐param overload)
$closeStr = $stream.GetType().GetMethod('Close', [Type[]]@())
$closeStr.Invoke($stream, @())

$closeCli = $client.GetType().GetMethod('Close', [Type[]]@())
$closeCli.Invoke($client, @())
