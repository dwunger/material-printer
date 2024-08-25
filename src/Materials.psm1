# Published CSV link:
#https://docs.google.com/spreadsheets/d/e/2PACX-1vRL6PKYNT-6OfbPxJDU7TiYXKYVYY75YhlEmfAD1HRF0fWXwTbJ2JwbRUG-jgOiOBKl-f_QIOjyG5Ne/pub?output=csv
#https://docs.google.com/spreadsheets/d/15leQ_Hy9kxP_PmoBwOqyDEln9Vvy5Bpilqm4LrJ56lE/edit?usp=sharing

# Mini Excel CSV engine with formula-aware CSV parsing
# Supports:
#   =CONCATENATE("text", A1, ";", J3, ...)
#   TODAY()
#   =<date-or-cell> - TODAY()   # day diff (see Get-InclusiveDaysUntil)

#---------------------- CSV parsing (formula-aware) ----------------------#
function Parse-CsvLineSmart {
    param([string]$line)

    $fields = @()
    $buf = New-Object System.Text.StringBuilder
    $inQuotes = $false
    $parenDepth = 0
    $i = 0

    while ($i -lt $line.Length) {
        $ch = $line[$i]

        if ($ch -eq '"') {
            # Handle escaped double-quote ("")
            if ($inQuotes -and $i+1 -lt $line.Length -and $line[$i+1] -eq '"') {
                [void]$buf.Append('"'); $i += 2; continue
            }
            $inQuotes = -not $inQuotes
            [void]$buf.Append($ch); $i++; continue
        }

        if (-not $inQuotes) {
            if ($ch -eq '(') { $parenDepth++; [void]$buf.Append($ch); $i++; continue }
            if ($ch -eq ')') { if ($parenDepth -gt 0) { $parenDepth-- } [void]$buf.Append($ch); $i++; continue }
            if ($ch -eq ',' -and $parenDepth -eq 0) {
                $fields += $buf.ToString()
                $buf.Clear() | Out-Null
                $i++; continue
            }
        }

        [void]$buf.Append($ch); $i++
    }

    $fields += $buf.ToString()
    return ,$fields
}

function Get-MaxCsvColumns {
    param([string[]]$Lines)
    $max = 0
    foreach ($line in $Lines) {
        $count = (Parse-CsvLineSmart $line).Count
        if ($count -gt $max) { $max = $count }
    }
    return $max
}

function ConvertTo-Grid {
    param([string]$CsvText)
    $lines = $CsvText -split "`r?`n" | Where-Object { $_ -ne "" }
    $cols = Get-MaxCsvColumns $lines

    $grid = @()
    foreach ($line in $lines) {
        $parts = Parse-CsvLineSmart $line
        # Pad to rectangular
        while ($parts.Count -lt $cols) { $parts += "" }
        # Normalize: remove surrounding quotes, keep inner "" as "
        for ($i=0; $i -lt $parts.Count; $i++) {
            $s = $parts[$i].Trim()
            if ($s -match '^"(.*)"$') { $s = $s.Substring(1, $s.Length-2) -replace '""','"' }
            $parts[$i] = $s
        }
        $grid += ,([object[]]$parts)
    }
    return ,$grid
}

#---------------------- A1 references ----------------------#
function Get-ColumnIndexFromA1 {
    param([string]$ref)
    $colLetters = ($ref -replace '[^A-Za-z]').ToUpper()
    $n = 0
    foreach ($ch in $colLetters.ToCharArray()) {
        $n = ($n * 26) + ([int][char]$ch - [int][char]'A' + 1)
    }
    return $n - 1
}
function Get-RowIndexFromA1 {
    param([string]$ref)
    $digits = ($ref -replace '[^0-9]')
    if ([string]::IsNullOrWhiteSpace($digits)) { throw "Invalid A1 reference '$ref' (no row number)." }
    return [int]$digits - 1
}

#---------------------- Formula evaluation ----------------------#
function Split-Args {
    param([string]$argsText)
    # Split on commas not in quotes
    $parts = @()
    $buf = New-Object System.Text.StringBuilder
    $inQuotes = $false
    for ($i=0; $i -lt $argsText.Length; $i++) {
        $ch = $argsText[$i]
        if ($ch -eq '"') {
            if ($inQuotes -and $i+1 -lt $argsText.Length -and $argsText[$i+1] -eq '"') {
                [void]$buf.Append('"'); $i++; continue
            }
            $inQuotes = -not $inQuotes
            [void]$buf.Append($ch)
        } elseif ($ch -eq ',' -and -not $inQuotes) {
            $parts += $buf.ToString().Trim()
            $buf.Clear() | Out-Null
        } else {
            [void]$buf.Append($ch)
        }
    }
    $parts += $buf.ToString().Trim()
    return $parts
}

