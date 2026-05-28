# ================================================
# THERMOTRON 2800 - LIVE TEMPERATURE CHART
# Standalone chart window launched by the GUI
# when "Show live temperature chart" is checked
# ================================================
# Parameters:
#   -DataFile   : path to the CSV data file
#   -TempScale  : "C" or "F"
# ================================================

param(
    [string]$DataFile = "",
    [string]$TempScale = "C"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================================================
# COLORS & FONTS
# ================================================
$clrBg        = [System.Drawing.Color]::FromArgb(25, 25, 25)
$clrPanel     = [System.Drawing.Color]::FromArgb(40, 40, 40)
$clrAccent    = [System.Drawing.Color]::FromArgb(255, 140, 0)
$clrText      = [System.Drawing.Color]::FromArgb(230, 230, 230)
$clrSubText   = [System.Drawing.Color]::FromArgb(140, 140, 140)
$clrGrid      = [System.Drawing.Color]::FromArgb(55, 55, 55)
$clrTempLine  = [System.Drawing.Color]::FromArgb(80, 160, 255)
$clrSetptLine = [System.Drawing.Color]::FromArgb(255, 140, 0)
$clrMarker    = [System.Drawing.Color]::FromArgb(100, 100, 100)
$clrInput     = [System.Drawing.Color]::FromArgb(55, 55, 55)
$clrGreen     = [System.Drawing.Color]::FromArgb(80, 200, 120)
$clrRed       = [System.Drawing.Color]::FromArgb(220, 80, 80)

$fntTitle     = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$fntLabel     = New-Object System.Drawing.Font("Consolas", 8,  [System.Drawing.FontStyle]::Regular)
$fntSmall     = New-Object System.Drawing.Font("Consolas", 7,  [System.Drawing.FontStyle]::Regular)
$fntBold      = New-Object System.Drawing.Font("Consolas", 8,  [System.Drawing.FontStyle]::Bold)
$fntButton    = New-Object System.Drawing.Font("Consolas", 9,  [System.Drawing.FontStyle]::Bold)

# ================================================
# DATA STORAGE
# ================================================
$script:dataPoints    = [System.Collections.ArrayList]@()
$script:testStart     = $null
$script:testEnd       = $null
$script:lastFilePos   = 0
$script:isRunning     = $true
$script:scrollOffset  = 0
$script:viewSeconds   = 3600
$script:autoScroll    = $true
$script:waited        = 0
# Incrementally tracked Y range — avoids full scan every redraw
$script:yMin          = [double]::MaxValue
$script:yMax          = [double]::MinValue

# Pre-allocated reusable brushes — created once, never leaked
# Disposed when the form closes
$script:brushBg       = New-Object System.Drawing.SolidBrush($clrBg)
$script:brushPanel    = New-Object System.Drawing.SolidBrush($clrPanel)
$script:brushText     = New-Object System.Drawing.SolidBrush($clrText)
$script:brushSubText  = New-Object System.Drawing.SolidBrush($clrSubText)
$script:brushMarker   = New-Object System.Drawing.SolidBrush($clrMarker)
$script:brushTemp     = New-Object System.Drawing.SolidBrush($clrTempLine)

# ================================================
# READ DATA FILE
# Only reads NEW lines since the last call by
# seeking to the last known byte position.
# For long tests this stays fast and memory-light
# regardless of how large the CSV has grown.
# ================================================
function Read-DataFile {
    if (-not (Test-Path $DataFile)) { return $false }
    $updated = $false
    try {
        $stream = [System.IO.File]::Open(
            $DataFile,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite)   # Share allows test script to keep writing

        # Seek to where we left off last time
        if ($script:lastFilePos -gt 0 -and $script:lastFilePos -le $stream.Length) {
            $stream.Seek($script:lastFilePos, [System.IO.SeekOrigin]::Begin) | Out-Null
        }

        $reader = New-Object System.IO.StreamReader($stream)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine().Trim()
            if ($line -eq "" -or $line.StartsWith("timestamp")) { continue }
            $parts = $line.Split(",")
            if ($parts.Count -lt 5) { continue }

            $elapsed  = 0 ; $setpoint = $null ; $temp = $null ; $event = ""
            try { $elapsed  = [int]$parts[1] }    catch { }
            try { $setpoint = [double]$parts[2] } catch { }
            try { $temp     = [double]$parts[3] } catch { }
            $event = if ($parts.Count -gt 4) { $parts[4].Trim() } else { "" }

            if ($event -match '^start:(.+)$') {
                try { $script:testStart = [datetime]$Matches[1] } catch { }
            }
            if ($event -match '^end:') {
                $script:isRunning = $false
                $script:testEnd   = Get-Date
            }

            if ($temp -ne $null -or $event -ne "") {
                $script:dataPoints.Add(@{
                    Elapsed  = $elapsed
                    Setpoint = $setpoint
                    Temp     = $temp
                    Event    = $event
                }) | Out-Null
                # Update Y range incrementally — no full scan needed on redraw
                if ($temp -ne $null) {
                    if ($temp -lt $script:yMin) { $script:yMin = $temp }
                    if ($temp -gt $script:yMax) { $script:yMax = $temp }
                }
                if ($setpoint -ne $null) {
                    if ($setpoint -lt $script:yMin) { $script:yMin = $setpoint }
                    if ($setpoint -gt $script:yMax) { $script:yMax = $setpoint }
                }
                $updated = $true
            }
        }

        # Save the current position so next call starts here
        $script:lastFilePos = $stream.Position
        $reader.Close()
        $stream.Close()
    } catch {
        # File may be locked briefly by the test script - skip this tick
    }
    return $updated
}

