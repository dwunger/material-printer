# ScreenManager.psm1

# ANSI escape sequences
$script:ESC = [char]27
$script:BOLD = "$ESC[1m"
$script:UNDERLINE = "$ESC[4m"
$script:RESET_FMT = "$ESC[0m"
$script:RED_FG = "$ESC[91m"
$script:GREEN_FG = "$ESC[92m"
$script:GRAY_BG = "$ESC[47m"
$script:BLACK_FG = "$ESC[30m"

function Set-Window-Dimensions {
    param (
        [Parameter(Mandatory=$true)]
        [int] $width,
        [Parameter(Mandatory=$true)]
        [int] $height
    )
    
    Write-Host "Width: $width"
    Write-Host "Height: $height"
    
    # Validate input parameters
    if ($width -le 0) {
        throw "Width must be a positive integer. Actual value was $width."
    }
    
    if ($height -le 0) {
        throw "Height must be a positive integer. Actual value was $height."
    }
    
    # Set console window dimensions
    [console]::WindowWidth = $width
    [console]::WindowHeight = $height
    [console]::BufferWidth = [console]::WindowWidth
    [console]::Title = "Rad Printer"
}

class Display {
    [int] $DEBUG_DELAY = 0
    [string[]] $deltabuffer
    [string[]] $frontbuffer
    [int] $maxlines = 0
    [int] $maxwidth = 0
    [int] $line_position
    [string[]] $header
    [string[]] $footer
    [int] $content_start
    [int] $content_end

    Display([int]$contentLines) {
        $this.deltabuffer = @()
        $this.frontbuffer = @()
        $this.header = @()
        $this.footer = @()
        $this.content_start = 0
        $this.content_end = $contentLines - 1
        $this.init($contentLines)
    }

    [void] init([int]$contentLines) {
        for ($i = 0; $i -lt $contentLines; $i++) {
            $this.deltabuffer += ""
            $this.frontbuffer += ""
        }
    }

    [void] setHeader([string[]]$header) {
        $this.header = $header
        $this.content_start = $header.Count
        $this.updateMaxDimensions()
    }

    [void] setFooter([string[]]$footer) {
        $this.footer = $footer
        $this.content_end = $this.frontbuffer.Count - $footer.Count - 1
        $this.updateMaxDimensions()
    }

    [void] updateMaxDimensions() {
        $allLines = $this.header + $this.frontbuffer + $this.footer
        $this.maxlines = $allLines.Count
        $this.maxwidth = ($allLines | Measure-Object -Property Length -Maximum).Maximum
    }

    [void] clear() {

        #Start-Sleep $this.DEBUG_DELAY
        $this.line_position = $this.content_start
        #for ($i = $this.content_start; $i -le $this.content_end; $i++) {
        #    $this.deltabuffer[$i] = ""
        #    $this.frontbuffer[$i] = ""
        #}
        $this.updateMaxDimensions()
    }

    [void] trim() {
        for ($i = $this.line_position; $i -le $this.content_end; $i++) {
            $this.deltabuffer[$i] = $white_space = (-join (" " * $this.maxwidth))
        }
    }

    [void] write($newline) {
        if ($this.line_position -gt $this.content_end) {
            return
        }

        if ($this.frontbuffer[$this.line_position] -ne $newline) {
            $this.deltabuffer[$this.line_position] = $newline
        }

        $this.line_position++
    }

    [void] flush() {
        # Update header if changed
        $white_space = (-join (" " * $this.maxwidth))

        for ($i = 0; $i -lt $this.header.Count; $i++) {
            if ($this.header[$i] -ne $this.frontbuffer[$i]) {
                [System.Console]::SetCursorPosition(0, $i)
                Write-Host $white_space 
                [System.Console]::SetCursorPosition(0, $i)
                Write-Host $this.header[$i] 
                $this.frontbuffer[$i] = $this.header[$i]
            }
        }

        # Highlight the first line of header

        [System.Console]::SetCursorPosition(0, 0)
        Write-Host $this.header[0] -ForegroundColor Black -BackgroundColor Gray



        # Update content
        for ($i = $this.content_start; $i -le $this.content_end; $i++) {
            if ($this.deltabuffer[$i] -ne "") {
                [System.Console]::SetCursorPosition(0, $i)
                Write-Host $white_space 
                [System.Console]::SetCursorPosition(0, $i)
                Write-Host $this.deltabuffer[$i] 
                $this.frontbuffer[$i] = $this.deltabuffer[$i]
                $this.deltabuffer[$i] = ""
            }
        }

        # Update footer if changed
        $footerStart = $this.content_end + 1
        for ($i = 0; $i -lt $this.footer.Count; $i++) {
            if ($this.footer[$i] -ne $this.frontbuffer[$footerStart + $i]) {
                
                [System.Console]::SetCursorPosition(0, $footerStart + $i)
                Write-Host $white_space -ForegroundColor Black -BackgroundColor Gray
                [System.Console]::SetCursorPosition(0, $footerStart + $i)
                Write-Host $this.footer[$i] -ForegroundColor Black -BackgroundColor Gray
                $this.frontbuffer[$footerStart + $i] = $this.footer[$i]
            }
        }
    }
}


