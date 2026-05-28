# ================================================
# THERMOTRON 2800 - PARAMETER GUI
# Standalone Windows PowerShell GUI
# No installation required
# Supports: Simple Soak, Ramp Cycle, Multi-Step
# ================================================
# HOW TO RUN:
#   Right-click > Run with PowerShell
#   OR double-click thermotron2800_gui.bat
# ================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================================================
# HELPER: Get available COM ports
# ================================================
function Get-ComPorts {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    if ($ports.Count -eq 0) { $ports = @("COM1","COM2","COM3","COM4") }
    return $ports
}

# ================================================
# COLORS & FONTS
# ================================================
$clrBg       = [System.Drawing.Color]::FromArgb(30, 30, 30)
$clrPanel    = [System.Drawing.Color]::FromArgb(45, 45, 45)
$clrAccent   = [System.Drawing.Color]::FromArgb(255, 140, 0)
$clrText     = [System.Drawing.Color]::FromArgb(230, 230, 230)
$clrSubText  = [System.Drawing.Color]::FromArgb(160, 160, 160)
$clrInput    = [System.Drawing.Color]::FromArgb(60, 60, 60)
$clrBorder   = [System.Drawing.Color]::FromArgb(80, 80, 80)
$clrGreen    = [System.Drawing.Color]::FromArgb(80, 200, 120)
$clrRed      = [System.Drawing.Color]::FromArgb(220, 80, 80)
$clrRowA     = [System.Drawing.Color]::FromArgb(50, 50, 50)
$clrRowB     = [System.Drawing.Color]::FromArgb(58, 58, 58)

$fntTitle    = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
$fntLabel    = New-Object System.Drawing.Font("Consolas", 9,  [System.Drawing.FontStyle]::Regular)
$fntInput    = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Regular)
$fntButton   = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$fntSmall    = New-Object System.Drawing.Font("Consolas", 8,  [System.Drawing.FontStyle]::Regular)
$fntBold     = New-Object System.Drawing.Font("Consolas", 9,  [System.Drawing.FontStyle]::Bold)

# ================================================
# MULTI-STEP STORAGE
# ================================================
$script:steps = [System.Collections.ArrayList]@()

# ================================================
# PROCESS TRACKING
# ================================================
$script:testProcess  = $null
$script:testComPort  = $null
$script:testGpibAddr = 2

# ================================================
# HELPER: Create labeled input field
# ================================================
function Add-InputField {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$LabelText,
        [string]$DefaultValue,
        [int]$X, [int]$Y,
        [int]$LabelWidth = 200,
        [int]$InputWidth = 100
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $LabelText
    $lbl.Location  = New-Object System.Drawing.Point($X, ($Y + 3))
    $lbl.Size      = New-Object System.Drawing.Size($LabelWidth, 20)
    $lbl.ForeColor = $clrText
    $lbl.Font      = $fntLabel
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Text        = $DefaultValue
    $txt.Location    = New-Object System.Drawing.Point(($X + $LabelWidth + 10), $Y)
    $txt.Size        = New-Object System.Drawing.Size($InputWidth, 24)
    $txt.BackColor   = $clrInput
    $txt.ForeColor   = $clrText
    $txt.Font        = $fntInput
    $txt.BorderStyle = "FixedSingle"
    $Parent.Controls.Add($lbl)
    $Parent.Controls.Add($txt)
    return $txt
}

# ================================================
# HELPER: Section header
# ================================================
function Add-SectionHeader {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$Y,
        [int]$Width = 445
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = "  $Text"
    $lbl.Location  = New-Object System.Drawing.Point(20, $Y)
    $lbl.Size      = New-Object System.Drawing.Size($Width, 22)
    $lbl.BackColor = $clrPanel
    $lbl.ForeColor = $clrAccent
    $lbl.Font      = $fntBold
    $Parent.Controls.Add($lbl)
}

# ================================================
# PROLOGIX BLOCK (embedded in generated scripts)
# ================================================
$prologixBlock = @'

function Init-Prologix {
    Write-Log "Initializing Prologix GPIB-USB adapter..."
    $port.WriteLine("++mode 1")          ; Start-Sleep -Milliseconds 200
    $port.WriteLine("++addr $GPIB_ADDR") ; Start-Sleep -Milliseconds 200
    $port.WriteLine("++auto 0")          ; Start-Sleep -Milliseconds 200
    $port.WriteLine("++eos 2")           ; Start-Sleep -Milliseconds 200
    $port.WriteLine("++eoi 0")           ; Start-Sleep -Milliseconds 200
    $port.WriteLine("++read_tmo_ms 3000"); Start-Sleep -Milliseconds 200
    $port.DiscardInBuffer()
    Write-Log "Prologix initialized. GPIB address: $GPIB_ADDR | Auto-read: OFF"
}

function Send-Command {
    param([string]$Command, [int]$DelayMs = 500)
    try {
        $port.DiscardInBuffer()
        $port.WriteLine($Command)
        Write-Log ">> Sent: $Command"
        Start-Sleep -Milliseconds $DelayMs
    } catch {
        Write-Log "ERROR sending '$Command': $_" "ERROR"
    }
}

function Read-Response {
    try {
        $response = $port.ReadLine().Trim()
        Write-Log "<< Received: $response"
        return $response
    } catch [System.TimeoutException] {
        Write-Log "<< WARNING: No response (timeout)" "WARN"
        return ""
    } catch {
        Write-Log "<< ERROR: $_" "ERROR"
        return ""
    }
}

function Send-DumpCommand {
    param([string]$Command, [int]$MaxRetries = 3, [int]$DelayMs = 500)
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        if ($attempt -gt 1) {
            Write-Log "  Retry $attempt of $MaxRetries for $Command..." "WARN"
            Start-Sleep -Milliseconds 500
        }
        $port.DiscardInBuffer()
        $port.WriteLine($Command)
        Write-Log ">> Sent: $Command"
        Start-Sleep -Milliseconds $DelayMs
        $port.WriteLine("++read eoi")
        Start-Sleep -Milliseconds 300
        $response = Read-Response
        if ($response -ne "") { return $response }
    }
    Write-Log "  $Command failed after $MaxRetries attempts." "WARN"
    return ""
}

function Poll-Temperature {
    $temp = Send-DumpCommand "DTV"
    # Write data point to chart CSV if enabled
    if ($CHART_DATA_FILE -ne "" -and $temp -ne "") {
        $elapsed = [math]::Round(((Get-Date) - $TEST_START_TIME).TotalSeconds, 0)
        $row = "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),$elapsed,$CURRENT_SETPOINT,$temp,data"
        Add-Content -Path $CHART_DATA_FILE -Value $row -ErrorAction SilentlyContinue
    }
    return $temp
}
function Poll-Status { return Send-DumpCommand "DST" }

