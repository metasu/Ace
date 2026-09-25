# Hermes Ubuntu — 本机直装部署

Hermes Agent CLI + WebUI + MCP Server 在 Ubuntu 22.04+ 上的本机直装部署方案。
包含一键部署脚本、运维控制脚本、MCP 定制补丁和 WebUI 移动端补丁。

> 本仓库为私有部署配置仓库，不含 `hermes-agent`、`hermes-webui`、`mcp` 等子仓库的运行时代码——首次部署时 `hermes-deploy.sh` 会自动从公开仓库拉取并构建。

---

## 目录结构

```
/opt/hermes/
├── hermes-deploy.sh          # 一键部署脚本（装依赖、clone 源码、构建 MCP、写 systemd）
├── hermesctl.sh              # 运维控制脚本（数字菜单、模型切换、MCP 管理）
├── .gitignore
├── README.md                 # 本文件
├── patches/                  # WebUI 移动端补丁 + 历史配置脚本
│   ├── apply_webui_mobile_toolsets.py   # 移动端圆形按钮 → Toolsets/MCP 入口
│   ├── fix_toolsets_mcp_additive.py     # 会话 MCP 勾选改为追加语义，不取代常规工具
│   ├── compact_request.py               # compact 保工具补丁源（同步到 hermes-agent/agent/）
│   └── ...
├── mcp-patches/              # MCP server 定制补丁（跨机必带）
│   ├── xiaoyi-grok-image/
│   ├── atlascloud-seedream-v5-pro/
│   ├── atlascloud-seedream-edit/
│   ├── atlascloud-seedream-edit-sequential/
│   ├── atlascloud-wan-edit/
│   ├── atlascloud-wan-edit-pro/
│   └── README.md
└── data/                     # 运行时数据目录（密钥文件已脱敏，仅提供 .example 模板）
    ├── .env.example          # 环境变量模板（所有密钥为 RRRR... 占位符）
    ├── config.yaml.example   # 模型/Provider 配置模板
    ├── auth.json.example     # 凭据池模板
    ├── refresh_auth_json.py  # auth.json 自动刷新脚本
    ├── SOUL.md               # Agent 人格提示词
    └── webui/                # WebUI 运行时状态
```

> `hermes-agent/`、`hermes-webui/`、`mcp/`、`venv/` 由部署脚本自动生成，不入仓库。
> `data/output/`、数据库文件、`.env`、`auth.json`、`config.yaml` 等运行时/敏感文件已通过 `.gitignore` 排除（详见文末「不入库内容」）。

---

## 部署前准备

### 环境要求

- Linux 服务器 / VPS（推荐 Ubuntu 22.04/24.04、Debian 12）
- systemd 可用、root 权限（部署脚本内 `ensure_root`，非 root 直接退出）
- 能访问 GitHub、pip、npm 源

`hermes-deploy.sh` 会**自动安装全部依赖**，无需手工预装：

- 系统包：`curl ca-certificates git openssl unzip tar build-essential python3-venv python3-dev`
- `uv`、Python `3.12.13`、Node.js（NodeSource current 通道）

> 只要系统能跑 `apt` 且有办法把本目录文件放上去（git clone / scp / 面板上传均可）即可。

---

## 快速部署

```bash
# 1. 克隆 Ace 仓库，把本快照目录复制到 /opt/hermes
git clone https://github.com/metasu/Ace.git /tmp/ace
sudo mkdir -p /opt/hermes
cp -r "/tmp/ace/Hermes_Linux部署运维/Hermes的linux直装/<快照日期>/." /opt/hermes/
cd /opt/hermes

# 2. 复制模板并填入真实密钥
cp data/.env.example data/.env
cp data/config.yaml.example data/config.yaml
cp data/auth.json.example data/auth.json

# 3. 编辑 .env，替换所有 RRRR... 占位符为真实 API Key
vi data/.env

# 4. 一键部署（装依赖、clone 源码、构建 MCP、写 systemd 服务）
FORCE=1 bash /opt/hermes/hermes-deploy.sh

# 5. 启动服务
/opt/hermes/hermesctl.sh start
# 或：systemctl enable --now hermes-gateway hermes-webui
```

`.env` 至少填写：

