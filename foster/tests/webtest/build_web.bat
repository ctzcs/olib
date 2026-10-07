@echo off
rem OFoster webtest - Web (js_wasm32) 构建
rem 产物: tests\webtest\webtest.wasm (+ 拷贝 odin.js; foster.js 由 index.html 相对引用 ../../src/internal/web/)
rem 运行: 在仓库根目录起本地服务(如 python -m http.server 8137),
rem       浏览器打开 http://localhost:8137/tests/webtest/
setlocal
where odin >nul 2>nul
if %errorlevel%==0 (set ODIN=odin) else (set ODIN=D:\Lib\odin\odin.exe)
cd /d "%~dp0..\.."
%ODIN% build tests/webtest -collection:ofoster=src -target:js_wasm32 -o:speed -out:tests\webtest\webtest.wasm
if errorlevel 1 exit /b 1
copy /y "D:\Lib\odin\core\sys\wasm\js\odin.js" tests\webtest\odin.js >nul
echo web build ok: tests\webtest\webtest.wasm
