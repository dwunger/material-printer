# ISECalibrators.ps1 - WinForms wizard with optional QR printing
# Hardcoded printer: PRT001062:9100

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -------------------- Printer config --------------------
$PRINTER_HOST = 'PRT001062'
$PRINTER_PORT = 9100

# -------------------- Helpers ---------------------------
function Trim-ScannerSlashes {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    # Scanners wrap with backslashes: \DATA\ -> keep the raw in state for QR, but for parsing remove '\'
    return ($s -replace '\\','').Trim()
}

function Parse-Barcode {
    param([string]$raw)
    $clean = Trim-ScannerSlashes $raw
    if ([string]::IsNullOrWhiteSpace($clean)) { return @{ Lot=""; Exp="" } }

    # Expect last 12 = YYMMDD, last 4 = Lot (as per your previous logic)
    if ($clean.Length -lt 12) { return @{ Lot=""; Exp="" } }

    $yy  = $clean.Substring($clean.Length-12, 2)
    $mm  = $clean.Substring($clean.Length-10, 2)
    $dd  = $clean.Substring($clean.Length-8,  2)
    $lot = if ($clean.Length -ge 4) { $clean.Substring($clean.Length-4,4) } else { "" }

    if (-not ($yy -match '^\d{2}$' -and $mm -match '^\d{2}$' -and $dd -match '^\d{2}$')) {
        return @{ Lot=""; Exp="" }
    }

    $yyyy = "20$yy"
    $exp  = "{0}-{1}-{2}" -f $yyyy,$mm,$dd
    return @{ Lot=$lot; Exp=$exp }
}

function YYMMDD-From-Exp {
    param([string]$exp) # YYYY-MM-DD
    if ($exp -notmatch '^\d{4}-\d{2}-\d{2}$') { return "" }
    $yy = $exp.Substring(2,2)
    $mm = $exp.Substring(5,2)
    $dd = $exp.Substring(8,2)
    return "$yy$mm$dd"
}

function Normalize-Lot4 {
    param([string]$lot)
    if ([string]::IsNullOrWhiteSpace($lot)) { return "0000" }
    $t = $lot.Trim()
    if ($t.Length -gt 4) { return $t.Substring($t.Length-4,4) }
    if ($t.Length -lt 4) { return $t.PadLeft(4,'0') }
    return $t
}

function Build-ManualBarcode-Masked {
    param([string]$expYyMmDd,[string]$lot4)
    # \XXXXXXXXXXXXXXXXXXXXXXXXYYMMDDXXLLLL\
    if ([string]::IsNullOrWhiteSpace($expYyMmDd) -or [string]::IsNullOrWhiteSpace($lot4)) { return "" }
    return "\XXXXXXXXXXXXXXXXXXXXXXXX{0}XX{1}\" -f $expYyMmDd, $lot4
}

function Build-ManualBarcode-Canonical {
    param([string]$expYyMmDd,[string]$lot4)
    # \01150995901400451124060517YYMMDD10LLLL\
    if ([string]::IsNullOrWhiteSpace($expYyMmDd) -or [string]::IsNullOrWhiteSpace($lot4)) { return "" }
    return "\01150995901400451124060517{0}10{1}\" -f $expYyMmDd, $lot4
}

function Build-Zpl-QR {
    param([string]$payload,[string]$caption)
@"
^XA
^CI28
^CF0,28,28
^FO30,30^BQN,2,7^FDLA,$payload^FS
^FO30,240^A0N,32,32^FD$caption^FS
^FO230,30^BQN,2,7^FDLA,$payload^FS
^FO230,240^A0N,32,32^FD$caption^FS
^XZ
"@
}

function Build-Zpl-Final {
    param(
        [string]$LowUrine, [string]$HighUrine,
        [string]$LowSerum, [string]$HighSerum
    )
@"
^XA
^CF0,20,20
^FO10,30^A0N,20,20^FDLow Serum Standard       Low Serum Standard^FS
^FO10,60^A0N,20,20^FD$LowSerum       $LowSerum^FS
^FO10,90^A0N,20,20^FDHigh Serum Standard      High Serum Standard^FS
^FO10,120^A0N,20,20^FD$HighSerum       $HighSerum^FS
^FO10,150^A0N,20,20^FDLow Urine Standard       Low Urine Standard^FS
^FO10,180^A0N,20,20^FD$LowUrine       $LowUrine^FS
^FO10,210^A0N,20,20^FDHigh Urine Standard      High Urine Standard^FS
^FO10,240^A0N,20,20^FD$HighUrine       $HighUrine^FS
^XZ
"@
}

