# 校验 foster 代码中的 [olib L-xxx] 标记与 docs/LOCAL_CHANGES.md 清单一一对应。
# 用法（任意目录）：powershell -File foster/tests/check_local_changes.ps1
# 退出码：0 一致；1 不一致。

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$fosterRoot = Split-Path -Parent $PSScriptRoot
$docPath = Join-Path $fosterRoot 'docs/LOCAL_CHANGES.md'

# 清单中的编号：表格行首列形如 "| L-001 |"
$docIds = @{}
foreach ($line in Get-Content -Encoding UTF8 $docPath) {
	if ($line -match '^\|\s*(L-\d{3})\s*\|') {
		$id = $Matches[1]
		if ($docIds.ContainsKey($id)) {
			Write-Host "清单中编号重复: $id"
			exit 1
		}
		$docIds[$id] = $true
	}
}

# 代码中的标记
$codeIds = @{}
Get-ChildItem -Path $fosterRoot -Recurse -Filter '*.odin' | ForEach-Object {
	$file = $_
	$n = 0
	foreach ($line in Get-Content -Encoding UTF8 $file.FullName) {
		$n++
		foreach ($m in [regex]::Matches($line, '\[olib (L-\d{3})\]')) {
			$id = $m.Groups[1].Value
			if (-not $codeIds.ContainsKey($id)) { $codeIds[$id] = @() }
			$rel = $file.FullName.Substring($fosterRoot.Length + 1)
			$codeIds[$id] += "${rel}:$n"
		}
	}
}

$ok = $true
foreach ($id in ($codeIds.Keys | Sort-Object)) {
	if (-not $docIds.ContainsKey($id)) {
		Write-Host "代码有标记但清单缺少 ${id}: $($codeIds[$id] -join ', ')"
		$ok = $false
	}
}
foreach ($id in ($docIds.Keys | Sort-Object)) {
	if (-not $codeIds.ContainsKey($id)) {
		Write-Host "清单有记录但代码中找不到标记: $id"
		$ok = $false
	}
}

if (-not $ok) { exit 1 }
Write-Host "本地修改标记一致：$($docIds.Count) 条记录"
exit 0