function Unquote {
    param([string]$s)
    if ($s -match '^"(.*)"$') {
        return ($Matches[1] -replace '""','"')
    }
    return $s
}

function Try-ParseDate {
    param([string]$s, [ref]$dt)
    $styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
    return [datetime]::TryParse($s, $culture, $styles, $dt)
}

function Get-Today { (Get-Date).Date }

# Inclusive day math as originally requested
function Get-InclusiveDaysUntil {
    param([datetime]$target, [datetime]$today)
    if ($target -ge $today) {
        return (($target - $today).Days + 1)
    } else {
        return -(([int]($today - $target).Days) - 1)
    }
}

function Evaluate-Cell {
    param(
        [object[][]]$Grid,
        [int]$RowIndex,
        [int]$ColIndex,
        [hashtable]$Cache
    )
    $key = "$RowIndex,$ColIndex"
    if ($Cache.ContainsKey($key)) { return $Cache[$key] }

    $raw = [string]$Grid[$RowIndex][$ColIndex]
    if ([string]::IsNullOrWhiteSpace($raw)) { $Cache[$key] = ""; return "" }

    if ($raw.StartsWith('=')) {
        $expr = $raw.Substring(1).Trim()

        # CONCATENATE(...)
        if ($expr -match '^CONCATENATE\s*\((.*)\)$') {
            $argsText = $Matches[1]
            $parts = Split-Args $argsText
            $sb = New-Object System.Text.StringBuilder
            foreach ($p in $parts) {
                $p2 = $p.Trim()
                if ($p2 -match '^".*"$') {
                    [void]$sb.Append( (Unquote $p2) )
                } elseif ($p2 -match '^[A-Za-z]+[0-9]+$') {
                    $c = Get-ColumnIndexFromA1 $p2
                    $r = Get-RowIndexFromA1 $p2
                    [void]$sb.Append( (Evaluate-Cell -Grid $Grid -RowIndex $r -ColIndex $c -Cache $Cache) )
                } elseif ($p2 -match '^TODAY\(\)$') {
                    [void]$sb.Append( (Get-Today).ToString('M/d/yyyy') )
                } else {
                    [void]$sb.Append($p2)
                }
            }
            $val = $sb.ToString()
            $Cache[$key] = $val
            return $val
        }

        # <thing> - TODAY()
        if ($expr -match '^(.*?)-\s*TODAY\(\)\s*$') {
            $left = $Matches[1].Trim()
            if ($left -match '^[A-Za-z]+[0-9]+$') {
                $c = Get-ColumnIndexFromA1 $left
                $r = Get-RowIndexFromA1 $left
                $left = Evaluate-Cell -Grid $Grid -RowIndex $r -ColIndex $c -Cache $Cache
            } elseif ($left -match '^".*"$') {
                $left = Unquote $left
            }

            $dt = [datetime]::MinValue
            if (Try-ParseDate -s $left -dt ([ref]$dt)) {
                $days = Get-InclusiveDaysUntil -target $dt.Date -today (Get-Today)
                $Cache[$key] = [string]$days
                return $Cache[$key]
            } else {
                throw "Left side '$left' is not a recognizable date for '$raw'."
            }
        }

        # TODAY()
        if ($expr -match '^TODAY\(\)$') {
            $val = (Get-Today).ToString('M/d/yyyy')
            $Cache[$key] = $val
            return $val
        }

        throw "Unsupported formula: $raw"
    }

    $Cache[$key] = $raw
    return $raw
}

function Invoke-CsvExcelEngine {
    param([Parameter(Mandatory)][string]$CsvText)
    $grid = ConvertTo-Grid -CsvText $CsvText
    $rows = @()
    for ($r=0; $r -lt $grid.Count; $r++) {
        $cache = @{}
        $rowOut = @()
        for ($c=0; $c -lt $grid[$r].Count; $c++) {
            $rowOut += (Evaluate-Cell -Grid $grid -RowIndex $r -ColIndex $c -Cache $cache)
        }
        # Trim trailing blanks
        for ($i = $rowOut.Count-1; $i -ge 0; $i--) {
            if ($rowOut[$i] -ne '') { break } else { $rowOut = $rowOut[0..($i-1)] }
        }
        $rows += ,($rowOut -join ',')
    }
    return ($rows -join "`r`n")
}