function Write-ChartEvent {
    param([string]$EventLabel)
    if ($CHART_DATA_FILE -ne "") {
        $elapsed = [math]::Round(((Get-Date) - $TEST_START_TIME).TotalSeconds, 0)
        $row = "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),$elapsed,$CURRENT_SETPOINT,,$EventLabel"
        Add-Content -Path $CHART_DATA_FILE -Value $row -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------
# Stop-Controller
# Sends the S command multiple times and verifies
# the controller has actually stopped by checking
# the status byte. Retries up to $MaxAttempts times
# with a delay between each attempt.
# Status byte bits 0-2 = 000 means Stop state.
# ------------------------------------------------
function Stop-Controller {
    param([int]$MaxAttempts = 5, [int]$DelayMs = 1000)
    Write-Log "Sending STOP to controller..."
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $port.DiscardInBuffer()
        $port.WriteLine("S")
        Write-Log ">> Sent: S (attempt $attempt of $MaxAttempts)"
        Start-Sleep -Milliseconds $DelayMs

        $status = Send-DumpCommand "DST"
        if ($status -ne "") {
            try {
                $statusInt = [int]$status
                $stateBits = $statusInt -band 7
                if ($stateBits -eq 0) {
                    Write-Log "Controller confirmed STOPPED (status: $status)."
                    # Unlock the keyboard so the chamber panel
                    # is usable again after the test ends
                    $port.DiscardInBuffer()
                    $port.WriteLine("LKS0")
                    Write-Log ">> Sent: LKS0 (keyboard unlocked)"
                    Start-Sleep -Milliseconds 500
                    return $true
                } else {
                    Write-Log "Controller not yet stopped (status: $status, state bits: $stateBits) - retrying..." "WARN"
                }
            } catch {
                Write-Log "Could not parse status byte '$status' - retrying..." "WARN"
            }
        } else {
            Write-Log "No status response - retrying S command..." "WARN"
        }
    }
    Write-Log "WARNING: Could not confirm controller stopped after $MaxAttempts attempts." "WARN"
    # Attempt keyboard unlock even if stop confirmation failed
    $port.DiscardInBuffer()
    $port.WriteLine("LKS0")
    Write-Log ">> Sent: LKS0 (keyboard unlock attempted)" "WARN"
    return $false
}

function Set-Temperature {
    param([int]$Temp)
    $script:CURRENT_SETPOINT = $Temp
    if ($Temp -ge 0) { $fmt = "LTS+" + $Temp.ToString("D3") }
    else             { $fmt = "LTS-" + ([math]::Abs($Temp)).ToString("D3") }
    Send-Command $fmt
    Write-ChartEvent "setpoint:$Temp"
    Start-Sleep -Seconds 1
}

# ------------------------------------------------
# Test-StopFlag
# Checks for the presence of a stop flag file
# written by the GUI Stop Test button.
# Returns $true if stop has been requested.
# ------------------------------------------------
function Test-StopFlag {
    return (Test-Path $STOP_FLAG_FILE)
}

# ------------------------------------------------
# Start-TimedWait
# Waits for the specified duration, polling the
# controller temperature at each interval.
# Checks for stop flag on every poll - if found,
# sends S command and throws to trigger cleanup.
# ------------------------------------------------
function Start-TimedWait {
    param([int]$Minutes, [string]$Description)
    $endTime = (Get-Date).AddSeconds($Minutes * 60)
    Write-Log "Waiting $Minutes min: $Description"
    while ((Get-Date) -lt $endTime) {
        # Check stop flag immediately at top of each cycle
        if (Test-StopFlag) {
            Write-Log "STOP flag detected - halting test immediately." "WARN"
            throw "STOP_REQUESTED"
        }
        $remaining = [math]::Round(($endTime - (Get-Date)).TotalMinutes, 1)
        Write-Log "  $remaining min remaining..."
        Poll-Temperature

        # Sleep in 2-second increments up to POLL_SECONDS
        # so the stop flag is checked frequently regardless
        # of how long the poll interval is set to
        $pollEnd = (Get-Date).AddSeconds($POLL_SECONDS)
        while ((Get-Date) -lt $pollEnd -and (Get-Date) -lt $endTime) {
            # Check stop flag on every 2-second tick
            if (Test-StopFlag) {
                Write-Log "STOP flag detected - halting test immediately." "WARN"
                throw "STOP_REQUESTED"
            }
            Start-Sleep -Seconds 2
        }
    }
    Write-Log "$Description complete."
}
'@

# ================================================
# SCRIPT GENERATOR: SIMPLE SOAK
# ================================================
function Generate-SoakScript {
    param(
        [string]$ComPort, [int]$GpibAddress,
        [int]$TargetTemp, [int]$HoldMinutes,
        [bool]$Indefinite, [string]$TempScale,
        [string]$OutputPath,
        [string]$LogPath = "",
        [int]$PollSeconds = 60,
        [string]$ChartDataFile = ""
    )
    $logLine = if ($LogPath -ne "") {
        "`$LOG_FILE = `"$LogPath\thermotron2800_log_`$(Get-Date -Format 'yyyyMMdd_HHmmss').txt`""
    } else {
        "`$LOG_FILE = `$null   # Logging disabled"
    }
    $logWrite = if ($LogPath -ne "") {
        "if (`$LOG_FILE) { Add-Content -Path `$LOG_FILE -Value `$entry }"
    } else {
        "# Logging disabled"
    }
    $holdDesc  = if ($Indefinite) { "indefinitely (manual stop required)" } else { "$HoldMinutes minutes" }
    $holdBlock = if ($Indefinite) {
'    Write-Log "Holding indefinitely - use Stop Test button to end."
    while ($true) { Poll-Temperature ; Start-Sleep -Seconds $POLL_SECONDS }'
    } else {
"    Start-TimedWait -Minutes `$HOLD_MINUTES -Description `"Soak at `${TARGET_TEMP}$TempScale`""
    }

    $script = @"
# ================================================
# THERMOTRON 2800 - SIMPLE SOAK
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Target: ${TargetTemp}$TempScale | Hold: $holdDesc
# Port: $ComPort | GPIB: $GpibAddress
# ================================================

`$COM_PORT      = "$ComPort"
`$GPIB_ADDR    = $GpibAddress
`$BAUD_RATE    = 9600
`$TARGET_TEMP  = $TargetTemp
`$HOLD_MINUTES = $HoldMinutes
`$POLL_SECONDS = $PollSeconds
`$STOP_FLAG_FILE  = "`$PSScriptRoot\thermotron2800_stop.flag"
`$CHART_DATA_FILE = "$ChartDataFile"
`$TEST_START_TIME = Get-Date
`$CURRENT_SETPOINT = $TargetTemp
$logLine
`$TIMEOUT_SEC  = 5

# Remove any leftover stop flag from a previous run
if (Test-Path `$STOP_FLAG_FILE) { Remove-Item `$STOP_FLAG_FILE -Force }

# Write chart data header if chart is enabled
if (`$CHART_DATA_FILE -ne "") {
    "timestamp,elapsed_sec,setpoint,temperature,event" |
        Out-File -FilePath `$CHART_DATA_FILE -Encoding UTF8 -Force
    `$startStr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    "`$startStr,0,$TargetTemp,,start:`$startStr" |
        Add-Content -Path `$CHART_DATA_FILE
}

function Write-Log {
    param([string]`$Message, [string]`$Level = "INFO")
    `$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$entry = "[`$ts] [`$Level] `$Message"
    Write-Host `$entry
    $logWrite
}

Write-Log "================================================"
Write-Log "  THERMOTRON 2800 - SIMPLE SOAK"
Write-Log "  Started:  `$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Log "  Target:   `${TARGET_TEMP}$TempScale | Hold: $holdDesc"
Write-Log "================================================"

try {
    `$port = New-Object System.IO.Ports.SerialPort
    `$port.PortName     = `$COM_PORT ; `$port.BaudRate     = `$BAUD_RATE
    `$port.Parity       = [System.IO.Ports.Parity]::None
    `$port.DataBits     = 8
    `$port.StopBits     = [System.IO.Ports.StopBits]::One
    `$port.Handshake    = [System.IO.Ports.Handshake]::None
    `$port.NewLine      = "``n"
    `$port.ReadTimeout  = (`$TIMEOUT_SEC * 1000) ; `$port.WriteTimeout = 2000
    `$port.Open()
    Write-Log "Port `$COM_PORT opened."
} catch { Write-Log "ERROR: `$_" "ERROR" ; exit 1 }
$prologixBlock

try {
    Init-Prologix
    Write-Log "" ; Write-Log "Stopping controller..."
    Stop-Controller
    Write-Log "" ; Write-Log "Entering Run Manual mode..."
    Send-Command "RM" ; Start-Sleep -Seconds 2 ; Poll-Status
    Write-Log "" ; Write-Log "Setting temperature to `${TARGET_TEMP}$TempScale..."
    Set-Temperature `$TARGET_TEMP ; Start-Sleep -Seconds 2
    Write-Log "" ; Write-Log "Holding at `${TARGET_TEMP}$TempScale..."
$holdBlock
    Write-Log "" ; Write-Log "Stopping controller..."
    Stop-Controller
    Write-Log ""; Write-Log "================================================"
    Write-Log "  SOAK COMPLETE. Log: `$LOG_FILE"
    Write-Log "================================================"
} catch {
    if (`$_.Exception.Message -eq "STOP_REQUESTED") {
        Write-Log "Test stopped by user. Sending STOP to controller..." "WARN"
        Stop-Controller
    } else {
        Write-Log "FATAL ERROR: `$_" "ERROR"
    }
} finally {
    if (Test-Path `$STOP_FLAG_FILE) { Remove-Item `$STOP_FLAG_FILE -Force }
    if (`$port.IsOpen) { `$port.Close() ; Write-Log "Port closed." }
}
"@
    $script | Out-File -FilePath $OutputPath -Encoding UTF8
}
# ================================================
function Generate-RampScript {
    param(
        [string]$ComPort, [int]$GpibAddress,
        [int]$StartTemp, [int]$HighTemp, [int]$LowTemp,
        [int]$RampMinutes, [int]$SoakMinutes,
        [int]$LoopCount, [string]$TempScale,
        [string]$OutputPath,
        [string]$LogPath = "",
        [int]$PollSeconds = 60,
        [string]$ChartDataFile = ""
    )
    $logLine = if ($LogPath -ne "") {
        "`$LOG_FILE = `"$LogPath\thermotron2800_log_`$(Get-Date -Format 'yyyyMMdd_HHmmss').txt`""
    } else {
        "`$LOG_FILE = `$null   # Logging disabled"
    }
    $logWrite = if ($LogPath -ne "") {
        "if (`$LOG_FILE) { Add-Content -Path `$LOG_FILE -Value `$entry }"
    } else {
        "# Logging disabled"
    }
    $script = @"
# ================================================
# THERMOTRON 2800 - RAMP CYCLE
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Profile: ${StartTemp}$TempScale -> ${HighTemp}$TempScale -> ${LowTemp}$TempScale x$LoopCount
# Port: $ComPort | GPIB: $GpibAddress
# ================================================

`$COM_PORT      = "$ComPort"
`$GPIB_ADDR    = $GpibAddress
`$BAUD_RATE    = 9600
`$LOOP_COUNT   = $LoopCount
`$HIGH_TEMP    = $HighTemp
`$LOW_TEMP     = $LowTemp
`$START_TEMP   = $StartTemp
`$RAMP_MINUTES = $RampMinutes
`$SOAK_MINUTES = $SoakMinutes
`$POLL_SECONDS = $PollSeconds
`$STOP_FLAG_FILE  = "`$PSScriptRoot\thermotron2800_stop.flag"
`$CHART_DATA_FILE = "$ChartDataFile"
`$TEST_START_TIME = Get-Date
`$CURRENT_SETPOINT = $StartTemp
$logLine
`$TIMEOUT_SEC  = 5

# Remove any leftover stop flag from a previous run
if (Test-Path `$STOP_FLAG_FILE) { Remove-Item `$STOP_FLAG_FILE -Force }

# Write chart data header if chart is enabled
if (`$CHART_DATA_FILE -ne "") {
    "timestamp,elapsed_sec,setpoint,temperature,event" |
        Out-File -FilePath `$CHART_DATA_FILE -Encoding UTF8 -Force
    `$startStr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    "`$startStr,0,$StartTemp,,start:`$startStr" |
        Add-Content -Path `$CHART_DATA_FILE
}

function Write-Log {
    param([string]`$Message, [string]`$Level = "INFO")
    `$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$entry = "[`$ts] [`$Level] `$Message"
    Write-Host `$entry
    $logWrite
}

Write-Log "================================================"
Write-Log "  THERMOTRON 2800 - RAMP CYCLE"
Write-Log "  Started:  `$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Log "  Profile:  `${START_TEMP}$TempScale -> `${HIGH_TEMP}$TempScale -> `${LOW_TEMP}$TempScale x`$LOOP_COUNT"
Write-Log "================================================"

try {
    `$port = New-Object System.IO.Ports.SerialPort
    `$port.PortName     = `$COM_PORT ; `$port.BaudRate     = `$BAUD_RATE
    `$port.Parity       = [System.IO.Ports.Parity]::None
    `$port.DataBits     = 8
    `$port.StopBits     = [System.IO.Ports.StopBits]::One
    `$port.Handshake    = [System.IO.Ports.Handshake]::None
    `$port.NewLine      = "``n"
    `$port.ReadTimeout  = (`$TIMEOUT_SEC * 1000) ; `$port.WriteTimeout = 2000
    `$port.Open()
    Write-Log "Port `$COM_PORT opened."
} catch { Write-Log "ERROR: `$_" "ERROR" ; exit 1 }
$prologixBlock

try {
    Init-Prologix
    Write-Log "" ; Write-Log "Stopping controller..."
    Stop-Controller
    Write-Log "" ; Write-Log "Entering Run Manual mode..."
    Send-Command "RM" ; Start-Sleep -Seconds 2 ; Poll-Status
    Write-Log "" ; Write-Log "Setting initial temp to `${START_TEMP}$TempScale..."
    Set-Temperature `$START_TEMP ; Start-Sleep -Seconds 2

    for (`$loop = 1; `$loop -le `$LOOP_COUNT; `$loop++) {
        Write-Log "" ; Write-Log "==============================="
        Write-Log "  CYCLE `$loop OF `$LOOP_COUNT"
        Write-Log "==============================="
        Write-Log "" ; Write-Log "  Ramping to `${HIGH_TEMP}$TempScale..."
        Set-Temperature `$HIGH_TEMP
        Start-TimedWait -Minutes `$RAMP_MINUTES -Description "Ramp to `${HIGH_TEMP}$TempScale"
        Write-Log "" ; Write-Log "  Soaking at `${HIGH_TEMP}$TempScale..."
        Start-TimedWait -Minutes `$SOAK_MINUTES -Description "Soak at `${HIGH_TEMP}$TempScale"
        Write-Log "" ; Write-Log "  Ramping to `${LOW_TEMP}$TempScale..."
        Set-Temperature `$LOW_TEMP
        Start-TimedWait -Minutes `$RAMP_MINUTES -Description "Ramp to `${LOW_TEMP}$TempScale"
        Write-Log "" ; Write-Log "  Soaking at `${LOW_TEMP}$TempScale..."
        Start-TimedWait -Minutes `$SOAK_MINUTES -Description "Soak at `${LOW_TEMP}$TempScale"
        Poll-Status ; Poll-Temperature
    }

    Write-Log "" ; Write-Log "==============================="
    Write-Log "  ALL `$LOOP_COUNT CYCLES COMPLETE"
    Write-Log "==============================="
    Write-Log "" ; Write-Log "Returning to `${START_TEMP}$TempScale..."
    Set-Temperature `$START_TEMP
    Start-TimedWait -Minutes `$RAMP_MINUTES -Description "Return to `${START_TEMP}$TempScale"
    Stop-Controller
    Write-Log "" ; Write-Log "================================================"
    Write-Log "  TEST COMPLETE. Log: `$LOG_FILE"
    Write-Log "================================================"
} catch {
    if (`$_.Exception.Message -eq "STOP_REQUESTED") {
        Write-Log "Test stopped by user. Sending STOP to controller..." "WARN"
        Stop-Controller
    } else {
        Write-Log "FATAL ERROR: `$_" "ERROR"
    }
} finally {
    if (Test-Path `$STOP_FLAG_FILE) { Remove-Item `$STOP_FLAG_FILE -Force }
    if (`$port.IsOpen) { `$port.Close() ; Write-Log "Port closed." }
}
"@
    $script | Out-File -FilePath $OutputPath -Encoding UTF8
}

