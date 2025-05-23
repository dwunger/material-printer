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
        [string]$Test = ""
    )

    # Adjust positions based on whether Test is provided, shifting all by 25 points upward.
    if ($Test -ne "") {
        $testFieldZPL = "^FO50,105^A0N,30,30^FDTest: $Test^FS`n"
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
$testFieldZPL^FO50,$barcodeY^BY2
^BCN,100,Y,N,N
^FD$BarcodeData^FS
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
    [PSCustomObject]@{ Name = "Chemistry"; IP = "PRT002131" }
    [PSCustomObject]@{ Name = "Urines"; IP = "PRT001070" }
)
foreach ($printer in $printers) {
    $comboPrinter.Items.Add($printer) | Out-Null
}
$comboPrinter.DisplayMember = "Name"
$comboPrinter.SelectedIndex = 0
$form.Controls.Add($comboPrinter)

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

# Instrument ID Input
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

# Button: Send Label
$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Location = New-Object System.Drawing.Point(140, 340)
$btnSend.Size = New-Object System.Drawing.Size(100, 30)
$btnSend.Text = "Send Label"
$form.Controls.Add($btnSend)

# Button: Next Patient (clears patient fields and sent labels)
$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Location = New-Object System.Drawing.Point(250, 340)
$btnNext.Size = New-Object System.Drawing.Size(100, 30)
$btnNext.Text = "Next Patient"
$form.Controls.Add($btnNext)

# Button: Exit
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Location = New-Object System.Drawing.Point(360, 340)
$btnExit.Size = New-Object System.Drawing.Size(100, 30)
$btnExit.Text = "Exit"
$form.Controls.Add($btnExit)

# Event handler for Send Label button
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
    # Call the function to send the label (using a hard-coded port of 9100 here)
    Send-ZPLLabel -PrinterIP $printerIP -PrinterPort 9100 -BarcodeData $barcodeData -Name $patientName -MRN $patientMRN -Test $testValue
    $txtInstrument.Clear()
    $txtTest.Clear()
})

# Event handler for Next Patient button: clear patient details and sent label history.
$btnNext.Add_Click({
    $txtPatientName.Clear()
    $txtPatientMRN.Clear()
    $txtInstrument.Clear()
    $txtTest.Clear()
    $listSent.Items.Clear()
})

# Exit button closes the form.
$btnExit.Add_Click({ $form.Close() })

$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)
