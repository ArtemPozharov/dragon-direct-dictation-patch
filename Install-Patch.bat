@echo off
rem ==============================================================================
rem Install-Patch.bat - Dragon Medical 12 Direct Dictation Patch
rem ==============================================================================

set SCRIPT_DIR=%~dp0
echo [%DATE% %TIME%] Starten van Dragon Medical 12 Direct Dictation Patch...

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Patch-DragonKWS.ps1" -ConfigFile "%SCRIPT_DIR%config.json"

if %ERRORLEVEL% NEQ 0 (
    echo [%DATE% %TIME%] Patch mislukt met foutcode %ERRORLEVEL%.
    exit /b %ERRORLEVEL%
)

echo [%DATE% %TIME%] Patch succesvol voltooid.
exit /b 0
