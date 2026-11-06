# 镜像与改造的常见坑

## 抓取阶段

**中文乱码**
`Invoke-WebRequest` 的 `.Content` 在 PS 5.1 下按 ANSI 解码。必须拿字节自己转：
```powershell
$bytes = $wc.DownloadData($url)
$text  = [System.Text.Encoding]::UTF8.GetString($bytes)
```

**只抓了 HTML，页面一片空白**
列表/画廊/文章多半来自 `fetch('/api/...')`。把 JSON 响应存成**无扩展名文件**放到对应路径，
静态服务器就会按原路径返回，页面立刻恢复。

**图片外链 403/418**
防盗链站点（豆瓣 `img*.doubanio.com` 只放行自家 Referer）在 `localhost` 或自己域名下必然失败。
两条路：
1. 落地本地（推荐）：带上对方站点的 Referer 下载，`<img src>` 改本地路径
2. 加 `referrerpolicy="no-referrer"` —— 注意有些站点对"无 Referer"更狠（豆瓣返回 418），别想当然

**Cloudflare 注入**
`/cdn-cgi/scripts/*/email-decode.min.js`、`static.cloudflareinsights.com/beacon.min.js`
是运行时注入的第三方脚本，不用抓，抓了也用不上。

**无限抓取**
同域资源用 `HashSet` 去重 + `MaxAssets` 上限；别跟着外链爬出去。

**视频被抓到了，但播放时还在打原站 CDN**
只下载不重写的话，`video.js` 里写死的 `https://cdn.xxx/vod/a.mp4` 仍然是外网地址——
文件在本地躺着，页面却还去请求别人。`mirror.ps1` 默认会把下载成功的绝对地址
批量换成 `/_ext/<host>/...`，需要保留原样时加 `-NoRewrite`。

自查：
```bash
grep -rn "https://.*\.mp4" mirror/assets/js/ mirror/*.html
```
还有命中就是没重写到。

**一个视频都没抓到**
两个原因，前者占九成：
1. 视频在独立 CDN（阿里云 OSS / 七牛 / 淘宝云视频 / mux）——按"同域"过滤会被整批挡掉。
   **媒体必须允许跨域**，这是 `mirror.ps1` 的默认行为
2. 地址是运行时拼接或带签名的（`/vod/${id}.mp4?sign=...&expires=...`），静态抓不到，
   只能等签名过期前手工补

**m3u8 只有索引，播放不了**
`.m3u8/.mpd` 是播放列表，真正的数据在 `.ts/.m4s` 分片里（动辄几百上千个）。
要完整离线播放，用 ffmpeg 拉流重封装：

```bash
ffmpeg -i "https://example.com/playlist.m3u8" -c copy -bsf:a aac_adtstoasc out.mp4
```

**视频太大 / 磁盘被塞满**
`-MaxMediaMB` 控制单个媒体上限（默认 200），超限的会跳过并写进 `_skipped-media.txt`；
`-SkipMedia` 整个关掉媒体下载。普通资源另有 `-MaxAssetMB`（默认 30），
防止类似 6 MB 巨型 SVG 这种意外。

**字体 / 图片全部 404，但页面看起来没问题**
先怀疑**自己解析错了**，再怀疑源站：

- CSS 里的 `url('../fonts/a.woff2')` 是相对 **CSS 文件自身**解析的，不是站点根。
  拿站点根去拼会得到一个规规矩矩的 404，而且报错看起来非常"合理"
- 引用所在文件在 `/assets/css/main.css`，实际地址就是 `/assets/fonts/a.woff2`

确认方法：浏览器里看 Network 面板请求的是什么路径，照着那个路径手工请求一次。
源站确实 404 的情况也有（CSS 声明了 `@font-face` 却没部署字体文件），
那就从系统字体栈兜底：

```css
font-family: "Montserrat", system-ui, -apple-system, "PingFang SC", sans-serif;
```

## 启动阶段

**`.webp` 显示不出来**
`python -m http.server` 可能不给 `.webp` 正确的 MIME。用 `scripts/serve.py`。

**API 返回 404 或 HTML**
Python 的 `SimpleHTTPRequestHandler` 对无扩展名文件默认 `application/octet-stream`，
`fetch().json()` 仍能解析；但如果服务器返回的是 SPA 的 `index.html`，就会解析失败。
用 `serve.py` 的 `ext == ""` → `application/json` 分支。

**POST 接口必然失效**
登录、访客计数、表单提交在静态镜像里一定挂。提前说明这是预期降级，不要试图伪造。

## 改造阶段

**后台标签页里页面卡在加载幕帘**
很多站点的开场动画用 `requestAnimationFrame` 驱动。标签页在后台时 rAF 不推进，
幕帘永远不消失，`body.loading { overflow: hidden }` 会让页面彻底无法滚动。

修法：加超时兜底。
```js
window.setTimeout(finish, 2600);   // rAF 不推进时也能收场
```

**动效脚本一旦抛错，整页隐形**
如果初始态是 `opacity: 0`（靠 JS 加 class 才显示），脚本挂了就是白屏但 DOM 正常。
两层兜底：
1. `<head>` 里内联 `document.documentElement.classList.add('js')`，
   CSS 写成 `html.js .rv:not(.on) { opacity: 0 }` —— JS 不可用时不隐藏
2. 末尾超时兜底：3.5s 后仍未见脚本就绪标志，给 `<html>` 加 `motion-off` 全量显示

**IntersectionObserver 在某些环境不触发**
无头浏览器 / 无渲染帧时可能一次都不回调。用 `scroll` + `getBoundingClientRect()` 判断更稳，
并且首屏要立即检查一次。

**CSS 变量改了没生效**
- 变量定义在被覆盖的 `:root` 里（多处 `:root`，后定义的赢）
- 组件里硬编码了色值，没引用变量
- 媒体查询里重新定义了同名变量

## 交付阶段

**改了品牌名但漏了残留**
批量替换后必须反向检查：
```powershell
Select-String -Path **\*.html,**\*.css,**\*.js -Pattern "旧品牌|Old_Brand|old-domain\.com"
```
链接类（`github.com/用户名`）不要动——账号名和品牌名常常不是一个东西。

**顺手优化导致 diff 爆炸**
每处改动前问一句"用户要求了吗"。没要求的：不动。
