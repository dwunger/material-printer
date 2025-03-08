$logFile = ".\error_log.txt"
$sourceCode = Get-Content -Path ".\src\Main.cs" -Raw
$assemblies = @("System.Drawing.dll", "System.Windows.Forms.dll", "System.Net.Http.dll")
try {
    $assembly = Add-Type -TypeDefinition $sourceCode -Language CSharp -ReferencedAssemblies $assemblies -PassThru
    if ($assembly) {
        $mainClass = $assembly | Where-Object { $_.GetMethod("Main") }
        if ($mainClass) {
            try {
                $mainClass::Main()
            } catch {
                $_ | Out-File -FilePath $logFile -Append
                Write-Host "Exception occurred in Main() method. Check error_log.txt"
            }
        } else {
            "No static Main() method found in the compiled code." | Out-File -FilePath $logFile -Append
        }
    }
} catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "Compilation failed. Check error_log.txt"
}
