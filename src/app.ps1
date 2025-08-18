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

if (Test-Path '~\Desktop\QC Label Printer `[TEST`].lnk') {
   Move '~\Desktop\QC Label Printer `[TEST`].lnk' '~\Desktop\Label Printer.lnk'
    # Define the path to the shortcut and icon
    $shortcutPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('Desktop'), 'Label Printer.lnk')
    $iconPath = [System.IO.Path]::Combine('C:\Users\dunger01\Documents\Quick Setup\QC Materials Printer', 'qclabelprinter1.ico')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.IconLocation = $iconPath
    $shortcut.Save()
    Write-Output "Shortcut icon has been changed."
}

#EXECUTION FLAGS
# powershell -ExecutionPolicy Bypass -File .\qc_labels.ps1
# Setting policy at runtime still fails to render some ANSI color codes. 
# Can't use the debugger since the ISE console doesn't handle escape codes for cursor positioning (Why Microsoft?)
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
$PrimaryDisplayMinWidth = 74
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

$STARTUP_LOGMSG = "- Now copies ISE calibrator barcodes`n  when scanned`n- Added conservative rounding for `n  near-midnight prints`n- Added special clean labels`n"

# prepend the orange alert, then color the body bright yellow
$STARTUP_LOGMSG = $STARTUP_LOGMSG -replace "`n", "`n$CYAN_FG"

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
        $actualPrinterName = $null
        foreach ($printer in $this.Printers) {
            if (($printer["Name"] -eq $printerName) -or ($printer["IpAddress"] -eq $printerName)) {
                $printer["IsDefault"] = "1"
                $global:printerIp = $printer["IpAddress"]
                $this.DefaultPrinterIp = $printer["IpAddress"]
                $actualPrinterName = $printer["Name"]
                $found = $true
            } else {
                $printer["IsDefault"] = ""
            }
        }
        if ($found) {
            $this.SaveConfig()
            Write-Host "Default printer set to: $actualPrinterName"
             $global:side_pane.push_down("Loaded Printer:`n ${global:GREEN_FG}$actualPrinterName")
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

function PrintRawLabel([Material] $material) {
    $rawZpl = $material.RawZPL
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient($global:PrinterIp, $global:PrinterPort)
        $networkStream = $tcpClient.GetStream()
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($rawZpl)
        $networkStream.Write($bytes, 0, $bytes.Length)
        $global:side_pane.push_down("${BOLD}${GREEN_FG}Printed raw label: $($material.name)${RESET}")
    }
    catch {
        Write-Host "Error sending raw label to printer: $_"
    }
    finally {
        if ($networkStream) { $networkStream.Close() }
        if ($tcpClient) { $tcpClient.Close() }
    }
}

