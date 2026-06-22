@echo off
setlocal
cd /d "%~dp0"

:menu
cls
echo ============================================================
echo   AUTOPILOT AND INTUNE SAFE RECOVERY TOOLKIT
echo ============================================================
echo   1. Diagnose only
echo   2. Run safe recovery set
echo   3. Restart Intune Management Extension
echo   4. Restart Windows MDM client services
echo   5. Trigger existing EnterpriseMgmt sync tasks
echo   6. Refresh current user Primary Refresh Token
echo   7. Flush DNS cache
echo   8. Archive Intune Management Extension logs
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" set ARGS=&goto run
if "%CHOICE%"=="2" set ARGS=-RepairAllSafe&goto run
if "%CHOICE%"=="3" set ARGS=-RestartIntuneManagementExtension&goto run
if "%CHOICE%"=="4" set ARGS=-RestartMdmServices&goto run
if "%CHOICE%"=="5" set ARGS=-TriggerMdmSync&goto run
if "%CHOICE%"=="6" set ARGS=-RefreshPrimaryRefreshToken&goto run
if "%CHOICE%"=="7" set ARGS=-FlushDns&goto run
if "%CHOICE%"=="8" set ARGS=-ArchiveIntuneLogs&goto run
if "%CHOICE%"=="0" goto end
goto menu

:run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0src\Invoke-AutopilotSafeRecovery.ps1' -ErrorAction SilentlyContinue"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" %ARGS%
echo.
pause
goto menu

:end
endlocal
