function Send-ZPLLabel {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PrinterIP,
        
        [Parameter(Mandatory=$true)]
        [int]$PrinterPort,
        
        [Parameter(Mandatory=$true)]
        [string]$BarcodeData,
        
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [string]$MRN,
        
        [Parameter(Mandatory=$false)]
        [string]$Test = "",

        [Parameter(Mandatory=$false)]
        [int]$Copies = 1
    )

    # Adjust positions based on whether Test is provided, shifting all by 25 points upward.
    if ($Test -ne "") {
        $testFieldZPL = "^FO50,105^A0N,30,30^FDTest: $Test^FSn"
        $barcodeY = 135
    }
    else {
        $testFieldZPL = ""
        $barcodeY = 105
    }

$zpl = @"
^XA
^FO50,25^A0N,30,30^FDName: $Name^FS
^FO50,65^A0N,30,30^FDMRN: $MRN^FS
$testFieldZPL^FO10,$barcodeY^BY2
^BCN,80,Y,N,N
^FD$BarcodeData^FS
^PQ$Copies
^XZ
"@

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($PrinterIP, $PrinterPort)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.Write($zpl)
        $writer.Flush()
        Write-Host "Label sent to printer."
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
    finally {
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client -and $client.Connected) { $client.Close() }
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Patient Label Batch Processor"
$form.Size = New-Object System.Drawing.Size(500, 450)
$form.StartPosition = "CenterScreen"

# Printer Selection Label and ComboBox
$lblPrinter = New-Object System.Windows.Forms.Label
$lblPrinter.Location = New-Object System.Drawing.Point(10, 20)
$lblPrinter.Size = New-Object System.Drawing.Size(120, 20)
$lblPrinter.Text = "Select Printer:"
$form.Controls.Add($lblPrinter)

$comboPrinter = New-Object System.Windows.Forms.ComboBox
$comboPrinter.Location = New-Object System.Drawing.Point(140, 20)
$comboPrinter.Size = New-Object System.Drawing.Size(200, 20)
$comboPrinter.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
# Define printers with friendly names and IPs
$printers = @(
    [PSCustomObject]@{ Name = "Central Processing"; IP = "PRT001065" },
    [PSCustomObject]@{ Name = "Hematology"; IP = "PRT001069" },
    [PSCustomObject]@{ Name = "Chemistry"; IP = "PRT002131" },
    [PSCustomObject]@{ Name = "Urines"; IP = "PRT001070" }
)
foreach ($printer in $printers) {
    $comboPrinter.Items.Add($printer) | Out-Null
}
$comboPrinter.DisplayMember = "Name"
$comboPrinter.SelectedIndex = 0
$form.Controls.Add($comboPrinter)

# COPIES (persists across prints; defaults to 1)
$lblCopies = New-Object System.Windows.Forms.Label
$lblCopies.Location = New-Object System.Drawing.Point(350, 20)
$lblCopies.Size = New-Object System.Drawing.Size(55, 20)
$lblCopies.Text = "Copies:"
$form.Controls.Add($lblCopies)

$nudCopies = New-Object System.Windows.Forms.NumericUpDown
$nudCopies.Location = New-Object System.Drawing.Point(410, 20)
$nudCopies.Size = New-Object System.Drawing.Size(60, 20)
$nudCopies.Minimum = 1
$nudCopies.Maximum = 100
$nudCopies.Value = 1
$form.Controls.Add($nudCopies)

# Patient Name
$lblPatientName = New-Object System.Windows.Forms.Label
$lblPatientName.Location = New-Object System.Drawing.Point(10, 60)
$lblPatientName.Size = New-Object System.Drawing.Size(120, 20)
$lblPatientName.Text = "Patient Name:"
$form.Controls.Add($lblPatientName)

$txtPatientName = New-Object System.Windows.Forms.TextBox
$txtPatientName.Location = New-Object System.Drawing.Point(140, 60)
$txtPatientName.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($txtPatientName)