function print_label([Material] $material){
    $material = $material.Clone()
    
    # If a raw override is provided, bypass formatting and print immediately.
    if ($material.RawZPL) {
        if ($global:LabelQueue.Count -gt 0) {
            $global:LabelQueue = @()  # Clear the queue if something's pending.
        }
        if (-not $global:DISABLE_PRINT) {
            PrintRawLabel $material
        }
        return  # Skip further processing.
    }
    
    # Otherwise, run the standard formatting and enqueue.
    $_ = $material.format_label($global:is_open)
    $global:LabelQueue += $material
    $global:side_pane.push_down("${BOLD}Enqueued: $($material.name) - ${RESET}$(&{open_helper2($material.is_open)})")

    if ($global:LabelQueue.Count -eq 2) {
        $global:QueuePending = $false 
        $mat1 = $global:LabelQueue[0]
        $mat2 = $global:LabelQueue[1]
        $global:side_pane.push_down("${BOLD}${GREEN_FG}Printing Queue!")
        if (-not $global:DISABLE_PRINT) {
            SendToPrinter $mat1 $mat2
        }
        $global:LabelQueue = @()
    }
    else {
        $global:QueuePending = $true
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
    [string]$LastBarcode

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

    [void] PrintRawBarcodeLabel([string]$raw, [string]$caption) {
        if ([string]::IsNullOrWhiteSpace($raw)) { return }

        $zpl = @"
^XA
^CI28
^CF0,28,28
^FO30,30^BQN,2,7^FDLA,$raw^FS
^FO30,240^A0N,32,32^FD$caption^FS
^FO230,30^BQN,2,7^FDLA,$raw^FS
^FO230,240^A0N,32,32^FD$caption^FS
^XZ
"@

        $tcpClient = $null
        $networkStream = $null
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient($this.PrinterIp, $this.PrinterPort)
            $networkStream = $tcpClient.GetStream()
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($zpl)
            $networkStream.Write($bytes, 0, $bytes.Length)

            if ($this.DEBUG) {
                Write-Host "DEBUG: Printed single raw barcode label:"
                Write-Host $zpl
            }
        }
        catch {
            Write-Host "Error printing raw barcode label: $_"
        }
        finally {
            if ($networkStream) { $networkStream.Close() }
            if ($tcpClient) { $tcpClient.Close() }
        }
    }

    [string] ParseElectrolyteBarcode([string]$message, [string]$rawCaption) {
        Clear-Host
        Write-Host $message
        $barcode = Read-Barcode

        if (-not $barcode) {
            # End key pressed; prompt for manual entry (no raw copy printed)
            $lot = Read-Host "Enter Lot number manually"
            $exp = Read-Host "Enter Expiration date (YYYY-MM-DD) manually"
            return "$lot $exp"
        }

        # Remember last raw scan and immediately print one raw copy with caption
        $this.LastBarcode = $barcode
        $this.PrintRawBarcodeLabel($barcode, $rawCaption)

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
        $urinelow_parsed  = $this.ParseElectrolyteBarcode("Scan Low Urine Barcode or press the End key for manual entry:",  "urine low")
        # (single raw-copy label for urine low is printed at scan-time)

        $urinehigh_parsed = $this.ParseElectrolyteBarcode("Scan High Urine Barcode or press the End key for manual entry:", "urine high")
        # (single raw-copy label for urine high is printed at scan-time)

        $serumlow_parsed  = $this.ParseElectrolyteBarcode("Scan Low Serum Barcode or press the End key for manual entry:",  "serum low")
        # (single raw-copy label for serum low is printed at scan-time)

        $serumhigh_parsed = $this.ParseElectrolyteBarcode("Scan High Serum Barcode or press the End key for manual entry:", "serum high")
        # (single raw-copy label for serum high is printed at scan-time)

        Clear-Host
        Write-Host "How many copies to print?"
        $this.Copies = [int](Read-Host)
        for ($i=0; $i -lt $this.Copies; $i++) {
            $this.SendToPrinter($urinelow_parsed,$urinehigh_parsed,$serumlow_parsed,$serumhigh_parsed)
        }
    }
}


function Set-DefaultPrinter {
     param(
     [string] $printerID # This is either a printer name or IP address
     )
     $printerManager = [PrinterManager]::new("./src/printer_config.csv")
     $printerManager.SetDefaultPrinter($printerID)
 }

function electrolyte-labels {
    
    if ($global:DISABLE_PRINT) {
        return
    }

    $savedIP = $global:PrinterIp
 
     Clear-Host
     Write-Host "Print ISE Calibration labels to..."
     select-printer
 
     # no, we are not anymore. we live in a society
     $printerIp = $global:PrinterIp

    $printerPort = 9100
    
    $electrolyteLabels = [ElectrolyteLabels]::new($printerIp, $printerPort)
    $electrolyteLabels.PrintLabels()
    Clear-Host

     $global:side_pane.push_down("Restored your printer preference.")
 
     Set-DefaultPrinter -printerID $savedIP
}

###################################ELECTROLYTE LABELS#######################################


