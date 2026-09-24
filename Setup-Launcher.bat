@echo off
:: ============================================================================
:: Setup-Launcher.bat - Bequemer Starter fuer Cloud Code + Ollama Setup
:: ============================================================================
chcp 65001 >nul
setlocal enabledelayedexpansion
title Cloud Code / Claude Code + Ollama Setup

echo ============================================================
echo   Cloud Code / Claude Code + Ollama Windows Setup Starter
echo ============================================================
echo.

:: Ausfuehrung des PowerShell-Setup-Skripts ohne erzwungene UAC-Erhoehung
cd /d "%~dp0"
set "PS_SCRIPT=%~dp0CloudCode_Ollama_Setup.ps1"

if not exist "%PS_SCRIPT%" (
    echo [FEHLER] Die Datei CloudCode_Ollama_Setup.ps1 wurde nicht im selben Ordner gefunden!
    echo Erwarteter Pfad: %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

echo [INFO] Starte PowerShell Setup mit umgangener ExecutionPolicy...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "EXIT_CODE=%errorlevel%"

echo.
echo ============================================================
if %EXIT_CODE% equ 0 (
    echo [OK] Setup wurde erfolgreich ausgefuehrt!
) else (
    echo [FEHLER] Setup beendet mit Exit-Code %EXIT_CODE%. Siehe Protokoll oben.
)
echo Druecken Sie eine beliebige Taste zum Schliessen dieses Fensters...
echo ============================================================
pause >nul
