# =========================================================
# mirror.ps1 — 把一个网站的资源抓到本地
#
#   1) 入口 HTML + link/script/img/srcset
#   2) CSS 里的 url() / @import / @font-face
#   3) 媒体层：video/audio/source/track + .mp4/.webm/.m3u8/.mp3/.vtt
#      媒体允许跨域（CDN 托管是常态：oss / 七牛 / 淘宝云视频…）
#   4) JS 里的 fetch() / "/api/..." 端点  -> 存成无扩展名文件
#   5) API 响应里的 /uploads/... 资源
#   6) 内联 JSON（Next.js __NEXT_DATA__ 等）里的媒体地址
#
# 用法:
#   powershell -File scripts/mirror.ps1 -Url https://example.com -OutDir ./mirror
#   powershell -File scripts/mirror.ps1 -Url https://example.com -OutDir ./mirror -SkipApi
#   powershell -File scripts/mirror.ps1 -Url https://example.com -OutDir ./mirror -MaxMediaMB 500
#   powershell -File scripts/mirror.ps1 -Url https://example.com -OutDir ./mirror -FollowPages
# =========================================================
param(
  [Parameter(Mandatory = $true)][string]$Url,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [int]$DelayMs = 900,
  [int]$MaxAssets = 800,
  [int]$MaxMediaMB = 200,
  [int]$MaxAssetMB = 30,
  [switch]$SkipApi,
  [switch]$SkipMedia,
  [switch]$FollowPages,
  [switch]$NoRewrite
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", $UA)

$base = [Uri]$Url
$origin = "$($base.Scheme)://$($base.Authority)"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 媒体扩展名：视频 / 音频 / 字幕 / 播放列表
$MEDIA_EXT = 'mp4|webm|ogv|mov|m4v|mkv|avi|mp3|wav|m4a|aac|ogg|flac|opus|m3u8|mpd|vtt|srt|ass'
$MEDIA_RE = "\.(?:$MEDIA_EXT)(?:\?|#|$)"
# 静态资源扩展名：命中这些才当资源下载，否则视为子页面
$RES_EXT = 'css|m?js|json|map|svg|png|jpe?g|gif|webp|avif|ico|bmp|woff2?|ttf|otf|eot|txt|xml|webmanifest|pdf'

$stats = @{ html = 0; asset = 0; api = 0; image = 0; media = 0; failed = 0; skipped = 0; oversize = 0; pages = 0 }
$seen = New-Object System.Collections.Generic.HashSet[string]
$bigFiles = New-Object System.Collections.Generic.List[string]
$streams = New-Object System.Collections.Generic.List[string]
# 原始绝对地址 -> 本地根相对路径，最后一步用来重写引用
$urlMap = @{}

function Resolve-Url([string]$rel) {
  if ([string]::IsNullOrWhiteSpace($rel)) { return $null }
  $rel = $rel.Trim()
  if ($rel.StartsWith("#") -or $rel.StartsWith("data:") -or $rel.StartsWith("blob:") -or
      $rel.StartsWith("javascript:") -or $rel.StartsWith("mailto:")) { return $null }
  try { return (New-Object Uri($base, $rel)).AbsoluteUri } catch { return $null }
}

# 以「引用所在文件的 URL」为基准解析相对路径。
# CSS 里的 url('../fonts/a.woff2') 是相对 CSS 文件自身，不是站点根——搞错会把路径解析歪。
function Resolve-UrlFrom([string]$rel, [string]$fromUrl) {
  if ([string]::IsNullOrWhiteSpace($rel)) { return $null }
  $rel = $rel.Trim()
  if ($rel.StartsWith("#") -or $rel.StartsWith("data:") -or $rel.StartsWith("blob:") -or
      $rel.StartsWith("javascript:") -or $rel.StartsWith("mailto:")) { return $null }
  if ($rel -match '^(?:https?:)?//') { return (Resolve-Url $rel) }
  if (-not $fromUrl) { return (Resolve-Url $rel) }
  try { return (New-Object Uri((New-Object Uri($fromUrl)), $rel)).AbsoluteUri } catch { return (Resolve-Url $rel) }
}

function Test-SameOrigin([string]$abs) {
  try { $u = [Uri]$abs; return ($u.Authority -eq $base.Authority) } catch { return $false }
}

function Get-RelPath([string]$abs) {
  $u = [Uri]$abs
  $p = $u.AbsolutePath.TrimStart("/")
  if ([string]::IsNullOrWhiteSpace($p)) { $p = "index.html" }
  if ($p.EndsWith("/")) { $p = $p + "index.html" }
  return ($p -replace "/", "\")
}

function Get-RemoteLength([string]$abs) {
  try {
    $req = [System.Net.WebRequest]::Create($abs)
    $req.Method = "HEAD"
    $req.UserAgent = $UA
    $req.Timeout = 15000
    $resp = $req.GetResponse()
    $len = $resp.ContentLength
    $resp.Close()
    return $len
  } catch { return -1 }
}

function Save-Asset([string]$abs, [switch]$StripExt) {
  $isMedia = $abs -match $MEDIA_RE
  $sameOrigin = Test-SameOrigin $abs

  # 媒体允许跨域（CDN 托管是常态）；非媒体资源仍限同域
  if (-not $sameOrigin -and -not $isMedia) { $script:stats.skipped++; return $null }
  if ($seen.Contains($abs)) { return $null }
  [void]$seen.Add($abs)
  if ($seen.Count -gt $MaxAssets) { return $null }

  $rel = Get-RelPath $abs
  if ($StripExt) {
    # API 端点：存成无扩展名文件，静态服务器才能按原路径响应 fetch()
    $rel = (Get-RelPath $abs) -replace "\.(json|php|aspx?)$", ""
  }
  # 跨域资源按 host 分目录，避免同名互相覆盖
  if (-not $sameOrigin) {
    $hostPart = ([Uri]$abs).Host -replace "[^\w\.\-]", "_"
    $rel = "_ext\$hostPart\$rel"
  }
  $dest = Join-Path $OutDir $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null

  # 体积保护：媒体用 MaxMediaMB，其他资源用 MaxAssetMB
  $limitMB = if ($isMedia) { $MaxMediaMB } else { $MaxAssetMB }
  if ($isMedia -and $SkipMedia) { $script:stats.skipped++; return $null }
  if ($isMedia -and $abs -match '\.(m3u8|mpd)(\?|$)') { [void]$streams.Add($abs) }

  $len = Get-RemoteLength $abs
  if ($len -gt ($limitMB * 1MB)) {
    $script:stats.oversize++
    $script:bigFiles.Add(("{0}  ({1:N1} MB)" -f $abs, ($len / 1MB)))
    Write-Host ("  SKIP 过大 {0:N1} MB  {1}" -f ($len / 1MB), $abs) -ForegroundColor DarkYellow
    return $null
  }

  try {
    $bytes = $wc.DownloadData($abs)
    [System.IO.File]::WriteAllBytes($dest, $bytes)
    # 记下映射：原地址 -> 本地根相对路径（供最后重写引用）
    $script:urlMap[$abs] = "/" + ($rel -replace "\\", "/")
    Start-Sleep -Milliseconds $DelayMs
    return [pscustomobject]@{ Path = $rel; Bytes = $bytes; Url = $abs }
  } catch {
    $script:stats.failed++
    Write-Host ("  ERR  {0}" -f $abs) -ForegroundColor DarkYellow
    return $null
  }
}

function Decode([byte[]]$bytes) {
  return [System.Text.Encoding]::UTF8.GetString($bytes)
}

# 从任意文本里挖媒体 URL（HTML/CSS/JS/JSON 通用，含跨域绝对地址）
function Get-MediaRefs([string]$text) {
  $out = New-Object System.Collections.Generic.List[string]
  $pattern = '["''(]\s*((?:https?://|/|\./|\.\./)[^"''\s\)]+?\.(?:' + $MEDIA_EXT + ')(?:\?[^"''\s\)]*)?)["''\)\s]'
  foreach ($m in [regex]::Matches($text, $pattern)) { $out.Add($m.Groups[1].Value) }
  return $out
}

# 是否是应该下载的资源（否则视为子页面）
function Test-IsResource([string]$abs) {
  if ($abs -match $MEDIA_RE) { return $true }
  return ($abs -match "\.(?:$RES_EXT)(?:\?|#|$)")
}

# ------------------------- 1. 入口 HTML -------------------------
Write-Host "== 1/6 抓入口 HTML" -ForegroundColor Cyan
$htmlBytes = $wc.DownloadData($base.AbsoluteUri)
[System.IO.File]::WriteAllBytes((Join-Path $OutDir "index.html"), $htmlBytes)
$html = Decode $htmlBytes
$stats.html++
Write-Host ("  index.html  {0} KB" -f [math]::Round($htmlBytes.Length / 1KB, 1))

# ------------------------- 2. 静态资源与媒体 -------------------------
Write-Host "== 2/6 抓静态资源与媒体" -ForegroundColor Cyan

$refs = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches($html, '(?:href|src|data-src|poster|data-poster|data-video|data-src|data-url|data-srcset)="([^"]+)"')) { $refs.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($html, 'srcset="([^"]+)"')) {
  foreach ($part in ($m.Groups[1].Value -split ",")) { $refs.Add(($part.Trim() -split "\s+")[0]) }
}
# 内联 style 与 <style> 里的 url()
foreach ($m in [regex]::Matches($html, 'url\(\s*[''"]?([^''")]+)')) { $refs.Add($m.Groups[1].Value) }
# 内联 JSON 与 <script> 里出现的媒体（可跨域）
foreach ($v in (Get-MediaRefs $html)) { $refs.Add($v) }

$assets = @()
foreach ($r in $refs) {
  $abs = Resolve-Url $r
  if (-not $abs) { continue }
  if ($abs -match "/cdn-cgi/") { continue }   # Cloudflare 注入，跳过
  if (-not (Test-IsResource $abs)) {
    # 子页面（/blog/ 之类）：默认不抓，避免顺着导航把整站拖下来
    if ($FollowPages) { $assets += $abs; $stats.pages++ }
    continue
  }
  if (-not (Test-SameOrigin $abs) -and -not ($abs -match $MEDIA_RE)) { continue }
  $assets += $abs
}
$assets = $assets | Sort-Object -Unique

$cssFiles = @()
$jsFiles = @()
foreach ($abs in $assets) {
  $saved = Save-Asset $abs
  if ($saved) {
    if ($abs -match $MEDIA_RE) { $stats.media++ } else { $stats.asset++ }
    if ($abs -match "\.css(\?|$)") { $cssFiles += $saved }
    if ($abs -match "\.m?js(\?|$)") { $jsFiles += $saved }
  }
}
Write-Host ("  资源 {0} / 媒体 {1} / 子页面 {2}" -f $stats.asset, $stats.media, $stats.pages)

# CSS 里的 url() / @import / 媒体
foreach ($css in $cssFiles) {
  $txt = [System.IO.File]::ReadAllText((Join-Path $OutDir $css.Path), [System.Text.Encoding]::UTF8)
  $inner = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($txt, 'url\(\s*[''"]?([^''")]+)')) { $inner.Add($m.Groups[1].Value) }
  foreach ($m in [regex]::Matches($txt, '@import\s+(?:url\()?[''"]([^''"]+)')) { $inner.Add($m.Groups[1].Value) }
  foreach ($v in (Get-MediaRefs $txt)) { $inner.Add($v) }
  foreach ($r in $inner) {
    $abs = Resolve-UrlFrom $r $css.Url
    if (-not $abs) { continue }
    if (-not (Test-SameOrigin $abs) -and -not ($abs -match $MEDIA_RE)) { continue }
    $saved = Save-Asset $abs
    if ($saved) { if ($abs -match $MEDIA_RE) { $stats.media++ } else { $stats.asset++ } }
  }
}

