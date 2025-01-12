# This is now just a wrapper for the actual QC label script which handles patching and script execution
using module '.\debug.psm1'

$DEBUG = $true


# Enumerate changes and patch files
# We don't have git, so I'll just handroll something


# Run the main script with error redirection or don't. 
if ($DEBUG){
    InitLogReader

    Start-Process powershell.exe `
        -ArgumentList '-ExecutionPolicy Bypass -File .\src\app.ps1' `
        -RedirectStandardError $env:TEMP\script_errors.log
} else {
    powershell -ExecutionPolicy Bypass -File .\src\app.ps1
}
