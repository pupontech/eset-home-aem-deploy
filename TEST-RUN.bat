@echo off
REM ============================================================
REM  ESET Splashtop AEM scripts - manual VM test runner
REM  Run this INSIDE an elevated (Administrator) CMD window on
REM  the test VM. AEM runs scripts as SYSTEM; an elevated CMD is
REM  close enough for install permissions.
REM ============================================================
setlocal
set "SCRIPTDIR=%~dp0"
set "WORKDIR=C:\Windows\Temp\ESETDeploy"

echo.
echo Which script do you want to test?
echo   [1] Install-ESET-HOME-Ultimate.ps1   (ESET Security Ultimate)
echo   [2] Install-ESET-HOME-Essential.ps1  (ESET NOD32 Antivirus)
echo   [3] Both, back to back
echo.
set /p CHOICE="Enter 1, 2 or 3: "

if "%CHOICE%"=="1" goto ultimate
if "%CHOICE%"=="2" goto essential
if "%CHOICE%"=="3" goto both
echo Invalid choice.
exit /b 9

:ultimate
call :runone "Install-ESET-HOME-Ultimate.ps1" "eset_ultimate_install.log"
goto end

:essential
call :runone "Install-ESET-HOME-Essential.ps1" "eset_essential_install.log"
goto end

:both
call :runone "Install-ESET-HOME-Ultimate.ps1" "eset_ultimate_install.log"
echo.
echo --- NOTE: second script should find ESET present, uninstall it, ---
echo ---       then install Essential on top. Watch for the UAC-style ---
echo ---       callmsi removal in the log. ---
echo.
call :runone "Install-ESET-HOME-Essential.ps1" "eset_essential_install.log"
goto end

:runone
echo.
echo ============================================================
echo  RUNNING: %~1
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTDIR%%~1"
set EC=%ERRORLEVEL%
echo.
echo  EXIT CODE: %EC%   (0 = pass, anything else = fail)
echo.
echo  ----- LOG (%WORKDIR\%~2) -----
if exist "%WORKDIR%\%~2" (type "%WORKDIR%\%~2") else (echo  [no log file written - script failed very early])
echo  ----- END LOG -----
exit /b 0

:end
echo.
echo Done. Check the checklist in TEST-CHECKLIST.txt against what you saw above.
endlocal
pause