# JS 里硬编码的媒体路径（video.js 这类常见写法，且往往指向 CDN）
if (-not $SkipMedia) {
  foreach ($js in $jsFiles) {
    $txt = [System.IO.File]::ReadAllText((Join-Path $OutDir $js.Path), [System.Text.Encoding]::UTF8)
    foreach ($r in (Get-MediaRefs $txt)) {
      $abs = Resolve-UrlFrom $r $js.Url
      if (-not $abs) { continue }
      $saved = Save-Asset $abs
      if ($saved) { $stats.media++ }
    }
  }
}

Write-Host ("  静态 {0} / 媒体 {1} / 失败 {2} / 外域跳过 {3} / 超大跳过 {4}" -f `
  $stats.asset, $stats.media, $stats.failed, $stats.skipped, $stats.oversize)

# ------------------------- 3. API 端点 -------------------------
if (-not $SkipApi) {
  Write-Host "== 3/6 抓 API 端点（这一层决定页面是否有内容）" -ForegroundColor Cyan

  $jsText = $html
  foreach ($f in (Get-ChildItem $OutDir -Recurse -Filter *.js -ErrorAction SilentlyContinue)) {
    $jsText += "`n" + [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  }

  $endpoints = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($jsText, '[''"]((?:/api|/v\d|/graphql|/wp-json)[A-Za-z0-9_\-/\.]*)[''"]')) {
    [void]$endpoints.Add($m.Groups[1].Value)
  }
  foreach ($m in [regex]::Matches($jsText, 'fetch\(\s*[''"]/api/([A-Za-z0-9_\-/\.]+)')) {
    [void]$endpoints.Add("/api/" + $m.Groups[1].Value)
  }

  $apiBodies = @()
  foreach ($ep in $endpoints) {
    $abs = "$origin$ep"
    $saved = Save-Asset $abs -StripExt
    if ($saved) {
      $stats.api++
      $apiBodies += (Decode $saved.Bytes)
      Write-Host ("  api {0,-38} {1} KB" -f $ep, [math]::Round($saved.Bytes.Length / 1KB, 1))
    }
  }

  # ------------------------- 4. API 里引用的资源 -------------------------
  Write-Host "== 4/6 抓 API 里引用的资源（图片 / 视频）" -ForegroundColor Cyan
  $mediaPaths = New-Object System.Collections.Generic.HashSet[string]
  foreach ($body in $apiBodies) {
    foreach ($m in [regex]::Matches($body, '"(/(?:uploads|media|images|img|files|assets|static|video|videos|audio|cdn)/[^"]+)"')) {
      [void]$mediaPaths.Add($m.Groups[1].Value)
    }
    foreach ($v in (Get-MediaRefs $body)) { [void]$mediaPaths.Add($v) }
  }
  foreach ($p in $mediaPaths) {
    $abs = Resolve-Url $p
    if (-not $abs) { continue }
    $saved = Save-Asset $abs
    if ($saved) {
      if ($abs -match $MEDIA_RE) { $stats.media++ } else { $stats.image++ }
    }
  }
  Write-Host ("  图片/文件 {0} 个" -f $stats.image)
} else {
  Write-Host "== 3-4/6 跳过 API（-SkipApi）" -ForegroundColor DarkGray
}

