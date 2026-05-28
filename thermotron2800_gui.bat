@echo off
REM ================================================
REM  THERMOTRON 2800 - GUI LAUNCHER
REM  Double-click this file to open the parameter
REM  configuration GUI
REM ================================================

echo.
echo ================================================
echo   THERMOTRON 2800 - PARAMETER CONFIGURATION GUI
echo ================================================
echo.
echo Launching GUI...

powershell -ExecutionPolicy Bypass -File "%~dp0thermotron2800_gui.ps1"

if %errorlevel% neq 0 (
    echo.
    echo ERROR: GUI failed to launch.
    echo Make sure thermotron2800_gui.ps1 is in the same folder as this file.
    pause
)
