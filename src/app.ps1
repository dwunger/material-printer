using module '.\Materials.psm1' 
using module '.\ScreenManager.psm1'
using module '..\huginn\utils.psm1'
using module '.\muginn.psm1'

# Launch asynchronous job to fetch the online CSV
$csvUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRL6PKYNT-6OfbPxJDU7TiYXKYVYY75YhlEmfAD1HRF0fWXwTbJ2JwbRUG-jgOiOBKl-f_QIOjyG5Ne/pub?output=csv"
$job = Start-Job -ScriptBlock {
    param($url)
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        return $response.Content
    } catch {
        return $null
    }
} -ArgumentList $csvUrl

#TODOs
# Printer configuration setup file (IP address, print method (xylene/standard))
# Add menu for printer configuration/selection
# Display open status of reagents


#BUGS
# Pushing printer onto stack lags one cycle
# Unmapped inputs cause an infinite display refresh loop - Appears to be fixed.

#EXECUTION FLAGS
# powershell -ExecutionPolicy Bypass -File .\qc_labels.ps1
# Setting policy at runtime still fails to render some ANSI color codes. 
# Can't use the debugger since the ISE console doesn't handle escape codes for cursor positioning (Why Microsoft?)
# That might not even help anyway since the runtime links to .NET
#######################################CONSTANTS##########################################
$global:TEST_BUILD = 0
$global:VERSION = Query-Parameter -File ".\MANIFEST" -Parameter "VERSION"
$global:DISABLE_PRINT = $false

$INSTRUMENT_SELECT = 0;
$MATERIAL_GROUP_SELECT = 1;
$MATERIAL_SELECT = 2;

$DXI_SELECT = 0;
$DXC_SELECT = 1;

# Write-Host won't work in this script due to the display implementations managing the console buffer. You have to write to a log file if print style debugging is necessary. This is intentional to discourage accumulating a bunch of write-host calls drawing things where they're unexpected and muddying the screen state
$DEBUG_LOGGING = $false
#$DEBUG_LOGFILE = 'C:\Users\dunger01\Documents\Quick Setup\QC Materials Printer\log.txt'
#$DEBUG_LOGFILE = 'C:\Users\denton\Documents\Quick Setup\QC Materials Printer\log.txt'

# Pseudo constant macros
# These are just indices into arrays 
$MATERIAL_GROUP = 0;
$INSTRUMENT = 1;
$REAGENT_NAMES = 2;
$EXPIRATION_TYPE = 3;
$STABILITY_TIME = 4;


$PrimaryDisplayHeight = 18
#####################################END CONSTANTS#########################################
Add-Type -AssemblyName System.Windows.Forms # For keycodes

#this shouldn't exist. I don't want to test removing PrinterManager instances, so c'est la vie
$global:startup = $false

$ESC = [char]27
$BOLD = "$ESC[1m"
$UNDERLINE = "$ESC[4m"
$RESET_FMT = "$ESC[0m"

$RED_FG = "$ESC[91m"
$GREEN_FG = "$ESC[92m"
$YELLOW_FG = "$ESC[93m"
$CYAN_FG = "$ESC[96m"

$GRAY_BG = "$ESC[47m" 
$BLACK_FG = "$ESC[30m"

$LEFT_ARROW = [char]0x2190
$DOWN_ARROW = [char]0x2193
$UP_ARROW = [char]0x2191
$RIGHT_ARROW = [char]0x2192

# CMA if in debug mode:
if ($DISABLE_PRINT){
    $global:VERSION += "$RED_FG - Printing is Disabled in Debug Mode."
} 

$STARTUP_LOGMSG = "- SP Thaw&Open $RIGHT_ARROW Thawed`n- Added manual entry for`n  ISE calibrators`n- Added Leaderboard!`n- Removed WebRequest Cache`n- Made WebRequest async`n  to speed up startup `n  routine`n- 's' - Snek Overhaul!`n- Huginn SemVer bug fix"
$STARTUP_LOGMSG = $STARTUP_LOGMSG -replace "`n", "`n$YELLOW_FG"

# Import-Module command with detailed parameter explanation

