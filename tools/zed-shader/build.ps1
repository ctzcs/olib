param([switch]$Install)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$toolchainRoot = Join-Path $repoRoot 'library/tmp/zed-shader-toolchain'
$grammarRoot = Join-Path $repoRoot 'library/tmp/zed-shader-grammar'
$packageRoot = Join-Path $repoRoot 'build/zed-shader'
$cliPath = Join-Path $toolchainRoot 'node_modules/tree-sitter-cli/tree-sitter.exe'

function Assert-CommandSuccess {
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
}

# 固定版本；工具缓存与解析器中间文件不写入源码树。
if (!(Test-Path -LiteralPath (Join-Path $toolchainRoot 'node_modules/web-tree-sitter/tree-sitter.js'))) {
    & npm.cmd install --prefix $toolchainRoot --ignore-scripts --no-audit --no-fund tree-sitter-cli@0.25.10 web-tree-sitter@0.25.10
    Assert-CommandSuccess
}
if (!(Test-Path -LiteralPath $cliPath)) {
    Push-Location (Join-Path $toolchainRoot 'node_modules/tree-sitter-cli')
    try {
        & node install.js
        Assert-CommandSuccess
    } finally { Pop-Location }
}
New-Item -ItemType Directory -Force (Join-Path $grammarRoot 'src'), (Join-Path $packageRoot 'grammars') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'grammar.js') -Destination (Join-Path $grammarRoot 'grammar.js') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scanner.c') -Destination (Join-Path $grammarRoot 'src/scanner.c') -Force
Push-Location $grammarRoot
try {
    & $cliPath generate --abi 14
    Assert-CommandSuccess
} finally { Pop-Location }

# 只构建语法库；不链接 Zig 的 WASI 程序入口，否则 Zed 会拒绝 main/args imports。
& zig cc -target wasm32-wasi -fPIC -shared -mexec-model=reactor -Os '-Wl,--export=tree_sitter_olib_shader' `
    -o (Join-Path $packageRoot 'grammars/olib_shader.wasm') -I (Join-Path $grammarRoot 'src') `
    (Join-Path $grammarRoot 'src/parser.c') (Join-Path $grammarRoot 'src/scanner.c')
Assert-CommandSuccess
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'extension.toml') -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'languages') -Destination $packageRoot -Recurse -Force
& node (Join-Path $repoRoot 'tests/tools/zed-shader/highlight_test.mjs')
Assert-CommandSuccess

if ($Install) {
    $extensionTarget = Join-Path $env:LOCALAPPDATA 'Zed/extensions/installed/olib-shader'
    New-Item -ItemType Directory -Force $extensionTarget | Out-Null
    foreach ($part in @('languages', 'grammars', 'extension.toml')) {
        Copy-Item -LiteralPath (Join-Path $packageRoot $part) -Destination $extensionTarget -Recurse -Force
    }
    Write-Output "Installed: $extensionTarget"
    Write-Output 'Zed will reload the extension; reopen the shader if its language was selected manually.'
}
Write-Output "Built: $packageRoot"
