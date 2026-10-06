@echo off
rem Build and run the odin-imgui x ofoster bridge example.
rem Set OFOSTER_PATH to your ofoster checkout if it is not ..\..\..\..\..\tinyglade\ofoster.
setlocal
cd /d "%~dp0"

if "%OFOSTER_PATH%"=="" set "OFOSTER_PATH=..\..\..\..\..\tinyglade\ofoster"
if not exist "%OFOSTER_PATH%\foster_framework.odin" (
	echo ofoster not found at "%OFOSTER_PATH%" - set OFOSTER_PATH to your checkout
	exit /b 1
)

if not exist build mkdir build
odin build . -collection:ofoster="%OFOSTER_PATH%" -out:build\example.exe -o:speed
if errorlevel 1 exit /b 1

rem Copy the SDL3 runtime bundled with Odin beside the exe so an older
rem SDL3.dll on PATH is not picked up instead.
for /f "delims=" %%i in ('odin root') do set "ODIN_ROOT=%%i"
if exist "%ODIN_ROOT%vendor\sdl3\SDL3.dll" copy /y "%ODIN_ROOT%vendor\sdl3\SDL3.dll" build\SDL3.dll >nul

build\example.exe
endlocal
