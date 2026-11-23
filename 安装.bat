@echo off
rem One-click installer for the US time desktop widget.
rem Unblocks files, creates a desktop shortcut, then starts the widget.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 pause
exit