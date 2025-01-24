function Get-Darkness() {
    param(
        [string] $printerIP
    )
   
    $printerPort = 9100
    $timeoutMilliseconds = 1000 # who's got time for that

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
                    Write-Host $printerIP
                    $response = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
                    $darkness = $response | findstr "DARKNESS"
                    Write-Host $darkness
                    Write-Host ';'
                } else {
                    # pass
                }
            } else {
                # pass
            }

            $stream.Close()
        } else {
            $tcpClient.Close()
        }
    } catch {
        Write-Host "Error: $_"
    } finally {
        $tcpClient.Close()
    }
}