# ================================================
# CHART DRAWING
# ================================================
function Draw-Chart {
    param([System.Windows.Forms.PaintEventArgs]$e)

    $g   = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $w   = $chartPanel.Width
    $h   = $chartPanel.Height

    # Margins
    $ml = 60 ; $mr = 20 ; $mt = 30 ; $mb = 50
    $cw = $w - $ml - $mr
    $ch = $h - $mt - $mb

    # Background — use pre-allocated brushes (no GDI leak)
    $g.FillRectangle($script:brushBg, 0, 0, $w, $h)
    $g.FillRectangle($script:brushPanel, $ml, $mt, $cw, $ch)

    if ($script:dataPoints.Count -eq 0) {
        $msg = "Waiting for data..."
        $sz  = $g.MeasureString($msg, $fntLabel)
        $g.DrawString($msg, $fntLabel, $script:brushSubText,
            ($ml + ($cw - $sz.Width) / 2), ($mt + ($ch - $sz.Height) / 2))
        return
    }

    # Use incrementally tracked Y range — no full data scan needed
    if ($script:yMin -eq [double]::MaxValue) {
        $g.DrawString("No data yet...", $fntLabel, $script:brushSubText, ($ml + 10), ($mt + 10))
        return
    }
    $minY   = [math]::Floor($script:yMin / 10) * 10 - 10
    $maxY   = [math]::Ceiling($script:yMax / 10) * 10 + 10
    $rangeY = $maxY - $minY
    if ($rangeY -eq 0) { $rangeY = 20 ; $minY -= 10 ; $maxY += 10 }

    # X range
    $maxElapsed = ($script:dataPoints | ForEach-Object { $_.Elapsed } | Measure-Object -Maximum).Maximum
    if ($maxElapsed -eq $null -or $maxElapsed -eq 0) { $maxElapsed = 60 }

    if ($script:autoScroll) {
        $script:scrollOffset = [math]::Max(0, $maxElapsed - $script:viewSeconds)
    }
    $xStart = $script:scrollOffset
    $xEnd   = $xStart + $script:viewSeconds

    function ToScreenX { param($elapsed)
        return $ml + [int](($elapsed - $xStart) / $script:viewSeconds * $cw) }
    function ToScreenY { param($val)
        return $mt + [int](($maxY - $val) / $rangeY * $ch) }

    # Grid lines and Y axis labels
    $gridPen = New-Object System.Drawing.Pen($clrGrid, 1)
    $gridPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
    $ySteps = 5
    for ($yi = 0; $yi -le $ySteps; $yi++) {
        $yVal = $minY + ($rangeY / $ySteps * $yi)
        $sy   = ToScreenY $yVal
        if ($sy -ge $mt -and $sy -le ($mt + $ch)) {
            $g.DrawLine($gridPen, $ml, $sy, ($ml + $cw), $sy)
            $g.DrawString("$([math]::Round($yVal,0)) $TempScale", $fntSmall,
                $script:brushSubText, 2, ($sy - 8))
        }
    }

    # X axis time labels
    $xLabelCount = 6
    for ($xi = 0; $xi -le $xLabelCount; $xi++) {
        $xElapsed = $xStart + ($script:viewSeconds / $xLabelCount * $xi)
        $sx = ToScreenX $xElapsed
        if ($sx -ge $ml -and $sx -le ($ml + $cw)) {
            $g.DrawLine($gridPen, $sx, $mt, $sx, ($mt + $ch))
            $mins  = [math]::Floor($xElapsed / 60)
            $secs  = [math]::Floor($xElapsed % 60)
            $label = ([string]$mins).PadLeft(2,'0') + ":" + ([string]$secs).PadLeft(2,'0')
            $sz = $g.MeasureString($label, $fntSmall)
            $g.DrawString($label, $fntSmall, $script:brushSubText,
                ($sx - $sz.Width / 2), ($mt + $ch + 5))
        }
    }
    $gridPen.Dispose()

    # Clip to chart area
    $g.SetClip([System.Drawing.Rectangle]::new($ml, $mt, $cw, $ch))

    # Step markers — only iterate visible range
    $markerPen = New-Object System.Drawing.Pen($clrMarker, 1)
    $markerPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    foreach ($pt in $script:dataPoints) {
        if ($pt.Elapsed -lt $xStart -or $pt.Elapsed -gt $xEnd) { continue }
        if ($pt.Event -match '^setpoint:(.+)$') {
            $sx = ToScreenX $pt.Elapsed
            $g.DrawLine($markerPen, $sx, $mt, $sx, ($mt + $ch))
            $g.DrawString("->$($Matches[1]) $TempScale", $fntSmall,
                $script:brushMarker, ($sx + 2), ($mt + 4))
        }
    }
    $markerPen.Dispose()

    # Build point arrays — visible range only, not all data
    $spPoints  = [System.Collections.ArrayList]@()
    $tmpPoints = [System.Collections.ArrayList]@()

    # Include one point before xStart for line continuity at left edge
    $prevSp = $null ; $prevTmp = $null
    foreach ($pt in $script:dataPoints) {
        if ($pt.Elapsed -lt $xStart) {
            if ($pt.Setpoint -ne $null) { $prevSp  = $pt }
            if ($pt.Temp     -ne $null) { $prevTmp = $pt }
        } else { break }
    }
    if ($prevSp -ne $null) {
        $spPoints.Add([System.Drawing.PointF]::new(
            (ToScreenX $xStart), (ToScreenY $prevSp.Setpoint))) | Out-Null
    }
    if ($prevTmp -ne $null) {
        $tmpPoints.Add([System.Drawing.PointF]::new(
            (ToScreenX $xStart), (ToScreenY $prevTmp.Temp))) | Out-Null
    }

    foreach ($pt in $script:dataPoints) {
        if ($pt.Elapsed -lt $xStart -or $pt.Elapsed -gt $xEnd) { continue }
        $sx = ToScreenX $pt.Elapsed
        if ($pt.Setpoint -ne $null) {
            $spPoints.Add([System.Drawing.PointF]::new($sx, (ToScreenY $pt.Setpoint))) | Out-Null
        }
        if ($pt.Temp -ne $null) {
            $tmpPoints.Add([System.Drawing.PointF]::new($sx, (ToScreenY $pt.Temp))) | Out-Null
        }
    }

    # Draw setpoint line (orange dashed)
    if ($spPoints.Count -gt 1) {
        $spPen = New-Object System.Drawing.Pen($clrSetptLine, 2)
        $spPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $g.DrawLines($spPen, $spPoints.ToArray([System.Drawing.PointF]))
        $spPen.Dispose()
    }

    # Draw temperature line (blue solid)
    if ($tmpPoints.Count -gt 1) {
        $tmpPen = New-Object System.Drawing.Pen($clrTempLine, 2)
        $g.DrawLines($tmpPen, $tmpPoints.ToArray([System.Drawing.PointF]))
        $tmpPen.Dispose()
        $lp = $tmpPoints[$tmpPoints.Count - 1]
        $g.FillEllipse($script:brushTemp, ($lp.X - 4), ($lp.Y - 4), 8, 8)
    }

    $g.ResetClip()

    # Chart border
    $borderPen = New-Object System.Drawing.Pen($clrAccent, 1)
    $g.DrawRectangle($borderPen, $ml, $mt, $cw, $ch)
    $borderPen.Dispose()

    # X axis label
    $xAxisLabel = "Elapsed Time (MM:SS)"
    $xSz = $g.MeasureString($xAxisLabel, $fntSmall)
    $g.DrawString($xAxisLabel, $fntSmall, $script:brushSubText,
        ($ml + ($cw - $xSz.Width) / 2), ($h - 18))

    # Legend — use pre-allocated brushes
    $legendX = $ml + $cw - 220 ; $legendY = $mt + 8
    $g.FillRectangle($script:brushBg, $legendX - 4, $legendY - 4, 220, 42)
    $tmpLegPen = New-Object System.Drawing.Pen($clrTempLine, 2)
    $g.DrawLine($tmpLegPen, $legendX, ($legendY + 6), ($legendX + 20), ($legendY + 6))
    $tmpLegPen.Dispose()
    $g.DrawString("Actual Temp", $fntSmall, $script:brushText, ($legendX + 25), ($legendY))
    $spLegPen = New-Object System.Drawing.Pen($clrSetptLine, 2)
    $spLegPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $g.DrawLine($spLegPen, $legendX, ($legendY + 24), ($legendX + 20), ($legendY + 24))
    $spLegPen.Dispose()
    $g.DrawString("Setpoint", $fntSmall, $script:brushText, ($legendX + 25), ($legendY + 18))
    $mkLegPen = New-Object System.Drawing.Pen($clrMarker, 1)
    $mkLegPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $g.DrawLine($mkLegPen, ($legendX + 120), ($legendY + 6), ($legendX + 140), ($legendY + 6))
    $mkLegPen.Dispose()
    $g.DrawString("Step change", $fntSmall, $script:brushText, ($legendX + 145), ($legendY))
}

