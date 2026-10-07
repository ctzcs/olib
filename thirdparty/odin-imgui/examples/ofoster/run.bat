@echo off
rem Build and run the odin-imgui x Foster bridge example.
setlocal
cd /d "%~dp0"

if not exist build mkdir build
odin build . -collection:olib=..\..\..\.. -out:build\example.exe -o:speed
if errorlevel 1 exit /b 1

rem Copy the SDL3 runtime bundled with Odin beside the exe so an older
rem SDL3.dll on PATH is not picked up instead.
for /f "delims=" %%i in ('odin root') do set "ODIN_ROOT=%%i"
if exist "%ODIN_ROOT%vendor\sdl3\SDL3.dll" copy /y "%ODIN_ROOT%vendor\sdl3\SDL3.dll" build\SDL3.dll >nul

build\example.exe
endlocal