#Import-Module [-Name] <string[]> # Name or path of the module to import, supports wildcards for names.
#  [-Global]                      # Imports the module into the global session state for all sessions.
#  [-Prefix <string>]             # Adds a prefix to the names of commands in the module.
#  [-Function <string[]>]         # Imports only the specified functions from the module.
#  [-Cmdlet <string[]>]           # Imports only the specified cmdlets from the module.
#  [-Variable <string[]>]         # Imports only the specified variables from the module.
#  [-Alias <string[]>]            # Imports only the specified aliases from the module.
#  [-Force]                       # Forces the import of the module, even if versions conflict.
#  [-PassThru]                    # Returns objects representing the module that was imported.
#  [-AsCustomObject]              # Imports the module's functions as methods of a custom object.
#  [-MinimumVersion <version>]    # Specifies the minimum version of the module to import.
#  [-MaximumVersion <string>]     # Specifies the maximum version of the module to import.
#  [-RequiredVersion <version>]   # Specifies the exact version of the module to import.
#  [-ArgumentList <Object[]>]     # Passes arguments to the module script during import.
#  [-DisableNameChecking]         # Disables warnings about command names that do not conform to standards.
#  [-NoClobber]                   # Prevents the import from overwriting existing functions, variables, etc.
#  [-Scope {Local | Global}]      # Specifies the scope in which this command is run.
#  [<CommonParameters>]           # Common parameters that can be used with most cmdlets.
###################################IMPORTS#################################################


##########################



#########################

# Function to read contents and return
function Get-FileContent {
    param ([string]$filePath)
    if (Test-Path $filePath) { $fileContent = Get-Content -Path $filePath
        return $fileContent
    } else {
        Write-Host "File does not exist: $filePath"
        return $null
    }
}


function count() {
    param(
        [string] $haystack,
        [string] $needle
    )
    return [int]([regex]::Matches($haystack, $needle)).Count
}

function abs($value) {
    return [Math]::Abs($value)
}



####################################################################################################################################################

######STRING VIEW##########
function Search-Between {
    param (
        [string] $haystack,
        [string] $start,
        [string] $end
    )

    $start_idx = $haystack.IndexOf($start)
    if ($start_idx -eq -1) {
        return ""
    }
    # Move just past the $start sequence
    $start_idx += $start.Length

    $end_idx = $haystack.IndexOf($end, $start_idx)
    if ($end_idx -eq -1) {
        return ""
    }

    return $haystack.Substring($start_idx, $end_idx - $start_idx)
}



###########################


##################################################################### MENUS #########################################################################
# used to track the last selected item when selecting materials to restore cursor position when a new menu is constructed 
$global:last_selected_item = 0
class Menu {
    [string[]] $items
    [int] $selectedItem = 0
    [Display] $display

    Menu([string[]] $menuItems, [Display] $display) {
        $this.items = $menuItems
        $this.display = $display
        $this.selectedItem = $global:last_selected_item
    }

    [void] DisplayMenu() {
        $this.display.clear()
        
        if (($this.selectedItem -lt $this.items.Length) -or ($this.selectedItem -gt $this.items.Length -1)) {
            $this.selectedItem = $this.selectedItem % $this.items.Length
        }
        #$global:side_pane.push_down("Selected item: " + $this.selectedItem.ToString())
        for ($i = 0; $i -lt $this.items.Length; $i++) {
            if ($i -eq $this.selectedItem) {
                $this.display.write("$global:ESC[36m--> $global:RESET_FMT" + "$global:UNDERLINE" + $this.items[$i] + "$global:RESET_FMT")
            } else {
                $this.display.write("    " + $this.items[$i])
            }
        }
        $this.display.trim()
        $this.display.flush()
    }

    [int] GetUserInput([System.Management.Automation.Host.KeyInfo]$initialKey) {
        $key = $initialKey
        
        do {
            switch ($key.VirtualKeyCode) {
                38 {  # UpArrow key code
                    if ($this.selectedItem -eq 0) {
                        $this.selectedItem = $this.items.Length - 1
                    } else {
                        $this.selectedItem--
                    }
                    $this.DisplayMenu()
                }
                40 {  # DownArrow key code
                    $this.selectedItem++
                    $this.DisplayMenu()

                }
                13 {  # Enter key code
                    #track the selected item when selecting materials to restore cursor position
                    if ($global:menu_level -eq $global:MATERIAL_SELECT){
                        $global:last_selected_item = $this.selectedItem
                    
                    }
                    return $this.selectedItem
                }

                39 {  # Right Arrow key code
                    #track the selected item when selecting materials to restore cursor position
                    if ($global:menu_level -eq $global:MATERIAL_SELECT){
                        $global:last_selected_item = $this.selectedItem
                    
                    }
                    return $this.selectedItem
                }

                default {
                    $global:LastUnprocessedKeystroke = $key
                    return -1
                }
            }
            $key = $global:Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } while ($true)
        return -1
    }
}
##################################################################### MATERIALS #########################################################################

##################################################################### PRINTER #########################################################################

class PrinterManager {
    [string]$ConfigPath
    [System.Collections.ArrayList]$Printers
    [hashtable]$PrinterHeaders
    [string]$DefaultPrinterIp
    [bool]$startup
    PrinterManager([string]$configPath) {
        $this.ConfigPath = $configPath
        $this.Printers = @()
        $this.PrinterHeaders = @{}
        $this.LoadConfig()
        $this.SetDefaultPrinterIp()

    }

