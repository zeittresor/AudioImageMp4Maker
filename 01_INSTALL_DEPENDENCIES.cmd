@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\INSTALL_DEPENDENCIES.ps1"
if errorlevel 1 (
  echo.
  echo Dependency setup failed.
  pause
  exit /b 1
)

echo.
echo Dependency setup completed successfully.
echo The release build will start automatically in 10 seconds.
for /L %%S in (10,-1,1) do (
  echo   Compiling in %%S seconds...
  timeout /t 1 /nobreak >nul
)

echo.
call "%~dp002_BUILD_RELEASE.cmd"
exit /b %errorlevel%