- `HERMES_XIAOYI_ASTRA_KEY` — xiaoyi gpt-6-astra key（默认主模型）
- `HERMES_XIAOYI_OPUS_KEY` — xiaoyi claude-opus-5-5 key
- `HERMES_ATLASCLOUD_KEY` — atlascloud fallback key
- `XIAOYI_GROK_IMAGE_KEY` — 图片生成 MCP key
- `HERMES_WEBUI_PASSWORD` — WebUI 登录密码

`config.yaml` 可按需调整默认 provider/model、`fallback_providers`；**`mcp_servers:` 段不要手改**——启动时由脚本从 `.env` 重新生成并覆盖。`auth.json` 无需手改，`refresh_auth_json.py` 会从 `.env` + `config.yaml` 自动生成。

部署脚本会自动：安装依赖 → 克隆 `NousResearch/hermes-agent` 与 `nesquena/hermes-webui` → 创建 `venv` → 生成/保留 `data/.env`、`data/config.yaml`、`data/refresh_auth_json.py`（已存在则备份到 `backups/`）→ 注入 MCP 配置 → 构建 MCP 并应用 `mcp-patches/`、`patches/` → 写入并启动 `hermes-gateway`、`hermes-webui`。

### 验证

```bash
/opt/hermes/hermesctl.sh status

# 检查 Gateway API
API_KEY=$(awk -F= '/^API_SERVER_KEY=/{print $2}' data/.env)
curl -s -H "Authorization: Bearer $API_KEY" http://127.0.0.1:50001/v1/models | head -c 200

# 检查 WebUI
curl -s http://127.0.0.1:8787/api/auth/status   # 期望 auth_enabled=true
```

WebUI 登录密码见 `data/.env` 中的 `HERMES_WEBUI_PASSWORD`。

---

## 密钥配置说明

所有密钥通过 `data/.env` 环境变量管理，`config.yaml` 仅通过 `key_env` 引用，不保存明文。

### 对话渠道密钥

| 环境变量 | 渠道 | 用途 |
|---|---|---|
| `HERMES_ATLASCLOUD_KEY` | AtlasCloud | Grok-4.6 / Grok-4.3（回退）|
| `HERMES_XIAOYI_ASTRA_KEY` | xiaoyiapi.xyz | gpt-6-astra |
| `HERMES_XIAOYI_OPUS_KEY` | xiaoyiapi.xyz | claude-opus-5-5 |

### MCP 服务密钥

| 环境变量 | 用途 |
|---|---|
| `XIAOYI_GROK_IMAGE_KEY` | xiaoyi-grok-image 图像生成 MCP |
| `XIAOYI_GROK_IMAGE_API_URL` | xiaoyi 图片 API 地址（默认 `https://image.xiaoyiapi.xyz/v1`）|
| `MCP_ATLASCLOUD_KEY` | AtlasCloud 图像生成/编辑 MCP |
| `MCP_ATLASCLOUD_API_URL` | AtlasCloud API 地址（默认 `https://api.atlascloud.ai`）|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub MCP（前往 https://github.com/settings/tokens 生成）|

### 其他

| 环境变量 | 说明 |
|---|---|
| `API_SERVER_KEY` | Gateway API 鉴权密钥（部署时自动随机生成）|
| `HERMES_WEBUI_PASSWORD` | WebUI 登录密码（**公网部署务必修改**）|
| `HERMES_USER_AGENT` | 反屏蔽 User-Agent（xiaoyiapi 有 Cloudflare 防护，缺它会被 1010 拦截）|

> **安全提醒**：本仓库中所有密钥均为 `RRRR...` 红色占位符。请勿将真实密钥提交到仓库。
> `.env`、`auth.json`、`config.yaml` 已在 `.gitignore` 中排除。

---

## 可用模型

通过 `hermesctl.sh` 数字菜单切换：

| 菜单 | Provider | 模型 |
|---|---|---|
| `[17]` | xiaoyi-gpt-6-astra | gpt-6-astra |
| `[18]` | xiaoyi-claude-opus-5-5 | claude-opus-5-5（当前生产）|
| `[19]` | atlascloud-grok-4.3 | xai/grok-4.3 |
| `[20]` | atlascloud-grok-4.6 | xai/grok-4.6 |

