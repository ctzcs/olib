# olib 一键验证：提交前运行，任何一项失败则以非零退出码结束。
# 用法（olib 根目录）：
#   powershell -File check.ps1              全部检查
#   powershell -File check.ps1 -NoSamples   跳过同级 OFoster_Sample 示例编译
# 产物写到 build/check/（已被 .gitignore 忽略）。

param(
	[switch]$NoSamples
)

# 不用 Stop：PowerShell 5.1 会把原生程序写到 stderr 的日志当作终止错误；成败只看退出码。
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = $PSScriptRoot
$out = Join-Path $root 'build/check'
New-Item -ItemType Directory -Force $out | Out-Null
Set-Location $root

$failed = New-Object System.Collections.Generic.List[string]
$passed = 0

# 运行一项检查；输出只在失败时打印，避免淹没结果。
function Invoke-Step([string]$name, [scriptblock]$action) {
	$log = & $action 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0) {
		Write-Host "FAIL  $name" -ForegroundColor Red
		Write-Host $log.TrimEnd()
		$script:failed.Add($name)
	} else {
		Write-Host "ok    $name"
		$script:passed++
	}
}

# ---- 包检查：自动发现 core/ 与 kit/ 下所有包，包括没有测试的包 ----
$packageFiles = Get-ChildItem -Path core, kit -Recurse -Filter '*.odin'
$packageDirs = $packageFiles |
	ForEach-Object { $_.DirectoryName } |
	Sort-Object -Unique
foreach ($dir in $packageDirs) {
	$pkgPath = (Resolve-Path -Relative $dir).TrimStart('.', '\', '/') -replace '\\', '/'
	$pkgName = Split-Path -Leaf $dir
	Invoke-Step "check  $pkgPath" { odin check $pkgPath -collection:olib=. -no-entry-point -vet "-vet-packages:$pkgName" }
}

# ---- 单元测试：自动发现 core/ 与 kit/ 下含 @(test) 的包 ----
$testDirs = $packageFiles |
	Where-Object { Select-String -Path $_.FullName -Pattern '@\(test\)' -Quiet } |
	ForEach-Object { $_.DirectoryName } |
	Sort-Object -Unique
foreach ($dir in $testDirs) {
	# 脚本块按调用时作用域取变量：循环变量不能与 Invoke-Step 的参数同名
	$pkgPath = (Resolve-Path -Relative $dir).TrimStart('.', '\', '/') -replace '\\', '/'
	$pkgName = Split-Path -Leaf $dir
	$exeName = $pkgPath -replace '/', '_'
	Invoke-Step "test   $pkgPath" { odin test $pkgPath -collection:olib=. -vet "-vet-packages:$pkgName" "-out:$out/test_$exeName.exe" }
}

# ---- foster：包检查 + 自带回归程序编译 ----
# foster/ 的实际 package 声明为 foster_framework，vet 必须按包名选择。
Invoke-Step 'check  foster' { odin check foster -collection:olib=. -no-entry-point -vet -vet-packages:foster_framework }
foreach ($t in 'port_regression', 'graphics_regression', 'webtest') {
	Invoke-Step "build  foster/tests/$t" { odin build "foster/tests/$t" -collection:olib=. "-out:$out/$t.exe" }
}
Invoke-Step 'local  foster LOCAL_CHANGES' { powershell -NoProfile -ExecutionPolicy Bypass -File foster/tests/check_local_changes.ps1 }

# ---- thirdparty 中依赖 foster 的绑定示例 ----
Invoke-Step 'build  odin-imgui ofoster example' {
	odin build thirdparty/odin-imgui/examples/ofoster -collection:olib=. "-out:$out/imgui_ofoster.exe"
}

# ---- 同级示例仓库（存在时） ----
$samples = Join-Path (Split-Path -Parent $root) 'OFoster_Sample'
if (-not $NoSamples -and (Test-Path (Join-Path $samples 'src'))) {
	foreach ($s in Get-ChildItem -Directory (Join-Path $samples 'src')) {
		Invoke-Step "sample $($s.Name)" {
			odin build $s.FullName "-collection:olib=$root" "-out:$out/sample_$($s.Name).exe"
		}
	}
} elseif (-not $NoSamples) {
	Write-Host "skip   OFoster_Sample（未在 $samples 找到）"
}

Write-Host ''
if ($failed.Count -gt 0) {
	Write-Host "$($failed.Count) 项失败，$passed 项通过：" -ForegroundColor Red
	$failed | ForEach-Object { Write-Host "  $_" }
	exit 1
}
Write-Host "全部 $passed 项通过" -ForegroundColor Green
exit 0