# Patient MRN
$lblPatientMRN = New-Object System.Windows.Forms.Label
$lblPatientMRN.Location = New-Object System.Drawing.Point(10, 100)
$lblPatientMRN.Size = New-Object System.Drawing.Size(120, 20)
$lblPatientMRN.Text = "Patient MRN:"
$form.Controls.Add($lblPatientMRN)

$txtPatientMRN = New-Object System.Windows.Forms.TextBox
$txtPatientMRN.Location = New-Object System.Drawing.Point(140, 100)
$txtPatientMRN.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($txtPatientMRN)

# Instrument ID Input (BarcodeData)
$lblInstrument = New-Object System.Windows.Forms.Label
$lblInstrument.Location = New-Object System.Drawing.Point(10, 140)
$lblInstrument.Size = New-Object System.Drawing.Size(120, 20)
$lblInstrument.Text = "Instrument ID:"
$form.Controls.Add($lblInstrument)

$txtInstrument = New-Object System.Windows.Forms.TextBox
$txtInstrument.Location = New-Object System.Drawing.Point(140, 140)
$txtInstrument.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($txtInstrument)

# Test Field Input
$lblTest = New-Object System.Windows.Forms.Label
$lblTest.Location = New-Object System.Drawing.Point(10, 180)
$lblTest.Size = New-Object System.Drawing.Size(120, 20)
$lblTest.Text = "Test (Optional):"
$form.Controls.Add($lblTest)

$txtTest = New-Object System.Windows.Forms.TextBox
$txtTest.Location = New-Object System.Drawing.Point(140, 180)
$txtTest.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($txtTest)

# ListBox to display sent label info
$lblSent = New-Object System.Windows.Forms.Label
$lblSent.Location = New-Object System.Drawing.Point(10, 220)
$lblSent.Size = New-Object System.Drawing.Size(120, 20)
$lblSent.Text = "Sent Labels:"
$form.Controls.Add($lblSent)

$listSent = New-Object System.Windows.Forms.ListBox
$listSent.Location = New-Object System.Drawing.Point(140, 220)
$listSent.Size = New-Object System.Drawing.Size(300, 100)
$form.Controls.Add($listSent)

# Button: Scan
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Location = New-Object System.Drawing.Point(30, 340)
$btnScan.Size = New-Object System.Drawing.Size(100, 30)
$btnScan.Text = "Scan Barcode"
$form.Controls.Add($btnScan)

# Button: Send Label
$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Location = New-Object System.Drawing.Point(140, 340)
$btnSend.Size = New-Object System.Drawing.Size(100, 30)
$btnSend.Text = "Print Label"
$form.Controls.Add($btnSend)

# Button: Next Patient (clears patient fields and sent labels)
$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Location = New-Object System.Drawing.Point(250, 340)
$btnNext.Size = New-Object System.Drawing.Size(100, 30)
$btnNext.Text = "Next Patient"
$form.Controls.Add($btnNext)

# Button: Exit
#$btnExit = New-Object System.Windows.Forms.Button
#$btnExit.Location = New-Object System.Drawing.Point(360, 340)
#$btnExit.Size = New-Object System.Drawing.Size(100, 30)
#$btnExit.Text = "Exit"
#$form.Controls.Add($btnExit)

# =========================
# NEW: Parse EMR Button
# =========================
$btnParse = New-Object System.Windows.Forms.Button
$btnParse.Location = New-Object System.Drawing.Point(360, 340)   # extra row; avoids shifting existing buttons
$btnParse.Size = New-Object System.Drawing.Size(100, 30)
$btnParse.Text = "Parse EMR"
$form.Controls.Add($btnParse)