# ================================================
# BUILD CHART FORM
# ================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Thermotron 2800 - Live Temperature Chart"
$form.Size            = New-Object System.Drawing.Size(900, 580)
$form.StartPosition   = "Manual"
$form.Location        = New-Object System.Drawing.Point(540, 100)
$form.BackColor       = $clrBg
$form.ForeColor       = $clrText
$form.FormBorderStyle = "Sizable"
$form.MinimumSize     = New-Object System.Drawing.Size(700, 450)

# Title bar area
$pnlTop = New-Object System.Windows.Forms.Panel
$pnlTop.Location  = New-Object System.Drawing.Point(0, 0)
$pnlTop.Size      = New-Object System.Drawing.Size(900, 55)
$pnlTop.BackColor = $clrBg
$pnlTop.Anchor    = "Top,Left,Right"
$form.Controls.Add($pnlTop)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "THERMOTRON 2800 - LIVE TEMPERATURE CHART"
$lblTitle.Font      = $fntTitle
$lblTitle.ForeColor = $clrAccent
$lblTitle.Location  = New-Object System.Drawing.Point(15, 10)
$lblTitle.Size      = New-Object System.Drawing.Size(600, 24)
$pnlTop.Controls.Add($lblTitle)

$lblStartTime = New-Object System.Windows.Forms.Label
$lblStartTime.Text      = "  Test start: --"
$lblStartTime.Font      = $fntSmall
$lblStartTime.ForeColor = $clrSubText
$lblStartTime.Location  = New-Object System.Drawing.Point(15, 34)
$lblStartTime.Size      = New-Object System.Drawing.Size(400, 16)
$pnlTop.Controls.Add($lblStartTime)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = "  Waiting for data..."
$lblStatus.Font      = $fntSmall
$lblStatus.ForeColor = $clrGreen
$lblStatus.Location  = New-Object System.Drawing.Point(420, 34)
$lblStatus.Size      = New-Object System.Drawing.Size(300, 16)
$pnlTop.Controls.Add($lblStatus)

