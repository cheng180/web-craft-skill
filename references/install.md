# 安装到各个 AI agent

> Skill 的本质就是一个目录：`<skills 根>/<名字>/SKILL.md`。
> 目录名必须和 `SKILL.md` 里 `name:` 字段一致，否则部分 agent 会静默忽略。
> **sk‍ills 目录下直接丢一个裸 `.md` 文件是无效的。**

---

## 0. 最快的方式：让 agent 自己装

把下面这段整个粘给 Codex / Claude Code / Reasonix，它会把剩下的事做完：

```text
请把这个 skill 安装到本机：
仓库 https://github.com/cheng180/web-craft-skill ，skill 名 web-craft-skill 。

要求：
1. 克隆或下载到临时目录，确认里面是 SKILL.md + scripts/ + references/ 的目录结构。
2. 复制到当前宿主对应的 skills 目录，目录名必须是 web-craft-skill：
   - Claude Code: ~/.claude/skills/web-craft-skill
   - Codex:       ${CODEX_HOME:-~/.codex}/skills/web-craft-skill
                  （同时复制一份到 ~/.agents/skills/web-craft-skill 兼容新版发现机制）
   - 其他遵循 Agent Skills 规范的宿主: ~/.agents/skills/web-craft-skill
3. 不要修改 SKILL.md 内容，不要动 scripts/ 里的文件。
4. 装完执行 `ls <目标目录>` 和 `head -5 <目标目录>/SKILL.md`，
   把路径和 frontmatter（name/description）贴给我确认。
5. 如果目标目录已存在，先告诉我，不要直接覆盖。
```

已经有本仓库副本时，直接用仓库自带脚本（Windows）：

```powershell
powershell -File scripts/install.ps1                    # 装 claude + agents + reasonix
powershell -File scripts/install.ps1 -Targets claude,codex
powershell -File scripts/install.ps1 -Link              # 符号链接，git pull 后全局生效
powershell -File scripts/install.ps1 -Targets project -ProjectRoot D:\my-site
```

macOS / Linux 没有这个脚本，用第 2 节的复制命令即可。

---

## 1. 各宿主读哪里

| 宿主 | 用户级路径 | 项目级路径 | 说明 |
|---|---|---|---|
| **Claude Code** | `~/.claude/skills/<name>/SKILL.md` | `<repo>/.claude/skills/<name>/` | 项目级可提交给团队共享 |
| **Codex**（官方文档） | `~/.agents/skills/<name>/` | `<repo>/.agents/skills/<name>/` | 从 CWD 向上找到 repo root |
| **Codex**（官方 skill-installer 实际写入） | `${CODEX_HOME:-~/.codex}/skills/<name>/` | — | 与上一条并存，建议两边都放或做链接 |
| **Reasonix** | `%APPDATA%\reasonix\skills\` 和 `~/.claude/skills/` | `<repo>/.claude/skills/` | 本机实测两个目录都会被扫描 |
| **通用（Agent Skills 规范）** | `~/.agents/skills/` | `<repo>/.agents/skills/` | 越来越多宿主认这个 |

同名 skill 在多处存在时**不会合并**，会各出现一次。想只维护一份，用符号链接。

---

## 2. 手动安装

### macOS / Linux

```bash
git clone https://github.com/cheng180/web-craft-skill.git /tmp/stm
mkdir -p ~/.claude/skills ~/.agents/skills ~/.codex/skills
cp -r /tmp/stm ~/.claude/skills/web-craft-skill
cp -r /tmp/stm ~/.agents/skills/web-craft-skill
cp -r /tmp/stm ~/.codex/skills/web-craft-skill     # Codex
rm -rf ~/.claude/skills/web-craft-skill/.git
```

符号链接版（改一处，所有宿主同步）：

```bash
git clone https://github.com/cheng180/web-craft-skill.git ~/skills/web-craft-skill
ln -s ~/skills/web-craft-skill ~/.claude/skills/web-craft-skill
ln -s ~/skills/web-craft-skill ~/.agents/skills/web-craft-skill
ln -s ~/skills/web-craft-skill ~/.codex/skills/web-craft-skill
```

### Windows

```powershell
git clone https://github.com/cheng180/web-craft-skill.git $env:TEMP\stm
Copy-Item -Recurse $env:TEMP\stm "$env:USERPROFILE\.claude\skills\web-craft-skill"
Copy-Item -Recurse $env:TEMP\stm "$env:USERPROFILE\.agents\skills\web-craft-skill"
Copy-Item -Recurse $env:TEMP\stm "$env:USERPROFILE\.codex\skills\web-craft-skill"
Remove-Item -Recurse "$env:USERPROFILE\.claude\skills\web-craft-skill\.git"
```

> 用 `scripts/install.ps1` 更省事，它会自动处理 `CODEX_HOME`、跳过 `.git`/`__pycache__`、校验 frontmatter。

### 项目级（跟仓库一起提交，团队共享）

```bash
mkdir -p .claude/skills
git clone https://github.com/cheng180/web-craft-skill.git .claude/skills/web-craft-skill
rm -rf .claude/skills/web-craft-skill/.git
```

---

## 3. Claude Code 的 marketplace 方式（适合长期分发）

Claude Code 支持把仓库做成 plugin marketplace，一条命令装：

```
/plugin marketplace add cheng180/web-craft-skill
/plugin install web-craft-skill@<marketplace-name>
```

前提是仓库根目录加 `.claude-plugin/marketplace.json`：

```json
{
  "name": "web-craft-skill",
  "owner": { "name": "cheng" },
  "plugins": [
    {
      "name": "web-craft-skill",
      "source": "./",
      "description": "镜像现有网站并在其代码上定点改造的 skill"
    }
  ]
}
```

注意 `@` 后面跟的是 marketplace 的 **name 字段**，不是 GitHub 仓库名。

---

## 4. Codex 的两种原生方式

**会话内安装器**（需要该 Codex 装过 `skill-installer`）：

```
$skill-installer https://github.com/cheng180/web-craft-skill
```

**官方脚本**：

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo cheng180/web-craft-skill --path .
```

