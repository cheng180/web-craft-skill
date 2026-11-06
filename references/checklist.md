# 交付前逐项清单

改动前先 `git init && git commit`，最后用 `git diff` 逐条核对。

---

## A. 抓取完整性

- [ ] 入口 HTML 已落盘，UTF-8 无乱码
- [ ] 所有 `<link>` / `<script>` / `<img>` / `srcset` 命中同域资源
- [ ] CSS 里的 `url()`、`@import`、`@font-face` 全部落地
- [ ] JS 里的 `/api/...`、`graphql`、`wp-json` 端点已识别
- [ ] API 响应存成**无扩展名**文件，路径与请求路径一致
- [ ] API 里引用的 `/uploads/`、`/media/` 图片已下载
- [ ] 第三方注入脚本（Cloudflare beacon / email-decode）未抓，HTML 里仍保留引用不报错
- [ ] 生成 `_manifest.json`，文件数与预期一致

## B. 本地运行

- [ ] `serve.py` 启动无异常
- [ ] 首页 200，CSS/JS 200
- [ ] `verify.ps1` PASS：DOM 长度正常、`img` 数量符合预期
- [ ] JS 真的跑了（`body`/`html` 的 class 有变化，或动态节点被渲染出来）
- [ ] 控制台无红色报错（有 CDP 时检查；无则用 dump-dom 找 `undefined`/`NaN`）
- [ ] POST 类接口的失效已向用户说明为预期降级

## C. 改造正确性

- [ ] 品牌名 / 缩写 / 标题 / 页脚 / 卡片署名 全部替换
- [ ] 反向残留检查 0 命中（排除真实账号名、域名）
- [ ] 链接指向真实目标，没有 404
- [ ] 图片全部本地化，`alt` 有意义
- [ ] 图片加载失败有回退（文字占位 / `onerror`）
- [ ] **用户没要求的改动：一个都没有**

## D. 视觉与响应式

- [ ] 桌面 1440 宽：无横向溢出、无元素重叠
- [ ] 平板 768：网格降列正常
- [ ] 手机 390：`--window-size=390,844` 跑一次，无横向滚动
- [ ] 长标题、长邮箱、长仓库名不撑破卡片
- [ ] hover / active / focus 态在改色后仍然可辨
- [ ] `::selection`、表单 placeholder、滚动条 都已检查

## E. 可访问性与降级

- [ ] `prefers-reduced-motion: reduce` 下无动画、内容完整
- [ ] 无 JS（`<noscript>`）时内容可见
- [ ] 动效脚本失效时不会白屏（`motion-off` 兜底）
- [ ] 标题层级合理（只有一个 h1）
- [ ] 焦点可键盘到达，`:focus-visible` 可见
- [ ] 图片 `alt`、装饰元素 `aria-hidden`

## F. 交付卫生

- [ ] `git diff` 只含需求内改动
- [ ] 临时脚本、抓取日志、截图不在交付目录
- [ ] 参考副本（未授权站点的镜像）已移出交付目录或标注清楚
- [ ] 第三方素材（图片/字体/插画）来源与作者记录在 `ATTRIBUTION.md`
- [ ] README 写明如何启动、如何改内容
- [ ] `python -m http.server` 之外没有任何隐藏依赖
