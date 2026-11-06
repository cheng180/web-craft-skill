# 精美网页制作 skill

> 别再让 AI 从一张白纸开始画页面了。**给它一个链接。**

`web-craft-skill` · 一个把现成网站整套搬到本地、再按你的意思改的 skill。

---

## 先说清楚现在的问题

现在的"AI 生成网站"skill，流程几乎都一样：你描述需求 → 它从空白文件开始写。

结果也很统一：

- 配色像 Bootstrap 默认值，或者满屏渐变紫
- 间距全靠猜，没有排版节奏
- 动效只会 `fade-in` 和 `hover: scale(1.05)`
- 字体是系统默认，层级靠字号硬拉
- 一眼看过去就知道：**这是 AI 做的**

行业里管这个叫「AI 味」。它不是你提示词写得不好，而是——
**你想要的那些细节，本来就是设计师调了几十遍的结果。**
滚动视差的速度、卡片 hover 倾斜的角度、缓动曲线的回弹感、留白的呼吸感……
让模型从零"想象"出来，它做不到；让它**在现成代码上改**，它做得到。

## 所以这个 skill 只做一件事

**把你觉得好看的那个网站，整个搬到本地，然后在你指定的地方改。**

你只要给我一个链接：

```
https://你喜欢的那个网站
```

剩下的事：

1. 把它的 HTML / CSS / JS / 图片 / **视频音频字幕** / 字体 / 接口数据 全部抓到本地
2. 启动起来给你看，和原站并排对照
3. 按你的要求改——品牌名、文案、配图、配色、栏目结构
4. 部署前跑一遍验收，无 404、无白屏、手机端不塌

**视觉底子是别人做好的，你只是换成自己的东西。** 这就是"精美"的来源。

---

## 它抓什么

大多数同类工具只抓第一层，所以经常出现"这网站明明有图，抓下来一片空白"。
这里把资源分成六层，全部覆盖：

| 层 | 内容 | 漏了会怎样 |
|---|---|---|
| 1 | 入口 HTML、`<link>`、`<script>`、`<img>`、`srcset` | 缺样式、缺交互 |
| 2 | CSS 里的 `url()`、`@import`、`@font-face` | 缺字体、缺背景图 |
| 3 | **媒体层**：`<video>`、`<audio>`、`<source>`、`<track>`、`.mp4/.webm/.m3u8/.mp3/.vtt` | 视频区黑屏 |
| 4 | **JS 里的 `fetch('/api/...')`** | 列表、画廊、文章全空 |
| 5 | API 返回的 `/uploads/` 图片与视频 | 有卡片没图 |
| 6 | 内联 JSON（Next.js `__NEXT_DATA__` 之类）里的媒体地址 | 首屏视频加载不出 |

关于视频：

- `.mp4/.webm` 等直接下载，超过 `-MaxMediaMB`（默认 200MB）的会跳过并列进 `_skipped-media.txt`，不会闷头把几个 G 拉下来
- `.m3u8/.mpd` 是流媒体索引，能抓到播放列表但拿不到分片（`.ts/.m4s`），会明确提示你
- `.vtt/.srt` 字幕、`poster` 封面一起抓
- 运行时由 JS 拼接出来的视频地址抓不到（比如带签名的 CDN 链接），这种情况会在结尾提示

## 实测一次给你看

拿 `https://agentscope.io/` 当靶子跑一遍（一个带背景视频的官方站点）：

```
== 2/6 抓静态资源与媒体
  静态 11 / 媒体 5 / 失败 0 / 外域跳过 0 / 超大跳过 0
== 5/6 重写引用（把外链指向本地副本）
  重写 1 个文件，替换 5 处外链

完成：HTML 1 / 静态 11 / API 0 / 图片 0 / 媒体 5 / 失败 0 / 共 26.7 MB
```

抓到了什么：

- 11 个资源：主 CSS（44.6 KB）、5 个 JS、logo、6 MB 的生态图 SVG、**3 个字体（89 KB）**
- **5 个视频**（合计 20.6 MB）——它们放在 `cloud.video.taobao.com`，跟主站不同域，
  按"同域"规则会被整批漏掉；脚本允许媒体跨域，落到 `_ext/<host>/` 下
- `video.js` 里写死的 CDN 绝对地址被批量替换成 `/_ext/cloud.video.taobao.com/vod/...`，
  所以离线打开照样能播，不再回源