# Chart panel
$chartPanel = New-Object System.Windows.Forms.Panel
$chartPanel.Location   = New-Object System.Drawing.Point(0, 55)
$chartPanel.Size       = New-Object System.Drawing.Size(900, 440)
$chartPanel.BackColor  = $clrBg
$chartPanel.Anchor     = "Top,Bottom,Left,Right"
$form.Controls.Add($chartPanel)

$chartPanel.Add_Paint({ param($s,$e) Draw-Chart $e })

# Bottom control bar
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Location  = New-Object System.Drawing.Point(0, 495)
$pnlBottom.Size      = New-Object System.Drawing.Size(900, 45)
$pnlBottom.BackColor = $clrPanel
$pnlBottom.Anchor    = "Bottom,Left,Right"
$form.Controls.Add($pnlBottom)

# View window label and selector
$lblView = New-Object System.Windows.Forms.Label
$lblView.Text      = "View window:"
$lblView.Location  = New-Object System.Drawing.Point(15, 13)
$lblView.Size      = New-Object System.Drawing.Size(90, 18)
$lblView.ForeColor = $clrText
$lblView.Font      = $fntLabel
$pnlBottom.Controls.Add($lblView)

$cmbView = New-Object System.Windows.Forms.ComboBox
$cmbView.Location      = New-Object System.Drawing.Point(110, 10)
$cmbView.Size          = New-Object System.Drawing.Size(110, 24)
$cmbView.BackColor     = $clrInput
$cmbView.ForeColor     = $clrText
$cmbView.Font          = $fntLabel
$cmbView.DropDownStyle = "DropDownList"
@("15 min","30 min","1 hour","2 hours","Full test") | ForEach-Object { $cmbView.Items.Add($_) | Out-Null }
$cmbView.SelectedIndex = 2
$cmbView.Add_SelectedIndexChanged({
    switch ($cmbView.SelectedIndex) {
        0 { $script:viewSeconds = 900  }
        1 { $script:viewSeconds = 1800 }
        2 { $script:viewSeconds = 3600 }
        3 { $script:viewSeconds = 7200 }
        4 {
            $max = ($script:dataPoints | ForEach-Object { $_.Elapsed } | Measure-Object -Maximum).Maximum
            $script:viewSeconds = [math]::Max($(if ($max) { $max } else { 60 }), 60)
            $script:scrollOffset = 0
        }
    }
    $chartPanel.Invalidate()
})
$pnlBottom.Controls.Add($cmbView)