    [void]LoadConfig() {
        if (-not (Test-Path $this.ConfigPath)) {
            Write-Host "Config file does not exist: $this.ConfigPath"
            return
        }

        $content = Get-Content -Path $this.ConfigPath
        $headers = $content[0] -split ';'
        $this.PrinterHeaders = @{
            "Name" = $headers[0]
            "IpAddress" = $headers[1]
            "ReservedField" = $headers[2]
            "IsDefault" = $headers[3]
        }

        for ($i = 1; $i -lt $content.Length; $i++) {
            $line = $content[$i] -split ';'
            $printer = @{
                "Name" = $line[0]
                "IpAddress" = $line[1]
                "ReservedField" = $line[2]
                "IsDefault" = $line[3]
            }
            $this.Printers.Add($printer)
        }
    }

    [void]SetDefaultPrinterIp() {
        foreach ($printer in $this.Printers) {
            if ($printer["IsDefault"] -eq "1") {
                $global:printerIp = $printer["IpAddress"]

                if ($global:startup) { 
                    $global:side_pane.push_down("Startup: Loaded Printer:`n ${global:GREEN_FG}$($printer["Name"])") 
                    $global:startup = $false
                } 
                
                $this.DefaultPrinterIp = $printer["IpAddress"]
                return
            }
        }
        
    }

    [void]SetDefaultPrinter([string]$printerName) {
        $found = $false
        foreach ($printer in $this.Printers) {
            if ($printer["Name"] -eq $printerName) {
                $printer["IsDefault"] = "1"
                $global:printerIp = $printer["IpAddress"]
                $this.DefaultPrinterIp = $printer["IpAddress"]
                $found = $true
                

            } else {
                $printer["IsDefault"] = ""
            }
        }
        if ($found) {
            $this.SaveConfig()
            Write-Host "Default printer set to: $printerName"
            $global:side_pane.push_down("Loaded Printer:`n ${global:GREEN_FG}$(&{$printerName})")
        } else {
            Write-Host "Printer not found: $printerName"
        }
    }

    [void]SaveConfig() {
        $output = @()
        $output += "$($this.PrinterHeaders["Name"]);$($this.PrinterHeaders["IpAddress"]);$($this.PrinterHeaders["ReservedField"]);$($this.PrinterHeaders["IsDefault"])"
        foreach ($printer in $this.Printers) {
            $output += "$($printer["Name"]);$($printer["IpAddress"]);$($printer["ReservedField"]);$($printer["IsDefault"])"
        }
        $output | Set-Content -Path $this.ConfigPath
    }
}

function open-status-helper() {
    # Just got tired of looking at this in main. Should be a ternary
    if ($global:is_open) {
            return "Printing reagents as: $ESC[92mOpened$ESC[0m   | 'o' to toggle status"
        } else {
            return "Printing reagents as: $ESC[91mUnopened$ESC[0m | 'o' to toggle status"
        }
}
##################################################################### PRINTER #########################################################################


##################################PRINT LABEL SECTION#####################################

$printerIp = "10.32.40.22" #micro dual
$printerIp = "10.32.48.12" #xylene printer hematology
$printerIp = "10.32.48.11" #chemistry
$global:printerName = "Chemistry"
$copies = 1

$printerPort = 9100


function SendToPrinter([Material]$mat1, [Material]$mat2) {
    #$global:side_pane.push_down("STP mat1: $($mat1.GetType().FullName)")
    #$global:side_pane.push_down("STP mat2: $($mat2.GetType().FullName)")
    
    $_ = $mat1.format_label($mat1.is_open)
    $_ = $mat2.format_label($mat2.is_open)
    $zplCommands = @"
^XA
^CF0,20,20
^FO17,35^A0N,16,16^FD$($mat1.name_string)^FS
^FO220,35^A0N,16,16^FD$($mat2.name_string)^FS
^FO17,55^A0N,16,16^FD$($mat1.open_string)^FS
^FO220,55^A0N,16,16^FD$($mat2.open_string)^FS
^FO17,75^A0N,16,16^FD$($mat1.preparation_string)^FS
^FO220,75^A0N,16,16^FD$($mat2.preparation_string)^FS
^FO17,95^A0N,16,16^FD$($mat1.expiration_string)^FS
^FO220,95^A0N,16,16^FD$($mat2.expiration_string)^FS
^FO17,115^A0N,16,16^FD$($mat1.remark_string_part_one)^FS
^FO220,115^A0N,16,16^FD$($mat2.remark_string_part_one)^FS
^FO17,135^A0N,16,16^FD$($mat1.remark_string_part_two)^FS
^FO220,135^A0N,16,16^FD$($mat2.remark_string_part_two)^FS
^XZ
"@

        $tcpClient = $null
        $networkStream = $null

        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient($global:PrinterIp, $global:PrinterPort)
            $networkStream = $tcpClient.GetStream()

            $bytes = [System.Text.Encoding]::ASCII.GetBytes($zplCommands)
            $networkStream.Write($bytes, 0, $bytes.Length)

            #Write-Host "Sent to printer:"
            #Write-Host $zplCommands
        }
        catch {
            Write-Host "Error sending data to printer: $_"
        }
        finally {
            if ($networkStream) { $networkStream.Close() }
            if ($tcpClient) { $tcpClient.Close() }
        }
}