function Convert-CsvExcelFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Path
    )
    $csv = Get-Content -Raw -LiteralPath $Path
    return (Invoke-CsvExcelEngine -CsvText $csv)
}

#### End Mini-excel engine

function Setup-MaterialGroups_original_version {
    # Read Resources File
    $f_info = Get-FileContent("./src/rsrc_info.csv")
    if ($null -eq $f_info) {
        Write-Host "Error: Unable to import QC material information."
        return $null
    }
    Write-Debug "Importing QC material information. . ."

    $MaterialGroupsByInstrument = @{}

    foreach ($line in ($f_info -split "\n"))
    {
        Write-Debug "Processing line: $line"
        $_temp_material_group_list = getMaterials($line)

        $new_material_group = [MaterialGroup]::new()
        $new_material_group.SetInstrument(($line -split ";")[$INSTRUMENT])
        $new_material_group.SetGroupName(($line -split ";")[$MATERIAL_GROUP])
    
        Write-Debug "Created group: $($new_material_group.group_name) for instrument: $($new_material_group.instrument)"
    
        foreach ($_material in $_temp_material_group_list)
        {
            Write-Debug "Adding material: $($_material.name) to group: $($new_material_group.group_name)"
            $new_material_group.AddMaterial($_material)
        }

        if ($new_material_group.IsValid()) {
            if (-not $MaterialGroupsByInstrument.ContainsKey($new_material_group.instrument)) {
                $MaterialGroupsByInstrument[$new_material_group.instrument] = @()
            }
            $MaterialGroupsByInstrument[$new_material_group.instrument] += $new_material_group
            Write-Debug "Added valid group to $($new_material_group.instrument) list: $($new_material_group.group_name)"
        } else {
            Write-Debug "Warning: Skipping invalid group: $($new_material_group.group_name)"
        }
    }

    # Print debug information
    foreach ($instrument in $MaterialGroupsByInstrument.Keys) {
        Write-Debug "$instrument Material Groups:"
        foreach ($group in $MaterialGroupsByInstrument[$instrument]) {
            Write-Debug "  $($group.group_name) (Valid: $($group.IsValid()))"
            $group.vPrintMaterialsInfo()
        }
    }

    return $MaterialGroupsByInstrument
}


function Setup-MaterialGroupsOFFLINEPATCH {
    # Initialize the MaterialGroupsByInstrument hashtable
    $MaterialGroupsByInstrument = @{}

    # Read and process the local CSV file
    $localFilePath = "./src/rsrc_info.csv"
    if (-not (Test-Path $localFilePath)) {
        Write-Host "Error: Local file 'rsrc_info.csv' not found."
        return $null
    }

    # Read the local CSV file content
    $localFileContent = Get-Content -Path $localFilePath -Raw
    $localLines = $localFileContent -split "`n"

    # Process local data lines
    $success = Process-MaterialGroupsLines -lines $localLines -MaterialGroupsByInstrument ([ref]$MaterialGroupsByInstrument) -Delimiter ";"
    if (-not $success) {
        Write-Host "Error: Failed to process local material groups."
        return $null
    }

    $remoteContent = Convert-CsvExcelFile .\src\excel_rsrc.csv

    # Pre-process the content to swap commas and semicolons
    $processedContent = Preprocess-OnlineCSV -content $remoteContent

    # Split the processed content into lines
    $remoteLines = $processedContent -split "`n"

    # Process remote data lines using the same delimiter as local CSV
    $success = Process-MaterialGroupsLines -lines $remoteLines -MaterialGroupsByInstrument ([ref]$MaterialGroupsByInstrument) -Delimiter ";"
    if (-not $success) {
        Write-Host "Error: Failed to process remote material groups."
        return $null
    }

    # Return the combined MaterialGroupsByInstrument
    return $MaterialGroupsByInstrument
}