它会拒绝覆盖已存在的目录——想更新就先删。

禁用某个 skill 而不删除，写 `~/.codex/config.toml`：

```toml
[[skills.config]]
path = "/home/you/.codex/skills/web-craft-skill/SKILL.md"
enabled = false
```

---

## 5. 第三方通用 CLI

```bash
npx skills add cheng180/web-craft-skill -a codex        # Vercel Labs skills CLI
npx skills add cheng180/web-craft-skill -g              # 装到全局并按宿主做链接
npx ai-agent-skills install cheng180/web-craft-skill    # 默认 ~/.claude/skills
```

这类工具底层都是"复制或软链到各宿主的 skills 目录"，行为可预期。

---

## 6. 验证

| 宿主 | 怎么确认装上了 |
|---|---|
| Claude Code | 重启会话 → `/skills` 或 `/doctor`；直接说"用 web-craft-skill 把 example.com 镜像下来" |
| Codex | 重启 → `/skills` 查看列表；用 `$web-craft-skill` 显式调用 |
| Reasonix | 直接说触发词；或看 catalog 里是否出现 `skill:web-craft-skill` |
| 通用 | `ls <skills 根>/web-craft-skill`，`head -5 SKILL.md` 看 frontmatter |

**新增顶层 skill 目录需要重启会话**；已存在 skill 的正文改动通常是热生效的。

---

## 7. 排错

| 现象 | 原因 |
|---|---|
| 列表里看不到 | 目录名和 `name:` 不一致；或放成了裸 `.md` 文件；或没重启 |
| Codex 看不到但 Claude 能看到 | Codex 可能只读 `~/.agents/skills` 或 `${CODEX_HOME}/skills`，两个都放一份 |
| 触发不到 | `description` 里没有用户实际会说的词，补上触发短语 |
| Windows 下脚本乱码/语法报错 | `.ps1` 必须存成 **UTF-8 with BOM**，PS 5.1 会按 ANSI 读无 BOM 文件 |
| 符号链接失效 | Windows 需要开发者模式或管理员权限；失败时改用复制 |

---

## 8. 安全提醒

Skill 里的 `scripts/*.ps1`、`*.py` 会被 agent 直接执行。
装第三方 skill 之前先读一遍 `SKILL.md` 和脚本；本仓库的三个脚本只做**网络抓取、本地静态服务、无头浏览器验证**，
不写注册表、不读凭证、不发起后台常驻进程。