$global:LabelQueue = @()

function print_label([Material] $material){
    $_ = $material.format_label($global:is_open) # this captures global state and saves it for printing, regardless of whether we're using the output
    $material = $material.Clone()
    $global:LabelQueue += $material
    $global:side_pane.push_down("${BOLD}Enqueued: $($material.name) - ${RESET}$(&{open_helper2($material.is_open)})")
    #$global:side_pane.push_down("Type of enqueued item: $($material.GetType().FullName)")

    if ($global:LabelQueue.Count -eq 2) {
        $global:QueuePending = $false 
        $mat1 = $global:LabelQueue[0]
        $mat2 = $global:LabelQueue[1]
        $global:side_pane.push_down("${BOLD}${GREEN_FG}Printing Queue!")
        #$global:side_pane.push_down("Type of mat1: $($mat1.GetType().FullName)")
        #$global:side_pane.push_down("Type of mat2: $($mat2.GetType().FullName)")

        if (-not $global:DISABLE_PRINT) {
            SendToPrinter $mat1 $mat2
        }
        $global:LabelQueue = @()
    } else {
        $global:QueuePending = $true # there's an item waiting in the queue that can be flushed
    }
}
###################################END PRINT LABEL SECTION##################################

###################################ELECTROLYTE LABELS#######################################

function Read-Barcode {
    $delimiters = 0
    $barcode = ""

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        
        # If End key is pressed, signal manual entry by returning $null
        if ($key.VirtualKeyCode -eq 35) {
            return $null
        }
        
        $barcode += $key.Character
        if ($key.Character -eq "\") {
            $delimiters += 1
        }
        if ($delimiters -gt 1) {
            break
        }
    }
    
    return $barcode
}

class ElectrolyteLabels {
    [string]$PrinterIp
    [int]$PrinterPort
    [int]$Copies
    [bool]$DEBUG = $false  # Set this to false to disable debug prints

    ElectrolyteLabels([string]$printerIp, [int]$printerPort) {
        $this.PrinterIp = $printerIp
        $this.PrinterPort = $printerPort
        $this.Copies = 1
    }

    [string] ParseBarcodeComponent([string]$input, [int]$start, [int]$length) {
        $result = $input.Trim("\")[$start..($start+$length-1)] -join ''
        if ($this.DEBUG) {
            Clear-Host
            Write-Host "DEBUG: ParseBarcodeComponent Input: $input, Start: $start, Length: $length"
            Write-Host "DEBUG: ParseBarcodeComponent Output: $result"
            Read-Host
        }
        return $result
    }

    [string] ParseBarcodeLot([string]$input) {
        $result = $this.ParseBarcodeComponent($input, -4, 4)
        if ($this.DEBUG) {
            Clear-Host
            Write-Host "DEBUG: ParseBarcodeLot Input: $input"
            Write-Host "DEBUG: ParseBarcodeLot Output: $result"
        }
        return $result
    }

    [string] ParseBarcodeExpiration([string]$input) {
        $dd = $this.ParseBarcodeComponent($input, -8, 2)
        $mm = $this.ParseBarcodeComponent($input, -10, 2)
        $yy = $this.ParseBarcodeComponent($input, -12, 2)
        $yyyy = "20$yy"
        $result = "$yyyy-$mm-$dd"
        if ($this.DEBUG) {
            Clear-Host
            Write-Host "DEBUG: ParseBarcodeExpiration Input: $input"
            Write-Host "DEBUG: ParseBarcodeExpiration Output: $result"
            Read-Host
        }
        return $result
    }

    [string] ParseElectrolyteBarcode([string]$message) {
        Clear-Host
        Write-Host $message
        $barcode = Read-Barcode

        if (-not $barcode) {
            # End key pressed; prompt for manual entry.
            $lot = Read-Host "Enter Lot number manually"
            $exp = Read-Host "Enter Expiration date (YYYY-MM-DD) manually"
            return "$lot $exp"
        }

        $lot = $this.ParseBarcodeLot($barcode)
        $expDate = $this.ParseBarcodeExpiration($barcode)
        return "$lot $expDate"
    }

    [void] SendToPrinter($urinelow_parsed,$urinehigh_parsed,$serumlow_parsed,$serumhigh_parsed) {

        $zplCommands = @"
^XA
^CF0,20,20
^FO10,30^A0N,20,20^FDLow Serum Standard       Low Serum Standard^FS
^FO10,60^A0N,20,20^FD$serumlow_parsed       $serumlow_parsed^FS
^FO10,90^A0N,20,20^FDHigh Serum Standard      High Serum Standard^FS
^FO10,120^A0N,20,20^FD$serumhigh_parsed       $serumhigh_parsed^FS
^FO10,150^A0N,20,20^FDLow Urine Standard       Low Urine Standard^FS
^FO10,180^A0N,20,20^FD$urinelow_parsed       $urinelow_parsed^FS
^FO10,210^A0N,20,20^FDHigh Urine Standard      High Urine Standard^FS
^FO10,240^A0N,20,20^FD$urinehigh_parsed       $urinehigh_parsed
^XZ
"@

        $tcpClient = $null
        $networkStream = $null

        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient($this.PrinterIp, $this.PrinterPort)
            $networkStream = $tcpClient.GetStream()

            $bytes = [System.Text.Encoding]::ASCII.GetBytes($zplCommands)
            $networkStream.Write($bytes, 0, $bytes.Length)

            Write-Host "Sent to printer:"
            Write-Host $zplCommands
        }
        catch {
            Write-Host "Error sending data to printer: $_"
        }
        finally {
            if ($networkStream) { $networkStream.Close() }
            if ($tcpClient) { $tcpClient.Close() }
        }
    }

