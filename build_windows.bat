@echo off
setlocal
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter is not on PATH. Install Flutter, then rerun this script.
  exit /b 1
)
if not exist windows\CMakeLists.txt (
  echo Generating the Windows Flutter runner...
  call flutter create --platforms=windows --project-name vyse_portal_player .
  if errorlevel 1 goto :fail
)
echo Fetching Flutter packages...
call flutter pub get
if errorlevel 1 goto :fail
echo Building the Windows release app...
call flutter build windows --release
if errorlevel 1 goto :fail
if not exist dist mkdir dist
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath 'dist\VysePortalPlayer-Windows-x64.zip' -Force"
if errorlevel 1 goto :fail
echo.
echo Build complete. Distribute the ZIP in dist\; it contains the EXE and required files.
exit /b 0
:fail
echo.
echo Build failed. Check the error above.
exit /b 1