function Send-Zpl {
    param([string]$zpl)
    $tcp = $null; $ns = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient($PRINTER_HOST, $PRINTER_PORT)
        $ns  = $tcp.GetStream()
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($zpl)
        $ns.Write($bytes, 0, $bytes.Length)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Printer error:`r`n$($_.Exception.Message)","Print Error",
            [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        throw
    } finally {
        if ($ns) { $ns.Close() }
        if ($tcp) { $tcp.Close() }
    }
}

# -------------------- UI (WinForms) ---------------------
$fontH = New-Object Drawing.Font("Segoe UI", 12, [Drawing.FontStyle]::Bold)
$fontB = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Regular)

$form = New-Object Windows.Forms.Form
$form.Text = "ISE Calibrators"
$form.StartPosition = 'CenterScreen'
$form.Size = [Drawing.Size]::new(600, 430)
$form.MinimumSize = [Drawing.Size]::new(600, 430)
$form.MaximizeBox = $false

$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 2
$layout.RowCount = 10
$layout.Padding = [Windows.Forms.Padding]::new(14)
[void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 35))
[void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 65))
for($i=0;$i -lt 10;$i++){ [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize)) }

# Step title
$lblStep = New-Object Windows.Forms.Label
$lblStep.Font = $fontH
$lblStep.Text = "Step 1 of 5 Low Urine"
$lblStep.AutoSize = $true
$layout.SetColumnSpan($lblStep, 2)
[void]$layout.Controls.Add($lblStep, 0, 0)

# Barcode input
$lblBarcode = New-Object Windows.Forms.Label
$lblBarcode.Text = "Scan barcode (or paste):"
$lblBarcode.Font = $fontB
$lblBarcode.AutoSize = $true
[void]$layout.Controls.Add($lblBarcode, 0, 1)

$txtBarcode = New-Object Windows.Forms.TextBox
$txtBarcode.Font = $fontB
$txtBarcode.Dock = 'Fill'
[void]$layout.Controls.Add($txtBarcode, 1, 1)

$btnParse = New-Object Windows.Forms.Button
$btnParse.Text = "Parse from Scan"
$btnParse.Font = $fontB
$btnParse.AutoSize = $true
[void]$layout.Controls.Add($btnParse, 1, 2)

# Manual entry
$lblLot = New-Object Windows.Forms.Label
$lblLot.Text = "Lot:"
$lblLot.Font = $fontB
$lblLot.AutoSize = $true
[void]$layout.Controls.Add($lblLot, 0, 3)

$txtLot = New-Object Windows.Forms.TextBox
$txtLot.Font = $fontB
$txtLot.Dock = 'Fill'
[void]$layout.Controls.Add($txtLot, 1, 3)

$lblExp = New-Object Windows.Forms.Label
$lblExp.Text = "Expiration (YYYY-MM-DD):"
$lblExp.Font = $fontB
$lblExp.AutoSize = $true
[void]$layout.Controls.Add($lblExp, 0, 4)

$txtExp = New-Object Windows.Forms.TextBox
$txtExp.Font = $fontB
$txtExp.Dock = 'Fill'
[void]$layout.Controls.Add($txtExp, 1, 4)

# Copies (final step only)
$lblCopies = New-Object Windows.Forms.Label
$lblCopies.Text = "Label Copies:"
$lblCopies.Font = $fontB
$lblCopies.AutoSize = $true
$lblCopies.Visible = $false
[void]$layout.Controls.Add($lblCopies, 0, 5)

$nudCopies = New-Object Windows.Forms.NumericUpDown
$nudCopies.Minimum = 1
$nudCopies.Maximum = 50
$nudCopies.Value = 1
$nudCopies.Font = $fontB
$nudCopies.Width = 80
$nudCopies.Visible = $false
[void]$layout.Controls.Add($nudCopies, 1, 5)

# QR options (final step only)
$chkQr = New-Object Windows.Forms.CheckBox
$chkQr.Text = "Also print QR code labels for each calibrator"
$chkQr.Font = $fontB
$chkQr.AutoSize = $true
$chkQr.Visible = $false
$layout.SetColumnSpan($chkQr, 2)
[void]$layout.Controls.Add($chkQr, 0, 6)

$lblQrCopies = New-Object Windows.Forms.Label
$lblQrCopies.Text = "QR Copies (each):"
$lblQrCopies.Font = $fontB
$lblQrCopies.AutoSize = $true
$lblQrCopies.Visible = $false
[void]$layout.Controls.Add($lblQrCopies, 0, 7)

$nudQrCopies = New-Object Windows.Forms.NumericUpDown
$nudQrCopies.Minimum = 1
$nudQrCopies.Maximum = 10
$nudQrCopies.Value = 1
$nudQrCopies.Font = $fontB
$nudQrCopies.Width = 80
$nudQrCopies.Visible = $false
[void]$layout.Controls.Add($nudQrCopies, 1, 7)

