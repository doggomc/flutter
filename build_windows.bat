@echo off
setlocal
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter is not on PATH. Install Flutter, then rerun this script.
  exit /b 1
)
if not defined PORTAL_USERNAME (
  echo Set PORTAL_USERNAME in the environment before building.
  exit /b 1
)
if not defined PORTAL_PASSWORD (
  echo Set PORTAL_PASSWORD in the environment before building.
  exit /b 1
)
if not exist windows\CMakeLists.txt (
  echo Generating the Windows Flutter runner...
  call flutter create --platforms=windows --project-name freef1_cockpit .
  if errorlevel 1 goto :fail
)
echo Fetching Flutter packages...
call flutter pub get
if errorlevel 1 goto :fail
echo Checking Dart source...
call flutter analyze
if errorlevel 1 goto :fail
echo Running unit tests...
call flutter test
if errorlevel 1 goto :fail
echo Building the Windows release app...
call flutter build windows --release --dart-define=PORTAL_USERNAME=%PORTAL_USERNAME% --dart-define=PORTAL_PASSWORD=%PORTAL_PASSWORD%
if errorlevel 1 goto :fail
if not exist dist mkdir dist
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath 'dist\FreeF1-Cockpit-Windows-x64.zip' -Force"
if errorlevel 1 goto :fail
echo.
echo Build complete. See dist\FreeF1-Cockpit-Windows-x64.zip.
exit /b 0
:fail
echo.
echo Build failed. Check the error above.
exit /b 1