# Auto-scroll checkbox
$chkAutoScroll = New-Object System.Windows.Forms.CheckBox
$chkAutoScroll.Text      = "Auto-scroll"
$chkAutoScroll.Location  = New-Object System.Drawing.Point(235, 12)
$chkAutoScroll.Size      = New-Object System.Drawing.Size(100, 20)
$chkAutoScroll.ForeColor = $clrText
$chkAutoScroll.Font      = $fntLabel
$chkAutoScroll.BackColor = [System.Drawing.Color]::Transparent
$chkAutoScroll.Checked   = $true
$chkAutoScroll.Add_CheckedChanged({ $script:autoScroll = $chkAutoScroll.Checked })
$pnlBottom.Controls.Add($chkAutoScroll)

# Scrollbar
$hScroll = New-Object System.Windows.Forms.HScrollBar
$hScroll.Location = New-Object System.Drawing.Point(350, 12)
$hScroll.Size     = New-Object System.Drawing.Size(250, 20)
$hScroll.Minimum  = 0
$hScroll.Maximum  = 100
$hScroll.Value    = 100
$hScroll.Add_Scroll({
    if (-not $script:autoScroll) {
        $maxElapsed = ($script:dataPoints | ForEach-Object { $_.Elapsed } | Measure-Object -Maximum).Maximum
        if ($maxElapsed -eq $null) { $maxElapsed = 0 }
        $script:scrollOffset = [math]::Round(
            ($hScroll.Value / 100.0) * [math]::Max(0, $maxElapsed - $script:viewSeconds), 0)
        $chartPanel.Invalidate()
    }
})
$pnlBottom.Controls.Add($hScroll)