$lblQrMode = New-Object Windows.Forms.Label
$lblQrMode.Text = "Manual QR format:"
$lblQrMode.Font = $fontB
$lblQrMode.AutoSize = $true
$lblQrMode.Visible = $false
[void]$layout.Controls.Add($lblQrMode, 0, 8)

$cmbQrMode = New-Object Windows.Forms.ComboBox
$cmbQrMode.DropDownStyle = 'DropDownList'
[void]$cmbQrMode.Items.AddRange(@(
    "Masked (XXXXXXXXXXXXXXXXXXXXXXXXYYMMDDXXLLLL)",
    "Canonical (01150995901400451124060517YYMMDD10LLLL)"
))
$cmbQrMode.SelectedIndex = 0
$cmbQrMode.Visible = $false
[void]$layout.Controls.Add($cmbQrMode, 1, 8)

# Buttons
$panelBtns = New-Object Windows.Forms.FlowLayoutPanel
$panelBtns.FlowDirection = 'RightToLeft'
$panelBtns.Dock = 'Bottom'
$panelBtns.AutoSize = $true
$layout.SetColumnSpan($panelBtns, 2)

$btnNext = New-Object Windows.Forms.Button
$btnNext.Text = "Next >"
$btnNext.Font = $fontB
$btnNext.AutoSize = $true
$panelBtns.Controls.Add($btnNext)

$btnBack = New-Object Windows.Forms.Button
$btnBack.Text = "< Back"
$btnBack.Font = $fontB
$btnBack.AutoSize = $true
$panelBtns.Controls.Add($btnBack)

$btnPrint = New-Object Windows.Forms.Button
$btnPrint.Text = "Print"
$btnPrint.Font = $fontB
$btnPrint.AutoSize = $true
$btnPrint.Visible = $false
$panelBtns.Controls.Add($btnPrint)

[void]$layout.Controls.Add($panelBtns, 0, 9)
[void]$form.Controls.Add($layout)

# -------------------- Wizard State (script scope) --------------------
$script:steps = @("Low Urine","High Urine","Low Serum","High Serum","Copies")
$script:current = 0
$script:data = [ordered]@{
    "Low Urine"  = @{ Lot=""; Exp=""; Raw="" }
    "High Urine" = @{ Lot=""; Exp=""; Raw="" }
    "Low Serum"  = @{ Lot=""; Exp=""; Raw="" }
    "High Serum" = @{ Lot=""; Exp=""; Raw="" }
}

function Refresh-Step {
    param([int]$idx)

    $isCopyStep = ($script:steps[$idx] -eq "Copies")

    $lblStep.Text = "Step {0} of 5 {1}" -f ($idx+1), $script:steps[$idx]
    $txtBarcode.Text = ""
    $txtLot.Text     = ""
    $txtExp.Text     = ""

    $lblBarcode.Visible = -not $isCopyStep
    $txtBarcode.Visible = -not $isCopyStep
    $btnParse.Visible   = -not $isCopyStep

    $lblLot.Visible = -not $isCopyStep
    $txtLot.Visible = -not $isCopyStep
    $lblExp.Visible = -not $isCopyStep
    $txtExp.Visible = -not $isCopyStep

    $lblCopies.Visible = $isCopyStep
    $nudCopies.Visible = $isCopyStep
    $chkQr.Visible     = $isCopyStep
    $lblQrCopies.Visible = $isCopyStep
    $nudQrCopies.Visible = $isCopyStep
    $lblQrMode.Visible   = $isCopyStep
    $cmbQrMode.Visible   = $isCopyStep

    $btnPrint.Visible  = $isCopyStep
    $btnNext.Visible   = -not $isCopyStep
    $btnBack.Enabled   = ($idx -gt 0)

    if (-not $isCopyStep) {
        $name = $script:steps[$idx]
        $existing = $script:data[$name]
        if ($existing) {
            $txtLot.Text = $existing.Lot
            $txtExp.Text = $existing.Exp
        }
        [void]$txtBarcode.Focus()
    } else {
        $nudCopies.Focus()
    }
}

# -------------------- Events --------------------------
$btnParse.Add_Click({
    $parsed = Parse-Barcode $txtBarcode.Text
    $txtLot.Text = $parsed.Lot
    $txtExp.Text = $parsed.Exp
    # store raw as entered (for QR), keep it as-is to preserve slashes
    $name = $script:steps[$script:current]
    if ($script:data.Contains($name)) {
        $script:data[$name].Raw = $txtBarcode.Text
    }
})