    [void] PrintLabels() {
        $urinelow_parsed = $this.ParseElectrolyteBarcode("Scan Low Urine Barcode or press the End key for manual entry:")
        $urinehigh_parsed = $this.ParseElectrolyteBarcode("Scan High Urine Barcode or press the End key for manual entry:")
        $serumlow_parsed = $this.ParseElectrolyteBarcode("Scan Low Serum Barcode or press the End key for manual entry:")
        $serumhigh_parsed = $this.ParseElectrolyteBarcode("Scan High Serum Barcode or press the End key for manual entry:")
    

        Clear-Host
        Write-Host "How many copies to print?"
        $this.Copies = [int](Read-Host)
        for ($i=0; $i -lt $this.Copies; $i++) {
            $this.SendToPrinter($urinelow_parsed,$urinehigh_parsed,$serumlow_parsed,$serumhigh_parsed)
        }
    }
}

function electrolyte-labels {
    
    if ($global:DISABLE_PRINT) {
        return
    }

    # yes we are hardcoding this
    $printerIp = "10.32.40.22" # micro dual
    $printerPort = 9100
    
    $electrolyteLabels = [ElectrolyteLabels]::new($printerIp, $printerPort)
    $electrolyteLabels.PrintLabels()
    Clear-Host
}

###################################ELECTROLYTE LABELS#######################################


#########################################MENU HELPER########################################
# Helper function for instrument selection
function Select-Instrument {
    param (
        [array]$instrument_select_array,
        [Display]$display
    )
    $display.setHeader(@("QC Material Label Printer".PadRight(71), "$global:open_status_message", "Select an instrument:"))
    $menu = [Menu]::new($instrument_select_array, $display)
    $menu.DisplayMenu()
    $userKey = $global:Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    return $menu.GetUserInput($userKey)
}

# Helper function for material group selection
function Select-MaterialGroup {
    param (
        [array]$material_groups,
        [Display]$display
    )
    $display.setHeader(@("QC Material Label Printer".PadRight(71), "$global:open_status_message", "Select a category:"))
    $menu_array = $material_groups | ForEach-Object { $_.group_name }
    $menu = [Menu]::new($menu_array, $display)
    $menu.DisplayMenu()
    $userKey = $global:Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    return $menu.GetUserInput($userKey)
}

# Helper function for material selection
function Select-Material {
    param (
        [MaterialGroup]$selected_group,
        [Display]$display
    )
    #$display.setHeader(@(($GRAY_BG + $BLACK_FG + $UNDERLINE + ("$QC Material Label Printer".PadRight(40)) + $RESET_FMT), "$global:open_status_message", "Select a reagent to print:"))
    $display.setHeader(@("QC Material Label Printer".PadRight(71), "$global:open_status_message", "Select a reagent to print:"))
    $menu_array = $selected_group.materials_list | ForEach-Object { $_.name }
    $menu = [Menu]::new($menu_array, $display)
    $menu.DisplayMenu()
    $userKey = $global:Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    return $menu.GetUserInput($userKey)
}

