# Published CSV link:
#https://docs.google.com/spreadsheets/d/e/2PACX-1vRL6PKYNT-6OfbPxJDU7TiYXKYVYY75YhlEmfAD1HRF0fWXwTbJ2JwbRUG-jgOiOBKl-f_QIOjyG5Ne/pub?output=csv
#https://docs.google.com/spreadsheets/d/15leQ_Hy9kxP_PmoBwOqyDEln9Vvy5Bpilqm4LrJ56lE/edit?usp=sharing



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
        #capture the open state
        $this.is_open = $open_state

        # This Builds a label string based on material properties incrementally
        $TIME_FMT = 'hh:mm'
        
        $DATE_FMT = 'MM-dd-yy'

        $today = Get-Date

        # Custom rule to round time forward for wash solutions
        $eveningStart = [datetime]::ParseExact("8:00pm", "h:mmtt", $null)
        $eveningEnd = [datetime]::ParseExact("11:59pm", "h:mmtt", $null)
        if ((contains -haystack $this.name -needle "% Wash") -and (((Get-Date) -gt $eveningStart) -and ((Get-Date) -lt $eveningEnd))) {
            $today = $today.AddDays(1)
            $global:side_pane.push_down("`nNotice: Rounding time forward`nto midnight for Wash`nSolution`n") 

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
                $this.open_string = "   Open: $todays_date $todays_time"
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
                $this.expiration_string = "     Exp:{0}" -f ((($today).AddDays($this.stability_time)).ToString($DATE_FMT))
                if ($this.instrument -eq "CS2500") {
                    $this.expiration_string = " {0}" -f $todays_time
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


function getMaterials {
    param ([string]$line)
    # Constants for field indices
    $MATERIAL_GROUP = 0
    $INSTRUMENT = 1

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