function Setup-MaterialGroups {
    # Initialize the MaterialGroupsByInstrument hashtable
    $MaterialGroupsByInstrument = @{}

    # Read and process the local CSV file
    $localFilePath = "./src/rsrc_info.csv"
    if (-not (Test-Path $localFilePath)) {
        Write-Host "Error: Local file 'rsrc_info.csv' not found."
        return $null
    }

    # Read the local CSV file content
    $localFileContent = Get-Content -Path $localFilePath -Raw
    $localLines = $localFileContent -split "`n"

    # Process local data lines
    $success = Process-MaterialGroupsLines -lines $localLines -MaterialGroupsByInstrument ([ref]$MaterialGroupsByInstrument) -Delimiter ";"
    if (-not $success) {
        Write-Host "Error: Failed to process local material groups."
        return $null
    }

    # Fetch and process the online CSV
    $csvUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRL6PKYNT-6OfbPxJDU7TiYXKYVYY75YhlEmfAD1HRF0fWXwTbJ2JwbRUG-jgOiOBKl-f_QIOjyG5Ne/pub?output=csv"

    try {
        # Fetch the CSV content
        $global:side_pane.push_down("Fetching online resources...")
        $webResponse = Invoke-WebRequest -Uri $csvUrl -UseBasicParsing
        if (-not $webResponse -or -not $webResponse.Content) {
            Write-Host "Error: Unable to fetch QC material information from the provided URL."
            return $null
        } else {
            $global:side_pane.push_down($GREEN_FG + "Download Success!")
        }

    } catch {
        $global:side_pane.push_down($RED_FG + "Failed to retrieve online resources")
        Write-Host "Error: Failed to fetch QC material information. Exception: $_"
        return $null
    }

    # Get the content
    $remoteContent = $webResponse.Content

    # Pre-process the content to swap commas and semicolons
    $processedContent = Preprocess-OnlineCSV -content $remoteContent

    # Split the processed content into lines
    $remoteLines = $processedContent -split "`n"

    # Process remote data lines using the same delimiter as local CSV
    $success = Process-MaterialGroupsLines -lines $remoteLines -MaterialGroupsByInstrument ([ref]$MaterialGroupsByInstrument) -Delimiter ";"
    if (-not $success) {
        Write-Host "Error: Failed to process remote material groups."
        return $null
    }

    # Return the combined MaterialGroupsByInstrument
    return $MaterialGroupsByInstrument
}

function Setup-MaterialGroups-Async {
    param(
        [string]$RemoteContent
    )
    # Initialize the MaterialGroupsByInstrument hashtable
    $MaterialGroupsByInstrument = @{}

    # Process local CSV
    $localFilePath = "./src/rsrc_info.csv"
    if (-not (Test-Path $localFilePath)) {
        Write-Host "Error: Local file 'rsrc_info.csv' not found."
        return $null
    }
    $localFileContent = Get-Content -Path $localFilePath -Raw
    $localLines = $localFileContent -split "`n"
    $success = Process-MaterialGroupsLines -lines $localLines -MaterialGroupsByInstrument ([ref]$MaterialGroupsByInstrument) -Delimiter ";"
    if (-not $success) {
        Write-Host "Error: Failed to process local material groups."
        return $null
    }

    # Process remote CSV content provided as parameter
    if (-not $RemoteContent) {
        
        $Global:side_pane.push_down("Error: Remote CSV content not provided.`nGoogle's server down.")
        #return $null
    }
    $processedContent = Preprocess-OnlineCSV -content $RemoteContent
    $remoteLines = $processedContent -split "`n"
    $success = Process-MaterialGroupsLines -lines $remoteLines -MaterialGroupsByInstrument ([ref]$MaterialGroupsByInstrument) -Delimiter ";"
    if (-not $success) {
        Write-Host "Error: Failed to process remote material groups."
        return $null
    }

    return $MaterialGroupsByInstrument
}

function Preprocess-OnlineCSV {
    param(
        [string]$content
    )

    # Use a temporary placeholder that is unlikely to appear in the data
    $tempPlaceholder = "|"

    # First, replace commas (,) with the placeholder (|)

    # Handle commas within quotes (e.g., "value1,value2") to avoid replacing commas inside quoted strings
    $content = [regex]::Replace($content, '(?<=^|;|,|")([^"]*?),(.*?)(?="|$|;|,)', { param($m) $m.Value -replace ',', $tempPlaceholder })

    # Replace remaining commas with the placeholder
    $content = $content -replace ',', $tempPlaceholder

    # Replace semicolons (;) with commas (,)
    $content = $content -replace ';', ','

    # Replace the placeholder (|) with semicolons (;)
    $content = $content -replace [regex]::Escape($tempPlaceholder), ';'

    return $content
}

