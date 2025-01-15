using module '..\huginn\utils.psm1'

$TestFile = '.\test_config.txt'

# Test file contents:
$test_file = @"
Param1=Value1
Param2=Value2
Param3 = Value3
# This is a comment
Param4=Value4
"@

$ESC = [char]27
$RESET_FMT = "$ESC[0m"
$RED_FG = "$ESC[91m"
$GREEN_FG = "$ESC[92m"

# Test 1: Check for a valid parameter
$Result = Query-Parameter -File $TestFile -Parameter "Param1"
if ($Result -eq "Value1") {
    Write-Host "{Query-Parameter} "  $GREEN_FG "Test 1 Passed: Param1 found"
} else {
    Write-Host "{Query-Parameter} "  $RED_FG "Test 1 Failed: Expected 'Value1', got '$Result'"
}

# Test 2: Check for a valid parameter with spaces around key
$Result = Query-Parameter -File $TestFile -Parameter "Param3"
if ($Result -eq "Value3") {
    Write-Host "{Query-Parameter} "  $GREEN_FG "Test 2 Passed: Param3 found with spaces"
} else {
    Write-Host "{Query-Parameter} "  $RED_FG "Test 2 Failed: Expected 'Value3', got '$Result'"
}

# Test 3: Check for a non-existent parameter
$Result = Query-Parameter -File $TestFile -Parameter "ParamX"
if ($Result -eq $null) {
    Write-Host "{Query-Parameter} "  $GREEN_FG "Test 3 Passed: Non-existent parameter returned null"
} else {
    Write-Host "{Query-Parameter} "  $RED_FG "Test 3 Failed: Expected null, got '$Result'"
}

# Test 4: Check behavior with comment lines
$Result = Query-Parameter -File $TestFile -Parameter "#"
if ($Result -eq $null) {
    Write-Host "{Query-Parameter} "  $GREEN_FG "Test 4 Passed: Comment lines ignored"
} else {
    Write-Host "{Query-Parameter} "  $RED_FG "Test 4 Failed: Expected null, got '$Result'"
}

# Test 5: Check for a valid parameter at the end
$Result = Query-Parameter -File $TestFile -Parameter "Param4"
if ($Result -eq "Value4") {
    Write-Host "{Query-Parameter} "  $GREEN_FG "Test 5 Passed: Param4 found at the end"
} else {
    Write-Host "{Query-Parameter} "  $RED_FG "Test 5 Failed: Expected 'Value4', got '$Result'"
}

# Clean up the test file
#Remove-Item -Path $TestFile
