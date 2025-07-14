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
    $global:side_pane.push_down($YELLOW_FG + $STARTUP_LOGMSG)

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
        # update open status
        $global:open_status_message = open-status-helper

        switch ($global:menu_level) {
            $INSTRUMENT_SELECT {
                # restore cursor
                $global:last_selected_item = $global:last_selected_index[$INSTRUMENT_SELECT]
                $selectedItem = Select-Instrument -instrument_select_array $instrument_select_array -display $global:display
                if ($selectedItem -ge 0) {
                    $instrument_menu_selection = $selectedItem
                    $global:menu_level         = $MATERIAL_GROUP_SELECT
                }
                $global:last_selected_index[$INSTRUMENT_SELECT] = $selectedItem
                Lock-CS2500-Open-Status
            }
            $MATERIAL_GROUP_SELECT {
                $selected_instrument = $instrument_select_array[$instrument_menu_selection]
                $material_groups     = $materialGroupsByInstrument[$selected_instrument]

                $global:last_selected_item = $global:last_selected_index[$MATERIAL_GROUP_SELECT]
                $selectedItem = Select-MaterialGroup -material_groups $material_groups -display $global:display
                if ($selectedItem -ge 0) {
                    $selected_group_index = $selectedItem
                    $global:menu_level    = $MATERIAL_SELECT
                }
                $global:last_selected_index[$MATERIAL_GROUP_SELECT] = $selectedItem
                Lock-CS2500-Open-Status
            }
            $MATERIAL_SELECT {
                $selected_instrument = $instrument_select_array[$instrument_menu_selection]
                $selected_group      = $materialGroupsByInstrument[$selected_instrument][$selected_group_index]

                $global:last_selected_item = $global:last_selected_index[$MATERIAL_SELECT]
                $selectedItem = Select-Material -selected_group $selected_group -display $global:display
                if ($selectedItem -ge 0) {
                    $selected_material_index = $selectedItem
                    print_label -material $selected_group.materials_list[$selected_material_index]
                }
                $global:last_selected_index[$MATERIAL_SELECT] = $selectedItem
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
