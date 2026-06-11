@echo off
title Auto-Allow (Claude Code)
:loop
echo [%time%] Starting Auto-Allow watcher...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { & '%~dp0Auto-Allow.ps1' -IntervalMs 1000 } catch { Write-Host ''; Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow }"
echo.
echo [%time%] Watcher exited. Restarting in 3 seconds...
timeout /t 3 /nobreak >nul
goto loop