# ================================================
# SCRIPT GENERATOR: MULTI-STEP
# ================================================
function Generate-MultiStepScript {
    param(
        [string]$ComPort, [int]$GpibAddress,
        [int]$StartTemp, [object[]]$Steps,
        [int]$LoopCount, [string]$TempScale,
        [string]$OutputPath,
        [string]$LogPath = "",
        [int]$PollSeconds = 60,
        [string]$ChartDataFile = ""
    )
    $logLine = if ($LogPath -ne "") {
        "`$LOG_FILE = `"$LogPath\thermotron2800_log_`$(Get-Date -Format 'yyyyMMdd_HHmmss').txt`""
    } else {
        "`$LOG_FILE = `$null   # Logging disabled"
    }
    $logWrite = if ($LogPath -ne "") {
        "if (`$LOG_FILE) { Add-Content -Path `$LOG_FILE -Value `$entry }"
    } else {
        "# Logging disabled"
    }
    $stepLines = ""
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $s = $Steps[$i] ; $n = $i + 1
        $stepLines += @"

        Write-Log "" ; Write-Log "  --- STEP $n OF $($Steps.Count) ---"
        Write-Log "  Target: $($s.Temp)$TempScale | Ramp: $($s.RampMin) min | Soak: $($s.SoakMin) min"
        Set-Temperature $($s.Temp)
        Start-TimedWait -Minutes $($s.RampMin) -Description "Ramp to $($s.Temp)$TempScale"
        Start-TimedWait -Minutes $($s.SoakMin) -Description "Soak at $($s.Temp)$TempScale"
        Poll-Status ; Poll-Temperature
"@
    }
    $stepSummary = ""
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $stepSummary += "#   Step $($i+1): $($Steps[$i].Temp)$TempScale | Ramp $($Steps[$i].RampMin)min | Soak $($Steps[$i].SoakMin)min`n"
    }

    $script = @"
# ================================================
# THERMOTRON 2800 - MULTI-STEP PROFILE
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Steps: $($Steps.Count) | Cycles: $LoopCount
# Port: $ComPort | GPIB: $GpibAddress
# ------------------------------------------------
$stepSummary# ================================================

`$COM_PORT      = "$ComPort"
`$GPIB_ADDR    = $GpibAddress
`$BAUD_RATE    = 9600
`$START_TEMP   = $StartTemp
`$LOOP_COUNT   = $LoopCount
`$POLL_SECONDS = $PollSeconds
`$STOP_FLAG_FILE  = "`$PSScriptRoot\thermotron2800_stop.flag"
`$CHART_DATA_FILE = "$ChartDataFile"
`$TEST_START_TIME = Get-Date
`$CURRENT_SETPOINT = $StartTemp
$logLine
`$TIMEOUT_SEC  = 5

# Remove any leftover stop flag from a previous run
if (Test-Path `$STOP_FLAG_FILE) { Remove-Item `$STOP_FLAG_FILE -Force }

# Write chart data header if chart is enabled
if (`$CHART_DATA_FILE -ne "") {
    "timestamp,elapsed_sec,setpoint,temperature,event" |
        Out-File -FilePath `$CHART_DATA_FILE -Encoding UTF8 -Force
    `$startStr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    "`$startStr,0,$StartTemp,,start:`$startStr" |
        Add-Content -Path `$CHART_DATA_FILE
}

function Write-Log {
    param([string]`$Message, [string]`$Level = "INFO")
    `$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$entry = "[`$ts] [`$Level] `$Message"
    Write-Host `$entry
    $logWrite
}

Write-Log "================================================"
Write-Log "  THERMOTRON 2800 - MULTI-STEP PROFILE"
Write-Log "  Started:  `$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Log "  Steps:    $($Steps.Count) | Cycles: `$LOOP_COUNT"
Write-Log "================================================"

try {
    `$port = New-Object System.IO.Ports.SerialPort
    `$port.PortName     = `$COM_PORT ; `$port.BaudRate     = `$BAUD_RATE
    `$port.Parity       = [System.IO.Ports.Parity]::None
    `$port.DataBits     = 8
    `$port.StopBits     = [System.IO.Ports.StopBits]::One
    `$port.Handshake    = [System.IO.Ports.Handshake]::None
    `$port.NewLine      = "``n"
    `$port.ReadTimeout  = (`$TIMEOUT_SEC * 1000) ; `$port.WriteTimeout = 2000
    `$port.Open()
    Write-Log "Port `$COM_PORT opened."
} catch { Write-Log "ERROR: `$_" "ERROR" ; exit 1 }
$prologixBlock