# Helper function to handle key input
function Handle-KeyInput-Deprecated {
    param (
        [System.Management.Automation.Host.KeyInfo]$key
    )
    if ($key.VirtualKeyCode -eq 66 -or  # 'b' key
        $key.VirtualKeyCode -eq 27 -or  # Escape key
        $key.VirtualKeyCode -eq 37) {   # Left arrow key
        return "back"
    }
    elseif ($key.VirtualKeyCode -eq 79) {   # 'o' key
        return "toggle"
    }
    elseif ($key.VirtualKeyCode -eq 80) { # 'p' key
        return "select-printer"
    }
    elseif ($key.VirtualKeyCode -eq 69) { # 'e' key - nice
        return "electrolyte-labels"
    }
    elseif ($key.VirtualKeyCode -eq 68) { # 'd' key
        return "debug"
    }
    elseif ($key.VirtualKeyCode -eq 70) { # 'f' key
        return "flush-queue"
    }
    elseif ($key.VirtualKeyCode -eq 82) { # 'r' key
        return "resource-config"
    }
    elseif ($key.VirtualKeyCode -eq 77) { # 'm' key
        return "muginn"
    }
    elseif ($key.VirtualKeyCode -eq 85) { # 'u' key
        return "update"
    }
    elseif ($key.VirtualKeyCode -eq 83) { # 's' key
        return "snek"
    }

    return "continue"
}

function Handle-KeyInput {
    param (
        [System.Management.Automation.Host.KeyInfo]$key
    )
    
    if ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::B -or
        $key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::Escape -or
        $key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::Left) {
        return "back"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::O) {
        return "toggle"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::P) {
        return "select-printer"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::E) {
        return "electrolyte-labels"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::D) {
        return "debug"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::F) {
        return "flush-queue"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::R) {
        return "resource-config"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::M) {
        return "muginn"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::U) {
        return "update"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::S) {
        return "snek"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::C) {
        return "cmd"
    }
    return "continue"
}


# Helper function for printer selection
function select-printer() {
    Clear-Host
    # Initialize display
    $global:display = [Display]::new(15)
    $menu_controls = "Menu Controls: $LEFT_ARROW - Back | $DOWN_ARROW - Down | $UP_ARROW - Up | $RIGHT_ARROW or [Enter] - Select";

    $global:display.setFooter(@("", $menu_controls))
    # Initialize PrinterManager
    $printerManager = [PrinterManager]::new("./src/printer_config.csv")

    # Create menu with printer names
    $menu_array = $printerManager.Printers | ForEach-Object { $_["Name"] }

    $menu = [Menu]::new($menu_array, $global:display)

    # Main Interactive Menu/Print loop
    while ($true) {

        $global:display.setHeader(@("QC Material Label Printer".PadRight(71), "", "Select a printer:"))
        #$global:display.setHeader(@((($GRAY_BG + $BLACK_FG + $UNDERLINE + ("$QC Material Label Printer".PadRight(71))) + $RESET_FMT), "", "Select a printer:"))
        $menu.DisplayMenu()

        $userKey = $global:Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $selectedPrinterIndex = $menu.GetUserInput($userKey)

        if ($selectedPrinterIndex -ge 0) {
            Clear-Host
            $selectedPrinterName = $menu_array[$selectedPrinterIndex]
            $printerManager.SetDefaultPrinter($selectedPrinterName)
            Write-Host "New default printer IP: $global:printerIp"
            break
        }
    }
}

function flush-queue($last_material) {
    $blank_mat = [Material]::new()
    $blank_mat.name = "This label is not blank"
    if ($global:QueuePending) {
        print_label($blank_mat)
    }
    
}
######################################END MENU HELPER########################################


$global:LastUnprocessedKeystroke = $null #This is used to handle unregistered input in the menu display loop
$global:is_open = $false

function refresh-display-helper($menu_controls, $state_controls, $global:VERSION) {
    $global:display = [Display]::new(18)
    $menu_controls = "Menu Controls: $LEFT_ARROW - Back | $DOWN_ARROW - Down | $UP_ARROW - Up | $RIGHT_ARROW or [Enter] - Select";
    $state_controls= "Misc Controls: 'p' - Change printer | 'e' - Electrolyte Labels";

    $global:display.setFooter(@("", $menu_controls, $state_controls, "'f' - flush queue | 'r' - Resource Config | 'm' - Muginn | 'u' - Update", $global:VERSION))
}

function open_helper() {
    if ($global:is_open){
        return ("{0}Open" -f $GREEN_FG)
    } else {
        return ("{0}Closed" -f $RED_FG )
    }
}

# Not sure if powershell does name mangling
function open_helper2([bool] $open) {
    if ($open){
        return ("{0}Open" -f $GREEN_FG)
    } else {
        return ("{0}Closed" -f $RED_FG )
    }
}

# Helper function for locking open status for CS2500
function Lock-CS2500-Open-Status {
    $selected_instrument = $instrument_select_array[$instrument_menu_selection]
    if (($selected_instrument -eq "CS2500") -and (-not $global:is_open)) {
        $global:is_open = $true
    }
}