# ------------------------- 5. 重写引用 -------------------------
Write-Host "== 5/6 重写引用（把外链指向本地副本）" -ForegroundColor Cyan

if ($NoRewrite) {
  Write-Host "  跳过（-NoRewrite）" -ForegroundColor DarkGray
} elseif ($urlMap.Count -eq 0) {
  Write-Host "  无需重写" -ForegroundColor DarkGray
} else {
  $textExts = @(".html", ".htm", ".css", ".js", ".mjs", ".json")
  $rewritten = 0
  $hitCount = 0
  foreach ($file in (Get-ChildItem $OutDir -Recurse -File | Where-Object { $textExts -contains $_.Extension.ToLower() })) {
    if ($file.Name -in @("_manifest.json", "_skipped-media.txt")) { continue }
    $txt = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $before = $txt
    # 长的先替换，避免短地址是长地址前缀时截断
    foreach ($k in ($urlMap.Keys | Sort-Object -Property Length -Descending)) {
      if ($txt.Contains($k)) {
        $hitCount += ([regex]::Matches($txt, [regex]::Escape($k))).Count
        $txt = $txt.Replace($k, $urlMap[$k])
      }
    }
    if ($txt -ne $before) {
      [System.IO.File]::WriteAllText($file.FullName, $txt, (New-Object System.Text.UTF8Encoding($false)))
      $rewritten++
    }
  }
  Write-Host ("  重写 {0} 个文件，替换 {1} 处外链" -f $rewritten, $hitCount)
}

