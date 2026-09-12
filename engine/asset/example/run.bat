@echo off
rem Build and run the olib:engine/asset pipeline example.
rem Set OFOSTER_PATH to your ofoster checkout (collection root = its src folder)
rem if it is not ..\..\..\..\OFoster\src (sibling of the olib repo).
rem NOTE: keep this file ASCII-only; cmd parses it in the ANSI codepage,
rem and %CD% expands at parse time, so keep set-on-its-own-line after pushd.
setlocal
cd /d "%~dp0"

rem olib root is three levels up (example -> asset -> engine -> olib).
rem odin -collection needs a normalized path (it does not accept ..\);
rem use pushd (always lands on a real dir) to normalize.
pushd "%~dp0..\..\.."
set "OLIB_ROOT=%CD%"
popd

if "%OFOSTER_PATH%"=="" set "OFOSTER_PATH=%~dp0..\..\..\..\OFoster\src"
pushd "%OFOSTER_PATH%" 2>nul
if errorlevel 1 (
    echo ofoster not found at "%OFOSTER_PATH%" - set OFOSTER_PATH to your ofoster src folder
    exit /b 1
)
set "OFOSTER_PATH=%CD%"
popd
if not exist "%OFOSTER_PATH%\framework.odin" (
    echo "%OFOSTER_PATH%" does not look like an ofoster src folder ^(framework.odin missing^)
    exit /b 1
)

if not exist build mkdir build
odin build . -collection:olib="%OLIB_ROOT%" -collection:ofoster="%OFOSTER_PATH%" -out:build\example.exe -o:speed
if errorlevel 1 exit /b 1

rem Copy the SDL3 runtime bundled with Odin beside the exe
for /f "delims=" %%i in ('odin root') do set "ODIN_ROOT=%%i"
if exist "%ODIN_ROOT%vendor\sdl3\SDL3.dll" copy /y "%ODIN_ROOT%vendor\sdl3\SDL3.dll" build\SDL3.dll >nul

build\example.exe
endlocal