#########################################MENU HELPER########################################
# Helper function for instrument selection
function Select-Instrument {
    param (
        [array]$instrument_select_array,
        [Display]$display
    )
    $display.setHeader(@("QC Material Label Printer".PadRight($PrimaryDisplayMinWidth), "$global:open_status_message", "Select an instrument:"))
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
    $display.setHeader(@("QC Material Label Printer".PadRight($PrimaryDisplayMinWidth), "$global:open_status_message", "Select a category:"))
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
    $display.setHeader(@("QC Material Label Printer".PadRight($PrimaryDisplayMinWidth), "$global:open_status_message", "Select a reagent to print:"))
    $menu_array = $selected_group.materials_list | ForEach-Object { $_.name }
    $menu = [Menu]::new($menu_array, $display)
    $menu.DisplayMenu()
    $userKey = $global:Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    return $menu.GetUserInput($userKey)
}

# Helper function to handle key input
function Handle-KeyInput {
    param (
        [System.Management.Automation.Host.KeyInfo]$key
    )
    
    if ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::Escape -or
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
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::F5) {
        return "reload"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::X) {
        return "pepe"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::H) {
        return "help"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::I) {
        return "duck"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::B) {
        return "barcode"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::G) {
        return "frogbog"
    }
    elseif ($key.VirtualKeyCode -eq [System.Windows.Forms.Keys]::OemQuestion) {
        return "advancedhelp"
    }
    return "continue"
}

function ayuda {
    # Developer controls (in reverse alphabetical order for the stack)
    $global:side_pane.push_down("$BOLD$CYAN_FG[u]$RESET_FMT  - Force update")
    $global:side_pane.push_down("$BOLD$CYAN_FG[m]$RESET_FMT  - Muginn utility")
    $global:side_pane.push_down("$BOLD$CYAN_FG[F5]$RESET_FMT - Reload application")
    $global:side_pane.push_down("$BOLD$CYAN_FG[d]$RESET_FMT  - Start Runtime Debugging")
    $global:side_pane.push_down("$BOLD$CYAN_FG[c]$RESET_FMT  - Open Powershell ISE")
    $global:side_pane.push_down("$BOLD$CYAN_FG[ DEVELOPER ]$RESET_FMT")

    # Regular controls (in reverse alphabetical order for the stack)
    $global:side_pane.push_down("$BOLD$CYAN_FG[s]$RESET_FMT  - Launch Snek")
    $global:side_pane.push_down("$BOLD$CYAN_FG[r]$RESET_FMT  - Edit online resources")
    $global:side_pane.push_down("$BOLD$CYAN_FG[p]$RESET_FMT  - Select printer")
    $global:side_pane.push_down("$BOLD$CYAN_FG[o]$RESET_FMT  - Toggle material open status")
    $global:side_pane.push_down("$BOLD$CYAN_FG[h]$RESET_FMT  - Show help output")
    $global:side_pane.push_down("$BOLD$CYAN_FG[g]$RESET_FMT  - Launch Frog Bog")
    $global:side_pane.push_down("$BOLD$CYAN_FG[f]$RESET_FMT  - Flush printing queue")
    $global:side_pane.push_down("$BOLD$CYAN_FG[e]$RESET_FMT  - Print ISE Calibration labels")
    $global:side_pane.push_down("$BOLD$CYAN_FG[b]$RESET_FMT  - Printer Downtime Barcodes")
    $global:side_pane.push_down("$BOLD$CYAN_FG[ CONTROLS HELP ]$RESET_FMT")
}