# Helper function for refreshing the display
function Refresh-Display {
    $global:display = [Display]::new($PrimaryDisplayHeight)
    $menu_controls = "Menu Controls: $LEFT_ARROW - Back | $DOWN_ARROW - Down | $UP_ARROW - Up | $RIGHT_ARROW or [Enter] - Select";
    $state_controls= "Misc Controls: 'p' - Change printer | 'e' - Electrolyte Labels";

    $global:display.setFooter(@("", $menu_controls, $state_controls, "'f' - flush queue | 'r' - Resource Config | 'm' - Muginn | 'u' - Update", $global:VERSION))
    $global:side_pane.DISABLE_REFRESH = $false
    $global:side_pane.redraw()
    $global:side_pane.draw_border()

}

function Muginn-Old {
    $global:side_pane.push_down($CYAN_FG + "Enter Printer Name:")
    [console]::SetCursorPosition(0,19)
    $addr = Read-Host
    $global:side_pane.push_down($CYAN_FG + "Muginn busy...")
    $value = Get-Darkness -printerIp $addr
    $global:side_pane.push_down($BOLD + "Darkness: $value")
}

function Muginn {
    $screen_height = 10
    $screen_width = 71

    #Need to expand the console to fit muginn
    Set-Window-Dimensions -width 108 -height (20 + $screen_height)
    $Screen = [StackScreen]::new(0,$PrimaryDisplayHeight, $screen_width, $screen_height)
    $Screen.draw_border()

    $Screen.push_down($CYAN_FG + "s - Set Darkness")
    $Screen.push_down($CYAN_FG + "g - Get Darkness")
    
    [console]::SetCursorPosition(1,21)
    [char] $user_input = Read-Host

    $junk = $Screen.pop()
    $junk = $Screen.pop()

    if ($user_input -notin ('g','s')) { return } 

    $Screen.push_down($CYAN_FG + "Enter Printer Name:")

    [console]::SetCursorPosition(21,19)
    $addr = Read-Host
    $junk = $Screen.pop()

    $Screen.push_down($CYAN_FG + "Enter Printer Name:" + $addr)
    $junk = $Screen.pop()

    switch ($user_input) {
        "g" 
        {  
            $DarknessSetting = Get-Darkness -printerIP $addr
        }
        "s" 
        {  
            $Screen.push_down($CYAN_FG + "Enter darkness setting:")
            [console]::SetCursorPosition(25,19)
            $value = Read-Host
            $DarknessSetting = Set-Darkness -printerIP $addr -value $value

            $junk = $Screen.pop()

        }

    }


    $Screen.push_down($CYAN_FG + "Muginn busy...")
    
    
    $value = Get-Darkness -printerIp $addr
    $Screen.push_down($BOLD + "Darkness: $value")
}