try {
    Init-Prologix
    Write-Log "" ; Write-Log "Stopping controller..."
    Stop-Controller
    Write-Log "" ; Write-Log "Entering Run Manual mode..."
    Send-Command "RM" ; Start-Sleep -Seconds 2 ; Poll-Status
    Write-Log "" ; Write-Log "Setting initial temp to `${START_TEMP}$TempScale..."
    Set-Temperature `$START_TEMP ; Start-Sleep -Seconds 2

    for (`$loop = 1; `$loop -le `$LOOP_COUNT; `$loop++) {
        Write-Log "" ; Write-Log "==============================="
        Write-Log "  CYCLE `$loop OF `$LOOP_COUNT"
        Write-Log "==============================="
$stepLines
    }

    Write-Log "" ; Write-Log "==============================="
    Write-Log "  ALL `$LOOP_COUNT CYCLES COMPLETE"
    Write-Log "==============================="
    Write-Log "" ; Write-Log "Returning to `${START_TEMP}$TempScale..."
    Set-Temperature `$START_TEMP
    Stop-Controller
    Write-Log "" ; Write-Log "================================================"
    Write-Log "  TEST COMPLETE. Log: `$LOG_FILE"
    Write-Log "================================================"
} catch {
    if (`$_.Exception.Message -eq "STOP_REQUESTED") {
        Write-Log "Test stopped by user. Sending STOP to controller..." "WARN"
        Stop-Controller
    } else {
        Write-Log "FATAL ERROR: `$_" "ERROR"
    }
} finally {
    if (Test-Path `$STOP_FLAG_FILE) { Remove-Item `$STOP_FLAG_FILE -Force }
    if (`$port.IsOpen) { `$port.Close() ; Write-Log "Port closed." }
}
"@
    $script | Out-File -FilePath $OutputPath -Encoding UTF8
}

# ================================================
# BATCH FILE GENERATOR
# ================================================
function Generate-BatchFile {
    param([string]$PS1Path, [string]$BatPath)
    $scriptName = [System.IO.Path]::GetFileName($PS1Path)
    $bat = @"
@echo off
REM THERMOTRON 2800 - GENERATED TEST LAUNCHER
echo.
echo ================================================
echo   THERMOTRON 2800 - RUNNING TEST
echo   $scriptName
echo ================================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0$scriptName"
if %errorlevel% neq 0 (echo WARNING: Script exited with errors.) else (echo Test completed.)
echo.
pause
"@
    $bat | Out-File -FilePath $BatPath -Encoding ASCII
}

# ================================================
# BUILD THE MAIN FORM
# ================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Thermotron 2800 - Test Parameter Setup"
$form.Size            = New-Object System.Drawing.Size(520, 930)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = $clrBg
$form.ForeColor       = $clrText
$form.Font            = $fntLabel
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox     = $false

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "THERMOTRON 2800"
$lblTitle.Font      = $fntTitle
$lblTitle.ForeColor = $clrAccent
$lblTitle.Location  = New-Object System.Drawing.Point(20, 15)
$lblTitle.Size      = New-Object System.Drawing.Size(340, 28)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = "Test Parameter Configuration"
$lblSub.Font      = $fntSmall
$lblSub.ForeColor = $clrSubText
$lblSub.Location  = New-Object System.Drawing.Point(22, 44)
$lblSub.Size      = New-Object System.Drawing.Size(300, 16)
$form.Controls.Add($lblSub)

$sep1 = New-Object System.Windows.Forms.Panel
$sep1.Location  = New-Object System.Drawing.Point(20, 68)
$sep1.Size      = New-Object System.Drawing.Size(465, 2)
$sep1.BackColor = $clrAccent
$form.Controls.Add($sep1)

# ================================================
# SECTION 1: CONNECTION
# ================================================
Add-SectionHeader -Parent $form -Text "CONNECTION" -Y 80

$lblCom = New-Object System.Windows.Forms.Label
$lblCom.Text = "COM Port" ; $lblCom.Location = New-Object System.Drawing.Point(30,113)
$lblCom.Size = New-Object System.Drawing.Size(200,20) ; $lblCom.ForeColor = $clrText
$form.Controls.Add($lblCom)

$cmbCom = New-Object System.Windows.Forms.ComboBox
$cmbCom.Location = New-Object System.Drawing.Point(240,110) ; $cmbCom.Size = New-Object System.Drawing.Size(100,24)
$cmbCom.BackColor = $clrInput ; $cmbCom.ForeColor = $clrText ; $cmbCom.Font = $fntInput
$cmbCom.DropDownStyle = "DropDownList"
Get-ComPorts | ForEach-Object { $cmbCom.Items.Add($_) | Out-Null }
$com3Index = $cmbCom.Items.IndexOf("COM3")
$cmbCom.SelectedIndex = if ($com3Index -ge 0) { $com3Index } else { 0 }
$form.Controls.Add($cmbCom)

$lblScale = New-Object System.Windows.Forms.Label
$lblScale.Text = "Temperature Scale" ; $lblScale.Location = New-Object System.Drawing.Point(30,143)
$lblScale.Size = New-Object System.Drawing.Size(200,20) ; $lblScale.ForeColor = $clrText
$form.Controls.Add($lblScale)

$cmbScale = New-Object System.Windows.Forms.ComboBox
$cmbScale.Location = New-Object System.Drawing.Point(240,140) ; $cmbScale.Size = New-Object System.Drawing.Size(100,24)
$cmbScale.BackColor = $clrInput ; $cmbScale.ForeColor = $clrText ; $cmbScale.Font = $fntInput
$cmbScale.DropDownStyle = "DropDownList"
$cmbScale.Items.Add("Celsius") | Out-Null ; $cmbScale.Items.Add("Fahrenheit") | Out-Null
$cmbScale.SelectedIndex = 0
$form.Controls.Add($cmbScale)

$txtGpib = Add-InputField -Parent $form -LabelText "GPIB Address" -DefaultValue "2" -X 30 -Y 173

# ================================================
# SECTION 2: TEST PROFILE
# ================================================
Add-SectionHeader -Parent $form -Text "TEST PROFILE" -Y 210

$lblProfile = New-Object System.Windows.Forms.Label
$lblProfile.Text = "Profile Type" ; $lblProfile.Location = New-Object System.Drawing.Point(30,243)
$lblProfile.Size = New-Object System.Drawing.Size(200,20) ; $lblProfile.ForeColor = $clrText
$form.Controls.Add($lblProfile)

$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.Location = New-Object System.Drawing.Point(240,240) ; $cmbProfile.Size = New-Object System.Drawing.Size(220,24)
$cmbProfile.BackColor = $clrInput ; $cmbProfile.ForeColor = $clrText ; $cmbProfile.Font = $fntInput
$cmbProfile.DropDownStyle = "DropDownList"
$cmbProfile.Items.Add("Simple Soak")  | Out-Null
$cmbProfile.Items.Add("Ramp Cycle")   | Out-Null
$cmbProfile.Items.Add("Multi-Step")   | Out-Null
$cmbProfile.SelectedIndex = 0
$form.Controls.Add($cmbProfile)

# ================================================
# PROFILE PANELS
# ================================================
$panelY = 278 ; $panelW = 470 ; $panelH = 365

# ------ PANEL: SIMPLE SOAK ------
$pnlSoak = New-Object System.Windows.Forms.Panel
$pnlSoak.Location = New-Object System.Drawing.Point(15, $panelY)
$pnlSoak.Size     = New-Object System.Drawing.Size($panelW, $panelH)
$pnlSoak.BackColor = $clrBg ; $pnlSoak.Visible = $true
$form.Controls.Add($pnlSoak)

Add-SectionHeader -Parent $pnlSoak -Text "SOAK SETTINGS" -Y 0 -Width $panelW
$txtSoakTarget = Add-InputField -Parent $pnlSoak -LabelText "Target Temperature" -DefaultValue "25" -X 10 -Y 32

$lblSoakRange = New-Object System.Windows.Forms.Label
$lblSoakRange.Text = "  Valid range: -87 to +190 (Celsius)"
$lblSoakRange.Location = New-Object System.Drawing.Point(10,62) ; $lblSoakRange.Size = New-Object System.Drawing.Size(380,16)
$lblSoakRange.ForeColor = $clrSubText ; $lblSoakRange.Font = $fntSmall
$pnlSoak.Controls.Add($lblSoakRange)

$chkIndefinite = New-Object System.Windows.Forms.CheckBox
$chkIndefinite.Text = "Hold indefinitely (manual stop required)"
$chkIndefinite.Location = New-Object System.Drawing.Point(10,88) ; $chkIndefinite.Size = New-Object System.Drawing.Size(380,20)
$chkIndefinite.ForeColor = $clrText ; $chkIndefinite.Font = $fntLabel
$chkIndefinite.BackColor = [System.Drawing.Color]::Transparent ; $chkIndefinite.Checked = $false
$pnlSoak.Controls.Add($chkIndefinite)

$txtSoakHold = Add-InputField -Parent $pnlSoak -LabelText "Hold Duration (minutes)" -DefaultValue "60" -X 10 -Y 118

$chkIndefinite.Add_CheckedChanged({
    $txtSoakHold.Enabled   = -not $chkIndefinite.Checked
    $txtSoakHold.BackColor = if ($chkIndefinite.Checked) { [System.Drawing.Color]::FromArgb(45,45,45) } else { $clrInput }
})

