function Extract-Float {
    param([string] $Value)

    # Remove everything not part of a float:
    $cleaned = $Value -replace '[^0-9.\+\-]', ''

    if ($cleaned -match '^[+-]?\d+(\.\d+)?$') {
        return [double]$cleaned
    }
    else {
        return $null
    }
}

function Get-Darkness {
    param(
        [string] $printerIP
    )

    $printerPort = 9100
    $timeoutMilliseconds = 1000
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $tcpClient.ReceiveTimeout = $timeoutMilliseconds
    $tcpClient.SendTimeout = $timeoutMilliseconds

    try {
        $asyncResult = $tcpClient.BeginConnect($printerIP, $printerPort, $null, $null)
        if ($asyncResult.AsyncWaitHandle.WaitOne($timeoutMilliseconds, $false)) {
            $tcpClient.EndConnect($asyncResult)
            $stream = $tcpClient.GetStream()

            $zplCommand = "^XA^HH^XZ"
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($zplCommand)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()

            $buffer = New-Object Byte[] 2048
            $asyncRead = $stream.BeginRead($buffer, 0, $buffer.Length, $null, $null)

            if ($asyncRead.AsyncWaitHandle.WaitOne($timeoutMilliseconds, $false)) {
                $bytesRead = $stream.EndRead($asyncRead)
                if ($bytesRead -gt 0) {
                    $response = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)

                    $darknessLines = $response | findstr "DARKNESS"

                    foreach ($line in $darknessLines) {
                        # Possibly print the line to debug:
                        # Write-Host "Line: $line"

                        $val = Extract-Float $line
                        if ($val -ne $null) {
                            return $val
                        }
                    }
                }
            }
            $stream.Close()
        }
    }
    catch {
        Write-Host "Error: $_"
    }
    finally {
        $tcpClient.Close()
    }
}


function Set-Darkness {
    param(
        [string] $printerIP,
        [float] $value
    )
    if ($value -gt 30.0) {
        $value = 30.0
    }
    if ($value -lt 10.0) {
        $value = 10.0
    } 
    
    $printerPort = 9100
    $timeoutMilliseconds = 1000
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $tcpClient.ReceiveTimeout = $timeoutMilliseconds
    $tcpClient.SendTimeout = $timeoutMilliseconds

    try {
        $asyncResult = $tcpClient.BeginConnect($printerIP, $printerPort, $null, $null)
        if ($asyncResult.AsyncWaitHandle.WaitOne($timeoutMilliseconds, $false)) {
            $tcpClient.EndConnect($asyncResult)
            $stream = $tcpClient.GetStream()

            $zplCommand = "~SD$value^XA^HH^XZ"
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($zplCommand)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()

            $buffer = New-Object Byte[] 2048
            $asyncRead = $stream.BeginRead($buffer, 0, $buffer.Length, $null, $null)

            if ($asyncRead.AsyncWaitHandle.WaitOne($timeoutMilliseconds, $false)) {
                $bytesRead = $stream.EndRead($asyncRead)
                if ($bytesRead -gt 0) {
                    $response = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)

                    $darknessLines = $response | findstr "DARKNESS"

                    foreach ($line in $darknessLines) {
                        # Possibly print the line to debug:
                        # Write-Host "Line: $line"

                        $val = Extract-Float $line
                        if ($val -ne $null) {
                            return $val
                        }
                    }
                }
            }
            $stream.Close()
        }
    }
    catch {
        Write-Host "Error: $_"
    }
    finally {
        $tcpClient.Close()
    }
}
