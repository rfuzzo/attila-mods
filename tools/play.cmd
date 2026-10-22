@echo off
rem Double-click: start the game with TWASE and the mods from this repo (tools\play.ps1, past PowerShell's script policy).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1" %*
if errorlevel 1 pause