# ------ PANEL: RAMP CYCLE ------
$pnlRamp = New-Object System.Windows.Forms.Panel
$pnlRamp.Location = New-Object System.Drawing.Point(15, $panelY)
$pnlRamp.Size     = New-Object System.Drawing.Size($panelW, $panelH)
$pnlRamp.BackColor = $clrBg ; $pnlRamp.Visible = $false
$form.Controls.Add($pnlRamp)

Add-SectionHeader -Parent $pnlRamp -Text "TEMPERATURE SETTINGS" -Y 0 -Width $panelW
$txtStartTemp = Add-InputField -Parent $pnlRamp -LabelText "Start Temperature"  -DefaultValue "25"  -X 10 -Y 32
$txtHighTemp  = Add-InputField -Parent $pnlRamp -LabelText "High Temperature"   -DefaultValue "85"  -X 10 -Y 65
$txtLowTemp   = Add-InputField -Parent $pnlRamp -LabelText "Low Temperature"    -DefaultValue "-40" -X 10 -Y 98

$lblRampRange = New-Object System.Windows.Forms.Label
$lblRampRange.Text = "  Valid range: -87 to +190 (Celsius)"
$lblRampRange.Location = New-Object System.Drawing.Point(10,128) ; $lblRampRange.Size = New-Object System.Drawing.Size(380,16)
$lblRampRange.ForeColor = $clrSubText ; $lblRampRange.Font = $fntSmall
$pnlRamp.Controls.Add($lblRampRange)

Add-SectionHeader -Parent $pnlRamp -Text "TIMING SETTINGS" -Y 152 -Width $panelW
$txtRampTime = Add-InputField -Parent $pnlRamp -LabelText "Ramp Time (minutes)" -DefaultValue "30" -X 10 -Y 182
$txtSoakTime = Add-InputField -Parent $pnlRamp -LabelText "Soak Time (minutes)" -DefaultValue "60" -X 10 -Y 215

Add-SectionHeader -Parent $pnlRamp -Text "CYCLE SETTINGS" -Y 252 -Width $panelW
$txtLoops = Add-InputField -Parent $pnlRamp -LabelText "Number of Cycles (1-255)" -DefaultValue "3" -X 10 -Y 282

# ------ PANEL: MULTI-STEP ------
$pnlMulti = New-Object System.Windows.Forms.Panel
$pnlMulti.Location = New-Object System.Drawing.Point(15, $panelY)
$pnlMulti.Size     = New-Object System.Drawing.Size($panelW, $panelH)
$pnlMulti.BackColor = $clrBg ; $pnlMulti.Visible = $false
$form.Controls.Add($pnlMulti)

Add-SectionHeader -Parent $pnlMulti -Text "MULTI-STEP SETTINGS" -Y 0 -Width $panelW
$txtMultiStart = Add-InputField -Parent $pnlMulti -LabelText "Start Temperature"        -DefaultValue "25" -X 10 -Y 32
$txtMultiLoops = Add-InputField -Parent $pnlMulti -LabelText "Number of Cycles (1-255)" -DefaultValue "1"  -X 10 -Y 65

# Step list column headers
foreach ($col in @(@{T="  #";X=10;W=30},@{T="Target Temp";X=45;W=110},@{T="Ramp (min)";X=160;W=100},@{T="Soak (min)";X=265;W=100})) {
    $lh = New-Object System.Windows.Forms.Label
    $lh.Text = $col.T ; $lh.Location = New-Object System.Drawing.Point($col.X, 102)
    $lh.Size = New-Object System.Drawing.Size($col.W, 18) ; $lh.ForeColor = $clrAccent ; $lh.Font = $fntSmall
    $pnlMulti.Controls.Add($lh)
}

# Scrollable step list
$lstSteps = New-Object System.Windows.Forms.Panel
$lstSteps.Location    = New-Object System.Drawing.Point(10, 122)
$lstSteps.Size        = New-Object System.Drawing.Size(440, 165)
$lstSteps.BackColor   = $clrPanel
$lstSteps.BorderStyle = "FixedSingle"
$lstSteps.AutoScroll  = $true
$pnlMulti.Controls.Add($lstSteps)

# Add step input row
Add-SectionHeader -Parent $pnlMulti -Text "ADD STEP" -Y 296 -Width $panelW
$txtNewTemp = Add-InputField -Parent $pnlMulti -LabelText "Target Temp" -DefaultValue "25"  -X 10  -Y 324 -LabelWidth 90 -InputWidth 45
$txtNewRamp = Add-InputField -Parent $pnlMulti -LabelText "Ramp"        -DefaultValue "30"  -X 160 -Y 324 -LabelWidth 40 -InputWidth 45
$txtNewSoak = Add-InputField -Parent $pnlMulti -LabelText "Soak"        -DefaultValue "60"  -X 260 -Y 324 -LabelWidth 40 -InputWidth 45

$btnAddStep = New-Object System.Windows.Forms.Button
$btnAddStep.Text = "+ ADD" ; $btnAddStep.Location = New-Object System.Drawing.Point(360, 322)
$btnAddStep.Size = New-Object System.Drawing.Size(75, 26) ; $btnAddStep.BackColor = $clrGreen
$btnAddStep.ForeColor = [System.Drawing.Color]::Black ; $btnAddStep.Font = $fntSmall
$btnAddStep.FlatStyle = "Flat" ; $btnAddStep.FlatAppearance.BorderSize = 0
$pnlMulti.Controls.Add($btnAddStep)

# ================================================
# REFRESH STEP LIST
# ================================================
function Refresh-StepList {
    $lstSteps.Controls.Clear()
    $scale = if ($cmbScale.SelectedItem -eq "Fahrenheit") { "F" } else { "C" }
    for ($i = 0; $i -lt $script:steps.Count; $i++) {
        $s = $script:steps[$i] ; $rowY = $i * 28
        $bg = if ($i % 2 -eq 0) { $clrRowA } else { $clrRowB }

        $rowPnl = New-Object System.Windows.Forms.Panel
        $rowPnl.Location = New-Object System.Drawing.Point(0, $rowY)
        $rowPnl.Size     = New-Object System.Drawing.Size(438, 26)
        $rowPnl.BackColor = $bg

        foreach ($col in @(
            @{T="  $($i+1)";   X=0;   W=35;  C=$clrSubText},
            @{T="$($s.Temp)$scale"; X=35;  W=110; C=$clrText},
            @{T="$($s.RampMin) min"; X=150; W=100; C=$clrText},
            @{T="$($s.SoakMin) min"; X=255; W=100; C=$clrText}
        )) {
            $cl = New-Object System.Windows.Forms.Label
            $cl.Text = $col.T ; $cl.Location = New-Object System.Drawing.Point($col.X, 5)
            $cl.Size = New-Object System.Drawing.Size($col.W, 18) ; $cl.ForeColor = $col.C ; $cl.Font = $fntSmall
            $rowPnl.Controls.Add($cl)
        }

        $btnRem = New-Object System.Windows.Forms.Button
        $btnRem.Text = "x" ; $btnRem.Location = New-Object System.Drawing.Point(370, 3)
        $btnRem.Size = New-Object System.Drawing.Size(22, 20) ; $btnRem.BackColor = $clrRed
        $btnRem.ForeColor = [System.Drawing.Color]::White ; $btnRem.Font = $fntSmall
        $btnRem.FlatStyle = "Flat" ; $btnRem.FlatAppearance.BorderSize = 0 ; $btnRem.Tag = $i
        $btnRem.Add_Click({ $script:steps.RemoveAt([int]$this.Tag) ; Refresh-StepList })
        $rowPnl.Controls.Add($btnRem)
        $lstSteps.Controls.Add($rowPnl)
    }
}

