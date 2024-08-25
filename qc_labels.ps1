# This is now just a wrapper for the actual QC label script which handles patching and script execution
# The name sucks, but we're stuck with it as the entry point
using module '.\debug.psm1'
using module '.\src\ScreenManager.psm1'
using module '.\huginn\utils.psm1'
using module '.\huginn\VerboseUpdateLogger.psm1'

Clear-Host # Please don't tell me how to name my functions, Microsoft.

$REMOTE_VERSION = Query-RemoteManifest -Parameter 'VERSION'
$LOCAL_VERSION = Query-Parameter -File '.\MANIFEST' -Parameter 'VERSION'

$DEBUG = $false
if (-not (Test-Path '.\muginn')) { mkdir '.\muginn' } # Since we can't force incremental version updates

# We don't have git, so I'll just handroll something
if ([System.Version]$LOCAL_VERSION -lt [System.Version]$REMOTE_VERSION) {
    
    # A basic version  of Update client has been ported to C#
    # We compile Huginn.cs with Huginn.ps1
    powershell.exe -ExecutionPolicy Bypass -File .\Huginn.ps1
    #Update-ClientVerbose 
    #Clear-Host
    #$UpdateClient = Monitored_Start -Process 'powershell' -Args '-ExecutionPolicy Bypass -File .\Update.ps1'
    #
    # while (!$UpdateClient.HasExited) {
    #     Start-Sleep -Milliseconds 500
    # }
} 
# Run the main script with error redirection or don't.
if ($DEBUG){
    InitLogReader

    Start-Process powershell.exe `
        -ArgumentList '-ExecutionPolicy Bypass -File .\src\app.ps1' `
        -RedirectStandardError $env:TEMP\script_errors.log
} else {
    powershell -ExecutionPolicy Bypass -File '.\src\app.ps1'
}
