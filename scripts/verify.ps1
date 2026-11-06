# =========================================================
# verify.ps1 — 用无头浏览器验证镜像/改造后的站点真的渲染出来了
#
# 只看 HTTP 200 是不够的：JS 没跑起来时页面照样 200，但内容是空的。
# 这里用 dump-dom 抓渲染后的 DOM，断言关键节点数量。
#
# 用法:
#   pwsh -File scripts/verify.ps1 -Url http://127.0.0.1:5174/
#   pwsh -File scripts/verify.ps1 -Url http://127.0.0.1:5173/ -MinImages 6 -Width 390 -Height 844
# =========================================================
param(
  [Parameter(Mandatory = $true)][string]$Url,
  [int]$MinImages = 1,
  [int]$MinCards = 0,
  [int]$Width = 1440,
  [int]$Height = 7000,
  [int]$WaitMs = 7000,
  [string]$Chrome = ""
)

$ErrorActionPreference = "Stop"

if (-not $Chrome) {
  $cands = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
  )
  $Chrome = ($cands | Where-Object { Test-Path $_ } | Select-Object -First 1)
}
if (-not $Chrome) { throw "找不到 Chrome/Edge，请用 -Chrome 指定路径" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("verify-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".html")

& $Chrome --headless=new --disable-gpu --hide-scrollbars `
  --window-size="$Width,$Height" --virtual-time-budget=$WaitMs `
  --dump-dom $Url 2>$null | Out-File -FilePath $tmp -Encoding utf8

$dom = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
Remove-Item $tmp -ErrorAction SilentlyContinue

$checks = [ordered]@{}
$checks["DOM 长度"]      = $dom.Length
$checks["img 数量"]      = ([regex]::Matches($dom, "<img\b")).Count
$checks["html class"]    = [regex]::Match($dom, '<html[^>]*class="([^"]*)"').Groups[1].Value
$checks["body class"]    = [regex]::Match($dom, '<body[^>]*class="([^"]*)"').Groups[1].Value
$checks["卡片数量"]      = ([regex]::Matches($dom, 'class="[^"]*(?:card|item|row)\b')).Count

# 只在可见文本里找失败痕迹：<script>/<style> 里的源码会带 undefined/NaN，属于误报
$visible = [regex]::Replace($dom, '(?s)<script\b.*?</script>|<style\b.*?</style>|<!--.*?-->', '')
$visible = [regex]::Replace($visible, '(?s)<[^>]+>', ' ')
$checks["失败占位"]      = ([regex]::Matches($visible, '\bundefined\b|\bNaN\b|\[object Object\]')).Count

Write-Host "== 渲染结果 ==" -ForegroundColor Cyan
foreach ($k in $checks.Keys) {
  $v = $checks[$k]
  Write-Host ("  {0,-12} {1}" -f $k, $v)
}

$fail = @()
if ($dom.Length -lt 2000) { $fail += "DOM 太短，页面可能没渲染（或整站白屏）" }
if ($checks["img 数量"] -lt $MinImages) { $fail += "img 数量 $($checks['img 数量']) < 期望 $MinImages" }
if ($MinCards -gt 0 -and $checks["卡片数量"] -lt $MinCards) { $fail += "卡片数量 $($checks['卡片数量']) < 期望 $MinCards" }
if ($checks["失败占位"] -gt 0) { $fail += "DOM 里出现 undefined / NaN / [object Object]，说明取值失败" }

if ($fail.Count -eq 0) {
  Write-Host "`nPASS" -ForegroundColor Green
  exit 0
}
Write-Host "`nFAIL" -ForegroundColor Red
$fail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
exit 1