function Process-MaterialGroupsLines_old {
    param(
        [string[]]$lines,
        [ref]$MaterialGroupsByInstrument,
        [string]$Delimiter = ";"
    )

    foreach ($line in $lines) {
        Write-Debug "Processing line: $line"

        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        # Use getMaterials to parse materials from the line
        $_temp_material_group_list = getMaterials $line $Delimiter

        if (-not $_temp_material_group_list) {
            Write-Debug "Warning: No materials extracted from line: $line"
            continue
        }

        # Split the line into fields using the specified delimiter
        $fields = $line -split $Delimiter

        # Constants for field indices
        $MATERIAL_GROUP = 0
        $INSTRUMENT = 1

        # Ensure the line has the expected number of fields
        if ($fields.Length -lt 5) {
            Write-Debug "Warning: Skipping line with insufficient fields: $line"
            continue
        }

        # Extract fields
        $MaterialGroup = $fields[$MATERIAL_GROUP].Trim()
        $Instrument = $fields[$INSTRUMENT].Trim()

        # Create a new material group
        $new_material_group = [MaterialGroup]::new()
        $new_material_group.SetInstrument($Instrument)
        $new_material_group.SetGroupName($MaterialGroup)

        Write-Debug "Created group: $($new_material_group.group_name) for instrument: $($new_material_group.instrument)"

        # Add materials to the group
        foreach ($_material in $_temp_material_group_list) {
            Write-Debug "Adding material: $($_material.name) to group: $($new_material_group.group_name)"
            $new_material_group.AddMaterial($_material)
        }

        if ($new_material_group.IsValid()) {
            if (-not $MaterialGroupsByInstrument.Value.ContainsKey($new_material_group.instrument)) {
                $MaterialGroupsByInstrument.Value[$new_material_group.instrument] = @()
            }
            $MaterialGroupsByInstrument.Value[$new_material_group.instrument] += $new_material_group
            Write-Debug "Added valid group to $($new_material_group.instrument) list: $($new_material_group.group_name)"
        } else {
            Write-Debug "Warning: Skipping invalid group: $($new_material_group.group_name)"
        }
    }

    return $true
}

function Process-MaterialGroupsLines {
    param(
        [string[]]$lines,
        [ref]$MaterialGroupsByInstrument,
        [string]$Delimiter = ";"
    )

    foreach ($line in $lines) {
        Write-Debug "Processing line: $line"

        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        # Get materials for this line
        $_temp_material_group_list = getMaterials $line $Delimiter
        if (-not $_temp_material_group_list) {
            Write-Debug "Warning: No materials extracted from line: $line"
            continue
        }

        # Split the line into fields using the specified delimiter
        $fields = $line -split $Delimiter
        $MATERIAL_GROUP = 0
        $INSTRUMENT = 1

        # Ensure the line has the expected number of fields
        if ($fields.Length -lt 5) {
            Write-Debug "Warning: Skipping line with insufficient fields: $line"
            continue
        }

        # Extract the group name and instrument
        $groupName = $fields[$MATERIAL_GROUP].Trim()
        $instrument = $fields[$INSTRUMENT].Trim()

        # Ensure there's an array for this instrument in the hashtable
        if (-not $MaterialGroupsByInstrument.Value.ContainsKey($instrument)) {
            $MaterialGroupsByInstrument.Value[$instrument] = @()
        }

        # Try to find an existing group with the same name
        $existingGroup = $MaterialGroupsByInstrument.Value[$instrument] | Where-Object { $_.group_name -eq $groupName }

        if ($existingGroup) {
            # Merge new materials into the existing group
            foreach ($material in $_temp_material_group_list) {
                $existingGroup.AddMaterial($material)
            }
            Write-Debug "Merged materials into existing group: $groupName for instrument: $instrument"
        }
        else {
            # Create a new group
            $new_material_group = [MaterialGroup]::new()
            $new_material_group.SetInstrument($instrument)
            $new_material_group.SetGroupName($groupName)
            foreach ($material in $_temp_material_group_list) {
                $new_material_group.AddMaterial($material)
            }
            if ($new_material_group.IsValid()) {
                $MaterialGroupsByInstrument.Value[$instrument] += $new_material_group
                Write-Debug "Created new group: $groupName for instrument: $instrument"
            } else {
                Write-Debug "Warning: Skipping invalid group: $groupName"
            }
        }
    }

    return $true
}


