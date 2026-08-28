@echo off
setlocal enableextensions
title HStream
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
for %%i in ("%HERE%\..") do set "ROOT=%%~fi"
set "APP=%ROOT%\app"
set "HS=%HERE%"
set "OUT=%ROOT%\output"

echo HStream
findstr /c:"HSTREAM_OVERLAY" "%HS%\apply.bat" >nul || (
  echo [error] apply.bat missing.
  pause & exit /b 1
)
if not exist "%ROOT%\setup.bat" (echo [error] setup.bat not found. & pause & exit /b 1)
if not exist "%APP%\flutter\pubspec.yaml" (echo [error] app missing. Run setup.bat [1] first. & pause & exit /b 1)
if not exist "%HS%\files\flutter\lib\main.dart" (echo [error] hstream\files missing. & pause & exit /b 1)

echo Applying overlay...
call "%HS%\apply.bat"
if errorlevel 1 (echo [error] Overlay failed. & pause & exit /b 1)

echo Starting builder. Choose [2] to compile, [4] to exit.
call "%ROOT%\setup.bat"

if exist "%OUT%\HStream.apk" (
  echo.
  echo APK: %OUT%\HStream.apk
) else if exist "%OUT%\FredTV-derleme.apk" (
  copy /y "%OUT%\FredTV-derleme.apk" "%OUT%\HStream.apk" >nul
  echo.
  echo APK: %OUT%\HStream.apk
)
echo.
pause