命令行切换：
```bash
/opt/hermes/hermesctl.sh switch xiaoyi-gpt-6-astra
/opt/hermes/hermesctl.sh switch xiaoyi-claude-opus-5-5
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.3
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.6
```

### 回退保护池

主模型请求失败时自动回退到以下 Provider（按顺序）。**回退链同时决定 WebUI 模型选择器顶部「已配置」平铺区的成员**（该区只列出 Primary + Fallback N，不在链上的渠道只出现在下方折叠分组里）：

1. xiaoyi-claude-opus-5-5 / claude-opus-5-5
2. xiaoyi-gpt-6-astra / gpt-6-astra
3. atlascloud-grok-4.3 / xai/grok-4.3
4. atlascloud-grok-4.6 / xai/grok-4.6

---

## 渠道更换/更名实操经验

以 2026-09 将 fable 渠道更名替换为 `claude-opus-5-5` 为例。一个对话渠道涉及以下位置，漏改任何一处都会留坑：

| 位置 | 内容 |
|---|---|
| `data/.env` | 渠道 key 环境变量；更名时改 key 名（值可保留）|
| `data/config.yaml` | `providers:` 渠道块（名称/key_env/model/models/base_url/timeout）+ `fallback_providers:` 回退链条目 |
| `data/auth.json` | **不用手改** — `hermesctl.sh refresh` 从 `.env`+`config.yaml` 重新生成 `custom:<provider>` 凭据池 |
| `hermesctl.sh` | `switch_provider` 的 case 别名、`switch` 默认 model、数字菜单项、usage 文案 |
| `hermes-deploy.sh` | `.env` 模板、`config.yaml` 模板、`step_env` 补齐循环、`step_config` 规范化（`known` 名单、`fallback_entry`、provider 块补齐、旧渠道清理/迁移）|
| `patches/compact_request.py` | `DEFAULT_COMPACT_PROVIDERS` 名单；改完跑 `python3 patches/fix_compact_keep_tools.py /opt/hermes` 同步已安装副本 |
| 文档与模板 | `README.md`、`data/.env.example`、`data/config.yaml.example` |

### 操作顺序（本机实测）

1. 先改 `data/.env` 的 key 名 → `data/config.yaml` 的 provider 块 + fallback 链
2. 再改 `hermesctl.sh` / `hermes-deploy.sh` / `patches/` / 模板与文档
3. 执行 `hermesctl.sh switch <新provider>`——内部依次做：`key_env` 已设置校验 → 写 `model.*` → refresh（注入 `mcp_servers` + 重生成 `auth.json`）→ 重启 gateway
4. 验证：`hermesctl.sh status`（服务/端口/当前模型）→ `hermesctl.sh test`（通道 + 模型在列表内）→ 最可靠的是直连 `/v1/chat/completions` 发一条真实消息

### 已知坑

- **xiaoyiapi 有 Cloudflare 防护**：裸 `curl`/Python urllib 默认 UA 会被拦，报 `403 error code: 1010`（ASN/签名 ban），与 key 权限无关。`hermesctl.sh test` 已改为发送 `model.default_headers.User-Agent`（回落 `HERMES_USER_AGENT`）。**诊断别的渠道报 403 时先确认 UA**，别误判成 key 失效。
- **`mcp_servers:` 段每次启动都会被重写**：MCP 密钥/URL 一律改 `.env`（`XIAOYI_GROK_IMAGE_*` / `MCP_ATLASCLOUD_*` / `GITHUB_PERSONAL_ACCESS_TOKEN`），改完 `hermesctl.sh refresh`。
- **WebUI 模型下拉框不等于渠道配置**：`providers.<渠道>.model` 只描述渠道默认模型，不能保证非当前渠道在对话框可选；给四个渠道各配 `models: [模型ID]` 才能在目录缓存或在线模型探测不可用时稳定显示 GPT-6、Opus 5.5、Grok 4.3、Grok 4.6。配置、示例和部署脚本均已同步；切换主模型后仍应检查 `/api/models` 是否列齐四路（缓存行为见下文「模型目录缓存」）。
- **provider 更名后 compact 补丁仍生效**：`provider_needs_compact` 是子串匹配（`"xiaoyi"`、`"claude-opus"` 等）+ `xiaoyiapi` URL 兜底，`xiaoyi-*` 命名自动命中。
- **升级（`FORCE=1` deploy）会规范化 config.yaml**：移除旧渠道 provider 块、托管 fallback 条目去重重排、主 provider 不在 `known` 名单则回退 astra。新增/更名渠道必须同步 deploy 脚本，否则下次升级被洗掉。
- **`auth.json` 是运行时文件**：gateway 启动时 `ExecStartPre` 重生成，运行中 gateway 也会自行维护。`custom:*` 池短暂为空不等于故障——主链路走 `config.yaml` 的 `key_env` 直读。