function count() {
    param(
        [string] $haystack,
        [string] $needle
    )
    return [int]([regex]::Matches($haystack, $needle)).Count
}

function contains($haystack, $needle) {
    return [bool]((count -haystack $haystack -needle $needle) -gt 0)
}

class Material {
    [string] $name
    [string] $open_date_priority # Open date determines expiration
    [string] $expiration_type
    [string] $stability_time
    [string] $instrument
    [bool] $is_open

    # This are being tacked on just to handle formatting issues with the printer.
    # Dynamic generation of the label format is tricky with the legacy code
    [string] $name_string
    [string] $open_string
    [string] $preparation_string #thaw/reconst/etc
    [string] $expiration_string
    [string] $remark_string_part_one # expiration criterion not met comment
    [string] $remark_string_part_two # expiration criterion not met comment

    [string] $RawZPL

    Material() {
    }

    [void] SetName([string] $name) {
        $this.name = $name
    }

    [void] SetExpirationType([string] $expiration_type) {
        $this.expiration_type = $expiration_type
        if ($expiration_type.ToLower().Contains("open")) {
            $this.open_date_priority = $true
        } else {
            $this.open_date_priority = $false
        }

    }

    [void] SetInstrument([string] $instrument) {
        $this.instrument = $instrument
    }

    [void] SetStabilityTime([string] $stability_time) {
        $this.stability_time = $stability_time
    }
    [void] vPrintMaterialInfo() {
        Write-Debug "==========MATERIAL============"
        Write-Debug ("Material name: {0}" -f $this.name)
        Write-Debug ("Material expiration: {0}" -f $this.expiration_type)
        Write-Debug ("Material stability: {0}" -f $this.stability_time)
        Write-Debug ("Material instrument: {0}" -f $this.instrument)
        Write-Debug "=============================="
    }

    [string] format_label($open_state) 
    {
        if ($this.RawZPL) {
            return $this.RawZPL
        }

        #capture the open state
        $this.is_open = $open_state

        # This Builds a label string based on material properties incrementally
        $TIME_FMT = 'hh:mm'
        
        $DATE_FMT = 'MM-dd-yy'

        $today = Get-Date

        $washRounded = $false

        # Custom rule to round time forward for wash solutions
        $eveningStart = [datetime]::ParseExact("8:00pm", "h:mmtt", $null)
        $eveningEnd = [datetime]::ParseExact("11:59pm", "h:mmtt", $null)
        if ((contains -haystack $this.name -needle "% Wash") -and (((Get-Date) -gt $eveningStart) -and ((Get-Date) -lt $eveningEnd))) {
            $today = $today.AddDays(1)
            $washRounded = $true
            $global:side_pane.push_down("`nNotice: Rounding time forward`nto midnight for Wash`nSolution`n") 

        }

        if (-not $washRounded) {
            # if within 15Ã¢â‚¬Â¯minutes of midnight, bump to 00:01 next day
            $midnight = $today.Date.AddDays(1)
            if ($today -ge $midnight.AddMinutes(-15) -and $today -lt $midnight) {
                $today = $midnight.AddMinutes(1)
                $global:side_pane.push_down("`nNotice: Rounding time forward`n  to just past midnight`n")
            }
        }
        

        $todays_date = $today.ToString($DATE_FMT)
        $todays_time = $today.ToString($TIME_FMT)


        # All labels
        # Removed spacing to accommodate hematology labels with long names
        $this.name_string = $this.name

        # Has reagent been opened?
        if ($open_state) {
            $this.open_string = "   Open: $todays_date"
            if ($global:printerIp -eq "127.0.0.1") {
                $global:side_pane.push_down("$this")
            }
            if ($this.instrument -eq "CS2500") {
                $this.open_string = " Open: $todays_date $todays_time"
            }
        } else {
            $this.open_string = "   Open:"
        }

        # HOW WAS IT PREPARED?
        # ====================
        # Thawed
        if ($this.expiration_type -eq "Thawed")
        {
            $this.preparation_string = "Thawed: $todays_date"

        }
        # Reconsistuted
        if ($this.expiration_type -eq "Reconstituted")
        {
            $this.preparation_string = "Reconst: $todays_date"
            if ($this.instrument -eq "CS2500") {
                $this.preparation_string += " $todays_time"
            }
        }
        # Thaw&Open still writes a thaw date
        if ($this.expiration_type -eq "Thaw&open")
        {
            $this.preparation_string = "Thawed: $todays_date"
        }
        # ====================
        # OPEN DATE DOES NOT DETERMINE EXPIRATION DATE
        if (($this.expiration_type -eq "Thawed") -or ($this.expiration_type -eq "Reconstituted"))
        {
            $this.expiration_string = "  Exp:{0}" -f (((Get-Date).AddDays($this.stability_time)).ToString($DATE_FMT))
        }
        # OPEN DATE DETERMINES EXPIRATION
        if (($this.expiration_type -eq "Thaw&open") -or ($this.expiration_type -eq "Opened"))
        {
            
            if ($open_state) {
                $label += "     Exp:{0}`n" -f (((Get-Date).AddDays($this.stability_time)).ToString($DATE_FMT))
                if ((contains -haystack $this.name -needle "100% Wash")) {
                    $today = Get-Date
                }
                $this.expiration_string = "  Exp:{0}" -f ((($today).AddDays($this.stability_time)).ToString($DATE_FMT))
                if ($this.instrument -eq "CS2500") {
                    $this.expiration_string = "  Exp: {0} $todays_time" -f ((($today).AddDays($this.stability_time)).ToString($DATE_FMT))
                }
            } else {
                $label += "     Exp:`n"
                $label += "**Expires {0} days`n  from open date" -f $this.stability_time
                $this.expiration_string = "     Exp:"
                $this.remark_string_part_one = "**Expires {0} days" -f $this.stability_time
                $this.remark_string_part_two = "  from open date"
            }
        }
        if ($global:TEST_BUILD) {
            $label+= "[Test Version {0}]" -f $global:VERSION
        }

        return $null
    }

