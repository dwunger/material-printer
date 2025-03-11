$logFile = ".\error_log.txt"
$sourceCode = Get-Content -Path ".\Huginn.cs" -Raw
$assemblies = @(
    "System.dll",
    "System.Net.Http.dll",
    "System.Core.dll",
    "System.Linq.dll",            
    "Microsoft.CSharp.dll"        
)

try {
    $assembly = Add-Type -TypeDefinition $sourceCode -Language CSharp -ReferencedAssemblies $assemblies -PassThru
    if ($assembly) {
        # Look for the Program class
        $programType = $assembly | Where-Object { $_.Name -eq "Program" }
        if ($programType) {
            try {
                # Get the Main method that takes string[] arguments
                $mainMethod = $programType.GetMethod("Main", [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static, $null, [Type[]]@([string[]]), $null)
                
                # If found, invoke it with an empty string array
                if ($mainMethod) {
                    $mainMethod.Invoke($null, @(,[string[]]@()))
                } else {
                    "Main method with string[] parameter not found." | Out-File -FilePath $logFile -Append
                    Write-Host "Main method with string[] parameter not found."
                }
            } catch {
                $_ | Out-File -FilePath $logFile -Append
                Write-Host "Exception occurred in Main() method. Check error_log.txt"
            }
        } else {
            "Program class not found in compiled assembly." | Out-File -FilePath $logFile -Append
            Write-Host "Program class not found in compiled assembly."
        }
    }
} catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "Compilation failed. Check error_log.txt"
}
