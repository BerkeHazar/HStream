@echo off
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "APP=%ROOT%\app"
set "HSTREAM_APPLY_DONE="
call "%ROOT%\hstream\apply.bat"
echo.
echo [launcher] exit=%errorlevel%
