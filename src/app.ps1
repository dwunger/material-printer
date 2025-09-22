using module '.\Materials.psm1' 
using module '.\ScreenManager.psm1'
using module '..\huginn\utils.psm1'
using module '.\muginn.psm1'

# Launch asynchronous job to fetch the online CSV


########### OFFLINE PATCH
#$csvUrl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRL6PKYNT-6OfbPxJDU7TiYXKYVYY75YhlEmfAD1HRF0fWXwTbJ2JwbRUG-jgOiOBKl-f_QIOjyG5Ne/pub?output=csv"
#$job = Start-Job -ScriptBlock {
#    param($url)
#    try {
#        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
#        return $response.Content
#    } catch {
#        return $null
#    }
#} -ArgumentList $csvUrl


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

$STARTUP_LOGMSG = "- In all their great wisdom`n  IT blocked part of Google's domain`n  So, this patch is offline with`n  a custom mini-Excel Engine`n- Added copies and scan features`n  to downtime barcode printer"

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
    [hashtable]$PrinterHeaders   # original header text/order for saving
    [string]$DefaultPrinterIp
    [bool]$AutoCreate = $true    # create file if missing with default header

    PrinterManager([string]$configPath) {
        $this.Printers       = [System.Collections.ArrayList]::new()
        $this.PrinterHeaders = @{}
        $this.ConfigPath     = $this.ResolveConfigPath($configPath)
        $this.LoadConfig()
        $this.SetDefaultPrinterIp()
    }

    hidden [string] NormalizeName([string]$s) {
        if (-not $s) { return $s }
        return ($s -replace '^\uFEFF','').Trim().ToLowerInvariant()
    }

    hidden [string] ExpandHome([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return $p }
        if ($p.StartsWith('~')) {
            $home = $HOME
            if (-not $home) { $home = [Environment]::GetFolderPath('UserProfile') }
            if ($p.Length -eq 1) { return $home }
            return (Join-Path $home $p.Substring(2))  # handles "~/..."
        }
        return $p
    }

    hidden [string] ResolveConfigPath([string]$raw) {
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $p = $this.ExpandHome($raw)

        # 1) If it’s already a rooted absolute path and exists, use it
        if ([System.IO.Path]::IsPathRooted($p) -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path }

        # 2) Try relative to current location
        try {
            $cand = Join-Path (Get-Location).Path $p
            if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
        } catch {}

        # 3) Try relative to the process base directory (WinForms can change CWD)
        try {
            $base = [AppDomain]::CurrentDomain.BaseDirectory
            if ($base) {
                $cand = Join-Path $base $p
                if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
            }
        } catch {}

        # 4) If it’s an absolute path that doesn’t exist, return as-is (maybe caller will create)
        if ([System.IO.Path]::IsPathRooted($p)) { return $p }

        # 5) Fallback: assume relative to current location (even if not present yet)
        return (Join-Path (Get-Location).Path $p)
    }

    [void]LoadConfig() {
        $this.Printers.Clear()

        if (-not (Test-Path -LiteralPath $this.ConfigPath)) {
            if ($this.AutoCreate) {
                # Create a new CSV with your canonical headers
                $defaultHeader = 'printer name;ip address;reserved field;is default'
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $this.ConfigPath) | Out-Null
                Set-Content -LiteralPath $this.ConfigPath -Value $defaultHeader -Encoding UTF8
            } else {
                Write-Host "Config file does not exist: $($this.ConfigPath)"
                return
            }
        }

        # Read first line - FIXED: Remove -Raw parameter when using -TotalCount
        try {
            $firstLine = (Get-Content -LiteralPath $this.ConfigPath -TotalCount 1)
            if ($firstLine -is [array] -and $firstLine.Count -gt 0) {
                $firstLine = $firstLine[0]
            }
        } catch {
            Write-Host "Failed to read config header: $_"
            return
        }
    
        if (-not $firstLine) {
            Write-Host "Config file is empty: $($this.ConfigPath)"
            return
        }

        $firstLineNoBom = $firstLine -replace '^\uFEFF',''
        $h = $firstLineNoBom -split ';'
        if ($h.Length -lt 4) {
            Write-Host "Invalid header row in $($this.ConfigPath)"
            return
        }

        $this.PrinterHeaders = @{
            "Name"          = $h[0]
            "IpAddress"     = $h[1]
            "ReservedField" = $h[2]
            "IsDefault"     = $h[3]
        }

        # Rest of the method remains the same...
        $rows = @()
        try {
            $rows = Import-Csv -LiteralPath $this.ConfigPath -Delimiter ';'
        } catch {
            Write-Host "Failed to parse CSV: $_"
            return
        }
        if (-not $rows -or $rows.Count -eq 0) { return }

        # Build normalized property map
        $propMap = @{}
        foreach ($p in $rows[0].PSObject.Properties.Name) {
            $propMap[ $this.NormalizeName($p) ] = $p
        }

        function Get-By([object]$row, [hashtable]$pm, [string]$normName) {
            $actual = $pm[$normName]
            if ($actual) { return $row.$actual }
            return $null
        }

        foreach ($r in $rows) {
            $name = Get-By $r $propMap 'printer name'
            $ip   = Get-By $r $propMap 'ip address'
            $res  = Get-By $r $propMap 'reserved field'
            $def  = Get-By $r $propMap 'is default'

            $name = if ($name) { "$name".Trim() } else { "" }
            $ip   = if ($ip)   { "$ip".Trim()   } else { "" }
            $res  = if ($res)  { "$res".Trim()  } else { "" }
            $def  = if ($def)  { "$def".Trim()  } else { "" }

            if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($ip)) { continue }

            [void]$this.Printers.Add([pscustomobject]@{
                Name          = $name
                IpAddress     = $ip
                ReservedField = $res
                IsDefault     = $def
            })
        }
    }

    [void]SaveConfig() {
        if (-not $this.PrinterHeaders -or $this.PrinterHeaders.Count -lt 4) {
            $this.PrinterHeaders = @{
                "Name"          = 'printer name'
                "IpAddress"     = 'ip address'
                "ReservedField" = 'reserved field'
                "IsDefault"     = 'is default'
            }
        }

        $out = foreach ($p in $this.Printers) {
            [pscustomobject]([ordered]@{
                $this.PrinterHeaders["Name"]          = $p.Name
                $this.PrinterHeaders["IpAddress"]     = $p.IpAddress
                $this.PrinterHeaders["ReservedField"] = $p.ReservedField
                $this.PrinterHeaders["IsDefault"]     = $p.IsDefault
            })
        }

        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $this.ConfigPath) | Out-Null
            $out | Export-Csv -LiteralPath $this.ConfigPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
        } catch {
            Write-Host "Failed to save config: $_"
        }
    }

    [void]SetDefaultPrinterIp() {
        $this.DefaultPrinterIp = $null
        foreach ($p in $this.Printers) {
            if ($p.IsDefault -eq '1') {
                $this.DefaultPrinterIp = $p.IpAddress
                break
            }
        }
    }

    [void]SetDefaultPrinter([string]$printerNameOrIp) {
        if ([string]::IsNullOrWhiteSpace($printerNameOrIp)) {
            Write-Host "Printer id is empty."
            return
        }

        $found = $false
        foreach ($p in $this.Printers) {
            if (($p.Name -eq $printerNameOrIp) -or ($p.IpAddress -eq $printerNameOrIp)) {
                $p.IsDefault = '1'
                $this.DefaultPrinterIp = $p.IpAddress
                $found = $true
            } else {
                $p.IsDefault = ''
            }
        }

        if ($found) {
            $this.SaveConfig()
        } else {
            Write-Host "Printer not found: $printerNameOrIp"
        }
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
    Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File ".\src\ISECalibrators.ps1"'
    return
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

    #####OFFLINE PATCH
    # wait for remote CSV
    #$remoteContent = Receive-Job -Job $global:job -Wait -AutoRemoveJob
    #$materialGroupsByInstrument = Setup-MaterialGroups-Async -RemoteContent $remoteContent
    $materialGroupsByInstrument = Setup-MaterialGroupsOFFLINEPATCH
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


function main_gui {
    # ---------- paths (absolute to this script) ----------
    $ScriptDir      = Split-Path -Parent $PSCommandPath            # ...\src
    $RootDir        = Split-Path -Parent $ScriptDir                # ...\QC Materials Printer
    $PrinterCsvPath = Join-Path $ScriptDir 'printer_config.csv'    # ...\src\printer_config.csv

    # ---------- globals / initial state ----------
    $global:last_selected_index = @(0,0,0)
    $global:menu_level = $INSTRUMENT_SELECT
    $global:QueuePending = $false
    $global:side_pane = $null
    $global:startup = $true

    # ---------- data boot ----------
    $materialGroupsByInstrument = Setup-MaterialGroupsOFFLINEPATCH
    if ($null -eq $materialGroupsByInstrument) {
        [System.Windows.Forms.MessageBox]::Show("Failed to initialize material groups.","QC Label Printer", 'OK','Error') | Out-Null
        return 1
    }

    # ---------- printers ----------
    $global:printerManager = [PrinterManager]::new($PrinterCsvPath)
    if ($global:printerManager.DefaultPrinterIp) {
        $global:printerIp = $global:printerManager.DefaultPrinterIp
    }

    function Get-PrinterDisplayItems {
        Write-Host "=== DEBUG: Starting Get-PrinterDisplayItems ===" -ForegroundColor Magenta
    
        $rows = $global:printerManager.Printers
        Write-Host "Rows from printerManager: $($rows.Count)" -ForegroundColor Magenta
        Write-Host "Rows type: $($rows.GetType().FullName)" -ForegroundColor Magenta
    
        if ($rows.Count -gt 0) {
            Write-Host "First row sample:" -ForegroundColor Magenta
            $rows[0] | Format-List | Out-Host
        }
    
        $items = @()
        $idx = 0
        foreach ($r in $rows) {
            Write-Host "Processing row $idx : Name=$($r.Name), IP=$($r.IpAddress)" -ForegroundColor Magenta
        
            $isDefault = ($r.IsDefault -eq "1")
            $label = if ($isDefault) {
                "{0}  ({1})  [default]" -f $r.Name, $r.IpAddress
            } else {
                "{0}  ({1})" -f $r.Name, $r.IpAddress
            }
            $items += [pscustomobject]@{
                Label     = $label
                Name      = $r.Name
                IpAddress = $r.IpAddress
                IsDefault = $r.IsDefault
                Index     = $idx
            }
            $idx++
        }
    
        Write-Host "Final items count: $($items.Count)" -ForegroundColor Magenta
        Write-Host "=== DEBUG: End Get-PrinterDisplayItems ===" -ForegroundColor Magenta
    
        return $items
    }

    function Get-CurrentPrinterName {
        foreach ($p in $global:printerManager.Printers) {
            if ($p["IsDefault"] -eq "1") { return $p["Name"] }
        }
        return $null
    }

    $instrumentList = ($materialGroupsByInstrument.Keys | Sort-Object)

    # ---------- UI ----------
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "QC Material Label Printer"
    $form.StartPosition = 'CenterScreen'
    $form.Size = [System.Drawing.Size]::new(1000, 650)
    $form.MinimumSize = [System.Drawing.Size]::new(900, 580)

    $fontTitle = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
    $fontBody  = New-Object Drawing.Font("Segoe UI", 9)

    $main = New-Object System.Windows.Forms.TableLayoutPanel
    $main.Dock = 'Fill'
    $main.ColumnCount = 3
    $main.RowCount = 1
    [void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33)))
    [void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 34)))
    [void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    # Column 0
    $col0 = New-Object System.Windows.Forms.TableLayoutPanel
    $col0.Dock = 'Fill'; $col0.Padding = [System.Windows.Forms.Padding]::new(12)
    $col0.RowCount = 4; $col0.ColumnCount = 1
    [void]$col0.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$col0.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$col0.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$col0.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    $lblInstrument = New-Object Windows.Forms.Label
    $lblInstrument.Text = "Instrument"; $lblInstrument.Font = $fontTitle; $lblInstrument.AutoSize = $true

    $cmbInstrument = New-Object Windows.Forms.ComboBox
    $cmbInstrument.DropDownStyle = 'DropDownList'; $cmbInstrument.Width = 280
    [void]$cmbInstrument.Items.AddRange($instrumentList)

    $lblCategory = New-Object Windows.Forms.Label
    $lblCategory.Text = "Category"; $lblCategory.Font = $fontTitle; $lblCategory.AutoSize = $true

    $lstCategory = New-Object Windows.Forms.ListBox; $lstCategory.Dock = 'Fill'

    [void]$col0.Controls.Add($lblInstrument, 0, 0)
    [void]$col0.Controls.Add($cmbInstrument, 0, 1)
    [void]$col0.Controls.Add($lblCategory, 0, 2)
    [void]$col0.Controls.Add($lstCategory, 0, 3)

    # Column 1
    $col1 = New-Object System.Windows.Forms.TableLayoutPanel
    $col1.Dock = 'Fill'; $col1.Padding = [System.Windows.Forms.Padding]::new(12)
    $col1.RowCount = 2; $col1.ColumnCount = 1
    [void]$col1.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$col1.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    $lblMaterial = New-Object Windows.Forms.Label
    $lblMaterial.Text = "Reagent"; $lblMaterial.Font = $fontTitle; $lblMaterial.AutoSize = $true

    $lstMaterial = New-Object Windows.Forms.ListBox; $lstMaterial.Dock = 'Fill'

    [void]$col1.Controls.Add($lblMaterial, 0, 0)
    [void]$col1.Controls.Add($lstMaterial, 0, 1)

    # Column 2
    $col2 = New-Object System.Windows.Forms.Panel; $col2.Dock = 'Fill'; $col2.Padding = [System.Windows.Forms.Padding]::new(12)

    $grpActions = New-Object System.Windows.Forms.GroupBox
    $grpActions.Text = "Actions"; $grpActions.Font = $fontTitle; $grpActions.Dock = 'Fill'

    $stack = New-Object System.Windows.Forms.TableLayoutPanel
    $stack.Dock = 'Fill'; $stack.ColumnCount = 1; $stack.RowCount = 8
    for ($i=0; $i -lt 7; $i++) { [void]$stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) }
    [void]$stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    function New-ActionButton($text) {
        $b = New-Object Windows.Forms.Button
        $b.Text = $text; $b.Font = $fontBody; $b.AutoSize = $true; $b.AutoSizeMode = 'GrowAndShrink'; $b.Dock = 'Top'
        return $b
    }

    $btnPrint         = New-ActionButton "Print Selected"
    $btnToggleOpen    = New-ActionButton "Toggle Open/Closed"
    $btnFlush         = New-ActionButton "Flush Print Queue"
    $btnISE           = New-ActionButton "ISE Calibration Labels"
    $btnSelectPrinter = New-ActionButton "Select Printer..."
    $btnHelp          = New-ActionButton "Help"
    $btnUpdate        = New-ActionButton "Update"

    [void]$stack.Controls.Add($btnPrint)
    [void]$stack.Controls.Add($btnToggleOpen)
    [void]$stack.Controls.Add($btnFlush)
    [void]$stack.Controls.Add($btnISE)
    [void]$stack.Controls.Add($btnSelectPrinter)
    [void]$stack.Controls.Add($btnHelp)
    [void]$stack.Controls.Add($btnUpdate)

    [void]$grpActions.Controls.Add($stack)
    [void]$col2.Controls.Add($grpActions)

    [void]$main.Controls.Add($col0, 0, 0)
    [void]$main.Controls.Add($col1, 1, 0)
    [void]$main.Controls.Add($col2, 2, 0)

    # Status bar
    $status    = New-Object Windows.Forms.StatusStrip
    $stPrinter = New-Object Windows.Forms.ToolStripStatusLabel
    $stOpen    = New-Object Windows.Forms.ToolStripStatusLabel
    $stQueue   = New-Object Windows.Forms.ToolStripStatusLabel
    $stVersion = New-Object Windows.Forms.ToolStripStatusLabel
    $stVersion.Spring = $true; $stVersion.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    [void]$status.Items.AddRange(@($stPrinter,$stOpen,$stQueue,$stVersion))

    [void]$form.Controls.Add($main)
    [void]$form.Controls.Add($status)

    # ---------- helpers ----------
    function Set-Status {
        $name = Get-CurrentPrinterName
        $stPrinter.Text = "Printer: " + (&{ if ($name) { $name } else { $global:printerIp } })
        $stQueue.Text   = if ($global:QueuePending) { "Queue: pending" } else { "Queue: idle" }
        $stVersion.Text = "Version: $($global:VERSION)"
        $status.Refresh()
        [System.Windows.Forms.Application]::DoEvents() | Out-Null
    }
    function Sync-OpenUI {
        $stOpen.Text = "Status: " + (&{ if ($global:is_open) { "Open" } else { "Closed" } })
        $btnToggleOpen.Text = (&{ if ($global:is_open) { "Set Closed" } else { "Set Open" } })
        $status.Refresh()
        [System.Windows.Forms.Application]::DoEvents() | Out-Null
    }

    function Populate-Categories([string]$instrumentName) {
        $lstCategory.Items.Clear(); $lstMaterial.Items.Clear()
        if ([string]::IsNullOrWhiteSpace($instrumentName)) { return }
        $groups = $materialGroupsByInstrument[$instrumentName]
        if ($null -eq $groups) { return }
        foreach ($g in $groups) { [void]$lstCategory.Items.Add($g.group_name) }
        if ($lstCategory.Items.Count -gt 0) {
            $lstCategory.SelectedIndex = [Math]::Min($global:last_selected_index[$MATERIAL_GROUP_SELECT], $lstCategory.Items.Count-1)
        }
    }
    function Populate-Materials([string]$instrumentName, [int]$groupIndex) {
        $lstMaterial.Items.Clear()
        if ([string]::IsNullOrWhiteSpace($instrumentName)) { return }
        $groups = $materialGroupsByInstrument[$instrumentName]
        if ($null -eq $groups -or $groupIndex -lt 0 -or $groupIndex -ge $groups.Count) { return }
        $selectedGroup = $groups[$groupIndex]
        foreach ($m in $selectedGroup.materials_list) { [void]$lstMaterial.Items.Add($m.name) }
        if ($lstMaterial.Items.Count -gt 0) {
            $lstMaterial.SelectedIndex = [Math]::Min($global:last_selected_index[$MATERIAL_SELECT], $lstMaterial.Items.Count-1)
        }
    }
    function Get-SelectedMaterial {
        if ($cmbInstrument.SelectedIndex -lt 0) { return $null }
        $instrumentName = $cmbInstrument.SelectedItem.ToString()
        $groups = $materialGroupsByInstrument[$instrumentName]
        if ($null -eq $groups) { return $null }
        $gi = $lstCategory.SelectedIndex; $mi = $lstMaterial.SelectedIndex
        if ($gi -lt 0 -or $mi -lt 0) { return $null }
        return $groups[$gi].materials_list[$mi]
    }

    function GUI-SelectPrinter {

        Write-Host "=== DEBUG: Starting GUI-SelectPrinter ===" -ForegroundColor Yellow
    
        # Check if printerManager exists and has data
        Write-Host "Global printerManager exists: $($null -ne $global:printerManager)" -ForegroundColor Cyan
        if ($global:printerManager) {
            Write-Host "Printers count: $($global:printerManager.Printers.Count)" -ForegroundColor Cyan
            Write-Host "First few printers:" -ForegroundColor Cyan
            $global:printerManager.Printers | Select-Object -First 3 | Format-Table -AutoSize | Out-Host
        }
    
        $items = @(Get-PrinterDisplayItems)
        Write-Host "Items returned from Get-PrinterDisplayItems: $($items.Count)" -ForegroundColor Cyan
        Write-Host "Items type: $($items.GetType().FullName)" -ForegroundColor Cyan
    
        if ($items.Count -gt 0) {
            Write-Host "First item details:" -ForegroundColor Cyan
            $items[0] | Format-List | Out-Host
        }
    
        if ($items.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No printers found in the database.", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return $null
        }
    
        $items = Get-PrinterDisplayItems
        if (-not $items -or $items.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No printers found in `n$PrinterCsvPath","QC Label Printer") | Out-Null
            return
        }

        $dlg = New-Object Windows.Forms.Form
        $dlg.Text = "Select Printer"; $dlg.StartPosition = 'CenterParent'
        $dlg.Size = [System.Drawing.Size]::new(460, 400)
        $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false

        $lst = New-Object Windows.Forms.ListBox
        $lst.Dock = 'Top'; $lst.Height = 280
        foreach($row in $items){ [void]$lst.Items.Add($row.Label) }

        # preselect current default
        $idxDefault = (0..($items.Count-1)) | Where-Object { $items[$_].IsDefault -eq '1' } | Select-Object -First 1
        if ($idxDefault -ne $null) { $lst.SelectedIndex = $idxDefault }

        $panelBtns = New-Object Windows.Forms.FlowLayoutPanel
        $panelBtns.Dock = 'Bottom'; $panelBtns.FlowDirection = 'RightToLeft'
        $panelBtns.Padding = [System.Windows.Forms.Padding]::new(6); $panelBtns.Height = 60

        $ok  = New-Object Windows.Forms.Button
        $ok.Text = "Set Default"; $ok.AutoSize = $true; $ok.DialogResult = [System.Windows.Forms.DialogResult]::None

        $cancel = New-Object Windows.Forms.Button
        $cancel.Text = "Cancel"; $cancel.AutoSize = $true; $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

        $panelBtns.Controls.Add($ok); $panelBtns.Controls.Add($cancel)
        $dlg.Controls.Add($lst); $dlg.Controls.Add($panelBtns)

        $lst.Add_DoubleClick({ if ($lst.SelectedIndex -ge 0) { $ok.PerformClick() } })

        $ok.Add_Click({
            if ($lst.SelectedIndex -lt 0) { return }
            $chosen = $items[$lst.SelectedIndex]
            try {
                # Legacy manager persists and updates globals
                $global:printerManager.SetDefaultPrinter($chosen.Name)
                $global:printerIp = $global:printerManager.DefaultPrinterIp
                Set-Status
                $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $dlg.Close()
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Failed to save printer selection: $_","QC Label Printer",'OK','Error') | Out-Null
            }
        })

        [void]$dlg.ShowDialog($form)
        $dlg.Dispose()
    }

    function Ensure-CS2500-OpenLock {
        $inst = if ($cmbInstrument.SelectedIndex -ge 0) { $cmbInstrument.SelectedItem.ToString() } else { "" }
        if ((@("CS2500","Core Lab") -contains $inst) -and ($lstCategory.SelectedIndex -ge 0 -or $lstMaterial.SelectedIndex -ge 0)) {
            if (-not $global:is_open) { $global:is_open = $true }
        }
        Sync-OpenUI
    }

    # ---------- events ----------
    $cmbInstrument.Add_SelectedIndexChanged({
        $global:last_selected_index[$INSTRUMENT_SELECT] = $cmbInstrument.SelectedIndex
        Populate-Categories $cmbInstrument.SelectedItem.ToString()
        $lstMaterial.Items.Clear()
        Ensure-CS2500-OpenLock
    })
    $lstCategory.Add_SelectedIndexChanged({
        $global:last_selected_index[$MATERIAL_GROUP_SELECT] = $lstCategory.SelectedIndex
        if ($cmbInstrument.SelectedIndex -ge 0) {
            Populate-Materials $cmbInstrument.SelectedItem.ToString() $lstCategory.SelectedIndex
        }
        Ensure-CS2500-OpenLock
    })
    $lstMaterial.Add_DoubleClick({
        $mat = Get-SelectedMaterial
        if ($null -ne $mat) {
            print_label -material $mat
            $global:last_selected_index[$MATERIAL_SELECT] = $lstMaterial.SelectedIndex
            Set-Status
        }
    })

    $btnPrint.Add_Click({
        $mat = Get-SelectedMaterial
        if ($null -eq $mat) {
            [System.Windows.Forms.MessageBox]::Show("Pick a reagent to print.","QC Label Printer") | Out-Null
            return
        }
        print_label -material $mat
        $global:last_selected_index[$MATERIAL_SELECT] = $lstMaterial.SelectedIndex
        Set-Status
    })
    $btnToggleOpen.Add_Click({
        $inst = if ($cmbInstrument.SelectedIndex -ge 0) { $cmbInstrument.SelectedItem.ToString() } else { "" }
        $atRoot = ($lstCategory.SelectedIndex -lt 0 -and $lstMaterial.SelectedIndex -lt 0)
        if ((@("CS2500","Core Lab") -contains $inst) -and (-not $atRoot)) { $global:is_open = $true }
        else { $global:is_open = -not $global:is_open }
        Sync-OpenUI
    })
    $btnFlush.Add_Click({ if ($global:QueuePending) { flush-queue $null }; Set-Status })
    $btnISE.Add_Click({ electrolyte-labels; Set-Status })
    $btnSelectPrinter.Add_Click({ GUI-SelectPrinter })
    $btnHelp.Add_Click({ AdvancedHelp })
    $btnUpdate.Add_Click({
        try {
            powershell.exe -ExecutionPolicy Bypass -File (Join-Path $RootDir 'Huginn.ps1')
            Start-Process powershell -ArgumentList ('-ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -NoNewWindow
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Update failed: $_","QC Label Printer",'OK','Error') | Out-Null
        }
    })

    $form.KeyPreview = $true
    $form.Add_KeyDown({
        switch ($_.KeyCode) {
            'P'     { GUI-SelectPrinter }
            'E'     { $btnISE.PerformClick() }
            'F'     { $btnFlush.PerformClick() }
            'H'     { $btnHelp.PerformClick() }
            'O'     { $btnToggleOpen.PerformClick() }
            'Enter' { if ($lstMaterial.Focused) { $btnPrint.PerformClick() } }
        }
    })

    # ---------- run ----------
    $form.Add_Shown({
        if ($cmbInstrument.Items.Count -gt 0) {
            $cmbInstrument.SelectedIndex = [Math]::Min($global:last_selected_index[$INSTRUMENT_SELECT], $cmbInstrument.Items.Count-1)
        }
        Set-Status
        Sync-OpenUI
    })

    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::Run($form)
    return 0
}


main_gui

#https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/product/tlp2824plus-ug-en.pdf
#https://www.zebra.com/content/dam/support-dam/en/documentation/unrestricted/guide/software/zplii-pm-vol1.pdf
