@echo off
setlocal
title dsh our-free-model installer
echo Running dsh-our-free-model desktop installer...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-our-free-model.ps1" %*
set EC=%ERRORLEVEL%
echo.
if "%EC%"=="0" (echo [done] installer finished successfully.) else (echo [!] installer exited with code %EC% - see messages above.)
echo.
pause
endlocal ^& exit /b %EC%