# ADD STEP event
$btnAddStep.Add_Click({
    $errs = @()
    if (-not ($txtNewTemp.Text -match '^-?\d+$'))                                           { $errs += "Target Temp must be a whole number." }
    elseif ([int]$txtNewTemp.Text -lt -87 -or [int]$txtNewTemp.Text -gt 190)               { $errs += "Temperature must be between -87 and 190." }
    if (-not ($txtNewRamp.Text -match '^\d+$') -or [int]$txtNewRamp.Text -lt 1)            { $errs += "Ramp time must be a positive whole number." }
    if (-not ($txtNewSoak.Text -match '^\d+$') -or [int]$txtNewSoak.Text -lt 1)            { $errs += "Soak time must be a positive whole number." }
    if ($script:steps.Count -ge 20)                                                         { $errs += "Maximum 20 steps allowed." }
    if ($errs.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(($errs -join "`n"), "Step Error",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $script:steps.Add(@{ Temp=[int]$txtNewTemp.Text; RampMin=[int]$txtNewRamp.Text; SoakMin=[int]$txtNewSoak.Text }) | Out-Null
    Refresh-StepList
    $txtNewTemp.Text = "25" ; $txtNewRamp.Text = "30" ; $txtNewSoak.Text = "60"
})

# Profile panel switch
$cmbProfile.Add_SelectedIndexChanged({
    $pnlSoak.Visible  = ($cmbProfile.SelectedIndex -eq 0)
    $pnlRamp.Visible  = ($cmbProfile.SelectedIndex -eq 1)
    $pnlMulti.Visible = ($cmbProfile.SelectedIndex -eq 2)
})

# ================================================
# STATUS, BUTTONS, CREDIT
# ================================================

# Log checkbox
$chkLog = New-Object System.Windows.Forms.CheckBox
$chkLog.Text      = "Create output log for this test"
$chkLog.Location  = New-Object System.Drawing.Point(20, 650)
$chkLog.Size      = New-Object System.Drawing.Size(280, 20)
$chkLog.ForeColor = $clrText
$chkLog.Font      = $fntLabel
$chkLog.BackColor = [System.Drawing.Color]::Transparent
$chkLog.Checked   = $false
$form.Controls.Add($chkLog)

# Poll interval field - on the same row as log checkbox
$lblPoll = New-Object System.Windows.Forms.Label
$lblPoll.Text      = "Poll interval (sec)"
$lblPoll.Location  = New-Object System.Drawing.Point(310, 653)
$lblPoll.Size      = New-Object System.Drawing.Size(125, 18)
$lblPoll.ForeColor = $clrText
$lblPoll.Font      = $fntSmall
$form.Controls.Add($lblPoll)

$txtPollInterval = New-Object System.Windows.Forms.TextBox
$txtPollInterval.Text        = "60"
$txtPollInterval.Location    = New-Object System.Drawing.Point(440, 650)
$txtPollInterval.Size        = New-Object System.Drawing.Size(50, 24)
$txtPollInterval.BackColor   = $clrInput
$txtPollInterval.ForeColor   = $clrText
$txtPollInterval.Font        = $fntInput
$txtPollInterval.BorderStyle = "FixedSingle"
$form.Controls.Add($txtPollInterval)

# Live chart checkbox - on its own row below log/poll
$chkChart = New-Object System.Windows.Forms.CheckBox
$chkChart.Text      = "Show live temperature chart during test"
$chkChart.Location  = New-Object System.Drawing.Point(20, 675)
$chkChart.Size      = New-Object System.Drawing.Size(300, 20)
$chkChart.ForeColor = $clrText
$chkChart.Font      = $fntLabel
$chkChart.BackColor = [System.Drawing.Color]::Transparent
$chkChart.Checked   = $false
$form.Controls.Add($chkChart)

# Log path display label
$lblLogPath = New-Object System.Windows.Forms.Label
$lblLogPath.Text      = "  No log folder selected"
$lblLogPath.Location  = New-Object System.Drawing.Point(20, 698)
$lblLogPath.Size      = New-Object System.Drawing.Size(465, 16)
$lblLogPath.ForeColor = $clrSubText
$lblLogPath.Font      = $fntSmall
$lblLogPath.Visible   = $false
$form.Controls.Add($lblLogPath)

$script:logFolder  = $null
$script:dataFile   = $null

$chkLog.Add_CheckedChanged({
    $lblLogPath.Visible = $chkLog.Checked
    if ($chkLog.Checked) {
        $logFolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $logFolderDialog.Description  = "Select folder to save the test log file"
        $logFolderDialog.SelectedPath = [Environment]::GetFolderPath("Desktop")
        if ($logFolderDialog.ShowDialog() -eq "OK") {
            $script:logFolder     = $logFolderDialog.SelectedPath
            $lblLogPath.Text      = "  Log folder: $($script:logFolder)"
            $lblLogPath.ForeColor = $clrGreen
        } else {
            $chkLog.Checked      = $false
            $lblLogPath.Visible  = $false
            $script:logFolder    = $null
        }
    } else {
        $script:logFolder     = $null
        $lblLogPath.Text      = "  No log folder selected"
        $lblLogPath.ForeColor = $clrSubText
    }
})

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = ""
$lblStatus.Location  = New-Object System.Drawing.Point(20, 720)
$lblStatus.Size      = New-Object System.Drawing.Size(465, 48)
$lblStatus.ForeColor = $clrGreen
$lblStatus.Font      = $fntSmall
$lblStatus.AutoSize  = $false
$form.Controls.Add($lblStatus)

$btnGenerate = New-Object System.Windows.Forms.Button
$btnGenerate.Text = "RUN TEST" ; $btnGenerate.Location = New-Object System.Drawing.Point(20, 775)
$btnGenerate.Size = New-Object System.Drawing.Size(200,36) ; $btnGenerate.BackColor = $clrAccent
$btnGenerate.ForeColor = [System.Drawing.Color]::Black ; $btnGenerate.Font = $fntButton
$btnGenerate.FlatStyle = "Flat" ; $btnGenerate.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnGenerate)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "STOP TEST" ; $btnStop.Location = New-Object System.Drawing.Point(20, 820)
$btnStop.Size = New-Object System.Drawing.Size(200,36) ; $btnStop.BackColor = $clrRed
$btnStop.ForeColor = [System.Drawing.Color]::White ; $btnStop.Font = $fntButton
$btnStop.FlatStyle = "Flat" ; $btnStop.FlatAppearance.BorderSize = 0 ; $btnStop.Enabled = $false
$form.Controls.Add($btnStop)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "CLOSE" ; $btnCancel.Location = New-Object System.Drawing.Point(265, 775)
$btnCancel.Size = New-Object System.Drawing.Size(200,80) ; $btnCancel.BackColor = $clrPanel
$btnCancel.ForeColor = $clrSubText ; $btnCancel.Font = $fntButton
$btnCancel.FlatStyle = "Flat" ; $btnCancel.FlatAppearance.BorderColor = $clrBorder
$btnCancel.FlatAppearance.BorderSize = 1
$form.Controls.Add($btnCancel)

$btnCancel.Add_Click({ $form.Close() })

# ================================================
# RUN TEST EVENT
# ================================================
$btnGenerate.Add_Click({
    $scale   = if ($cmbScale.SelectedItem -eq "Fahrenheit") { "F" } else { "C" }
    $profile = $cmbProfile.SelectedIndex
    $errors  = @()

    if (-not ($txtGpib.Text -match '^\d+$') -or [int]$txtGpib.Text -lt 0 -or [int]$txtGpib.Text -gt 30) {
        $errors += "GPIB Address must be between 0 and 30." }
    if (-not ($txtPollInterval.Text -match '^\d+$') -or [int]$txtPollInterval.Text -lt 5) {
        $errors += "Poll interval must be a whole number of 5 seconds or more." }

    if ($profile -eq 0) {
        if (-not ($txtSoakTarget.Text -match '^-?\d+$'))                                        { $errors += "Target Temperature must be a whole number." }
        elseif ([int]$txtSoakTarget.Text -lt -87 -or [int]$txtSoakTarget.Text -gt 190)         { $errors += "Target Temperature must be between -87 and 190." }
        if (-not $chkIndefinite.Checked -and (-not ($txtSoakHold.Text -match '^\d+$') -or [int]$txtSoakHold.Text -lt 1)) {
            $errors += "Hold Duration must be a positive whole number." }
    } elseif ($profile -eq 1) {
        foreach ($f in @($txtStartTemp,$txtHighTemp,$txtLowTemp)) {
            if (-not ($f.Text -match '^-?\d+$')) { $errors += "$($f.Name) must be a whole number." } }
        if (-not ($txtRampTime.Text -match '^\d+$') -or [int]$txtRampTime.Text -lt 1) { $errors += "Ramp Time must be a positive whole number." }
        if (-not ($txtSoakTime.Text -match '^\d+$') -or [int]$txtSoakTime.Text -lt 1) { $errors += "Soak Time must be a positive whole number." }
        if (-not ($txtLoops.Text -match '^\d+$') -or [int]$txtLoops.Text -lt 1 -or [int]$txtLoops.Text -gt 255) { $errors += "Cycles must be between 1 and 255." }
        if ($errors.Count -eq 0 -and [int]$txtHighTemp.Text -le [int]$txtLowTemp.Text) { $errors += "High Temperature must be greater than Low Temperature." }
    } elseif ($profile -eq 2) {
        if ($script:steps.Count -lt 1)                                                          { $errors += "Please add at least one step." }
        if (-not ($txtMultiStart.Text -match '^-?\d+$'))                                        { $errors += "Start Temperature must be a whole number." }
        if (-not ($txtMultiLoops.Text -match '^\d+$') -or [int]$txtMultiLoops.Text -lt 1 -or [int]$txtMultiLoops.Text -gt 255) {
            $errors += "Cycles must be between 1 and 255." }
    }

    if ($errors.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show("Please fix the following:`n`n" + ($errors -join "`n"),
            "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will generate and immediately launch the test.`n`nProceed?",
        "Confirm Test Start", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne "Yes") { return }

    # Save generated files to the same folder as this GUI script
    $outputFolder = $PSScriptRoot
    $timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
    $ps1Path      = Join-Path $outputFolder "thermotron2800_test_$timestamp.ps1"
    $batPath      = Join-Path $outputFolder "thermotron2800_test_$timestamp.bat"

    try {
        # Pre-compute all conditional values into clean variables
        $logPath      = if ($chkLog.Checked -and $script:logFolder) { $script:logFolder } else { "" }
        $pollSeconds  = [int]$txtPollInterval.Text
        $gpibAddress  = [int]$txtGpib.Text
        $holdMins     = if ($chkIndefinite.Checked) { 0 } else { [int]$txtSoakHold.Text }
        $chartDataPath = if ($chkChart.Checked) {
            Join-Path $outputFolder "thermotron2800_chartdata_$timestamp.csv"
        } else { "" }
        $script:dataFile = $chartDataPath

        if ($profile -eq 0) {
            Generate-SoakScript `
                -ComPort       $cmbCom.SelectedItem `
                -GpibAddress   $gpibAddress `
                -TargetTemp    ([int]$txtSoakTarget.Text) `
                -HoldMinutes   $holdMins `
                -Indefinite    $chkIndefinite.Checked `
                -TempScale     $scale `
                -OutputPath    $ps1Path `
                -LogPath       $logPath `
                -PollSeconds   $pollSeconds `
                -ChartDataFile $chartDataPath

        } elseif ($profile -eq 1) {
            Generate-RampScript `
                -ComPort       $cmbCom.SelectedItem `
                -GpibAddress   $gpibAddress `
                -StartTemp     ([int]$txtStartTemp.Text) `
                -HighTemp      ([int]$txtHighTemp.Text) `
                -LowTemp       ([int]$txtLowTemp.Text) `
                -RampMinutes   ([int]$txtRampTime.Text) `
                -SoakMinutes   ([int]$txtSoakTime.Text) `
                -LoopCount     ([int]$txtLoops.Text) `
                -TempScale     $scale `
                -OutputPath    $ps1Path `
                -LogPath       $logPath `
                -PollSeconds   $pollSeconds `
                -ChartDataFile $chartDataPath

        } elseif ($profile -eq 2) {
            Generate-MultiStepScript `
                -ComPort       $cmbCom.SelectedItem `
                -GpibAddress   $gpibAddress `
                -StartTemp     ([int]$txtMultiStart.Text) `
                -Steps         $script:steps.ToArray() `
                -LoopCount     ([int]$txtMultiLoops.Text) `
                -TempScale     $scale `
                -OutputPath    $ps1Path `
                -LogPath       $logPath `
                -PollSeconds   $pollSeconds `
                -ChartDataFile $chartDataPath
        }

        Generate-BatchFile -PS1Path $ps1Path -BatPath $batPath
        $lblStatus.Text = "  Files saved. Launching test..." ; $lblStatus.ForeColor = $clrGreen

        $script:testProcess  = Start-Process -FilePath $batPath -WorkingDirectory $outputFolder -PassThru
        $script:testComPort  = $cmbCom.SelectedItem
        $script:testGpibAddr = ([int]$txtGpib.Text)

        $btnGenerate.Enabled = $false ; $btnGenerate.BackColor = [System.Drawing.Color]::FromArgb(100,100,100)
        $btnStop.Enabled = $true
        $lblStatus.Text = "  Test running (PID: $($script:testProcess.Id))..." ; $lblStatus.ForeColor = $clrGreen

        # Launch chart window if checkbox is checked
        if ($chkChart.Checked -and $chartDataPath -ne "") {
            $chartScript  = Join-Path $PSScriptRoot "thermotron2800_chart.ps1"
            $chartBatPath = Join-Path $PSScriptRoot "thermotron2800_chart_launch.bat"
            $diagFile     = Join-Path $PSScriptRoot "thermotron2800_chart_diag.txt"

            # Write diagnostic log so we can see exactly what paths are being used
            $diagLines = @(
                "=== CHART LAUNCH DIAGNOSTIC ==="
                "Time:         $(Get-Date)"
                "PSScriptRoot: $PSScriptRoot"
                "ChartScript:  $chartScript"
                "ChartBat:     $chartBatPath"
                "DataFile:     $chartDataPath"
                "TempScale:    $scale"
                "ChartExists:  $(Test-Path $chartScript)"
                "DataExists:   $(Test-Path $chartDataPath)"
            )
            $diagLines | Out-File -FilePath $diagFile -Encoding ASCII -Force

            if (Test-Path $chartScript) {
                try {
                    # Write the batch launcher
                    $line1 = "@echo off"
                    $line2 = "echo Launching chart..."
                    $line3 = "powershell.exe -ExecutionPolicy Bypass -File `"$chartScript`" -DataFile `"$chartDataPath`" -TempScale $scale"
                    $line4 = "if %errorlevel% neq 0 pause"
                    ($line1,$line2,$line3,$line4) -join "`r`n" |
                        Out-File -FilePath $chartBatPath -Encoding ASCII -Force

                    Add-Content -Path $diagFile -Value "BatchContent written OK"

                    #$proc = Start-Process -FilePath $chartBatPath -PassThru Old Line
                    Start-Process -FilePath $chartBatPath -WindowStyle Hidden
                    Add-Content -Path $diagFile -Value "Start-Process called. PID: $($proc.Id)"

                    $lblStatus.Text      = "  Test running - chart launching (PID: $($proc.Id))..."
                    $lblStatus.ForeColor = $clrGreen
                } catch {
                    Add-Content -Path $diagFile -Value "ERROR: $_"
                    $lblStatus.Text      = "  WARNING: Chart launch error - see chart_diag.txt"
                    $lblStatus.ForeColor = $clrRed
                }
            } else {
                Add-Content -Path $diagFile -Value "ERROR: Chart script not found at path above"
                $lblStatus.Text      = "  WARNING: thermotron2800_chart.ps1 not found - see chart_diag.txt"
                $lblStatus.ForeColor = $clrRed
            }
        }

        [System.Windows.Forms.MessageBox]::Show(
            "Test started!`n`nGenerated files saved to:`n$outputFolder`n`nUse STOP TEST to safely halt at any time.",
            "Test Launched", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

        $timer = New-Object System.Windows.Forms.Timer ; $timer.Interval = 3000
        $timer.Add_Tick({
            if ($script:testProcess -ne $null -and $script:testProcess.HasExited) {
                $btnGenerate.Enabled = $true ; $btnGenerate.BackColor = $clrAccent
                $btnStop.Enabled = $false ; $btnStop.BackColor = [System.Drawing.Color]::FromArgb(100,60,60)
                $lblStatus.Text = "  Test finished (exit code: $($script:testProcess.ExitCode))."
                $lblStatus.ForeColor = $clrSubText ; $script:testProcess = $null ; $timer.Stop()
                # Write end marker to chart data file
                if ($script:dataFile -ne $null -and (Test-Path $script:dataFile)) {
                    $endStr  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    $elapsed = ""
                    try {
                        $firstLine = (Get-Content $script:dataFile -TotalCount 2)[1]
                        $startStr  = $firstLine.Split(",")[0]
                        $elapsed   = [math]::Round(((Get-Date) - [datetime]$startStr).TotalSeconds, 0)
                    } catch { }
                    # Build end marker row as variable to avoid
                    # PowerShell misinterpreting the commas as syntax
                    $endRow = $endStr + "," + $elapsed + ",,,end:" + $endStr
                    $endRow | Add-Content -Path $script:dataFile
                }
            }
        })
        $timer.Start()

    } catch {
        $lblStatus.Text = "  ERROR: $_" ; $lblStatus.ForeColor = $clrRed
        [System.Windows.Forms.MessageBox]::Show("Error launching test:`n`n$_", "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ================================================
# STOP TEST EVENT
# ================================================
$btnStop.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Stop the test?`n`nThis will signal the running script to send a`nSTOP command to the controller and exit cleanly.",
        "Confirm Stop", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne "Yes") { return }

    $lblStatus.Text      = "  Stop signal sent - waiting for script to halt controller..." 
    $lblStatus.ForeColor = $clrRed

    # Write the stop flag file to the same folder as the GUI
    # The running test script checks for this file on every poll
    # and sends S to the controller then exits cleanly when found
    $stopFlagPath = Join-Path $PSScriptRoot "thermotron2800_stop.flag"
    try {
        "STOP" | Out-File -FilePath $stopFlagPath -Encoding ASCII -Force
        $lblStatus.Text = "  Stop flag written - controller will halt at next poll interval..."
    } catch {
        $lblStatus.Text = "  WARNING: Could not write stop flag - force killing process..."
        $lblStatus.ForeColor = $clrRed
    }

    # Wait up to 15 seconds for the script to stop cleanly on its own
    $waited = 0
    while ($waited -lt 15) {
        Start-Sleep -Seconds 1
        $waited++
        if ($script:testProcess -eq $null -or $script:testProcess.HasExited) { break }
        [System.Windows.Forms.Application]::DoEvents()
    }

    # If still running after 15 seconds, force kill as fallback
    if ($script:testProcess -ne $null -and -not $script:testProcess.HasExited) {
        try {
            Get-WmiObject Win32_Process | Where-Object { $_.ParentProcessId -eq $script:testProcess.Id } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Stop-Process -Id $script:testProcess.Id -Force -ErrorAction SilentlyContinue
            $lblStatus.Text = "  Script force-stopped after timeout. Check controller state manually."
        } catch { }
    }

    # Clean up flag file if still present
    if (Test-Path $stopFlagPath) {
        Remove-Item $stopFlagPath -Force -ErrorAction SilentlyContinue
    }

    $script:testProcess  = $null
    $script:testComPort  = $null
    $btnGenerate.Enabled = $true
    $btnGenerate.BackColor = $clrAccent
    $btnStop.Enabled     = $false
    $btnStop.BackColor   = [System.Drawing.Color]::FromArgb(100,60,60)
    $lblStatus.Text      = "  Test stopped by user."
    $lblStatus.ForeColor = $clrRed

    [System.Windows.Forms.MessageBox]::Show(
        "Test stopped.`n`nThe controller has been sent a STOP command via the running script.",
        "Test Stopped", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

# ================================================
# CREDIT LABEL
# ================================================
$lblCredit = New-Object System.Windows.Forms.Label
$lblCredit.Text      = "Created by Chris Herkey with Claude"
$lblCredit.Font      = $fntSmall
$lblCredit.ForeColor = $clrSubText
$lblCredit.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblCredit.Location  = New-Object System.Drawing.Point(20, 870)
$lblCredit.Size      = New-Object System.Drawing.Size(465, 16)
$form.Controls.Add($lblCredit)

# ================================================
# STARTUP CLEANUP CHECK
# Runs when the GUI first opens. Counts generated
# test files (.ps1 and .bat with thermotron2800_test
# prefix) in the GUI folder and offers to clean up
# if more than 10 are found.
# ================================================
function Invoke-StartupCleanup {
    $testFiles = @(Get-ChildItem -Path $PSScriptRoot -File |
        Where-Object { $_.Name -match '^thermotron2800_(test_|chartdata_).*\.(ps1|bat|csv)$' })

    $fileCount = $testFiles.Count
    if ($fileCount -le 10) { return }

    # Build a summary of what was found
    $oldest = ($testFiles | Sort-Object CreationTime | Select-Object -First 1).CreationTime.ToString("yyyy-MM-dd")
    $newest = ($testFiles | Sort-Object CreationTime | Select-Object -Last 1).CreationTime.ToString("yyyy-MM-dd")

    $result = [System.Windows.Forms.MessageBox]::Show(
        "Cleanup Recommended`n`n$fileCount generated test files were found in:`n$PSScriptRoot`n`nOldest: $oldest`nNewest: $newest`n`nWould you like to review and clean up old files?",
        "Startup Cleanup Check",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information)

    if ($result -ne "Yes") { return }

    # Build cleanup dialog form
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Clean Up Generated Test Files"
    $dlg.Size            = New-Object System.Drawing.Size(560, 480)
    $dlg.StartPosition   = "CenterScreen"
    $dlg.BackColor       = $clrBg
    $dlg.ForeColor       = $clrText
    $dlg.Font            = $fntLabel
    $dlg.FormBorderStyle = "FixedSingle"
    $dlg.MaximizeBox     = $false

    $lblDlgTitle = New-Object System.Windows.Forms.Label
    $lblDlgTitle.Text      = "Select files to delete"
    $lblDlgTitle.Font      = $fntBold
    $lblDlgTitle.ForeColor = $clrAccent
    $lblDlgTitle.Location  = New-Object System.Drawing.Point(15, 15)
    $lblDlgTitle.Size      = New-Object System.Drawing.Size(400, 20)
    $dlg.Controls.Add($lblDlgTitle)

    $lblDlgSub = New-Object System.Windows.Forms.Label
    $lblDlgSub.Text      = "  $fileCount files found in: $PSScriptRoot"
    $lblDlgSub.Font      = $fntSmall
    $lblDlgSub.ForeColor = $clrSubText
    $lblDlgSub.Location  = New-Object System.Drawing.Point(15, 38)
    $lblDlgSub.Size      = New-Object System.Drawing.Size(520, 16)
    $dlg.Controls.Add($lblDlgSub)

    # Checked list box of files
    $chkList = New-Object System.Windows.Forms.CheckedListBox
    $chkList.Location      = New-Object System.Drawing.Point(15, 60)
    $chkList.Size          = New-Object System.Drawing.Size(520, 310)
    $chkList.BackColor     = $clrInput
    $chkList.ForeColor     = $clrText
    $chkList.Font          = $fntSmall
    $chkList.CheckOnClick  = $true
    $chkList.BorderStyle   = "FixedSingle"

    # Add files sorted oldest first - pre-check all but the 5 newest
    $sortedFiles = $testFiles | Sort-Object CreationTime
    foreach ($f in $sortedFiles) {
        $age  = [math]::Round(((Get-Date) - $f.CreationTime).TotalDays, 0)
        $size = [math]::Round($f.Length / 1KB, 1)
        $chkList.Items.Add("$($f.Name)  [$age days old | $size KB]") | Out-Null
    }
    # Pre-check everything except the 5 most recent .ps1 files
    $recentPs1 = ($sortedFiles | Where-Object { $_.Extension -eq ".ps1" } |
        Sort-Object CreationTime | Select-Object -Last 5).Name
    for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
        $fileName = $chkList.Items[$i].ToString().Split(" ")[0]
        $chkList.SetItemChecked($i, ($recentPs1 -notcontains $fileName))
    }
    $dlg.Controls.Add($chkList)

    # Select All / Select None buttons
    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "Select All" ; $btnAll.Location = New-Object System.Drawing.Point(15, 378)
    $btnAll.Size = New-Object System.Drawing.Size(90, 26) ; $btnAll.BackColor = $clrPanel
    $btnAll.ForeColor = $clrSubText ; $btnAll.Font = $fntSmall
    $btnAll.FlatStyle = "Flat" ; $btnAll.FlatAppearance.BorderColor = $clrBorder
    $btnAll.FlatAppearance.BorderSize = 1
    $btnAll.Add_Click({
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) { $chkList.SetItemChecked($i, $true) }
    })
    $dlg.Controls.Add($btnAll)

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = "Select None" ; $btnNone.Location = New-Object System.Drawing.Point(115, 378)
    $btnNone.Size = New-Object System.Drawing.Size(90, 26) ; $btnNone.BackColor = $clrPanel
    $btnNone.ForeColor = $clrSubText ; $btnNone.Font = $fntSmall
    $btnNone.FlatStyle = "Flat" ; $btnNone.FlatAppearance.BorderColor = $clrBorder
    $btnNone.FlatAppearance.BorderSize = 1
    $btnNone.Add_Click({
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) { $chkList.SetItemChecked($i, $false) }
    })
    $dlg.Controls.Add($btnNone)

    # Delete selected / Cancel buttons
    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "DELETE SELECTED" ; $btnDelete.Location = New-Object System.Drawing.Point(295, 375)
    $btnDelete.Size = New-Object System.Drawing.Size(155, 32) ; $btnDelete.BackColor = $clrRed
    $btnDelete.ForeColor = [System.Drawing.Color]::White ; $btnDelete.Font = $fntButton
    $btnDelete.FlatStyle = "Flat" ; $btnDelete.FlatAppearance.BorderSize = 0
    $dlg.Controls.Add($btnDelete)

    $btnSkip = New-Object System.Windows.Forms.Button
    $btnSkip.Text = "SKIP" ; $btnSkip.Location = New-Object System.Drawing.Point(460, 375)
    $btnSkip.Size = New-Object System.Drawing.Size(75, 32) ; $btnSkip.BackColor = $clrPanel
    $btnSkip.ForeColor = $clrSubText ; $btnSkip.Font = $fntButton
    $btnSkip.FlatStyle = "Flat" ; $btnSkip.FlatAppearance.BorderColor = $clrBorder
    $btnSkip.FlatAppearance.BorderSize = 1
    $btnSkip.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnSkip)

    # Status label inside dialog
    $lblDlgStatus = New-Object System.Windows.Forms.Label
    $lblDlgStatus.Text      = ""
    $lblDlgStatus.Location  = New-Object System.Drawing.Point(15, 415)
    $lblDlgStatus.Size      = New-Object System.Drawing.Size(520, 18)
    $lblDlgStatus.ForeColor = $clrGreen
    $lblDlgStatus.Font      = $fntSmall
    $dlg.Controls.Add($lblDlgStatus)

    $btnDelete.Add_Click({
        $checkedItems = $chkList.CheckedItems
        if ($checkedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No files selected.", "Nothing to Delete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Delete $($checkedItems.Count) selected file(s)?`n`nThis cannot be undone.",
            "Confirm Delete",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne "Yes") { return }

        $deleted = 0 ; $failed = 0
        foreach ($item in @($checkedItems)) {
            $fileName = $item.ToString().Split(" ")[0]
            $filePath = Join-Path $PSScriptRoot $fileName
            try {
                Remove-Item $filePath -Force
                $deleted++
            } catch {
                $failed++
            }
        }

        $lblDlgStatus.Text      = "  Deleted $deleted file(s)$(if ($failed -gt 0) { " | $failed failed" })."
        $lblDlgStatus.ForeColor = if ($failed -gt 0) { $clrRed } else { $clrGreen }

        # Refresh the list
        $chkList.Items.Clear()
        $remaining = @(Get-ChildItem -Path $PSScriptRoot -File |
            Where-Object { $_.Name -match '^thermotron2800_test_.*\.(ps1|bat)$' } |
            Sort-Object CreationTime)
        foreach ($f in $remaining) {
            $age  = [math]::Round(((Get-Date) - $f.CreationTime).TotalDays, 0)
            $size = [math]::Round($f.Length / 1KB, 1)
            $chkList.Items.Add("$($f.Name)  [$age days old | $size KB]") | Out-Null
        }
        if ($remaining.Count -eq 0) {
            $lblDlgStatus.Text = "  All generated test files removed."
            Start-Sleep -Milliseconds 800
            $dlg.Close()
        }
    })

    $dlg.ShowDialog() | Out-Null
}

# ================================================
# SHOW FORM
# ================================================
$form.Add_Shown({
    $form.Activate()
    # Run cleanup check after form is visible
    Invoke-StartupCleanup
})
[System.Windows.Forms.Application]::Run($form)
