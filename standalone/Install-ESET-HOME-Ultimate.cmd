@echo off
rem ============================================================
rem  Standalone ESET Home Security Ultimate installer
rem  Double-click me. A UAC prompt appears once (admin needed).
rem ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ESET-HOME.ps1" -Product Ultimate