$btnNext.Add_Click({
    $name = $script:steps[$script:current]

    # If user scanned but didn't click Parse, try once:
    if (([string]::IsNullOrWhiteSpace($txtLot.Text) -or [string]::IsNullOrWhiteSpace($txtExp.Text)) -and
        -not [string]::IsNullOrWhiteSpace($txtBarcode.Text)) {
        $p = Parse-Barcode $txtBarcode.Text
        if ($txtLot.Text -eq "") { $txtLot.Text = $p.Lot }
        if ($txtExp.Text -eq "") { $txtExp.Text = $p.Exp }
        # store raw
        if ($script:data.Contains($name)) { $script:data[$name].Raw = $txtBarcode.Text }
    }

    if ([string]::IsNullOrWhiteSpace($txtLot.Text) -or [string]::IsNullOrWhiteSpace($txtExp.Text)) {
        [Windows.Forms.MessageBox]::Show("Please provide both Lot and Expiration before continuing.",
            "Missing Data",[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if ($txtExp.Text -notmatch '^\d{4}-\d{2}-\d{2}$') {
        [Windows.Forms.MessageBox]::Show("Expiration must be in format YYYY-MM-DD.","Invalid Date",
            [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:data[$name].Lot = $txtLot.Text.Trim()
    $script:data[$name].Exp = $txtExp.Text.Trim()
    if (-not $script:data[$name].Raw) { $script:data[$name].Raw = "" }

    if ($script:current -lt 4) {
        $script:current++
        Refresh-Step $script:current
    }
})

$btnBack.Add_Click({
    if ($script:current -gt 0) {
        $script:current--
        Refresh-Step $script:current
    }
})

$btnPrint.Add_Click({
    $summary = @"
Low Urine : $($script:data['Low Urine'].Lot) $($script:data['Low Urine'].Exp)
High Urine: $($script:data['High Urine'].Lot) $($script:data['High Urine'].Exp)
Low Serum : $($script:data['Low Serum'].Lot) $($script:data['Low Serum'].Exp)
High Serum: $($script:data['High Serum'].Lot) $($script:data['High Serum'].Exp)

Label Copies: $($nudCopies.Value)
QR: $(if ($chkQr.Checked) { 'Yes' } else { 'No' })
"@
    $res = [Windows.Forms.MessageBox]::Show("Print these labels?`r`r$summary","Confirm Print",
        [Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)

    if ($res -ne [Windows.Forms.DialogResult]::Yes) { return }

    $ul = "{0} {1}" -f $script:data['Low Urine'].Lot,  $script:data['Low Urine'].Exp
    $uh = "{0} {1}" -f $script:data['High Urine'].Lot, $script:data['High Urine'].Exp
    $sl = "{0} {1}" -f $script:data['Low Serum'].Lot,  $script:data['Low Serum'].Exp
    $sh = "{0} {1}" -f $script:data['High Serum'].Lot, $script:data['High Serum'].Exp

    $zpl = Build-Zpl-Final -LowUrine $ul -HighUrine $uh -LowSerum $sl -HighSerum $sh

    try {
        for ($i=1; $i -le [int]$nudCopies.Value; $i++) {
            Send-Zpl $zpl
        }

        if ($chkQr.Checked) {
            # For each calibrator, decide QR payload: raw if scanned; else manual (masked/canonical)
            $qrMode = if ($cmbQrMode.SelectedIndex -eq 0) { "masked" } else { "canonical" }

            $stepsToPrint = @(
                @{ Key="Low Urine";  Caption="urine low"  }
                @{ Key="High Urine"; Caption="urine high" }
                @{ Key="Low Serum";  Caption="serum low"  }
                @{ Key="High Serum"; Caption="serum high" }
            )

            foreach($step in $stepsToPrint) {
                $entry = $script:data[$step.Key]
                $payload = $null

                if ($entry.Raw -and $entry.Raw.Trim().Length -gt 0) {
                    # Use the raw scanned text as-is
                    $payload = $entry.Raw.Trim()
                } else {
                    # Manual: generate from Lot/Exp
                    $yymmdd = YYMMDD-From-Exp $entry.Exp
                    $lot4   = Normalize-Lot4 $entry.Lot
                    if ($qrMode -eq "masked") {
                        $payload = Build-ManualBarcode-Masked $yymmdd $lot4
                    } else {
                        $payload = Build-ManualBarcode-Canonical $yymmdd $lot4
                    }
                }

                if ([string]::IsNullOrWhiteSpace($payload)) { continue }

                $qrZpl = Build-Zpl-QR -payload $payload -caption $step.Caption
                for ($n=1; $n -le [int]$nudQrCopies.Value; $n++) {
                    Send-Zpl $qrZpl
                }
            }
        }

        [Windows.Forms.MessageBox]::Show(("Sent to printer: {0}:{1}" -f $PRINTER_HOST, $PRINTER_PORT),"Printed",
            [Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        $form.Close()
    } catch {
        # Error dialog already shown in Send-Zpl
    }
})

# Enter = Next (on textboxes)
$txtBarcode.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $btnNext.PerformClick() } })
$txtLot.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $btnNext.PerformClick() } })
$txtExp.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $btnNext.PerformClick() } })

# -------------------- Run -----------------------------
Refresh-Step 0
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::Run($form)
