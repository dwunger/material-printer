using module '.\ScreenManager.psm1'

class UpdateLogger {
    [StackScreen]$mainScreen
    [StackScreen]$statusScreen
    [StackScreen]$warningScreen
    [int]$updateCount = 0
    [int]$totalFiles = 0
    [bool]$smsFixed = $false
    [System.Collections.Queue]$warningMessages
    
    UpdateLogger() {
        # Initialize screens in different regions
        $consoleWidth = [console]::WindowWidth
        $consoleHeight = [console]::WindowHeight
        
        # Main update log takes up left 60% of screen
        $mainWidth = [math]::Floor($consoleWidth * 0.6)
        $this.mainScreen = [StackScreen]::new(0, 0, $mainWidth, $consoleHeight)
        
        # Status screen takes up top-right
        $statusWidth = $consoleWidth - $mainWidth
        $statusHeight = [math]::Floor($consoleHeight * 0.4)
        $this.statusScreen = [StackScreen]::new($mainWidth, 0, $statusWidth, $statusHeight)
        
        # Warning screen takes bottom-right
        $this.warningScreen = [StackScreen]::new($mainWidth, $statusHeight, $statusWidth, $consoleHeight - $statusHeight)
        
        # Initialize warning message queue
        $this.warningMessages = [System.Collections.Queue]::new()
        $this.InitializeWarnings()
    }
    
    [void]InitializeWarnings() {
        $warnings = @(
            "WARNING: SMS License Expired - Initiating contingency...",
            "ERROR: Snack Management System offline!",
            "CRITICAL: Unauthorized snack consumption detected",
            "ALERT: Initiating SMS recovery protocol...",
            "STATUS: Checking backup snack repositories...",
            "WARNING: Reduced snack availability may impact productivity",
            "INFO: Attempting SMS license renewal...",
            "ALERT: SMS failsafe engaged - switching to emergency rations",
            "STATUS: Recalibrating snack dispensers...",
            "SUCCESS: SMS License renewed! Normal operations resumed"
        )
        
        foreach ($warning in $warnings) {
            $this.warningMessages.Enqueue($warning)
        }
    }
    
    [void]StartUpdate([int]$fileCount) {
        $this.totalFiles = $fileCount
        $this.updateCount = 0
        
        $this.mainScreen.Clear()
        $this.statusScreen.Clear()
        $this.warningScreen.Clear()
        
        $this.mainScreen.push_down("=== Update Process Started ===")
        $this.statusScreen.push_down("Files to process: $fileCount")
        $this.ProcessNextWarning()
    }
    
    [void]LogFileStatus([string]$file, [string]$status) {
        $statusColor = switch ($status) {
            "Pending" { "${script:BLACK_FG}${script:GRAY_BG}" }
            "Downloading" { "${script:UNDERLINE}${script:GREEN_FG}" }
            "Downloaded" { "${script:BOLD}${script:GREEN_FG}" }
            default { "${script:RESET_FMT}" }
        }
        
        $logMessage = "$statusColor[$status]${script:RESET_FMT} $file"
        $this.mainScreen.push_down($logMessage)
        
        if ($status -eq "Downloaded") {
            $this.updateCount++
            $progress = [math]::Round(($this.updateCount / $this.totalFiles) * 100)
            $this.statusScreen.Clear()
            $this.statusScreen.push_down("Progress: $progress%")
            $this.statusScreen.push_down("Files processed: $($this.updateCount)/$($this.totalFiles)")
        }
        
        # Random chance to process next warning
        if ((Get-Random -Minimum 1 -Maximum 100) -lt 30) {
            $this.ProcessNextWarning()
        }
    }
    
    [void]ProcessNextWarning() {
        if ($this.warningMessages.Count -gt 0) {
            $warning = $this.warningMessages.Dequeue()
            $this.warningScreen.push_down($warning)
            
            # If this is the last message, SMS is fixed
            if ($this.warningMessages.Count -eq 0) {
                $this.smsFixed = $true
                Start-Sleep -Milliseconds 500
                $this.warningScreen.push_down("")
                $this.warningScreen.push_down("${script:GREEN_FG}All systems nominal${script:RESET_FMT}")
            }
        }
    }
    
    [void]CompleteUpdate() {
        $this.mainScreen.push_down("")
        $this.mainScreen.push_down("=== Update Process Completed ===")
        $this.statusScreen.Clear()
        $this.statusScreen.push_down("Final Status: Complete")
        $this.statusScreen.push_down("Total files processed: $($this.totalFiles)")
        
        if (-not $this.smsFixed) {
            while ($this.warningMessages.Count -gt 0) {
                $this.ProcessNextWarning()
                Start-Sleep -Milliseconds 200
            }
        }
    }
}

