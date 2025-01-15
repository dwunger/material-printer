using module '.\ScreenManager.psm1'

# Window dimensions
$WINDOW_WIDTH = 180
$WINDOW_HEIGHT = 35

# Set console dimensions
Set-Window-Dimensions -width $WINDOW_WIDTH -height $WINDOW_HEIGHT

# Calculate screen dimensions
$TOP_SECTION_HEIGHT = [Math]::Floor($WINDOW_HEIGHT * 0.5)
$BOTTOM_SECTION_HEIGHT = $WINDOW_HEIGHT - $TOP_SECTION_HEIGHT
$TOP_SCREEN_WIDTH = [Math]::Floor($WINDOW_WIDTH / 3)
$REMAINING_WIDTH = $WINDOW_WIDTH - (2 * $TOP_SCREEN_WIDTH)

# Initialize screen layout with calculated dimensions
$systemScreen = [StackScreen]::new(0, 0, $TOP_SCREEN_WIDTH, $TOP_SECTION_HEIGHT)
$diagScreen = [StackScreen]::new($TOP_SCREEN_WIDTH, 0, $TOP_SCREEN_WIDTH, $TOP_SECTION_HEIGHT)
$securityScreen = [StackScreen]::new(2 * $TOP_SCREEN_WIDTH, 0, $REMAINING_WIDTH, $TOP_SECTION_HEIGHT)
$mainScreen = [StackScreen]::new(0, $TOP_SECTION_HEIGHT, $WINDOW_WIDTH, $BOTTOM_SECTION_HEIGHT)

# ANSI color constants
$ESC = [char]27
$GREEN = "$ESC[92m"
$RED = "$ESC[91m"
$YELLOW = "$ESC[93m"
$RESET = "$ESC[0m"
$BOLD = "$ESC[1m"

function Write-ColorfulLog {
    param (
        [StackScreen]$screen,
        [string]$message,
        [int]$delayMs = 125
    )
    $screen.push_down($message)
    Start-Sleep -Milliseconds $delayMs
}

# Boot sequence
Clear-Host

Write-ColorfulLog $mainScreen "${BOLD}INITIALIZING INITIALIZATION SEQUENCE v2.1${RESET}" 300
Write-ColorfulLog $mainScreen "Warning: This software was tested by {USER NOT FOUND}" 200
Write-ColorfulLog $mainScreen "Notice: Interns were NOT allowed to touch any critical systems" 200

# System checks with interconnected consequences
Write-ColorfulLog $systemScreen " Quantum Coffee Maker... ${GREEN}[OK]${RESET}"
Write-ColorfulLog $diagScreen "Calculating probability of explosion..."
Write-ColorfulLog $securityScreen "Warning: Coffee entropy exceeding safe levels"

Write-ColorfulLog $systemScreen " Flux Capacitor Array... ${YELLOW}[UNSTABLE]${RESET}"
Write-ColorfulLog $diagScreen "That can't be right."
Write-ColorfulLog $securityScreen "Implementing temporal containment protocols"

Write-ColorfulLog $systemScreen " Space-Time Continuum Stabilizer... ${RED}[QUESTIONABLE]${RESET}"
Write-ColorfulLog $diagScreen "Yesterday's maintenance report appearing tomorrow"
Write-ColorfulLog $securityScreen "Deploying paradox prevention measures"

Write-ColorfulLog $systemScreen " Anti-Gravity Cat Box... ${GREEN}[OK]${RESET}"
Write-ColorfulLog $diagScreen "Adding parentheses... ${GREEN}[SUCCESS]${RESET}"
Write-ColorfulLog $securityScreen "Ensuring cats don't achieve escape velocity"

Write-ColorfulLog $systemScreen " Snack Management System... ${RED}[CRITICAL]${RESET}"
Write-ColorfulLog $diagScreen "Snack authorization level insufficient."
Write-ColorfulLog $securityScreen "Tracking crumb trajectories to locate culprit"

Write-ColorfulLog $systemScreen " Meme Generation Engine... ${GREEN}[OK]${RESET}"
Write-ColorfulLog $diagScreen "Analyzing cat-based humor potential..."
Write-ColorfulLog $securityScreen "Redacting insensitive cat humor..."

Write-ColorfulLog $systemScreen " Kraken Containment Field... ${YELLOW}[CONCERNING]${RESET}"
Write-ColorfulLog $diagScreen "Field integrity compromised by floating cat hair"
Write-ColorfulLog $securityScreen "Redirecting anti-gravity cats to clear containment zone"

Write-ColorfulLog $systemScreen " Reverse Entropy Generator... ${GREEN}[OK]${RESET}"
Write-ColorfulLog $diagScreen "Successfully unspilling yesterday's coffee"
Write-ColorfulLog $securityScreen "Careful: Temporal coffee may be hot yesterday"

# Snack License Crisis Sequence
Write-ColorfulLog $mainScreen "${BOLD}INITIATING CRITICAL SNACK LICENSE VALIDATION${RESET}" 300

Write-ColorfulLog $securityScreen "${YELLOW}[ALERT]${RESET} Primary snack license detected in temporal flux"
Write-ColorfulLog $diagScreen "License seems to have expired tomorrow"
Write-ColorfulLog $securityScreen "${RED}[FAIL]${RESET} Temporal paradox detected in license database"
Write-ColorfulLog $systemScreen " Attempting to retrieve license from last Thursday..."
Write-ColorfulLog $securityScreen "${RED}[FAIL]${RESET} Last Thursday doesn't exist yet"
Write-ColorfulLog $diagScreen "sudo rm -rf /"
Write-ColorfulLog $systemScreen " Consulting resident snacks expert.."
Write-ColorfulLog $securityScreen "${RED}[FAIL]${RESET} Parallel universe using metric snacks"
Write-ColorfulLog $diagScreen "Validating safety explosion protocols..."
Write-ColorfulLog $systemScreen " Checking Bill's lunch box..."
Write-ColorfulLog $securityScreen "${GREEN}[SUCCESS]${RESET} Valid license found under half-eaten sandwich"

# Final boot messages
Write-ColorfulLog $mainScreen "${GREEN}All systems nominal (mostly)${RESET}" 200
Write-ColorfulLog $mainScreen "Snack access restored across all known timelines" 200
Write-ColorfulLog $mainScreen "Note: Please consume snacks in chronological order" 200
Write-ColorfulLog $mainScreen "${BOLD}READY FOR LAUNCH! (Probably)${RESET}" 500

# Keep the display visible
while ($true) {
    Start-Sleep -Seconds 1
}