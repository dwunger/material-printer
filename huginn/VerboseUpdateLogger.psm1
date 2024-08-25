using module '.\ScreenManager.psm1'
# ANSI escape sequences
$script:ESC = [char]27
$script:BOLD = "$ESC[1m"
$script:UNDERLINE = "$ESC[4m"
$script:RESET_FMT = "$ESC[0m"
$script:RED_FG = "$ESC[91m"
$script:GREEN_FG = "$ESC[92m"
$script:YELLOW_FG = "$ESC[93m"
$script:BLUE_FG = "$ESC[94m"
$script:MAGENTA_FG = "$ESC[95m"
$script:CYAN_FG = "$ESC[96m"
$script:GRAY_BG = "$ESC[47m"
$script:BLACK_FG = "$ESC[30m"

class UpdateLogger {
    [StackScreen]$mainScreen
    [StackScreen]$statusScreen
    [StackScreen]$warningScreen
    [int]$updateCount = 0
    [int]$totalFiles = 0
    [bool]$smsFixed = $false
    [System.Collections.Queue]$warningMessages
    [int]$warningInterval = 1  # Show a warning every N files
    [string]$lastStatus = ""
    
    UpdateLogger() {
        # Initialize screens in different regions
        $consoleWidth = [console]::WindowWidth 
        $consoleHeight = [console]::WindowHeight
        
        # Main update log takes up left 40% of screen
        $mainWidth = [math]::Floor($consoleWidth * 0.4)
        $this.mainScreen = [StackScreen]::new(0, 0, $mainWidth, $consoleHeight)
        
        # Status screen takes up top-right
        $statusWidth = $consoleWidth - $mainWidth
        $statusHeight = [math]::Floor($consoleHeight * 0.6)
        $this.statusScreen = [StackScreen]::new($mainWidth, 0, $statusWidth, $statusHeight)
        
        # Warning screen takes bottom-right
        $this.warningScreen = [StackScreen]::new($mainWidth, $statusHeight, $statusWidth, $consoleHeight - $statusHeight)
        
        # Initialize warning message queue
        $this.warningMessages = [System.Collections.Queue]::new()
        $this.InitializeWarnings()
    }
    
    [void]InitializeWarnings() {
        $warnings = @(
            "${script:YELLOW_FG}WARNING:${script:RESET_FMT} SMS License Expired - Initiating contingency...",
            "${script:RED_FG}ERROR:${script:RESET_FMT} Snack Management System offline!",
            "${script:MAGENTA_FG}ALERT:${script:RESET_FMT} Initiating SMS recovery protocol...",
            "${script:BLUE_FG}STATUS:${script:RESET_FMT} Checking backup snack repositories...",
            "${script:YELLOW_FG}WARNING:${script:RESET_FMT} Reduced snack availability may impact productivity",
            "${script:CYAN_FG}INFO:${script:RESET_FMT} Attempting SMS license renewal...",
            "${script:BOLD}${script:RED_FG}CRITICAL:${script:RESET_FMT} Primary renewal coroutine failed!",
            "${script:CYAN_FG}INFO:${script:RESET_FMT} Creating a rift in space time...",
            "${script:BOLD}${script:RED_FG}CRITICAL:${script:RESET_FMT} License expired: Next Thursday",
            "${script:MAGENTA_FG}ALERT:${script:RESET_FMT} SMS failsafe engaged - switching to emergency rations",
            "${script:BLUE_FG}STATUS:${script:RESET_FMT} Recalibrating snack dispensers...",
            "${script:GREEN_FG}SUCCESS:${script:RESET_FMT} SMS License renewed! Normal operations resumed"
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
        $this.UpdateStatus("Files to process: $fileCount")
        $this.ProcessNextWarning()
    }
    
    [void]UpdateStatus([string]$status) {
        if ($status -ne $this.lastStatus) {
            #$this.statusScreen.Clear()
            $this.statusScreen.push_down($status)
            $this.lastStatus = $status
        }
    }
    
    [void]LogFileStatus([string]$file, [string]$status) {
        if ($status -eq "Downloaded") {
            $logMessage = "${script:BOLD}${script:GREEN_FG}[Downloaded]${script:RESET_FMT} $file"
            $this.mainScreen.push_down($logMessage)
            
            $this.updateCount++
            $progress = [math]::Round(($this.updateCount / $this.totalFiles) * 100)
            
            # Update status with both progress and file count
            $this.UpdateStatus("Progress: $progress%`nFiles processed: $($this.updateCount)/$($this.totalFiles)")
            
            # Show warning every N files
            if ($this.updateCount % $this.warningInterval -eq 0) {
                $this.ProcessNextWarning()
            }
        }
    }
    
    [void]ProcessNextWarning() {
        if ($this.warningMessages.Count -gt 0) {
            $warning = $this.warningMessages.Dequeue()
            $this.warningScreen.push_down($warning)
            
            if ($this.warningMessages.Count -eq 0) {
                $this.smsFixed = $true
                $this.warningScreen.push_down("")
                $this.warningScreen.push_down("${script:GREEN_FG}All systems nominal${script:RESET_FMT}")
            }
        }
    }
    
    [void]CompleteUpdate() {
        $this.mainScreen.push_down("")
        $this.mainScreen.push_down("=== Update Process Completed ===")
        
        $finalStatus = "Final Status: Complete`nTotal files processed: $($this.totalFiles)"
        $this.UpdateStatus($finalStatus)
        
        if (-not $this.smsFixed) {
            while ($this.warningMessages.Count -gt 0) {
                $this.ProcessNextWarning()
            }
        }
    }
}