function main() {
    
    #Set-Window-Dimensions -width 69 -height 20 # Without side pane
    #Set-Window-Dimensions -width 105 -height 20 # With side pane
    Set-Window-Dimensions -width 107 -height 20 # With side pane
    Clear-Host

    #$global:side_pane = [StackScreen]::new(67,0,34,18)
    $global:side_pane = [StackScreen]::new(71,0,34,$PrimaryDisplayHeight)

    $global:side_pane.draw_border()

    $global:side_pane.push_down("Local version: " + $global:VERSION)
    $global:side_pane.push_down($YELLOW_FG + $STARTUP_LOGMSG)


    $global:startup = $true
    $printerManager = [PrinterManager]::new("./src/printer_config.csv")
    $global:printerIp = $printerManager.DefaultPrinterIp

    # Wait for the remote CSV fetch to complete
    $remoteContent = Receive-Job -Job $global:job -Wait -AutoRemoveJob

    $materialGroupsByInstrument = Setup-MaterialGroups-Async -RemoteContent $remoteContent
    if ($null -eq $materialGroupsByInstrument) {
        Write-Host "Failed to initialize material groups. Exiting."
        return 1
    }


    $global:menu_level = $INSTRUMENT_SELECT
    $instrument_select_array = $materialGroupsByInstrument.Keys | Sort-Object

    $global:display = [Display]::new($PrimaryDisplayHeight)
    $menu_controls = "Menu Controls: $LEFT_ARROW - Back | $DOWN_ARROW - Down | $UP_ARROW - Up | $RIGHT_ARROW or [Enter] - Select";
    $state_controls= "Misc Controls: 'p' - Change printer | 'e' - Electrolyte Labels";

    $global:display.setFooter(@("", $menu_controls, $state_controls, "'f' - flush queue | 'r' - Resource Config | 'm' - Muginn | 'u' - Update", $global:VERSION))

    $instrument_menu_selection = 0
    $selected_group_index = 0
    $selected_material_index = 0

    # Interactive menu loop
    while ($true) 
    {

        # Unlock open status at menu root
        if ((($selected_instrument -eq "CS2500") -or ($selected_instrument -eq "Core Lab")) -and ($global:menu_level -eq $INSTRUMENT_SELECT)) {
            $TOGGLE_ENABLED = $true
        }

        # Lock open status to `open` for CS2500 items
        if ((($selected_instrument -eq "CS2500")  -or ($selected_instrument -eq "Core Lab")) -and (-not $global:is_open)) {
            $global:is_open = (-not $global:is_open)
            $TOGGLE_ENABLED = $false
        } else {
            $TOGGLE_ENABLED = $true
        }

        $global:open_status_message = open-status-helper



        switch ($global:menu_level) {
            $INSTRUMENT_SELECT {
                $selectedItem = Select-Instrument -instrument_select_array $instrument_select_array -display $global:display
                if ($selectedItem -ge $INSTRUMENT_SELECT) {
                    $instrument_menu_selection = $selectedItem
                    $global:menu_level = $MATERIAL_GROUP_SELECT
                }
                Lock-CS2500-Open-Status

            }
            $MATERIAL_GROUP_SELECT {
                $selected_instrument = $instrument_select_array[$instrument_menu_selection]

                $material_groups = $materialGroupsByInstrument[$selected_instrument]
                $selectedItem = Select-MaterialGroup -material_groups $material_groups -display $global:display
                if ($selectedItem -ge $INSTRUMENT_SELECT) {
                    $selected_group_index = $selectedItem
                    $global:menu_level = $MATERIAL_SELECT
                }
                Lock-CS2500-Open-Status
            }
            $MATERIAL_SELECT {
                $selected_instrument = $instrument_select_array[$instrument_menu_selection]
                $selected_group = $materialGroupsByInstrument[$selected_instrument][$selected_group_index]
                $selectedItem = Select-Material -selected_group $selected_group -display $global:display
                if ($selectedItem -ge $INSTRUMENT_SELECT) {
                    $selected_material_index = $selectedItem
                    $selected_material = $selected_group.materials_list[$selected_material_index]
                    print_label -material $selected_material
                    #Write-Error -Message $selected_material
                    #Write-Host "Selected material: $($selected_material.name)"
                    #$global:side_pane.push_down("${BOLD}Printed: $($selected_material.name) - ${RESET}$(&{open_helper})")
                }
                Lock-CS2500-Open-Status

            }
        }

        # User supplied an input with no mapping above. Let this fall through so it's not lost
        if ($global:LastUnprocessedKeystroke) 
        {
            $key = $global:LastUnprocessedKeystroke
            $global:LastUnprocessedKeystroke = $null
            $action = Handle-KeyInput -key $key

            switch ($action) 
            {
                    "back" 
                    {
                        if ($global:menu_level -gt $INSTRUMENT_SELECT) { $global:menu_level-- }
                    }
                    "toggle" 
                    {
                        if ($TOGGLE_ENABLED) { $global:is_open = (-not $global:is_open) }
                    }
                    "select-printer" 
                    {
                        $global:side_pane.Hide()
                        select-printer
                        $global:side_pane.Show()
                        Refresh-Display
                    }
                    "electrolyte-labels" 
                    {
                        $global:side_pane.Hide()
                        electrolyte-labels
                        $global:side_pane.Show()
                        Refresh-Display
                    }
                    "flush-queue" 
                    {
                        if ($global:QueuePending) {
                            flush-queue($selected_material)
                        }
                    }
                    "resource-config" 
                    {
                        $browser = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
                        $link = 'https://docs.google.com/spreadsheets/d/15leQ_Hy9kxP_PmoBwOqyDEln9Vvy5Bpilqm4LrJ56lE/edit?usp=sharing'
                        if (Test-Path $browser) {
                            $global:side_pane.push_down("Launching Edge...")
                            & $browser $link # Requires the invocation operator
                        } else {
                            $global:side_pane.push_down("[ERROR] Browser unavailable.")
                        }
                    }
                    "muginn" 
                    {
                        Muginn
                    }
                    "update"
                    {
                        Update-Client
                        Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ".\src\app.ps1"' -NoNewWindow
                        exit
                    }
                    "snek"
                    {
                        Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ".\src\BootStrapper.ps1" 2> error.txt' -NoNewWindow -Wait
                     }
                    "cmd"
                    {
                        Start-Process powershell_ise.exe '.\src\app.ps1'
                        Start-Process powershell.exe
                     }
                    "debug"
                    {
                        $host.EnterNestedPrompt()
                    }
           }
        }
    }
    return 0
}
main

#https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/product/tlp2824plus-ug-en.pdf
#https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/software/zplii-pm-vol1.pdf