# Save PNG button
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text      = "SAVE AS PNG"
$btnSave.Location  = New-Object System.Drawing.Point(615, 8)
$btnSave.Size      = New-Object System.Drawing.Size(120, 30)
$btnSave.BackColor = $clrAccent
$btnSave.ForeColor = [System.Drawing.Color]::Black
$btnSave.Font      = $fntButton
$btnSave.FlatStyle = "Flat"
$btnSave.FlatAppearance.BorderSize = 0
$btnSave.Add_Click({
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Title  = "Save Chart as PNG"
    $saveDialog.Filter = "PNG Image (*.png)|*.png"
    $saveDialog.FileName = "thermotron2800_chart_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
    $saveDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($DataFile)
    if ($saveDialog.ShowDialog() -eq "OK") {
        $bmp = New-Object System.Drawing.Bitmap($chartPanel.Width, $chartPanel.Height)
        $chartPanel.DrawToBitmap($bmp, [System.Drawing.Rectangle]::new(0,0,$chartPanel.Width,$chartPanel.Height))
        $bmp.Save($saveDialog.FileName, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        [System.Windows.Forms.MessageBox]::Show(
            "Chart saved to:`n$($saveDialog.FileName)",
            "Saved", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$pnlBottom.Controls.Add($btnSave)

# Close button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text      = "CLOSE"
$btnClose.Location  = New-Object System.Drawing.Point(748, 8)
$btnClose.Size      = New-Object System.Drawing.Size(80, 30)
$btnClose.BackColor = $clrPanel
$btnClose.ForeColor = $clrSubText
$btnClose.Font      = $fntButton
$btnClose.FlatStyle = "Flat"
$btnClose.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(80,80,80)
$btnClose.FlatAppearance.BorderSize  = 1
$btnClose.Add_Click({ $form.Close() })
$pnlBottom.Controls.Add($btnClose)

# Resize handler to reposition bottom panel
$form.Add_Resize({
    $pnlBottom.Location = New-Object System.Drawing.Point(0, ($form.ClientSize.Height - 45))
    $pnlBottom.Width    = $form.ClientSize.Width
    $chartPanel.Size    = New-Object System.Drawing.Size(
        $form.ClientSize.Width,
        ($form.ClientSize.Height - 55 - 45))
    $hScroll.Width      = [math]::Max(100, $form.ClientSize.Width - 650)
    $btnSave.Location   = New-Object System.Drawing.Point(($form.ClientSize.Width - 215), 8)
    $btnClose.Location  = New-Object System.Drawing.Point(($form.ClientSize.Width - 90), 8)
    $chartPanel.Invalidate()
})

# ================================================
# REFRESH TIMER - reads data file and redraws
# ================================================
$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 10000   # Refresh every 10 seconds
$refreshTimer.Add_Tick({
    $updated = Read-DataFile
    if ($updated -or $script:dataPoints.Count -gt 0) {
        # Update start time label
        if ($script:testStart -ne $null) {
            $lblStartTime.Text = "  Test start: $($script:testStart.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        # Update status
        if ($script:isRunning) {
            $pts = $script:dataPoints | Where-Object { $_.Temp -ne $null }
            if ($pts.Count -gt 0) {
                $last    = $pts | Select-Object -Last 1
                $elapsed = [math]::Floor($last.Elapsed / 60)
                $lblStatus.Text      = "  Running - Last: $($last.Temp) $TempScale at ${elapsed}min"
                $lblStatus.ForeColor = $clrGreen
            }
        } else {
            $lblStatus.Text      = "  Test complete"
            $lblStatus.ForeColor = $clrSubText
            $refreshTimer.Stop()
        }
        # Update scrollbar maximum
        $maxElapsed = ($script:dataPoints | ForEach-Object { $_.Elapsed } | Measure-Object -Maximum).Maximum
        if ($maxElapsed -eq $null) { $maxElapsed = 0 }
        if ($maxElapsed -gt $script:viewSeconds) {
            $hScroll.Maximum = 100
            if ($script:autoScroll) { $hScroll.Value = 100 }
        }
        $chartPanel.Invalidate()
    }
})

$form.Add_FormClosed({
    # Dispose all pre-allocated GDI brushes on close
    $script:brushBg.Dispose()
    $script:brushPanel.Dispose()
    $script:brushText.Dispose()
    $script:brushSubText.Dispose()
    $script:brushMarker.Dispose()
    $script:brushTemp.Dispose()
    $refreshTimer.Stop()
})

# ================================================
# SHOW FORM
# ================================================
$form.Add_Shown({
    $form.Activate()

    $lblStatus.Text      = "  Waiting for test to start writing data..."
    $lblStatus.ForeColor = $clrSubText
    $script:waited = 0

    $script:waitTimer = New-Object System.Windows.Forms.Timer
    $script:waitTimer.Interval = 1000
    $script:waitTimer.Add_Tick({
        $script:waited++
        if (Test-Path $DataFile) {
            $script:waitTimer.Stop()
            $lblStatus.Text      = "  Data file found - reading..."
            $lblStatus.ForeColor = $clrGreen
            Read-DataFile
            $refreshTimer.Start()
            $chartPanel.Invalidate()
        } elseif ($script:waited -ge 60) {
            $script:waitTimer.Stop()
            $lblStatus.Text      = "  WARNING: Data file not found after 60s. Check the chart checkbox was enabled before starting the test."
            $lblStatus.ForeColor = $clrRed
        } else {
            $lblStatus.Text      = "  Waiting for data file... ($($script:waited) s)"
        }
    })
    $script:waitTimer.Start()
})
[System.Windows.Forms.Application]::Run($form)
$refreshTimer.Stop()
