@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\run-pester-coverage.ps1"
pause