    [Material] Clone() {
        # Create a new instance of the Material class
        $clone = [Material]::new()

        # Copy each property to the new instance
        $clone.name = $this.name
        $clone.open_date_priority = $this.open_date_priority
        $clone.expiration_type = $this.expiration_type
        $clone.stability_time = $this.stability_time
        $clone.instrument = $this.instrument
        $clone.is_open = $this.is_open
        $clone.name_string = $this.name_string
        $clone.open_string = $this.open_string
        $clone.preparation_string = $this.preparation_string
        $clone.expiration_string = $this.expiration_string
        $clone.remark_string_part_one = $this.remark_string_part_one
        $clone.remark_string_part_two = $this.remark_string_part_two
        $clone.RawZPL = $this.RawZPL

        return $clone
    }
    [string] ToString() {
        # Format the string representation of the object
        $open_status = if ($this.is_open) { "Open" } else { "Closed" }
        $formattedString = @"
Material Details:
=======================
Name                : $($this.name)
Open Date Priority  : $($this.open_date_priority)
Expiration Type     : $($this.expiration_type)
Stability Time      : $($this.stability_time)
Instrument          : $($this.instrument)
Is Open             : $open_status
Name String         : $($this.name_string)
Open String         : $($this.open_string)
Preparation String  : $($this.preparation_string)
Expiration String   : $($this.expiration_string)
Remark String Part 1: $($this.remark_string_part_one)
Remark String Part 2: $($this.remark_string_part_two)
=======================
"@
        return $formattedString
    }
}



class MaterialGroup {
    [string] $group_name
    [string] $instrument
    [Material[]] $materials_list = @()

    MaterialGroup() {
    }

    [void] SetInstrument([string] $instrument) {
        $this.instrument = $instrument
    }



    [void] SetGroupName([string] $group_name) {
        if (![string]::IsNullOrWhiteSpace($group_name)) {
            $this.group_name = $group_name
        } else {
            Write-Debug "Warning: Attempted to set empty group name"
        }
    }

    [bool] IsValid() {
        return ![string]::IsNullOrWhiteSpace($this.group_name) -and $this.materials_list.Count -gt 0
    }

    [void] AddMaterial([Material] $material) {
        $this.materials_list += $material
    }

    [void] RemoveMaterial([Material] $material) {
        $this.materials_list = $this.materials_list.Where({ $_ -ne $material })
    }

    [void] vPrintMaterialsInfo() {
        foreach ($_mat in $this.materials_list)
        {
            $_mat.vPrintMaterialInfo()
        }
    }
}


