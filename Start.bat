@echo off
setlocal
title PROJECT: PLAYTIME - Downgrader
chcp 65001 >nul

rem Czcionka rastrowa nie zawiera znaków ramek - wymuszamy TrueType.
reg add "HKCU\Console\PROJECT: PLAYTIME - Downgrader" /v FaceName /t REG_SZ /d "Consolas" /f >nul 2>&1

where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\PJPT-Downgrader.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\PJPT-Downgrader.ps1" %*
)

if errorlevel 1 (
    echo.
    echo Program zakonczyl sie bledem. Szczegoly w katalogu logs.
    pause
)
endlocal
