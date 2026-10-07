#!/bin/sh
# OFoster webtest - Web (js_wasm32) 构建(Linux/macOS)
# 产物: tests/webtest/webtest.wasm (+ 拷贝 odin.js; foster.js 由 index.html 相对引用 ../../internal/web/)
# 运行: 仓库根目录起本地服务(python3 -m http.server 8137),
#       浏览器打开 http://localhost:8137/tests/webtest/
set -e
cd "$(dirname "$0")/../.."
ODIN_BIN="${ODIN:-odin}"
ODIN_ROOT="$("$ODIN_BIN" root 2>/dev/null || true)"
ODIN_JS="$ODIN_ROOT/core/sys/wasm/js/odin.js"
$ODIN_BIN build tests/webtest -collection:ofoster=src -target:js_wasm32 -o:speed -out:tests/webtest/webtest.wasm
if [ ! -f tests/webtest/odin.js ]; then
	if [ -f "$ODIN_JS" ]; then
		cp "$ODIN_JS" tests/webtest/odin.js
	else
		echo "warn: 未找到 odin.js, 请手动从 Odin 安装的 core/sys/wasm/js/ 复制到 tests/webtest/"
	fi
fi
echo "web build ok: tests/webtest/webtest.wasm"
