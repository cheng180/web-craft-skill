# =========================================================
# install.ps1 — 把 web-craft-skill 装到本机的各个 AI agent
#
# 各 agent 的 skills 目录约定（实测/官方文档）：
#   claude    ~/.claude/skills/<name>/SKILL.md      用户级，所有项目
#   agents    ~/.agents/skills/<name>/SKILL.md      Agent Skills 通用用户根
#   codex     $CODEX_HOME/skills/<name>             默认 ~/.codex/skills
#   reasonix  %APPDATA%\reasonix\skills\<name>      Reasonix 自有目录
#   project   <root>\.claude\skills + <root>\.agents\skills   项目级（可提交）
#
# 用法:
#   powershell -File scripts/install.ps1
#   powershell -File scripts/install.ps1 -Targets claude,codex
#   powershell -File scripts/install.ps1 -Targets project -ProjectRoot D:\my-site
#   powershell -File scripts/install.ps1 -Link          # 用符号链接，改一处全生效
# =========================================================
param(
  [ValidateSet("claude", "agents", "codex", "reasonix", "project")]
  [string[]]$Targets = @("claude", "agents", "reasonix"),
  [string]$ProjectRoot = "",
  [switch]$Link,
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$SkillName = "web-craft-skill"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Test-Path (Join-Path $Source "SKILL.md"))) {
  throw "找不到 SKILL.md，Source 是否正确？当前：$Source"
}

function Get-SkillRoot([string]$Target) {
  switch ($Target) {
    "claude"   { return (Join-Path $env:USERPROFILE ".claude\skills") }
    "agents"   { return (Join-Path $env:USERPROFILE ".agents\skills") }
    "codex"    { $home2 = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }; return (Join-Path $home2 "skills") }
    "reasonix" { return (Join-Path $env:APPDATA "reasonix\skills") }
    "project"  { return "" }
    default    { throw "未知目标: $Target" }
  }
}

function Install-One([string]$Dest) {
  if (Test-Path $Dest) {
    if (-not $Force) {
      return [pscustomobject]@{ Path = $Dest; Status = "已存在（加 -Force 覆盖）" }
    }
    Remove-Item -Recurse -Force $Dest
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null

  if ($Link) {
    try {
      New-Item -ItemType SymbolicLink -Path $Dest -Target $Source | Out-Null
      return [pscustomobject]@{ Path = $Dest; Status = "符号链接" }
    } catch {
      # 没有开发者模式/管理员权限时回退到复制
    }
  }

  Copy-Item -Recurse $Source $Dest
  Remove-Item -Recurse -Force (Join-Path $Dest ".git") -ErrorAction SilentlyContinue
  Get-ChildItem $Dest -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  return [pscustomobject]@{ Path = $Dest; Status = "已复制" }
}

$results = @()

foreach ($t in $Targets) {
  if ($t -eq "project") {
    if (-not $ProjectRoot) {
      $results += [pscustomobject]@{ Path = "(跳过 project：需要 -ProjectRoot)"; Status = "跳过" }
      continue
    }
    $root = (Resolve-Path $ProjectRoot).Path
    foreach ($sub in @(".claude\skills", ".agents\skills")) {
      $results += Install-One (Join-Path $root (Join-Path $sub $SkillName))
    }
    continue
  }

  $skillsRoot = Get-SkillRoot $t
  $results += Install-One (Join-Path $skillsRoot $SkillName)
}

Write-Host ""
Write-Host "== $SkillName 安装结果 ==" -ForegroundColor Cyan
$results | ForEach-Object {
  $color = if ($_.Status -like "已*") { "Green" } else { "Yellow" }
  Write-Host ("  [{0,-22}] {1}" -f $_.Status, $_.Path) -ForegroundColor $color
}

# 校验 frontmatter
Write-Host ""
$skillMd = Join-Path $Source "SKILL.md"
$head = [System.IO.File]::ReadAllLines($skillMd, [System.Text.Encoding]::UTF8) | Select-Object -First 5
if (($head -join "`n") -match "name:\s*$SkillName") {
  Write-Host "frontmatter OK: name=$SkillName" -ForegroundColor Green
} else {
  Write-Host "警告：SKILL.md frontmatter 的 name 与目录名不一致，部分 agent 会忽略该技能" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "下一步：" -ForegroundColor Cyan
Write-Host "  Claude Code : 重启会话后执行 /skills 查看，或直接说“用 web-craft-skill 把某站镜像下来”"
Write-Host "  Codex       : 重启后 /skills 查看，用 `$web-craft-skill 显式调用"
Write-Host "  Reasonix    : 直接说触发词即可，如“照着这个网站做一个”"
