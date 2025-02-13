$sourceCode = Get-Content -Path ".\src\Main.cs" -Raw
$assemblies = @("System.Drawing.dll", "System.Windows.Forms.dll")
try {
    $assembly = Add-Type -TypeDefinition $sourceCode -Language CSharp -ReferencedAssemblies $assemblies -PassThru
    if ($assembly) {
        $mainClass = $assembly | Where-Object { $_.GetMethod("Main") }
        if ($mainClass) {
            $mainClass::Main()
        } else {
            Write-Host "No static Main() method found in the compiled code."
        }
    }
} catch {
    Write-Host "Compilation failed: $_"
}