function getMaterials_old {
    param ([string]$line)
    # Constants for field indices
    $MATERIAL_GROUP = 0
    $INSTRUMENT = 1
    $EXPIRATION_TYPE = 3

    $_materials = @()
    $csv_list = ($line -split ";")
    $_material_group = $csv_list[$MATERIAL_GROUP]
    $_instrument = $csv_list[$INSTRUMENT]
    $_expiration_type = $csv_list[$EXPIRATION_TYPE]
    
    Write-Debug "Material group: $_material_group"
    Write-Debug "Instrument: $_instrument"
    Write-Debug "Expiration type: $_expiration_type"
    
    $reagent_names = ($csv_list[$REAGENT_NAMES] -split ",")
    $stability_times = ($csv_list[$STABILITY_TIME] -split ",")

    for ($i = 0; $i -lt $reagent_names.Length; $i++)
    {
        $_new_material = [Material]::new()
        $_new_material.SetName($reagent_names[$i].Trim())
        $_new_material.SetExpirationType($_expiration_type)
        if ($_expiration_type -eq $null) {
            Write-Error($_new_material)
        }
        $_new_material.SetStabilityTime($stability_times[$i].Trim())
        $_new_material.SetInstrument($_instrument)
        $_materials += $_new_material
    }

    Write-Debug "Parsed materials:"
    $_materials | ForEach-Object { Write-Debug $_.name }
    return $_materials
}


function getMaterials {
    param ([string]$line)
    # Constants for field indices
    $MATERIAL_GROUP = 0
    $INSTRUMENT = 1
    $EXPIRATION_TYPE = 3

    $_materials = @()
    $csv_list = ($line -split ";")
    $_material_group = $csv_list[$MATERIAL_GROUP]
    $_instrument = $csv_list[$INSTRUMENT]
    $_expiration_type = $csv_list[$EXPIRATION_TYPE]
    
    Write-Debug "Material group: $_material_group"
    Write-Debug "Instrument: $_instrument"
    Write-Debug "Expiration type: $_expiration_type"
    
    $reagent_names = ($csv_list[$REAGENT_NAMES] -split ",")
    $stability_times = ($csv_list[$STABILITY_TIME] -split ",")

    # Optionally, get the override field if present (assumed index 5)
    $override = $null
    if ($csv_list.Length -ge 6) {
        $override = $csv_list[5].Trim()
    }

    # Attempt to parse the override if it exists and is in the expected format
    $overrideParsed = $null
    if ($override -and $override -match '^{override=(.+)}$') {
        $jsonString = $matches[1]
        try {
            $overrideParsed = $jsonString | ConvertFrom-Json
        } catch {
            Write-Debug "Error parsing override JSON: $jsonString"
        }
    }
    
    # Loop through each reagent entry
    for ($i = 0; $i -lt $reagent_names.Length; $i++) {
        $_new_material = [Material]::new()
        $_new_material.SetName($reagent_names[$i].Trim())
        $_new_material.SetExpirationType($_expiration_type)
        $_new_material.SetStabilityTime($stability_times[$i].Trim())
        $_new_material.SetInstrument($_instrument)
        
        # If an override is parsed, assign it.
        if ($overrideParsed) {
            if ($overrideParsed -is [System.Collections.IEnumerable] -and -not ($overrideParsed -is [Hashtable])) {
                # It's an array Ã¢â‚¬â€œ if the counts match, assign per reagent.
                if ($overrideParsed.Count -eq $reagent_names.Length) {
                    $currentOverride = $overrideParsed[$i]
                    if ($currentOverride.raw_zplii) {
                        $_new_material.RawZPL = $currentOverride.raw_zplii
                    }
                } else {
                    # Otherwise, fall back to the same override for all reagents.
                    if ($overrideParsed.raw_zplii) {
                        $_new_material.RawZPL = $overrideParsed.raw_zplii
                    }
                }
            } elseif ($overrideParsed -is [Hashtable] -or $overrideParsed.PSObject -ne $null) {
                # Single override object: assign to all reagents.
                if ($overrideParsed.raw_zplii) {
                    $_new_material.RawZPL = $overrideParsed.raw_zplii
                }
            }
        }
        
        $_materials += $_new_material
    }

    Write-Debug "Parsed materials:"
    $_materials | ForEach-Object { Write-Debug $_.name }
    return $_materials
}