# --- Scan modal logic (existing) ---
function Show-ScanDialog {
    param([System.Windows.Forms.Form]$owner)

    $scanForm = New-Object System.Windows.Forms.Form
    $scanForm.Text = "Scan Label"
    $scanForm.StartPosition = "CenterParent"
    $scanForm.Size = New-Object System.Drawing.Size(360, 150)
    $scanForm.FormBorderStyle = 'FixedDialog'
    $scanForm.MaximizeBox = $false
    $scanForm.MinimizeBox = $false
    $scanForm.TopMost = $true
    $scanForm.KeyPreview = $true
    $scanForm.ShowInTaskbar = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.Size = New-Object System.Drawing.Size(300, 20)
    $lbl.Text = "Scan label to continue"
    $scanForm.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(20, 50)
    $txt.Size = New-Object System.Drawing.Size(300, 20)
    $scanForm.Controls.Add($txt)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(245, 80)
    $btnCancel.Add_Click({ $scanForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $scanForm.Close() })
    $scanForm.Controls.Add($btnCancel)

    # Accept when the scanned text starts and ends with "\" (e.g., \12345\)
    $txt.Add_TextChanged({
        $s = $txt.Text.Trim()
        if ($s.Length -ge 2 -and $s.StartsWith("\") -and $s.EndsWith("\")) {
            $scanForm.Tag = $s.Trim('\')   # Store cleaned value
            $scanForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $scanForm.Close()
        }
    })

    # Allow Esc to cancel
    $scanForm.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq 'Escape') {
            $scanForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $scanForm.Close()
        }
    })

    $scanForm.Add_Shown({ $txt.Focus() })
    return $scanForm.ShowDialog($owner), $scanForm.Tag
}

# =========================
# NEW: EMR Parse popup
# =========================
function Show-ParseDialog {
    param([System.Windows.Forms.Form]$owner)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Paste EMR Patient Info"
    $dlg.StartPosition = "CenterParent"
    $dlg.Size = New-Object System.Drawing.Size(520, 340)
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.TopMost = $true
    $dlg.ShowInTaskbar = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(12, 10)
    $lbl.Size = New-Object System.Drawing.Size(480, 30)
    $lbl.Text = "Paste the patient information from the specimen summary on EPIC's outstanding list to automatically populate the fields"
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ScrollBars = 'Vertical'
    $txt.Location = New-Object System.Drawing.Point(12, 40)
    $txt.Size = New-Object System.Drawing.Size(480, 220)
    $dlg.Controls.Add($txt)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "Parse"
    $btnOK.Location = New-Object System.Drawing.Point(316, 270)
    $btnOK.Add_Click({ $dlg.Tag = $txt.Text; $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $dlg.Close() })
    $dlg.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(407, 270)
    $btnCancel.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })
    $dlg.Controls.Add($btnCancel)

    $dlg.Add_Shown({ $txt.Focus() })
    return $dlg.ShowDialog($owner), $dlg.Tag
}

