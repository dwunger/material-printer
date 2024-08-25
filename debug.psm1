function InitLogReader {
    Start-Process powershell -ArgumentList @(
        '-NoProfile'
        '-Command'
        @"
          Write-Host 'Error Monitor' -ForegroundColor Red
          while(1) {
            if(Test-Path $env:TEMP\script_errors.log) {
              Get-Content $env:TEMP\script_errors.log -Wait
            }
            Start-Sleep -Seconds 1
          }
"@
    ) -WindowStyle Normal
}