# ------------------------- 提示 -------------------------

if ($streams.Count -gt 0) {
  Write-Host "  检测到流媒体播放列表（只能拿到索引，分片 .ts/.m4s 需另外拉）：" -ForegroundColor Yellow
  $streams | Sort-Object -Unique | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor Yellow }
}

if ($bigFiles.Count -gt 0) {
  Write-Host ("  以下文件超过体积上限未下载（媒体 -MaxMediaMB={0}，其他 -MaxAssetMB={1}）：" -f $MaxMediaMB, $MaxAssetMB) -ForegroundColor Yellow
  $bigFiles | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor Yellow }
  $bigFiles | Set-Content -Path (Join-Path $OutDir "_skipped-media.txt") -Encoding UTF8
}

if ($stats.media -eq 0 -and -not $SkipMedia) {
  Write-Host "  未发现媒体文件。若页面确实有视频，可能是签名地址或 m3u8，见 references/troubleshooting.md" -ForegroundColor DarkGray
}

# ------------------------- 6. 清单 -------------------------
Write-Host "== 6/6 清单" -ForegroundColor Cyan

$manifest = Get-ChildItem $OutDir -Recurse -File | ForEach-Object {
  [pscustomobject]@{
    path = $_.FullName.Replace((Resolve-Path $OutDir).Path + "\", "") -replace "\\", "/"
    kb   = [math]::Round($_.Length / 1KB, 1)
  }
}
$manifest | ConvertTo-Json | Set-Content -Path (Join-Path $OutDir "_manifest.json") -Encoding UTF8

$totalMB = [math]::Round((($manifest | Measure-Object kb -Sum).Sum) / 1024, 1)
Write-Host ""
Write-Host ("完成：HTML {0} / 静态 {1} / API {2} / 图片 {3} / 媒体 {4} / 失败 {5} / 共 {6} MB" -f `
  $stats.html, $stats.asset, $stats.api, $stats.image, $stats.media, $stats.failed, $totalMB) -ForegroundColor Green
Write-Host "下一步：python scripts/serve.py --root $OutDir --port 5174" -ForegroundColor Green
