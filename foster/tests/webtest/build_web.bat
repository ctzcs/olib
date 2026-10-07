@echo off
rem Foster webtest - Web (js_wasm32) 构建
rem 产物: foster\tests\webtest\webtest.wasm (+ 拷贝 odin.js; foster.js 由 index.html 相对引用 ../../internal/web/)
rem 运行: 在仓库根目录起本地服务(如 python -m http.server 8137),
rem       浏览器打开 http://localhost:8137/foster/tests/webtest/
setlocal
where odin >nul 2>nul
if %errorlevel%==0 (set ODIN=odin) else (set ODIN=D:\Lib\odin\odin.exe)
cd /d "%~dp0..\..\.."
%ODIN% build foster/tests/webtest -collection:olib=. -target:js_wasm32 -o:speed -out:foster\tests\webtest\webtest.wasm
if errorlevel 1 exit /b 1
copy /y "D:\Lib\odin\core\sys\wasm\js\odin.js" foster\tests\webtest\odin.js >nul
echo web build ok: foster\tests\webtest\webtest.wasm
