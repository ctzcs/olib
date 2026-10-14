# Compiles every *.hlsl in a directory (skipping *.hlsli includes) with
# SDL_shadercross, the same pipeline as upstream Foster's compile.sh:
#   HLSL -> .spv (Vulkan), then .spv -> .dxil (D3D12) and .spv -> .msl (Metal).
# Each shader needs vertex_main and fragment_main entry points.
# Output goes to <Dir>/Compiled. Web (GLSL ES) is hand-written and not covered.
#
# Usage:
#   powershell -File build_shaders.ps1                 # this directory (kit DebugLine3D)
#   powershell -File build_shaders.ps1 -Dir <shaders>  # a game's / sample's own shaders
#
# shadercross is looked up on PATH, then at D:\Tools\ShaderCross\bin.
# ASCII-only on purpose (see docs/CODE_STYLE.md).
param(
    [string]$Dir = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'

$cmd = Get-Command shadercross -ErrorAction SilentlyContinue
$shadercross = if ($cmd) { $cmd.Source } else { 'D:\Tools\ShaderCross\bin\shadercross.exe' }
if (-not (Test-Path $shadercross)) { Write-Error 'shadercross not found (put it on PATH)'; exit 1 }

$Dir = (Resolve-Path $Dir).Path
$out = Join-Path $Dir 'Compiled'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Invoke-Shadercross([string[]]$arguments) {
    & $shadercross @arguments
    if ($LASTEXITCODE -ne 0) { Write-Error "shadercross failed: $($arguments -join ' ')"; exit 1 }
}

$sources = Get-ChildItem -Path $Dir -Filter '*.hlsl' | Where-Object { $_.Extension -eq '.hlsl' }
if (-not $sources) { Write-Error "no .hlsl files in $Dir"; exit 1 }
foreach ($src in $sources) {
    foreach ($stage in 'vertex', 'fragment') {
        $base = Join-Path $out "$($src.BaseName).$stage"
        $entry = "${stage}_main"
        Invoke-Shadercross @($src.FullName, '-s', 'HLSL', '-d', 'SPIRV', '-t', $stage, '-e', $entry, '-I', $Dir, '-o', "$base.spv")
        Invoke-Shadercross @("$base.spv", '-s', 'SPIRV', '-d', 'DXIL', '-t', $stage, '-e', $entry, '-o', "$base.dxil")
        Invoke-Shadercross @("$base.spv", '-s', 'SPIRV', '-d', 'MSL', '-t', $stage, '-e', $entry, '-o', "$base.msl")
    }
    Write-Host "compiled $($src.Name)"
}