###########################################################STACK SCREEN#############################################################################
class Screen {
    [int] $x
    [int] $y
    [int] $height
    [int] $width

    Screen([int]$x, [int]$y, [int]$width, [int]$height) {
        $this.x = $x
        $this.y = $y
        $this.height = $height
        $this.width = $width
        $this.Fill("█", 0, 0, $width, $height)
        $this.Clear()
    }

    [bool] _in_bounds([int]$rel_x, [int]$rel_y) {
        $abs_x = $this.x + $rel_x
        $abs_y = $this.y + $rel_y
        if ($rel_x -lt 0 -or $rel_y -lt 0) { return $false }
        if ($rel_y -ge $this.height) { return $false }
        if ($rel_x -ge $this.width) { return $false }
        return $true
    }

    # Top Left <rel_x>, <rel_y>, <width>, <height>
    [void] Fill([string] $glyph, $rel_x, $rel_y, $width, $height) {
        if (-not ($this._in_bounds($rel_x, $rel_y) -and $this._in_bounds($rel_x + $width - 1, $rel_y + $height - 1))) {
            Write-Debug "Screen.Fill Attempted to write out of bounds"
            return
        }

        $line = $glyph * $width

        for ($i = 0; $i -lt $height; $i++) {
            [console]::SetCursorPosition($this.x + $rel_x, $this.y + $rel_y + $i)
            Write-Host $line -NoNewline
        }
    }

    [void] Clear() {
        $this.Fill(" ", 0, 0, $this.width, $this.height)
    }


    [void] Position_Write([string]$str, [int] $rel_x, [int] $rel_y) {
        # Bounds Checking
        if (-not $this._in_bounds($rel_x, $rel_y)) { return }
    
        $lines = $str -split "`n"
        $string_head = $lines[0]
        $string_tail = if ($lines.Count -gt 1) { $lines[1..($lines.Count-1)] -join "`n" } else { "" }
    
        # Calculate remaining width on the current line
        $remaining_width = $this.width - $rel_x
    
        # Truncate string_head if it's longer than the remaining width
        if ($string_head.Length -gt $remaining_width) {
            $string_head = $string_head.Substring(0, $remaining_width)
        }
    
        [console]::SetCursorPosition($this.x + $rel_x, $this.y + $rel_y)
        Write-Host $string_head -NoNewline
    
        if ($string_tail -ne "") {
            # Move to the next line if there's more to write
            $this.Position_Write($string_tail, 0, $rel_y + 1)
        }
    }

    [void] draw_border() {   
        #Top
        $this.Fill("█", 0, 0, $this.width, 1)
        #Left
        $this.Fill("█", 0, 0, 1, $this.height)
        #Right
        $this.Fill("█", $this.width - 1, 0, 1, $this.height)
        #Bottom
        $this.Fill("█", 0, $this.height - 1 , $this.width, 1)
    }
}

class StackScreen : Screen {
    [string[]]$content
    [bool] $DISABLE_REFRESH = $false
    [bool] $HIDE_BORDER = $false

    StackScreen([int]$x, [int]$y, [int]$width, [int]$height) : base($x, $y, $width, $height) {
        $this.content = @()
    }
    [void] Hide() {
        $this.DISABLE_REFRESH = $true
        $this.HIDE_BORDER = $true
        # Clear the screen (including borders)
        $this.Fill(" ", 0, 0, $this.width, $this.height)
    }

    [void] Show() {
        $this.DISABLE_REFRESH = $false
        $this.HIDE_BORDER = $false
        $this.Redraw()
        $this.draw_border()
    }

    [void] push_down([string]$new_line) {
        # Split the new_line into an array of lines
        $lines = $new_line -split "`n"

        # Add each line to the top of our content array
        $this.content = $lines + $this.content

        # Trim the content array if it exceeds the screen height
        if ($this.content.Count -gt ($this.height - 2)) {  # -2 to account for borders
            $this.content = $this.content[0..($this.height - 3)]
        }

        if ($this.DISABLE_REFRESH) {
            return
        }

        # Clear the screen (except borders)
        $this.Fill(" ", 1, 1, $this.width - 2, $this.height - 2)

        $this.Redraw() 
        ([Screen]$this).draw_border()
    }

    [void] Redraw() {
        if ($this.DISABLE_REFRESH) {
            return
        }

        for ($i = 0; $i -lt $this.content.Count; $i++) {
            $this.Position_Write($this.content[$i], 1, $i + 1)
        }

        ([Screen]$this).draw_border()
    }

    [string] pop() {
        if ($this.content.Count -eq 0) {
            return $null
        }

        # Remove the top line and store it
        $popped_line = $this.content[0]
        $this.content = $this.content[1..($this.content.Count - 1)]

        # Clear the screen (except borders)
        $this.Fill(" ", 1, 1, $this.width - 2, $this.height - 2)

        $this.Redraw() 

        return $popped_line
    }

    # Override the draw_border method to redraw content after drawing the border
    [void] draw_border() {

        if ($this.DISABLE_REFRESH) {
            return
        }
        # Call the parent's draw_border method
        ([Screen]$this).draw_border()

        $this.Redraw() 
    }
}
