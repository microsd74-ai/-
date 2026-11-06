@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"
echo FHZL read-only diagnostic
echo Open FHZLPrinterManager first. Extract all files before running.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-Fhzl.ps1"
echo.
echo Reports are saved in the reports folder next to this file.
pause
endlocal
