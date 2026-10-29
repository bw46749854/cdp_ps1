@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0main\run_job.ps1" -JobName "MonthlyInstallReport"
pause
