@echo off
rem install.ps1 puts this launcher in <install dir>\bin and reel.ps1 one level above it. Only bin is
rem on PATH: if reel.ps1 were on PATH, PowerShell would run it in-process instead of this file and
rem fail under a Restricted execution policy. -NoProfile keeps start-up independent of the profile.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\reel.ps1" %*
