# Compiles 3D HLSL shaders to SPIR-V (Vulkan) and DXIL (D3D12) using
# the Vulkan SDK dxc. Metal (msl) and WebGL (glsl) targets must be
# cross-compiled on their platforms; see README.
# ASCII-only on purpose (see docs/CODE_STYLE.md).
$ErrorActionPreference = 'Stop'

$cmd = Get-Command dxc -ErrorAction SilentlyContinue
$dxc = if ($cmd) { $cmd.Source } else { $null }
if (-not $dxc) {
    $sdk = Get-ChildItem 'C:/VulkanSDK' -Directory | Sort-Object Name -Descending |
        Select-Object -First 1
    if ($sdk) { $dxc = Join-Path $sdk.FullName 'Bin/dxc.exe' }
}
if (-not (Test-Path $dxc)) { Write-Error 'dxc not found (install Vulkan SDK)'; exit 1 }

$shaderDir = $PSScriptRoot
$out = Join-Path $shaderDir 'Compiled'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$shaders = @('Standard3D', 'Standard3DSkinned', 'DepthOnly', 'DepthOnlySkinned', 'DebugLine3D')
foreach ($name in $shaders) {
    $src = Join-Path $shaderDir "$name.hlsl"
    & $dxc -spirv -T vs_6_0 -E vertex_main -Fo (Join-Path $out "$name.vertex.spv") $src
    & $dxc -spirv -T ps_6_0 -E fragment_main -Fo (Join-Path $out "$name.fragment.spv") $src
    & $dxc -T vs_6_0 -E vertex_main -Fo (Join-Path $out "$name.vertex.dxil") $src
    & $dxc -T ps_6_0 -E fragment_main -Fo (Join-Path $out "$name.fragment.dxil") $src
    if ($LASTEXITCODE -ne 0) { Write-Error "compile failed: $name"; exit 1 }
    Write-Host "compiled $name"
}
