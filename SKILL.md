---
name: site-template-mirror
description: 把一个现有网站完整镜像到本地、启动起来、然后在镜像代码上定点改造（文案/图片/配色/风格）的工程化流程。当用户说“照着这个网站做一个”“把这个站扒下来改”“要的就是这个前端模板，不要凭空生成”“在他的代码上改别重写”“改一下这个站的颜色/风格”时使用。包含来源判定、四层资源抓取、本地启动、diff 基线、grep 定位改造、配色替换与交付验收。
---

# Site Template Mirror

用户要的通常是**一个具体的现成前端**，而不是"一个像它的新前端"。本 skill 的唯一目的：
把那个前端**原封不动搬到本地**，然后在**它自己的代码**上按需求改。

> 顺序不可跳：**镜像 → 启动对照 → 定点改造 → 验收**。
> 最常见的失败不是技术，是模型自作主张重写一遍。

---

## 0. 三条铁律

1. **不重写。** 除非用户明确说"重做一版"，否则一律在镜像代码上编辑。
   重写等于把用户的参考物丢掉，还会引入用户没要求的风格漂移。
2. **不魔改。** 用户没提的部分，一个字节都不动。没有"顺手优化"。
3. **不反复纠缠。** 判定做完（第 1 节）就一路做到底，不要每一步都回来讨论授权或方案。

先建 git 基线，后面所有改动都能 `git diff` 说清楚：

```bash
cd <镜像目录> && git init && git add -A && git commit -m "baseline: 原始镜像"
```

---

## 1. 来源判定（唯一一次，30 秒）

| 来源 | 处理 |
|---|---|
| 用户自己的站 / 用户以前的版本 | 全流程，直接在镜像上改 |
| 客户/团队授权交付的站 | 全流程，直接在镜像上改 |
| 有明确开源许可的模板、主题、UI kit | 全流程，**保留原 LICENSE 文件** |
| 无授权的第三方站点 | 镜像只作**本地对照参考**；交付物按其设计参数（色板/tokens/间距/缓动/组件结构）自行实现。向用户说明**一句话**，然后继续把视觉做到一致 |

判定结果写进 `<work>/.mirror-source` 一行，例如：
`source=third-party-reference  url=https://x.com  decision=reimplement-by-spec`

之后不再讨论这件事，直接进入执行。用户如果坚持要搬源码，说明一次立场即可，不要长篇论证、不要重复劝说。

---

## 2. 全量镜像（漏一层就白干）

**HTML 只是第一层。** 一个"看起来没图"的站点，图片往往在第 4 层；一个"有背景视频"的站点，视频往往在第 3 层。

| 层 | 内容 | 漏了会怎样 |
|---|---|---|
| 1 | 入口 HTML、`<link>`、`<script>`、`<img>`、`srcset` | 缺样式/交互 |
| 2 | CSS 里的 `url()`、`@import`、`@font-face` | 缺字体、缺背景图 |
| 3 | **媒体层**：`<video>`/`<audio>`/`<source>`/`<track>`、`.mp4/.webm/.m3u8/.mp3/.vtt` | 视频区黑屏 |
| 4 | **JS 里的 `fetch()` / `/api/` 端点** | 列表、画廊、文章全空 |
| 5 | API 返回的 `/uploads/` 等资源 | 有卡片没图 |
| 6 | 内联 JSON（Next.js `__NEXT_DATA__`）里的媒体地址 | 首屏视频/封面加载不出 |

用脚本一把抓完：

```powershell
powershell -File scripts/mirror.ps1 -Url https://example.com -OutDir ./mirror
```

脚本做的事（读它，不要重写它）：

1. 抓入口 HTML（按 UTF-8 解码，避免中文乱码）
2. 提取引用：`href/src/srcset/poster`、CSS `url()`、JS 里 `"/api/..."`、任意文本里的媒体绝对地址
3. 按原路径结构落盘，`a/b.css` → `mirror\a\b.css`
4. **把 API 的 JSON 响应存成无扩展名文件**（`mirror/api/galleries`），
   这样静态服务器能直接响应 `fetch('/api/galleries')`，页面立刻活过来
5. **媒体允许跨域**，落到 `_ext/<host>/...`；超过 `-MaxMediaMB`（默认 200MB）跳过并记入 `_skipped-media.txt`
6. **重写引用**：把下载成功的绝对地址换成 `/_ext/...` 本地路径——
   否则文件下载了却没人引用，离线打开照样去打别人 CDN

要点：
- **视频多半不在主域**（oss / 七牛 / 淘宝云视频 / mux）。按"同域"过滤会把视频全漏掉，
  这是最常见的假成功："抓了 26MB，但视频一个都没有"
- `.m3u8/.mpd` 只能拿到索引，分片 `.ts/.m4s` 抓不到，脚本会明确提示
- 子页面（`/blog/` 这种导航链接）默认不抓，避免顺着链接把整站拖下来；需要时加 `-FollowPages`
- `?v=123` 这类查询串不影响落盘文件名，但要保留在 HTML 里
- Cloudflare 的 `email-decode.min.js`、`beacon.min.js` 是第三方注入，**不用抓**
- 请求间隔 800ms~1s，别把人家站点打崩，也别触发风控
- **CSS 里的 `url()` 是相对 CSS 文件自身解析的**：`/assets/css/main.css` 里写 `../fonts/a.woff2`，
  实际地址是 `/assets/fonts/a.woff2`。按站点根去拼会得到一个规规矩矩的 404，看着特别像
  "源站就没部署这个字体"，实际是自己解析歪了。浏览器 Network 面板是唯一可信的对照
