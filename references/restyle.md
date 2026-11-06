# 改色系 / 改字体 / 改间距

原则：**先找变量，再动组件，最后才碰结构。** 90% 的"换配色"只改第一层。

---

## 1. 找 tokens 层（按优先级）

```powershell
# 1) CSS 自定义属性
Select-String -Path src\*.css,src\**\*.css -Pattern "^\s*:root|--[a-z-]+:\s*#" | Select-Object -First 40

# 2) Tailwind / UnoCSS
Get-ChildItem -Recurse -Include tailwind.config.*,uno.config.*,theme.* | Select-Object FullName

# 3) SCSS/LESS 变量与主题文件
Select-String -Path **\*.scss,**\*.less -Pattern '^\$[a-z-]+:' | Select-Object -First 40

# 4) 设计 token 文件
Get-ChildItem -Recurse -Include tokens.json,design-tokens.*,theme.json | Select-Object FullName
```

找到变量表后，**先把"变量名 → 当前值"列成表给用户看**，一次确认方向，不要改一轮问一次。

---

## 2. 硬编码色值怎么处理

```powershell
# 统计硬编码色值出现次数，决定是否批量替换
Select-String -Path src\*.css -Pattern "#[0-9a-fA-F]{3,8}|rgba?\(" -AllMatches |
  ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } |
  Group-Object | Sort-Object Count -Descending | Select-Object -First 20
```

- 出现 1~3 次 → 手动定点改
- 出现 10+ 次且语义一致（全是卡片边框）→ 批量替换成变量
- 语义不一致（`#fff` 既是文字又是背景）→ **必须**逐个看，不能批量

---

## 3. 换配色时的连带检查

改完主色后，这些地方最容易穿帮：

| 位置 | 检查什么 |
|---|---|
| `::selection` | 选中态是否还协调 |
| 深色区块 | `.section--ink` 之类反色区域的文字对比度 |
| hover / active | 变量改了但硬编码的 hover 色没跟上 |
| 边框与阴影 | 硬投影用的是深色时，改了底色可能糊成一团 |
| 图片蒙层 | 半透明遮罩的色相是否变脏 |
| 表单控件 | `input::placeholder`、`focus` 边框 |
| 滚动条 | `::-webkit-scrollbar` 若自定义过 |

对比度至少 4.5:1（正文）/ 3:1（大字与图形）。

---

## 4. 换字体

1. 有 `@font-face` → 先把字体文件抓到本地（`mirror.ps1` 已覆盖 `url()`），再改 `font-family`
2. 系统字体栈优先：中文 `"PingFang SC", "Microsoft YaHei"`，等宽 `"Cascadia Code", Consolas`
3. 换字体后**必查**：字号是否需要跟着调（字面高度差异很大）、`letter-spacing`、行高、按钮最小宽度

```powershell
Select-String -Path src\*.css -Pattern "@font-face|font-family" | Select-Object -First 30
```

---

## 5. 换间距节奏

如果只改 `padding`/`gap` 会散架。正确顺序：

1. 找间距的比例习惯（4/8 网格？`clamp()` 流式？）
2. 改**一处**基准值，看三处受影响的地方，再决定是否推广
3. 记录改动前后的 DOM 高度差（`dump-dom` 后比对 section 数量与顺序更直接）

---

## 6. 需要"整体换设计语言"时

不只是换色（要改版式、字体层级、动效气质）：

1. 先读 `design-taste-frontend` skill，按它的 brief 推断流程定方向
2. 仍然**在现有结构上改**，不要推翻重写——用户要的是这个站的骨架
3. 一次只改一类：先色彩 → 再看排版 → 最后动效。每步都能回退