- 3 个字体在 `assets/fonts/` —— 注意 CSS 里写的是 `url('../fonts/x.woff2')`，
  **相对 CSS 文件自身解析**，不是站点根。按站点根解析会得到一个干净的 404，
  很容易误判成"源站就没部署字体"

启动后验证：DOM 177 KB、33 张图、49 个卡片块，`verify.ps1` 通过；
视频以 `video/mp4` 返回，渲染后的 `<video>` 的 `src` 指向本地路径并自动播放。

## 本地启动对照

```bash
python scripts/serve.py --root ./mirror --port 5174
```

比 `python -m http.server` 多三件事：补 `.webp/.avif/.mjs/.woff2` 的 MIME、
把无扩展名的 `/api/xxx` 当 JSON 返回、可选 SPA fallback。

镜像站和你的站两个端口一起开着，**并排看**，哪里不像当场说，我当场改。

---

## 用法

装好之后，正常说话就行：

```
照着 https://example.com 做一个，把品牌换成我的，配色改成深色
```

```
把这个站扒下来，文字和图片换成我的，其他都不要动
```

```
在它的代码上改，别重写。就改文案
```

触发词：**照这个网站做一个 / 把这个站弄下来改 / 要这个前端模板别凭空生成 /
在它的代码上改别重写 / 改一下这个站的颜色**。

## 安装

Skill 就是一个目录：`<skills 根>/web-craft-skill/SKILL.md`。
目录名必须和 `name:` 字段一致，往 skills 目录里丢一个裸 `.md` 是无效的。

### 最快：让 agent 自己装

把仓库地址丢给它：

```text
请把这个 skill 安装到本机：https://github.com/cheng180/web-craft-skill
skill 名 web-craft-skill。复制到宿主对应的 skills 目录：
  Claude Code → ~/.claude/skills/web-craft-skill
  Codex       → ${CODEX_HOME:-~/.codex}/skills/web-craft-skill
                以及 ~/.agents/skills/web-craft-skill
装完 ls 目标目录并 head -5 SKILL.md 给我确认。已存在就先问我，别覆盖。
```

### Windows 一键

```powershell
powershell -File scripts/install.ps1                  # claude + agents + reasonix
powershell -File scripts/install.ps1 -Targets claude,codex
powershell -File scripts/install.ps1 -Link            # 符号链接，git pull 后全局生效
```

### 手动

```bash
git clone https://github.com/cheng180/web-craft-skill.git /tmp/stm
cp -r /tmp/stm ~/.claude/skills/web-craft-skill          # Claude Code
cp -r /tmp/stm ~/.agents/skills/web-craft-skill          # Agent Skills 通用
cp -r /tmp/stm ~/.codex/skills/web-craft-skill           # Codex
```

各宿主路径差异、Codex `$skill-installer`、marketplace 发布、验证与排错：
见 **[references/install.md](references/install.md)**。

---

## 目录

```
SKILL.md                        主流程（精简，细节按需加载）
scripts/mirror.ps1              六层资源抓取（含视频/音频/字幕）
scripts/serve.py                带 MIME 修正的静态服务器
scripts/verify.ps1              无头浏览器渲染验证（不只看 HTTP 200）
scripts/install.ps1             一键装到 claude / codex / agents / reasonix
references/install.md           各宿主安装方式
references/restyle.md           配色/字体/间距的系统化替换
references/troubleshooting.md   编码、防盗链、MIME、视频、白屏兜底
references/checklist.md         交付前逐项清单
```

## 三条铁律

写进 SKILL.md 最前面，防止模型自作主张：

1. **不重写** — 在镜像代码上编辑。用户没要求"重做一版"就绝不另起一份
2. **不魔改** — 用户没提的部分一个字节都不动，没有"顺手优化"
3. **不反复纠缠** — 来源判定做一次，之后一路做到底，不每一步回来问

## 适用范围

这个 skill 面向**你有权作为基座使用的前端**：

| 来源 | 处理 |
|---|---|
| 自己的站、自己的旧版本 | 全流程 |
| 客户/团队授权的交付 | 全流程 |
| 有开源许可的模板、主题、UI kit | 全流程，保留原 LICENSE |
| 无授权的第三方站点 | 镜像作本地对照；交付按它的设计参数（色板、tokens、间距、缓动、组件结构）实现 |

最后一行是刻意留的：**学别人的设计、还原它的视觉，是正常工作流；
把别人的整站源码改成自己的名字发布，不是。** skill 会在第一步判定来源并记一行结论，
之后不再讨论，直接进入执行。

## License

MIT