# =========================
# NEW: EMR text parser
# =========================
function Parse-EMRText {
    param([string]$Raw)

    $result = [PSCustomObject]@{
        Name         = $null
        MRN          = $null
        InstrumentID = $null
    }
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $result }

    # Normalize and split into trimmed lines (no regex)
    $text  = $Raw.Replace("`r","")
    $lines = $text.Split(@("`n"), [System.StringSplitOptions]::None) |
             ForEach-Object { $_.Trim() } |
             Where-Object { $_ -ne "" }

    # 1) Instrument ID: find the line that starts with "Instrument ID:"
    $idLine = $lines | Where-Object { $_.StartsWith("Instrument ID:", [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($idLine) {
        $colon = $idLine.IndexOf(":")
        if ($colon -ge 0) { $result.InstrumentID = $idLine.Substring($colon + 1).Trim() }
    }

    # 2) Name + MRN: find the line that contains "(MRN"
    $nmLine = $null
    foreach ($line in $lines) {
        if ($line.IndexOf("(MRN", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $nmLine = $line; break }
    }

    if ($nmLine) {
        # Pull everything before the "(" as the raw "Last, First [Middle]" block
        $paren = $nmLine.IndexOf("(")
        $nameBlock = if ($paren -gt 0) { $nmLine.Substring(0, $paren).Trim() } else { $nmLine.Trim() }

        # Keep EMR's "Last, First [Middle]" format exactly as provided
        $result.Name = $nameBlock.Trim()


        # Extract MRN token after "MRN"
        $mrnIdx = $nmLine.IndexOf("MRN", [System.StringComparison]::OrdinalIgnoreCase)
        if ($mrnIdx -ge 0) {
            $after = $nmLine.Substring($mrnIdx + 3)  # skip 'MRN'
            # Skip separators (spaces, punctuation)
            $i = 0
            while ($i -lt $after.Length -and -not ([char]::IsLetterOrDigit($after[$i]) -or $after[$i] -eq '-')) { $i++ }
            # Read MRN chars (letters, digits, hyphen) until a non-MRN char or ')'
            $j = $i
            while ($j -lt $after.Length -and (
                      [char]::IsLetterOrDigit($after[$j]) -or $after[$j] -eq '-')) { $j++ }
            if ($j -gt $i) { $result.MRN = $after.Substring($i, $j - $i) }
        }
    }

    return $result
}


# --- Event handler: Scan button (existing) ---
$btnScan.Add_Click({
    $result, $value = Show-ScanDialog -owner $form
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $value) {
        # Populate BarcodeData (Instrument ID) without slashes
        $txtInstrument.Text = [string]$value
        $txtTest.Focus()
    }
})

# --- Event handler: Send Label (existing) ---
$btnSend.Add_Click({
    $selectedPrinter = $comboPrinter.SelectedItem
    if (-not $selectedPrinter) {
        [System.Windows.Forms.MessageBox]::Show("Please select a printer.")
        return
    }
    $printerIP = $selectedPrinter.IP
    $barcodeData = $txtInstrument.Text.Trim()
    if ([string]::IsNullOrEmpty($barcodeData)) {
        [System.Windows.Forms.MessageBox]::Show("Instrument ID cannot be empty.")
        return
    }
    $patientName = $txtPatientName.Text
    $patientMRN = $txtPatientMRN.Text
    $testValue = $txtTest.Text
    $copies = [int]$nudCopies.Value

    # Send one job with ^PQ for multiple copies
    Send-ZPLLabel -PrinterIP $printerIP -PrinterPort 9100 -BarcodeData $barcodeData -Name $patientName -MRN $patientMRN -Test $testValue -Copies $copies

    # Log to "Sent Labels"
    $listSent.Items.Add(("{0} | {1} | MRN {2} | {3} copy/copies {4}" -f (Get-Date).ToString("HH:mm:ss"), $barcodeData, $patientMRN, $copies, $selectedPrinter.Name)) | Out-Null

    # Clear fields (copies persists by design)
    $txtInstrument.Clear()
    $txtTest.Clear()
})

# --- Event handler: Next Patient (existing) ---
$btnNext.Add_Click({
    $txtPatientName.Clear()
    $txtPatientMRN.Clear()
    $txtInstrument.Clear()
    $txtTest.Clear()
    $listSent.Items.Clear()
})

# --- Event handler: Exit (existing) ---
#$btnExit.Add_Click({ $form.Close() })

# =========================
# NEW: Event handler: Parse EMR
# =========================
$btnParse.Add_Click({
    $result, $raw = Show-ParseDialog -owner $form
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $parsed = Parse-EMRText -Raw $raw

        $filled = @()
        if ($parsed.Name)        { $txtPatientName.Text = $parsed.Name; $filled += 'Name' }
        if ($parsed.MRN)         { $txtPatientMRN.Text = $parsed.MRN; $filled += 'MRN' }
        if ($parsed.InstrumentID){ $txtInstrument.Text = $parsed.InstrumentID; $filled += 'Instrument ID' }

        if ($filled.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Couldn't parse Name, MRN, or Instrument ID. Please check the pasted text and try again.", "Parse failed")
        } else {
            # Move cursor to next useful field
            if (-not $txtInstrument.Text) { $txtInstrument.Focus() }
            elseif (-not $txtTest.Text)  { $txtTest.Focus() }
            else                         { $btnSend.Focus() }
        }
    }
})

$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)
