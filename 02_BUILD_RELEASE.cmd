@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\BUILD_RELEASE.ps1"
if errorlevel 1 (
  echo.
  echo Build failed. The application will not be started.
  pause
  exit /b 1
)

set "APP=%~dp0dist\AudioImageMp4Maker-win-x64\AudioImageMp4Maker.exe"
if not exist "%APP%" (
  echo.
  echo Build reported success, but the compiled application was not found:
  echo %APP%
  pause
  exit /b 1
)

echo.
echo Build completed successfully.
echo The compiled application will start automatically in 10 seconds.
for /L %%S in (10,-1,1) do (
  echo   Starting application in %%S seconds...
  timeout /t 1 /nobreak >nul
)

echo.
start "" "%APP%"
exit /b 0