# Helper function for printer selection
function select-printer() {
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

        $global:display.setHeader(@("QC Material Label Printer".PadRight($PrimaryDisplayMinWidth), "", "Select a printer:"))
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
    $state_controls= "P - Change printer | E - ISE Labels | F - flush print queue | H - Help";

    $global:display.setFooter(@("", $menu_controls, $state_controls, $global:VERSION))
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
    $state_controls= "P - Change printer | E - ISE Labels | F - flush print queue | H - Help";

    $global:display.setFooter(@("", $menu_controls, $state_controls, $global:VERSION))
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
    $screen_width = $PrimaryDisplayMinWidth

    #Need to expand the console to fit muginn
    Set-Window-Dimensions -width 115 -height (20 + $screen_height)
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

# Draw a duck frame using direct cursor positioning for each line.
function Write-DuckFrame {
    param(
        [int]$x,
        [string]$frameType,  # Accepts "open", "normal", or "closed"
        [int]$y = 0
    )
    $CIRCLED_WHITE_BULLET = [char]0x2022
    [System.Console]::SetCursorPosition($x, $y)
    Write-Host "    _" -NoNewline
    [System.Console]::SetCursorPosition($x, $y + 1)
    switch ($frameType) {
        "open"   { Write-Host " __($CIRCLED_WHITE_BULLET)<" -NoNewline }
        "normal" { Write-Host " __($CIRCLED_WHITE_BULLET)=" -NoNewline }
        "closed" { Write-Host " __($CIRCLED_WHITE_BULLET)>" -NoNewline }
    }
    [System.Console]::SetCursorPosition($x, $y + 2)
    Write-Host " \___)" -NoNewline
}

# Clear the region where the duck frame was drawn by writing spaces.
function Clear-DuckFrame {
    param(
        [int]$x,
        [int]$y,
        [int]$clearWidth = 20  # Number of characters to clear per line
    )
    for ($i = 0; $i -lt 3; $i++) {
        [System.Console]::SetCursorPosition($x, $y + $i)
        Write-Host (" " * $clearWidth) -NoNewline
    }
}

# Animate the duck moving across the screen using position writes for both drawing and erasing.
function Invoke-DuckAnimation {
    $width = [System.Console]::WindowWidth
    $maxX = $width - 65  # Reserve room so the duck doesn't run off-screen.
    $duckY = 10         # Fixed vertical position for the duck.
    $states = @("open", "normal", "closed", "normal")
    
    [Console]::CursorVisible = $false
    Clear-Host
    $oldX = $null
    for ($x = 0; $x -le $maxX; $x++) {
        # Erase the previous duck frame by overwriting with spaces.
        if ($oldX -ne $null) {
            Clear-DuckFrame -x $oldX -y $duckY
        }
        $state = $states[$x % $states.Length]
        Write-DuckFrame -x $x -frameType $state -y $duckY
        Start-Sleep -Milliseconds 15
        $oldX = $x
    }
    # Clear the final duck frame.
    Clear-DuckFrame -x $oldX -y $duckY
    [Console]::CursorVisible = $true
}

# Animate an explosion using math-based particle motion.
function Invoke-AsciiExplosion {
    [Console]::CursorVisible = $false
    $width   = [System.Console]::WindowWidth
    $height  = [System.Console]::WindowHeight
    $centerX = [Math]::Floor($width / 2)
    $centerY = [Math]::Floor($height / 2)

    $numParticles = 100
    $colors = @("Red", "DarkYellow", "Yellow")
    $sizes  = @('*', 'o', '.', '@', '%', '&', '$', '~', ',')

    $particles = @()
    for ($i = 0; $i -lt $numParticles; $i++) {
        $angle = Get-Random -Minimum 0 -Maximum (2 * [Math]::PI)
        $speed = Get-Random -Minimum 5 -Maximum 20
        $colorIndex = Get-Random -Minimum 0 -Maximum $colors.Count
        $sizeIndex  = Get-Random -Minimum 0 -Maximum $sizes.Count

        $particles += [PSCustomObject]@{
            x      = $centerX
            y      = $centerY
            vx     = $speed * [Math]::Cos($angle)
            vy     = $speed * [Math]::Sin($angle)
            color  = $colors[$colorIndex]
            char   = $sizes[$sizeIndex]
            lastX  = $centerX
            lastY  = $centerY
        }
    }

    $frames  = 25
    $dt      = 5.0 / $frames
    $gravity = 3.0

    for ($frame = 0; $frame -lt $frames; $frame++) {
        foreach ($p in $particles) {
            # Clear previous position
            $lastXi = [Math]::Round($p.lastX)
            $lastYi = [Math]::Round($p.lastY)

            if ($lastXi -ge 0 -and $lastXi -lt $width -and $lastYi -ge 0 -and $lastYi -lt $height) {
                [System.Console]::SetCursorPosition($lastXi, $lastYi)
                Write-Host ' ' -NoNewline
            }

            # Update position
            $p.lastX = $p.x
            $p.lastY = $p.y

            $p.x += $p.vx * $dt
            $p.y += $p.vy * $dt
            $p.vy += $gravity * $dt
        }

        foreach ($p in $particles) {
            $xi = [Math]::Round($p.x)
            $yi = [Math]::Round($p.y)

            if ($xi -ge 0 -and $xi -lt $width -and $yi -ge 0 -and $yi -lt $height) {
                [System.Console]::SetCursorPosition($xi, $yi)
                Write-Host $p.char -ForegroundColor $p.color -NoNewline
            }
        }

        Start-Sleep -Seconds $dt
    }

    # Final clear of particles
    foreach ($p in $particles) {
        $xi = [Math]::Round($p.x)
        $yi = [Math]::Round($p.y)

        if ($xi -ge 0 -and $xi -lt $width -and $yi -ge 0 -and $yi -lt $height) {
            [System.Console]::SetCursorPosition($xi, $yi)
            Write-Host ' ' -NoNewline
        }
    }

    [Console]::CursorVisible = $true
    Clear-Host
}

# Main function: Animate the duck crossing the screen, then trigger the explosion.
function Invoke-DuckAndExplosion {
    Invoke-DuckAnimation
    Start-Sleep -Seconds 0.5  # Brief pause between animations
    Invoke-AsciiExplosion
}

function AdvancedHelp {
    # Get the full absolute path to the help file
    $helpFilePath = (Resolve-Path ".\src\Help.html").Path
    
    # Create a temporary directory if it doesn't exist
    $tempDir = Join-Path $env:TEMP "QCLabelPrinterHelp"
    if (-not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    }
    
    # Create a temporary file with a unique name
    $tempFile = Join-Path $tempDir "Help_$(Get-Date -Format 'yyyyMMddHHmmss').html"
    
    # Read the help file content
    $helpContent = Get-Content -Path $helpFilePath -Raw
    
    # Replace the version placeholder with the actual version
    $helpContent = $helpContent -replace 'VERSION_PLACEHOLDER', $global:VERSION
    
    # Write the updated content to the temp file
    $helpContent | Set-Content -Path $tempFile -Force
    
    try {
        # Try using the default system handler to open the temp file
        Invoke-Item $tempFile
        $global:side_pane.push_down("Advanced help opened in browser.")
        
        # Optional: Schedule cleanup of temp file after some time
        Start-Job -ScriptBlock {
            param($file)
            Start-Sleep -Seconds 300  # Wait 5 minutes
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
        } -ArgumentList $tempFile | Out-Null
    }
    catch {
        # Fallback method if Invoke-Item fails
        $browser = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        if (Test-Path $browser) {
            Start-Process -FilePath $browser -ArgumentList "`"$tempFile`""
            $global:side_pane.push_down("Advanced help opened in Edge browser.")
        } else {
            $global:side_pane.push_down("Failed to open help file. Please check the path: $tempFile")
        }
    }
}


function main {
    # initialize per-level cursor history: 0=instrument, 1=group, 2=material
    $global:last_selected_index = @(0, 0, 0)

    # set up layout
    Set-Window-Dimensions -width 115 -height (20 + $screen_height)
    Clear-Host

    # side pane
    $global:side_pane = [StackScreen]::new($PrimaryDisplayMinWidth, 0, 39, $PrimaryDisplayHeight)
    $global:side_pane.draw_border()
    $global:side_pane.push_down("Local version: " + $global:VERSION)
    $global:side_pane.push_down($CYAN_FG + $STARTUP_LOGMSG)

    # printer init
    $global:startup = $true
    $printerManager = [PrinterManager]::new("./src/printer_config.csv")
    $global:printerIp = $printerManager.DefaultPrinterIp

    # wait for remote CSV
    $remoteContent = Receive-Job -Job $global:job -Wait -AutoRemoveJob
    $materialGroupsByInstrument = Setup-MaterialGroups-Async -RemoteContent $remoteContent
    if ($null -eq $materialGroupsByInstrument) {
        Write-Host "Failed to initialize material groups. Exiting."
        return 1
    }

    # menu state
    $global:menu_level       = $INSTRUMENT_SELECT
    $instrument_select_array = $materialGroupsByInstrument.Keys | Sort-Object

    # footer controls
    $global:display = [Display]::new($PrimaryDisplayHeight)
    $menu_controls  = "Menu Controls: $LEFT_ARROW - Back | $DOWN_ARROW - Down | $UP_ARROW - Up | $RIGHT_ARROW or [Enter] - Select"
    $state_controls = "P - Change printer | E - ISE Labels | F - flush print queue | H - Help"
    $global:display.setFooter(@("", $menu_controls, $state_controls, $global:VERSION))

    # track selections per level
    $instrument_menu_selection = 0
    $selected_group_index      = 0
    $selected_material_index   = 0

    # interactive loop
    while ($true) {
        # unlock open toggle at root for CS2500/Core Lab
        if ((($instrument_select_array[$instrument_menu_selection] -eq "CS2500") -or ($instrument_select_array[$instrument_menu_selection] -eq "Core Lab")) -and ($global:menu_level -eq $INSTRUMENT_SELECT)) {
            $TOGGLE_ENABLED = $true
        }
        # force open and lock toggle for CS2500 group/material levels
        if ((($global:menu_level -ne $INSTRUMENT_SELECT) -and (($instrument_select_array[$instrument_menu_selection] -eq "CS2500") -or ($instrument_select_array[$instrument_menu_selection] -eq "Core Lab"))) -and (-not $global:is_open)) {
            $global:is_open     = $true
            $TOGGLE_ENABLED     = $false
        } else {
            $TOGGLE_ENABLED = $true
        }

        # update open status
        $global:open_status_message = open-status-helper

        switch ($global:menu_level) {
            $INSTRUMENT_SELECT {
                # header for instrument
                $global:display.setHeader(@("QC Material Label Printer".PadRight($PrimaryDisplayMinWidth), $global:open_status_message, "Select an instrument:"))
                # restore previous cursor
                $menu = [Menu]::new($instrument_select_array, $global:display)
                $menu.selectedItem = $global:last_selected_index[$INSTRUMENT_SELECT]
                $menu.DisplayMenu()
                $key = $global:Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                $sel = $menu.GetUserInput($key)
                if ($sel -ge 0) {
                    $instrument_menu_selection = $sel
                    $global:menu_level         = $MATERIAL_GROUP_SELECT
                    $global:last_selected_index[$INSTRUMENT_SELECT] = $sel
                }
                Lock-CS2500-Open-Status
            }
            $MATERIAL_GROUP_SELECT {
                $selected_instrument = $instrument_select_array[$instrument_menu_selection]
                $groups              = $materialGroupsByInstrument[$selected_instrument]
                # header for category
                $global:display.setHeader(@("QC Material Label Printer".PadRight($PrimaryDisplayMinWidth), $global:open_status_message, "Select a category:"))

                $menu = [Menu]::new($groups.group_name, $global:display)
                $menu.selectedItem = $global:last_selected_index[$MATERIAL_GROUP_SELECT]
                $menu.DisplayMenu()
                $key = $global:Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                $sel = $menu.GetUserInput($key)
                if ($sel -ge 0) {
                    $selected_group_index = $sel
                    $global:menu_level    = $MATERIAL_SELECT
                    $global:last_selected_index[$MATERIAL_GROUP_SELECT] = $sel
                }
                Lock-CS2500-Open-Status
            }
            $MATERIAL_SELECT {
                $selected_instrument = $instrument_select_array[$instrument_menu_selection]
                $group               = $materialGroupsByInstrument[$selected_instrument][$selected_group_index]
                # header for material
                $global:display.setHeader(@("QC Material Label Printer".PadRight($PrimaryDisplayMinWidth), $global:open_status_message, "Select a reagent to print:"))

                $menu = [Menu]::new($group.materials_list.name, $global:display)
                $menu.selectedItem = $global:last_selected_index[$MATERIAL_SELECT]
                $menu.DisplayMenu()
                $key = $global:Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                $sel = $menu.GetUserInput($key)
                if ($sel -ge 0) {
                    $selected_material_index = $sel
                    print_label -material $group.materials_list[$sel]
                    $global:last_selected_index[$MATERIAL_SELECT] = $sel
                }
                Lock-CS2500-Open-Status
            }
        }

        # handle unmapped keystrokes
        if ($global:LastUnprocessedKeystroke) {
            $key = $global:LastUnprocessedKeystroke
            $global:LastUnprocessedKeystroke = $null
            $action = Handle-KeyInput -key $key

            switch ($action) {
                "back"               { if ($global:menu_level -gt $INSTRUMENT_SELECT) { $global:menu_level-- } }
                "toggle"             { if ($TOGGLE_ENABLED) { $global:is_open = -not $global:is_open } }
                "select-printer"     {
                    $global:side_pane.Hide(); Clear-Host
                    select-printer
                    $global:side_pane.Show()
                    Refresh-Display
                }
                "electrolyte-labels" {
                    $global:side_pane.Hide(); electrolyte-labels; $global:side_pane.Show(); Refresh-Display
                }
                "flush-queue"        { if ($global:QueuePending) { flush-queue($null) } }
                "resource-config"    {
                    $browser = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
                    $link    = 'https://docs.google.com/spreadsheets/d/15leQ_Hy9kxP_PmoBwOqyDEln9Vvy5Bpilqm4LrJ56lE/edit?usp=sharing'
                    if (Test-Path $browser) { $global:side_pane.push_down("Launching Edge..."); & $browser $link } 
                    else { $global:side_pane.push_down("[ERROR] Browser unavailable.") }
                }
                "muginn"             { Muginn }
                "update"             {
                    powershell.exe -ExecutionPolicy Bypass -File .\Huginn.ps1
                    Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ".\src\app.ps1"' -NoNewWindow
                    exit
                }
                "snek"               { Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ".\src\BootStrapper.ps1" 2> error.txt' -NoNewWindow -Wait }
                "cmd"                { Start-Process powershell_ise.exe '.\src\app.ps1'; Start-Process powershell.exe }
                "debug"              { $host.EnterNestedPrompt() }
                "reload"             { Start-Process conhost.exe -ArgumentList 'powershell -ExecutionPolicy Bypass -File ".\src\app.ps1"'; return 0 }
                "help"               { ayuda; AdvancedHelp }
                "duck"               { Invoke-DuckAndExplosion; Refresh-Display }
                "barcode"            { Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ".\src\BarcodeGenerator.ps1"' -NoNewWindow }
                "frogbog"            { Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -STA -File ".\src\FrogBog.ps1"' -NoNewWindow }
                "advancedhelp"       { AdvancedHelp }
                "pepe"               { powershell.exe -NoProfile -File .\src\ImagePrint.ps1 -PrinterIp $global:printerIp }
            }
        }
    }
    return 0
}


main

#https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/product/tlp2824plus-ug-en.pdf
#https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/software/zplii-pm-vol1.pdf
