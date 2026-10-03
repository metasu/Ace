# Hermes 修复交接:上下文窗口阈值 + 手机端奇门九宫格渲染

> 交接对象:其他机器上的 AI 运维代理
> 来源机器:Hermes Agent v0.21.5 + HermesWebUI 0.52.113(部署于 `/opt/hermes`,`HERMES_HOME=/opt/hermes/data`)
> 适用前提:目标机器也用 hermes-agent(配置问题)和 hermes-webui(九宫格问题)。两个修复互相独立,可分开执行。

---

## 问题 1:上下文窗口与自动压缩阈值

### 症状

- 模型配置 `context_length` 已改成 1,000,000,会话页显示 1.0M 窗口;
- 但自动压缩仍在很低的 token 数触发(本机实测为 256k,即旧阈值 0.5 × 旧窗口)——`compression.threshold` 未随窗口一起调。

### 修复步骤

1. 定位配置:`hermes config path`(默认 `~/.hermes/config.yaml`;若部署用 `HERMES_HOME`,则为 `$HERMES_HOME/config.yaml`)。
2. 写入:

   ```bash
   hermes config set model.context_length 1000000
   hermes config set compression.threshold 0.75
   ```

   或直接编辑 config.yaml,确保有:

   ```yaml
   model:
     context_length: 1000000
   compression:
     enabled: true
     threshold: 0.75
     target_ratio: 0.2
     protect_last_n: 20
   ```

3. `hermes config check` 通过。
4. 重启网关使其加载:`systemctl restart hermes-gateway`(服务名不同则用 `systemctl list-units | grep -i hermes` 查找;非 systemd 部署则重启对应进程)。
5. 验证:刷新会话页,应显示 1.0M 窗口、自动压缩约 750k(75%)。

### 关键事实(避免走弯路)

- `model.context_length` 是**本地声明值**,控制 UI 显示和压缩触发基准;它不改变上游 API 真实上限。
- 官方 `-900k` 别名(如 `gpt-6.1-sol-900k`)**只对 Codex OAuth 路由有效**,作用是纠偏"广告 272K、实测收 ~900K"的路由;对 kuaipao 这类 OpenAI 兼容中转**不适用也不需要** —— 自定义 provider 直接用 `context_length` 即可。
- `gpt-6.1-sol` 官方规格:1,050,000 上下文 / 922,000 输入上限 / 128,000 输出;输入 >272K 整单按长上下文价(输入与缓存 ×2,输出 ×1.5)。
- 中转上游若为 Codex/Pro 号池,实测可收 ~900K+。**0.75 阈值 → 750K 触发,低于所有可能的真实上限,安全。**
- 想让显示更精确可设 `922000`(对齐官转输入上限)或 `900000`(对齐号池实测),保持 1,000,000 也没问题。

---

## 问题 2:手机端奇门九宫格渲染错乱

### 症状与根因

yinpanqimen 技能交付的等宽 ASCII 九宫格( ` ```text ` 围栏代码块、`+---+` 边框、`【宫位】` 标签、神/星/门/天/引 行)在手机端列错位。

根因:`static/style.css` 的 `@media(max-width:700px)` 对所有 `.msg-body pre` 强制 `white-space:pre-wrap`,固定宽度盘面被折碎。

### 修复思路

JS 检测出"奇门九宫格"代码块并加 `qimen-grid-block` class;CSS 对该 class 豁免折行、缩小字体、允许横向触摸滚动。

### 改动 1:`static/ui.js`(两处)

**(a)** 在 `function renderMd(raw){` 定义**之前**插入检测函数(本机插入于 `_stripVisibleAssistantEchoFromThinking` 之后):

```js
function _looksLikeQimenGridCode(code){
  const text=String(code||'');
  if(!/[+][-=]{3,}[+]/.test(text)) return false;
  const palaceLabels=(text.match(/\|\s*【[^】]+】/g)||[]).length;
  if(palaceLabels<3) return false;
  return /\|\s*(?:神|星|门|天|引)(?:\s|$)/.test(text);
}
```

判定条件三者为 AND:有 `+---+` 边框;≥3 个 `|【宫位】` 标签;存在 `|神 ` / `|星 ` / `|门 ` / `|天 ` / `|引 ` 行 —— 避免误伤普通 ASCII 表格。

> 注意:行尾断言必须用 `(?:\s|$)`,**不要用 `\b`** —— JS 中 `\b` 基于 `\w`(仅 ASCII),CJK 字符后跟空格不构成边界,会漏判。

**(b)** 在 `renderMd` 内 fenced code block 渲染分支(mermaid 判断之后的 `else`,`h`/`langAttr` 定义之后;本机约 7247 行)找到:

```js
const preClass=/^(md|markdown|mdx)$/.test(lang)?' class="md-source-block"':'';
```

改为:

```js
const preClass=/^(md|markdown|mdx)$/.test(lang)?' class="md-source-block"':(_looksLikeQimenGridCode(code)?' class="qimen-grid-block"':'');
```

### 改动 2:`static/style.css`

在 `@media(max-width:700px){ ... }` 块内、强制 `pre-wrap` 的那组规则之后(本机约 2345 行)追加:

```css
    /* Qimen nine-palace grids are intentional fixed-width ASCII layouts. Keep
       their columns aligned on phones and let the user pan horizontally instead
       of wrapping border lines and palace contents into unrelated rows. */
    .msg-body pre.qimen-grid-block{
      max-width:100%;
      overflow-x:auto !important;
      overflow-y:hidden;
      white-space:pre !important;
      overflow-wrap:normal !important;
      word-break:normal !important;
      font-family:var(--font-mono,ui-monospace),monospace !important;
      /* Shrink the complete grid on phones before enabling pan. */
      font-size:clamp(8px,2.2vw,var(--message-pre-code-font-size)) !important;
      line-height:1.35 !important;
      -webkit-overflow-scrolling:touch;
      overscroll-behavior-inline:contain;
      touch-action:pan-x pan-y;
    }
    .msg-body pre.qimen-grid-block code{
      display:block;
      width:max-content;
      min-width:100%;
      font-size:inherit !important;
      line-height:inherit !important;
      white-space:pre !important;
      overflow-wrap:normal !important;
      word-break:normal !important;
    }
    .msg-body pre.qimen-grid-block code .token{
      white-space:pre !important;
      overflow-wrap:normal !important;
      word-break:normal !important;
    }
```

> 若目标机器 CSS 变量名不同(`--font-mono`、`--message-pre-code-font-size`),按其 style.css 现有变量名微调;媒体查询断点同理(本机 700px)。

### 验证

```bash
cd <hermes-webui 目录>
node --check static/ui.js
git diff --check
# 确认线上服务提供的就是改后的文件(端口按实际部署):
sha256sum static/ui.js
curl -s http://127.0.0.1:<port>/static/ui.js | sha256sum
```

手机端需**硬刷新**(本机静态资源 `Cache-Control: max-age=300`,等 5 分钟或清站点缓存)。

### 边界与限制(如实交接)

- 只对**围栏代码块**生效。若模型把盘面裸写在普通段落或 Markdown 表格中,检测不会触发 —— yinpanqimen 技能规范已要求九宫必须用 ` ```text ` 代码块交付,属配套约束。
- 检测依赖 `【宫位】` 标签 + `神/星/门/天/引` 行首标记;其他盘式(纯 `|` 表格、无宫位标签的盘)不会命中,不会享受豁免。
- 本机 ui.js 该段 diff 里还混有其他无关改动(模型下拉、file:// 正则等),移植时**只搬上述两处 qimen 相关代码**,不要整文件覆盖。
