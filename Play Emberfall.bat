@echo off
cd /d "%~dp0"
"%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64.exe" --path "%~dp0godot"
if errorlevel 1 pause