---

## MCP Server

部署时自动从公开仓库 [slot181/openapi-integrator-mcp](https://github.com/slot181/openapi-integrator-mcp) 构建，复制为 6 个 MCP 目录，再应用 `mcp-patches/` 中的定制补丁。

| MCP Server | 用途 |
|---|---|
| xiaoyi-grok-image | xiaoyi 文生图/图生图（gpt-image-2.5-sunburst-cf）|
| atlascloud-seedream-v5-pro | Seedream v5.0 Pro 文生图 |
| atlascloud-seedream-v5-pro-edit | Seedream v5.0 Pro 图生图 |
| atlascloud-seedream-v5.0-lite-sequential | Seedream v5.0 Lite 连续编辑 |
| atlascloud-wan-edit | Wan 2.7 图生图 |
| atlascloud-wan-edit-pro | Wan 2.7 Pro 图生图 |
| github | GitHub MCP（npx @modelcontextprotocol/server-github）|

### MCP 重建

在 VPS 上修改 MCP 定制后，导出补丁并重建：

```bash
# 导出当前运行目录的定制到 mcp-patches/
/opt/hermes/hermesctl.sh mcp-export-patches

# 从上游重建 + 应用补丁
MCP_FROM_UPSTREAM=1 MCP_ONLY=1 bash /opt/hermes/hermes-deploy.sh
# 或
/opt/hermes/hermesctl.sh mcp-rebuild
```

---

## hermesctl.sh 命令一览

```bash
/opt/hermes/hermesctl.sh              # 数字菜单（推荐）
/opt/hermes/hermesctl.sh start        # 启动 gateway + webui
/opt/hermes/hermesctl.sh stop         # 停止
/opt/hermes/hermesctl.sh restart      # 重启
/opt/hermes/hermesctl.sh status       # 查看服务状态
/opt/hermes/hermesctl.sh logs         # 查看日志
/opt/hermes/hermesctl.sh switch <provider>   # 切换主模型
/opt/hermes/hermesctl.sh mcp          # 查看 MCP 状态
/opt/hermes/hermesctl.sh mcp-rebuild  # 重建 MCP
/opt/hermes/hermesctl.sh mcp-export-patches  # 导出 MCP 补丁
/opt/hermes/hermesctl.sh mcp-apply-patches   # 应用 MCP 补丁
/opt/hermes/hermesctl.sh webui-patch  # WebUI 移动端补丁
/opt/hermes/hermesctl.sh refresh      # 刷新 auth.json + 注入 MCP 配置
/opt/hermes/hermesctl.sh env          # 编辑 .env
/opt/hermes/hermesctl.sh config       # 编辑 config.yaml
/opt/hermes/hermesctl.sh test         # 连通性测试（已带浏览器 UA）
/opt/hermes/hermesctl.sh doctor       # 诊断
/opt/hermes/hermesctl.sh ports        # 端口检查
```

---

## systemd 服务

| 服务 | 端口 | 说明 |
|---|---|---|
| `hermes-gateway` | 50001 | Hermes Agent Gateway API |
| `hermes-webui` | 8787 | WebUI 网页界面 |

```bash
systemctl status hermes-gateway hermes-webui
journalctl -u hermes-gateway -f    # 实时日志
```

### 公网访问

WebUI 默认监听 `0.0.0.0:8787`，建议通过 Nginx Proxy Manager 等反代并启用 HTTPS。
Gateway API（50001）不对公网暴露。

---

## 升级

```bash
# 重新部署（保留现有 .env 和 config.yaml）
FORCE=1 bash /opt/hermes/hermes-deploy.sh

# 仅重建 MCP
MCP_FROM_UPSTREAM=1 MCP_ONLY=1 bash /opt/hermes/hermes-deploy.sh
```

> `FORCE=1` 会重新拉取子仓库并重新打补丁，但默认保留 `data/.env` 和 `data/config.yaml`（会先备份到 `backups/`）。

---

## WebUI 移动端补丁

`patches/apply_webui_mobile_toolsets.py` 为 WebUI 添加移动端底部 Toolsets/MCP 圆形入口按钮。
部署时自动应用；升级 WebUI 后需重新应用：

```bash
/opt/hermes/hermesctl.sh webui-patch
```

手机端入口：底部输入区点圆形配置按钮（带 0/上下文环）→ Toolsets/MCP。

---

## Compact / MCP 叠加（改文件失败时看这里）

- **Compact 不再阉工具。** `patches/compact_request.py` 接到 `conversation_loop`：Xiaoyi（gpt-6-astra / claude-opus-5-5，防网关超时）只在 system prompt > 8k 或历史过长时瘦文本；**永远保留全部 tools + tool_choice**；裁历史不拆 assistant/tool 成对；生图意图只加提示，不删其它工具。短请求原样发送。
- **会话勾选 MCP 是叠加，不是覆盖。** `_merge_session_toolsets`：勾选 github 等 MCP 不会关掉终端/文件（`hermes-cli` 仍在）。工具集 chip 在 MCP-only 时显示 `defaults + github`。
- **上游权限问题走 failover。** 渠道侧的 `HTTP 403 无权访问 xx 分组`（API 层报错，区别于 Cloudflare 1010）仍走现有 fallback（AtlasCloud Grok），不是本机工具集问题。

升级 agent/webui 后请再跑一次 `/opt/hermes/hermesctl.sh webui-patch`（会重打 compact 钩子 + MCP 追加）。改完须重启 WebUI（`hermesctl.sh restart`）。验证方式：让主模型「写 md」，成功标志是日志里 `in=` 从几百升到上万，并出现 `tool write_file completed`。

---

## 会话排障与已知问题

### 归因：会话选的模型 ≠ 实际生成的模型

WebUI 会话元数据记录的是**用户选定**的模型；主模型请求中途失败时 gateway 会按 `fallback_providers` 链自动回退，同一段回复可能由不同后端接力生成。排查「某模型答错/排错盘」先查日志确认实际后端，再谈模型能力：

```bash
# 流式中断、自动回退、上游报错都在 errors.log（WARNING 级以上）
grep -nE "Streaming failed|fallback|HTTP [45]" /opt/hermes/data/logs/errors.log
journalctl -u hermes-gateway --since "<时间>"    # gateway 侧流水

# 会话元数据与逐事件流水
data/webui/sessions/<session_id>.json
data/webui/sessions/_run_journal/<session_id>/
```

> 2026-09 实例：会话 `7bbc4cf08e36`（奇门排盘）选定 Opus 5.5，流式中途抛 `'NoneType' object has no attribute 'choices'`，部分流里的 `skill_view`/`terminal` 工具调用被丢弃，随后自动回退 Grok 4.3。错误盘面是**回退后**生成的——四柱、阴遁四局、甲申旬遁庚都对，但从地盘起错（阴四局巽四宫应为戊、写成乙），值符/值使连带全错、惊门重复死门缺失，即模型没执行 `yinpanqimen` 技能要求的逐层自检。归因时把「Opus 流式故障」与「回退模型的计算错误」分开。

### 上游兼容性（已修复，两处部署补丁）

xiaoyi 网关的 SSE 流有两个非标准行为，已通过「配置 + 补丁」组合修复，升级 hermes-agent 后需确认补丁仍在（`hermesctl.sh webui-patch` / 部署脚本会自动重打）：

- **`data: null` SSE 帧**：opus 流在 finish 块与 usage 块之间会发一帧 `data: null`，OpenAI SDK 解出 `None` chunk，主循环 `chunk.choices` 直接崩溃为 `'NoneType' object has no attribute 'choices'`。表现为流式中途死掉 → 按截断重试 → 最坏时报「Response remained truncated after N continuation attempts」或触发回退。修复：`patches/fix_stream_null_chunk.py` 在共享迭代器 `_iter_provider_stream_chunks` 中跳过 `None` chunk（改的是 `hermes-agent/agent/chat_completion_helpers.py` 安装副本，升级会被洗掉、必须重打）。
- **非流式强制 `max_tokens`**：opus 上游是 Anthropic 风格端点，非流式请求缺 `max_tokens` 返回 `HTTP 400 not found 'max_tokens'`（流式无此要求）。内部压缩/摘要/审批等非流式调用曾因此报错并被误归类为上下文溢出。修复：`config.yaml` 根级 `max_tokens: 64000`（WebUI Settings 同名字段），所有请求统一带上限；实测对四个渠道流式/非流式均无回归。输出被截断时 Hermes 有续写机制兜底，64000 只作安全上限。

### 已知问题（未修复）

- **旧会话残留前缀型模型 ID**：历史会话可能存了 `atlascloud-grok-4.6/xai/grok-4.6` 这类 `provider/model` 拼接串，发请求时上游返回 `400 {"code":400,"msg":"not found"}`。打开旧会话后在模型下拉框**重新选择**纯模型 ID（如 `xai/grok-4.6`）即可。
- **Grok 4.3/4.6 在选择器中各显示两行**：WebUI 徽标归一化生成 `provider/model` 变体键后去重不彻底，两行指向同一后端，纯显示问题。

### 模型目录缓存

- `/api/models` 有磁盘缓存 `data/webui/models_cache.json`（只含模型目录，无密钥）。在线探测超过 **4s 前台预算**时先返回缓存/兜底目录、后台异步重建——errors.log 里对应 `live provider-catalog rebuild exceeded 4.0s budget`。
- 改了 `providers.*.models` 后下拉框没变：刷新页面稍等缓存重建，或 `hermesctl.sh restart`；前端/单渠道精确失效走 `POST /api/models/refresh`（body `{"provider":"<id>"}`）。
- 不登录想确认目录内容，直接看 `models_cache.json` 的 `groups` 字段。**不要**用新 Python 进程调 `get_available_models()` 验证——冷进程必然超 4s 预算返回兜底空目录，不代表生产实际目录。

---

## 常见问题

### Q: 部署后 WebUI 无法访问？
确认 `HERMES_WEBUI_PASSWORD` 已设置，防火墙放行 8787 端口，服务已启动：
```bash
systemctl status hermes-webui
```

### Q: MCP 图像生成报 ECONNRESET？
AtlasCloud 需适配 `/api/v1/model/generateImage` + 异步轮询，确保 `mcp-patches/` 补丁已应用：
```bash
/opt/hermes/hermesctl.sh mcp
/opt/hermes/hermesctl.sh mcp-apply-patches
```

### Q: `hermesctl.sh test` 报 403？
先看报错形态：`403 error code: 1010` 是 Cloudflare 拦 UA（test 已带浏览器 UA，若仍出现说明上游防护策略变了）；`无权访问 xx 分组` 是渠道 key 的 API 层权限问题，走 fallback 或换 key。

### Q: 切换模型后不生效？
切换后需重启 gateway：
```bash
/opt/hermes/hermesctl.sh switch xiaoyi-claude-opus-5-5
/opt/hermes/hermesctl.sh restart
```

### Q: 如何添加/更换新渠道？
按「渠道更换/更名实操经验」一节的位置清单逐项修改，最少路径：
1. `data/.env` 加 `HERMES_XXX_KEY=你的密钥`
2. `data/config.yaml` 的 `providers:` 加 provider 块（需要回退则同步 `fallback_providers:`）
3. `hermesctl.sh` 的 `switch_provider` case 和菜单中加条目
4. `hermes-deploy.sh` 模板与规范化逻辑同步（否则升级被洗掉）
5. `/opt/hermes/hermesctl.sh refresh && /opt/hermes/hermesctl.sh restart`

---

## 不入库内容

以下内容**不应提交到 GitHub**，`.gitignore` 已默认排除：

- `data/.env`、`data/config.yaml`、`data/auth.json` — 真实密钥（仓库只放 `.example` 模板）
- `data/output/` — 图片/文件输出目录
- `venv/`、数据库（`*.db*`）、缓存、日志、会话、`data/webui/`
- `backups/`、`deploy.log` — 本机备份与部署日志
- `hermes-agent/`、`hermes-webui/`、`mcp/` — 子仓库（由部署脚本重建）