- 源站确实 404 的资源（CSS 声明了 `@font-face` 却没部署文件）镜像也会 404，这是忠实复现

---

## 3. 本地启动对照

```powershell
python scripts/serve.py --root ./mirror --port 5174
```

用 `scripts/serve.py`，不要用 `python -m http.server`：它会补 `.webp/.avif/.mjs/.woff2`
的 MIME（缺 MIME 时部分浏览器不渲染），并可选 SPA fallback。

启动后必须做一次运行时验证，别只看 HTTP 200：

```powershell
powershell -File scripts/verify.ps1 -Url http://127.0.0.1:5174/
```

验证项：DOM 长度、`<img>` 数量、卡片数量、`body`/`html` 的 class 变化（说明 JS 跑起来了）。
**预期内的降级**要提前跟用户讲清楚：`POST` 接口（登录、计数、提交表单）在静态镜像里必然失效。

把两个端口一起给用户：镜像 `<port A>`、目标站 `<port B>`，让他并排看。

---

## 4. 定点改造（核心）

### 4.1 定位，不要通读

```powershell
Select-String -Path mirror\*.html,mirror\*.css -Pattern "旧文案|品牌名|品牌缩写" | Select-Object -First 40
```

只读命中的那一段窗口（`read_file` + `offset/limit`），不要整文件加载。
一个 50KB 的 CSS 全文读一次就是几千 token，读十次就废了。

### 4.2 用映射表批量换文案

品牌名、缩写、链接后缀这类**全局重复**的替换，一次跑完并打印每条的命中数：

```powershell
$map = [ordered]@{ "OLD_BRAND" = "NEW"; "old.com" = "new.com" }
# 逐条 Replace + 打印命中数，最后残留检查
```

替换后必须做**残留检查**：`Select-String` 确认 0 命中（域名/链接类要排除，别改坏跳转）。

### 4.3 区块级改造用 `edit_file`

单个卡片、单个 section：`old_string` 取到足够上下文保证唯一，一次一处。
**不要**为了改一张卡去重写整段区块，更不要重写整个文件。

### 4.4 图片替换

- 新图放 `assets/`，改 `<img src>`，保留 `alt`
- 加 `onerror` / 回退文本（`<span class="fallback">书名</span>`），图挂了也不难看
- 外链图床先测可用性：**豆瓣图床只放行自家 Referer，外链必然 418/403** → 必须落地本地
- 大图压到显示宽度的 2 倍即可（560px 卡片 → 560px 图，100KB 量级）

---

## 5. 改色系 / 改风格

**顺序：先 tokens，再组件，最后才动结构。**

1. 找变量层：`:root { --xxx }`、`tailwind.config`、`theme.ts`、`_variables.scss`、`tokens.json`
   → 90% 的"换配色"只改这里就够
2. 改之前先列出**变量清单和当前值**给用户确认（一次问清配色方向，别改一轮问一次）
3. 有 CSS 变量就绝不硬编码颜色；发现硬编码色值（`#fff`、`rgba(...)`）先统计出现次数再决定是否批量换
4. 需要"整体换一种设计语言"（不只是换色）时，加载 `design-taste-frontend` skill
5. 改完必须跑第 6 节验收，重点看：对比度、深色区块上的文字、hover 态、`::selection`

---

## 6. 交付验收清单

- [ ] `verify.ps1` 通过，无 404、无控制台报错
- [ ] 品牌/文案残留检查 0 命中
- [ ] 移动端断点：`--window-size=390,844` 跑一次 `dump-dom`，检查横向溢出
- [ ] 图片全部本地化，且 `alt` 完整
- [ ] `prefers-reduced-motion` 下内容仍完整可见
- [ ] **动效脚本失效时不会白屏**（加 `html.motion-off` 之类兜底，见 `references/troubleshooting.md`）
- [ ] `git diff` 只包含用户要求的改动，没有"顺手优化"
- [ ] 参考副本/临时脚本清理干净，或明确移出交付目录

---

## 7. 省 token 的做法

| 做法 | 收益 |
|---|---|
| 先 `Select-String` 定位，再读 20~40 行窗口 | 避免整文件读取 |
| 用脚本做机械抓取/替换 | 一次调用代替几十轮试错 |
| `edit_file` 定点改，不 `write_file` 整文件 | 差异小、可 review、不误伤 |
| 同批独立操作并行调用 | 减少往返 |
| 验证用 `dump-dom` 断言关键节点 | 比截图省，且模型能读结果 |

---

## 参考文件（按需加载，不要全读）

- `references/install.md` — 装到 Claude Code / Codex / 其他宿主，验证与排错
- `references/restyle.md` — 配色/字体/间距的系统化替换方法
- `references/troubleshooting.md` — 编码、防盗链、MIME、rAF 不跑、SPA、CSS 变量失效
- `references/checklist.md` — 交付前逐项打勾的完整版清单
