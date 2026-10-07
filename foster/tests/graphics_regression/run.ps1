param(
    [string]$SpirvDxc,
    [string]$DxilDxc,
    [string]$GlslangValidator = 'glslangValidator',
    [ValidateSet('d3d12', 'vulkan')]
    [string[]]$Drivers = @('d3d12', 'vulkan')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputDirectory = Join-Path $repoRoot 'build/graphics-regression'
New-Item -ItemType Directory -Force $outputDirectory | Out-Null

if (!$SpirvDxc) { $SpirvDxc = (Get-Command dxc -ErrorAction Stop).Source }
if (!$DxilDxc) {
    $sdkBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    $DxilDxc = Get-ChildItem -LiteralPath $sdkBin -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64/dxc.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}
if (!$DxilDxc) { throw 'Pass -DxilDxc with a matching DXC/dxil.dll installation.' }

$shader = Join-Path $PSScriptRoot 'shader.hlsl'
foreach ($entry in @(
    @('vertex', 'vertex_main', 'vs_6_0'),
    @('fragment', 'fragment_main', 'ps_6_0'),
    @('incompatible', 'incompatible_vertex', 'vs_6_0')
)) {
    & $SpirvDxc -spirv -T $entry[2] -E $entry[1] -Fo (Join-Path $outputDirectory ($entry[0] + '.spv')) $shader
    if ($LASTEXITCODE -ne 0) { throw "SPIR-V compilation failed: $($entry[0])" }
    & $DxilDxc -T $entry[2] -E $entry[1] -Fo (Join-Path $outputDirectory ($entry[0] + '.dxil')) $shader
    if ($LASTEXITCODE -ne 0) { throw "DXIL compilation failed: $($entry[0])" }
}

$odinRoot = (& odin root).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot locate Odin.' }
& $DxilDxc -T cs_6_0 -E compute_main -Fo (Join-Path $outputDirectory 'compute.dxil') (Join-Path $PSScriptRoot 'compute.hlsl')
if ($LASTEXITCODE -ne 0) { throw 'Compute DXIL compilation failed.' }
& $GlslangValidator -V -S comp -o (Join-Path $outputDirectory 'compute.spv') (Join-Path $PSScriptRoot 'compute.glsl')
if ($LASTEXITCODE -ne 0) { throw 'Compute SPIR-V compilation failed.' }
Copy-Item -LiteralPath (Join-Path $odinRoot 'vendor/sdl3/SDL3.dll') -Destination $outputDirectory
$executable = Join-Path $outputDirectory 'graphics-regression.exe'
& odin build $PSScriptRoot "-collection:ofoster=$repoRoot/src" "-out:$executable"
if ($LASTEXITCODE -ne 0) { throw 'Graphics regression build failed.' }
foreach ($driver in $Drivers) {
    & $executable $driver $outputDirectory
    if ($LASTEXITCODE -ne 0) { throw "Graphics regression failed: $driver" }
}
