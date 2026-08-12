# Hermes Agent Linux 本机直装部署教程（CLI + WebUI + MCP）

> 以本机 `/opt/hermes` 实际部署为准  
> 设计思路参考：`notes/Hermes Agent Windows本地便携部署教程.html`  
> 部署方式：**主机直装（非 Docker Compose）**  
> 适用：Ubuntu 22.04+ / root / systemd

---

## 1. 目标与架构

在一台 Linux 服务器上部署：

| 组件 | 作用 | 端口 |
|------|------|------|
| Hermes CLI / Gateway | 多模型聚合 Agent + OpenAI 兼容 API | `50001` |
| Hermes WebUI | 浏览器对话界面 | `8787`（默认仅本机） |
| MCP Servers（Node.js） | 文生图 / 图生图工具 | 由 gateway 按需拉起（stdio） |

统一目录：

```text
/opt/hermes/
├── hermes-deploy.sh          # 一键部署脚本（自动应用 MCP + 移动端补丁）
├── hermesctl.sh              # 运维控制台（数字菜单，对齐 start.bat）
├── patches/                  # 前置补丁脚本（跨机必带）
│   ├── apply_webui_mobile_toolsets.py
│   └── README.md
├── mcp-patches/              # MCP handlers/definitions 定制（跨机必带）
│   ├── README.md
│   ├── kuaipao-image/
│   └── atlascloud-*/
├── hermes-agent/             # hermes-agent 源码
├── hermes-webui/             # hermes-webui 源码（static 会被移动端补丁改写）
├── data/                     # 运行数据与配置（HERMES_HOME）
│   ├── .env                  # 所有 API Key 集中管理
│   ├── config.yaml           # 模型 / provider / MCP 配置
│   ├── auth.json             # 由 refresh_auth_json.py 自动生成
│   ├── refresh_auth_json.py
│   ├── output/               # MCP 生图输出目录
│   ├── logs/
│   └── webui/
├── venv/                     # Python 3.12.13 虚拟环境
├── mcp/                      # MCP server（Node.js 构建产物 + 已打补丁）
│   ├── kuaipao-image/
│   ├── atlascloud-seedream-v5-pro/
│   ├── atlascloud-seedream-edit/
│   ├── atlascloud-seedream-edit-sequential/
│   ├── atlascloud-wan-edit/
│   └── atlascloud-wan-edit-pro/
└── backups/                  # 配置备份
```

### 设计原则（对齐 Windows 便携教程）

1. **密钥集中在 `.env`**，`config.yaml` 的 provider 用 `key_env` 引用，不写明文 key。  
2. **MCP：先公开仓库 Node 构建，再自动应用 `mcp-patches/`**（handlers/definitions；Atlas 原生 API）。  
2b. **MCP 配置注入**：`mcp_servers` 段由 `hermesctl.sh` / `hermes-deploy.sh` 的 shell 函数从 `.env` 读取密钥和 API_URL 动态生成，不硬编码在 `config.yaml` 中；每次注入都会重新读取 `.env`。  
2c. **WebUI 移动端 Toolsets/MCP**：`patches/apply_webui_mobile_toolsets.py` 在部署/升级后自动打入 static。  
3. **CLI 与 WebUI 都在 `/opt/hermes` 下**，脚本也放在同一目录。  
4. **systemd 托管 gateway + webui**，开机自启。  
5. **升级默认保留 `data/` 与 `mcp-patches/`**。

---

## 2. 前置条件

### 2.1 系统

- Ubuntu 22.04+（其他 Debian 系可参考）
- root 权限
- 出网（GitHub、NodeSource、PyPI、模型 API）
- 端口：`50001`、`8787` 可用（升级场景若已被 Hermes 占用可继续）

### 2.2 可选

- Nginx Proxy Manager（NPM）做域名反代 WebUI
- 已有 Windows 便携部署的 `mcp/` 目录或 `mcp.zip`（推荐，最省事）

---

## 3. 快速部署（推荐流程）

### 3.1 新机最小文件（推荐：只拷两个脚本）

**不必上传 `mcp/`、`venv/`、`hermes-agent/`、`data/`。** 新机只需：

```bash
mkdir -p /opt/hermes
scp /opt/hermes/hermes-deploy.sh /opt/hermes/hermesctl.sh root@新服务器:/opt/hermes/
scp -r /opt/hermes/mcp-patches /opt/hermes/patches root@新服务器:/opt/hermes/
ssh root@新服务器 'chmod 700 /opt/hermes/hermes-deploy.sh /opt/hermes/hermesctl.sh'
```

| 文件 | 是否必须 |
|------|----------|
| `hermes-deploy.sh` | **必须** |
| `hermesctl.sh` | 强烈推荐 |
| `mcp-patches/` | **强烈推荐**（kuaipao + Atlas 定制；无则 Atlas 为上游原版易 400） |
| `patches/` | **强烈推荐**（移动端 Toolsets 入口 + config API_URL 规范化） |
| `mcp/` / `venv/` / 源码 | **不要传**（脚本自动生成） |

脚本联网自动：系统依赖、uv/Python/Node、clone hermes-agent & webui、从公开仓库构建 MCP、写 systemd。

### 3.2 MCP（脚本自动，无需预上传）

1. 下载 `slot181/openapi-integrator-mcp` → `npm run build`  
2. 复制为 6 个图像 MCP 目录  
3. 若存在 `mcp-patches/` 则应用；**无补丁也能装好**（上游原版，可在 VPS 再定制）
4. GitHub MCP 通过 `npx -y @modelcontextprotocol/server-github` 直接运行，不占用 `mcp/` 构建目录  

```bash
/opt/hermes/hermesctl.sh mcp-rebuild   # 仅重建 MCP
```

详见第 6 章。

### 3.3 执行一键部署

```bash
# 非交互（适合批量装机）
FORCE=1 bash /opt/hermes/hermes-deploy.sh

# 或交互确认
bash /opt/hermes/hermes-deploy.sh
```

脚本会自动完成：

1. 安装系统依赖（curl/git/unzip/build-essential…）
2. 安装 `uv` + Python **3.12.13**
3. 安装最新 Node.js（NodeSource `current`）
4. 克隆/更新 `hermes-agent`、`hermes-webui`
5. 创建 venv，安装：
   - `hermes-agent[messaging,anthropic,mcp]`  ← **必须含 mcp**
   - webui `requirements.txt`
6. 生成/保留 `.env`、`config.yaml`
7. 写入 systemd：`hermes-gateway` / `hermes-webui`
8. 安装/解压/构建 6 个图像 MCP，并应用 `mcp-patches/`
9. 注入 MCP 配置到 `config.yaml`（shell 函数从 `.env` 读取密钥 + API_URL + 动态路径；GitHub MCP 使用 npx）
10. 应用 WebUI 移动端 Toolsets/MCP 入口（`patches/apply_webui_mobile_toolsets.py`）

### 3.4 启动

```bash
# 方式 A：数字菜单（推荐，对齐 Windows start.bat）
/opt/hermes/hermesctl.sh
# → 选 [1] 启动 Gateway + WebUI

# 方式 B：命令行
/opt/hermes/hermesctl.sh start
# 会先刷新 MCP/auth.json，随后最多等待 30 秒，确认两个服务均 active 且 50001/8787 已监听
# 直接 systemctl enable --now hermes-gateway hermes-webui 只负责拉起 systemd 服务
```

### 3.5 验证

```bash
/opt/hermes/hermesctl.sh          # 菜单：[4] 状态  [6] 测 API  [12] MCP
# 或命令行：
/opt/hermes/hermesctl.sh status
/opt/hermes/hermesctl.sh mcp
/opt/hermes/hermesctl.sh test
```

期望：

- `hermes-gateway` / `hermes-webui` 均为 `active`
- `50001`、`8787` 监听
- `hermesctl.sh status` 的 HTTP 检查中，Gateway 返回 `401`（未带 API key）及 WebUI 返回 `302`（跳转登录）均属于已就绪的正常结果
- `hermes mcp test kuaipao-image` 显示 `Connected` 且发现 `generate_image`
- `hermes mcp test github` 可连接（需先在 `.env` 设置 `GITHUB_PERSONAL_ACCESS_TOKEN`）
- `hermesctl.sh status` / `hermesctl.sh mcp` 显示 `WebUI 移动端底部 MCP/Toolsets 入口: 已就绪`
- WebUI：`http://服务器IP:8787` 或经 NPM 域名访问
- 移动端 WebUI：底部输入区点击圆形配置按钮（带 `0` / 上下文环）→ `Toolsets`，可选择全局默认或指定 MCP server

带 Key 测 API：

```bash
curl -s -H "Authorization: Bearer $(awk -F= '/^API_SERVER_KEY=/{print $2}' /opt/hermes/data/.env)" \
  http://127.0.0.1:50001/v1/models | head -c 300
```

---

## 4. 部署脚本环境变量

| 变量 | 含义 | 示例 |
|------|------|------|
| `FORCE=1` | 非交互，跳过“是否继续”确认 | `FORCE=1 bash ...` |
| `MCP_ONLY=1` | 只执行 MCP 构建、配置修复和 WebUI 补丁步骤 | `MCP_ONLY=1 bash ...` |
| `MCP_FROM_UPSTREAM=1` | 强制从上游重建全部 6 个 MCP 服务 | `MCP_FROM_UPSTREAM=1 bash ...` |
| `MCP_SKIP_PATCH=1` | 使用上游原版，不应用 `mcp-patches/` | 调试用 |
| `MCP_ZIP=/path/mcp.zip` | 解压定制 build 包 | `MCP_ZIP=/tmp/mcp.zip bash ...` |
| `MCP_GIT_URL=...` | 自定义 MCP 上游仓库（默认 slot181 仓库） | |
| `FORCE_MCP_REBUILD=1` | 等同于 `MCP_FROM_UPSTREAM=1`，强制重建全部 MCP | |
| `KEEP_MCP_ZIP=1` | 解压后保留 `mcp.zip` | |
| `DEBUG=1` | 脚本调试输出 | |

示例：

```bash
# 导入定制 build zip 并执行完整部署
MCP_ZIP=/root/mcp.zip FORCE=1 bash /opt/hermes/hermes-deploy.sh

# 只从上游重建全部 6 个 MCP 服务并应用补丁
MCP_ONLY=1 MCP_FROM_UPSTREAM=1 bash /opt/hermes/hermes-deploy.sh
```

---

## 5. 配置说明

### 5.1 `.env`（密钥中心）

路径：`/opt/hermes/data/.env`  
权限：`600`

关键项：

```bash
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=50001
API_SERVER_KEY=<随机生成，WebUI/客户端连 gateway 用>

# 对话渠道密钥（config.yaml key_env 引用）
HERMES_ATLASCLOUD_KEY=...
HERMES_CCVIBE_GROK_KEY=...
HERMES_CCVIBE_GPT_KEY=...
HERMES_KUAIPAO_GPT_KEY=...

# MCP 服务配置（hermesctl.sh / hermes-deploy.sh shell 函数读取）
MCP_KUAIPAO_KEY=...
MCP_KUAIPAO_API_URL=https://kuaipao.ai/v1
MCP_ATLASCLOUD_KEY=...
MCP_ATLASCLOUD_API_URL=https://api.atlascloud.ai

# GitHub MCP：npx @modelcontextprotocol/server-github
# 在 https://github.com/settings/tokens 生成 Personal Access Token（classic）
# 建议至少勾选 repo / read:org / read:user / gist
GITHUB_PERSONAL_ACCESS_TOKEN=ghp_...

HERMES_WEBUI_AGENT_DIR=/opt/hermes/hermes-agent
HERMES_WEBUI_STATE_DIR=/opt/hermes/data/webui

# WebUI 登录密码（公网反代必开）
HERMES_WEBUI_PASSWORD=YOUR_WEBUI_PASSWORD   # 初始值，上线后务必改为强密码
```

> 注意：`config.yaml` 里 provider 的 `key_env: HERMES_ATLASCLOUD_KEY` 必须在 `.env` 中存在同名变量。  
> MCP 密钥 `MCP_KUAIPAO_KEY` / `MCP_ATLASCLOUD_KEY` 和 API_URL 由 shell 函数在启动时读取，动态注入 `mcp_servers` 段。

### 5.2 `config.yaml`

路径：`/opt/hermes/data/config.yaml`

要点：

1. **provider 用 `key_env`，不写明文 key**  
2. **必须配置 `platform_toolsets.cli`**，否则 WebUI/TUI 看不到 MCP 工具：

```yaml
platform_toolsets:
  cli:
    - hermes-cli
    - kuaipao-image
    - atlascloud-seedream-v5.0-pro
    - atlascloud-seedream-v5.0-pro-edit
    - atlascloud-seedream-v5.0-lite-sequential
    - atlascloud-wan-edit
    - atlascloud-wan-edit-pro
    - github
```

3. **MCP 入口**（由 shell 函数在启动时从 `.env` 动态注入，不硬编码在 config.yaml）：

`mcp_servers` 段由 `hermesctl.sh` 的 `inject_mcp_config()` 或 `hermes-deploy.sh` 的 `step_inject_mcp()` 在启动时生成，读取 `.env` 中的 `MCP_KUAIPAO_KEY` / `MCP_KUAIPAO_API_URL` / `MCP_ATLASCLOUD_KEY` / `MCP_ATLASCLOUD_API_URL` / `GITHUB_PERSONAL_ACCESS_TOKEN`，路径自动适配 `/opt/hermes`。生成后内容类似：

```yaml
mcp_servers:
  kuaipao-image:
    command: node
    args:
      - /opt/hermes/mcp/kuaipao-image/build/index.js
    timeout: 660
    env:
      API_KEY: <从 .env MCP_KUAIPAO_KEY 读取>
      API_URL: <从 .env MCP_KUAIPAO_API_URL 读取>
      DEFAULT_IMAGE_MODEL: gpt-image-2-2k
      DEFAULT_OUTPUT_PATH: /opt/hermes/data/output
      REQUEST_TIMEOUT: "600000"
  github:
    command: npx
    args:
      - -y
      - '@modelcontextprotocol/server-github'
    timeout: 120
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: <从 .env GITHUB_PERSONAL_ACCESS_TOKEN 读取>
```

> MCP key 和 API_URL 完全走 `.env`，`config.yaml` 中不保存任何明文密钥。  
> 修改 MCP 配置只需编辑 `.env`，然后 `hermesctl.sh inject-mcp` 或重启服务即可。

### 5.2.1 对话上游故障保护

为避免某个对话上游返回 502 时页面长时间显示“卡住”，当前配置对对话渠道启用了单次请求超时和跨渠道 fallback：

```yaml
providers:
  atlascloud:
    models:
      gpt-5.6-luna:
        timeout_seconds: 60
      xai/grok-4.5:
        timeout_seconds: 60
  cc-vibe-grok:
    models:
      grok-4.5:
        timeout_seconds: 60
  cc-vibe-gpt:
    models:
      gpt-5.6-luna:
        timeout_seconds: 60
      gpt-5.6-sol:
        timeout_seconds: 60
  kuaipao-gpt:
    models:
      gpt-5.6-luna:
        timeout_seconds: 60
      gpt-5.6-sol:
        timeout_seconds: 60

agent:
  api_max_retries: 1

fallback_providers:
  - provider: kuaipao-gpt
    model: gpt-5.6-sol
    key_env: HERMES_KUAIPAO_GPT_KEY
  - provider: cc-vibe-gpt
    model: gpt-5.6-sol
    key_env: HERMES_CCVIBE_GPT_KEY
  - provider: atlascloud
    model: gpt-5.6-luna
    key_env: HERMES_ATLASCLOUD_KEY
  - provider: atlascloud-grok-4.3
    model: xai/grok-4.3
    key_env: HERMES_ATLASCLOUD_KEY
```

`api_max_retries: 1` 表示主渠道只请求一次；默认主模型为 `cc-vibe-gpt/gpt-5.6-luna`。主渠道返回 500/502/503、超时或连接失败时，Hermes 会按 `fallback_providers` 顺序尝试其他渠道。

### 5.3 WebUI 底部 MCP / Toolsets 入口

WebUI 的 MCP 选择不是模型选择器，而是 **Session Toolsets** 控件：

- PC / 宽屏：在底部输入区 footer 直接显示 `Toolsets` chip。
- 移动端：同样在底部输入区，但为了避免挤占宽度，收进圆形配置按钮（按钮里显示上下文环/`0`）。点击该按钮后，在弹出的底部配置面板中选择 `Toolsets`。
- `Global / Profile defaults` 表示使用 `platform_toolsets.cli` 配置的全局默认工具集。
- 勾选具体 MCP server 后，会作为当前会话的 `enabled_toolsets` 覆盖；清除则回到全局默认。

检查移动端入口是否随 WebUI 静态文件存在：

```bash
/opt/hermes/hermesctl.sh status
/opt/hermes/hermesctl.sh mcp
# 期望看到：WebUI 移动端底部 MCP/Toolsets 入口: 已就绪
```


### 5.3.1 移动端 Toolsets / MCP 入口（本机补丁）

上游在窄屏（容器宽度 &lt; ~1100px / `max-width:640px`）会 **隐藏** 底部 `Toolsets` chip（issue #1431），只保留圆形配置按钮，但面板内原先 **没有** Toolsets 项，导致手机点小圆钮看不到 MCP / Global defaults。

**部署时自动应用**：`hermes-deploy.sh` 在 `step_webui_mobile_patch` 调用 `patches/apply_webui_mobile_toolsets.py`；升级 WebUI 后也可：

```bash
/opt/hermes/hermesctl.sh webui-patch   # 菜单 [16]
```

补丁写入 `hermes-webui/static/`：

- `index.html`：`#composerMobileToolsetsAction` + `#composerMobileToolsetsLabel` 加入 `#composerMobileConfigPanel`
- `ui.js`：`toggleToolsetsDropdown` / `_positionToolsetsDropdown` 在 chip 隐藏时改走 mobile action；同步移动端标签
- `boot.js`：隐藏偏好同时覆盖 mobile toolsets action

**用法（手机）：** 底部圆形配置按钮 → **Toolsets / MCP** → 勾选 MCP 或 “Use active profile defaults”。

升级 WebUI 后若入口消失，检查上述三文件是否被覆盖，可从 git diff 恢复或重做本补丁。

### 5.4 `auth.json`

由 `/opt/hermes/data/refresh_auth_json.py` 在 gateway 启动前自动生成，**不要手改**。  
systemd 中：

```ini
ExecStartPre=/bin/bash /opt/hermes/hermesctl.sh inject-mcp
ExecStartPre=.../python .../refresh_auth_json.py
ExecStart=.../hermes gateway run --replace
```

---

## 6. MCP 部署详解（公开仓库 + VPS 定制）

### 6.1 标准流程（你要的方式）

```text
① git clone 公开仓库 slot181/openapi-integrator-mcp
② 在 VPS 上 npm install && npm run build
③ 复制为 6 个目录（kuaipao + 5 个 atlascloud）
④ 用 /opt/hermes/mcp-patches/ 覆盖 handlers.js / definitions.js（VPS 定制）
⑤ config.yaml 里用 env 配 API_URL / API_KEY / MODEL（运行时，无需重编）
```

上游公开仓库：

```text
https://github.com/slot181/openapi-integrator-mcp
```

### 6.2 目录职责

| 路径 | 作用 |
|------|------|
| `/opt/hermes/mcp/<name>/` | **运行目录**（gateway 启动的 `node build/index.js`） |
| `/opt/hermes/mcp-patches/<name>/` | **VPS 定制补丁**（`handlers.js`、`definitions.js`） |
| `config.yaml` → `mcp_servers.*.env` | **运行时** API_URL / API_KEY / 默认模型 |

补丁示例：

```text
/opt/hermes/mcp-patches/
  README.md
  kuaipao-image/{handlers.js,definitions.js}
  atlascloud-seedream-v5-pro/{handlers.js,definitions.js}
  atlascloud-seedream-edit/...
  atlascloud-seedream-edit-sequential/...
  atlascloud-wan-edit/...
  atlascloud-wan-edit-pro/...
```

当前环境已从现有定制 build **导出**了一份补丁到 `mcp-patches/`，可直接改。

### 6.3 为什么 atlascloud 要改代码

对齐 Windows 教程：

- kuaipao：OpenAI 兼容 `/v1/images/...`
- AtlasCloud：原生 `/api/v1/model/generateImage` + **异步轮询**
- 不改 `handlers.js` / `definitions.js` 直接套 kuaipao 代码 → 易 `ECONNRESET`

因此流程是：**先上游构建，再在 VPS 打补丁**，而不是指望 API URL 自动生成 6 套逻辑。

### 6.4 一键命令

```bash
# 从公开仓库重建 6 个 MCP，并应用 mcp-patches（只动 MCP）
/opt/hermes/hermesctl.sh mcp-rebuild
/opt/hermes/hermesctl.sh webui-patch   # 升级 WebUI 后恢复移动端 MCP 入口

# 等价
MCP_ONLY=1 MCP_FROM_UPSTREAM=1 bash /opt/hermes/hermes-deploy.sh

# 在 VPS 上改补丁后，仅覆盖运行目录（不重新 git）
nano /opt/hermes/mcp-patches/atlascloud-seedream-v5-pro/handlers.js
/opt/hermes/hermesctl.sh mcp-apply-patches
/opt/hermes/hermesctl.sh webui-patch
/opt/hermes/hermesctl.sh restart

# 若直接改了运行目录，导出回补丁目录固化
nano /opt/hermes/mcp/atlascloud-seedream-v5-pro/build/tools/handlers.js
/opt/hermes/hermesctl.sh mcp-export-patches
```

### 6.5 部署脚本处理顺序

`step_build_mcp`：

1. （可选）解压 `MCP_ZIP`；若尚无补丁则 **自动 export** 到 `mcp-patches/`  
2. 若缺 MCP 或 `MCP_FROM_UPSTREAM=1`：  
   - clone 公开仓库 → `npm install` → `npm run build`  
   - 复制为 6 个目录  
   - 应用 `mcp-patches`  
3. 已齐全则跳过上游，只补依赖并再 apply 一次补丁  

环境变量：

| 变量 | 含义 |
|------|------|
| `MCP_ONLY=1` | 只跑 MCP 步骤 |
| `MCP_FROM_UPSTREAM=1` | 强制上游重建 + 打补丁 |
| `MCP_SKIP_PATCH=1` | 只要上游原版，不打补丁（调试） |
| `MCP_GIT_URL=...` | 自定义上游 git |
| `MCP_ZIP=...` | 导入现成包并导出/应用补丁 |

### 6.6 在 VPS 上做 AtlasCloud 定制（步骤）

1. 确保已有上游构建：

```bash
/opt/hermes/hermesctl.sh mcp-rebuild
```

2. 编辑补丁（推荐改补丁目录）：

```bash
# 重点文件
/opt/hermes/mcp-patches/atlascloud-seedream-v5-pro/handlers.js
/opt/hermes/mcp-patches/atlascloud-seedream-v5-pro/definitions.js
# 其余 atlascloud-* 同理（edit / sequential / wan / wan-pro）
```

定制要点（Windows 教程）：

- 调用 AtlasCloud 原生 `generateImage` API  
- 实现任务提交 + **异步轮询**拿结果  
- `definitions.js` 中工具描述/参数与模型名匹配  

3. 应用并重启：

```bash
/opt/hermes/hermesctl.sh mcp-apply-patches
/opt/hermes/hermesctl.sh restart
/opt/hermes/hermesctl.sh mcp
```

4. 跨机迁移时 **带上补丁目录**：

```bash
scp -r /opt/hermes/mcp-patches root@新机:/opt/hermes/
# 新机：
MCP_ONLY=1 MCP_FROM_UPSTREAM=1 bash /opt/hermes/hermes-deploy.sh
```

### 6.7 Python MCP SDK

```bash
# hermes-agent 必须带 mcp extra
uv pip install --python /opt/hermes/venv/bin/python \
  -e "/opt/hermes/hermes-agent[messaging,anthropic,mcp]"
```

- Python `mcp`：Hermes 调度 MCP 进程  
- Node `build/index.js`：图片工具本体  

### 6.8 验证

```bash
/opt/hermes/hermesctl.sh mcp
```

期望：

```text
就绪: 6/6，补丁: 6/6
✓ Connected
generate_image
```

### 6.9 生图输出

```text
/opt/hermes/data/output/
```

`config.yaml` 中 `DEFAULT_OUTPUT_PATH` 指向该目录。改 `API_URL` **不需要**重新 Node 构建。

---


---

## 6.A MCP 定制补丁实装说明（对齐 Windows 教程，可移植）

> 对应 Windows：`notes/Hermes Agent Windows本地便携部署教程.html` 中 AtlasCloud 原生 API / kuaipao 路径规则。  
> 补丁目录：`/opt/hermes/mcp-patches/` + `/opt/hermes/patches/`（**跨机务必拷贝**）  
> **部署脚本已前置集成**：`hermes-deploy.sh` → `step_build_mcp` → `step_inject_mcp`（shell 函数从 `.env` 读取） → `step_webui_mobile_patch`  
> 手动：`hermesctl.sh mcp-apply-patches` / `inject-mcp` / `webui-patch` / `restart`

### 6.A.1 故障现象与根因

| MCP | 异常 | 根因 | 修复 |
|-----|------|------|------|
| `kuaipao-image` | `Invalid URL (POST /v1/v1/images/generations)` | `API_URL` 已含 `/v1`，handler 再拼 `/v1/...` | 补丁 `openaiV1Base()`；`API_URL=https://kuaipao.ai` |
| `atlascloud-*` | `400 bad request` / `ECONNRESET` | 上游 OpenAI `/v1/images/*` 与 Atlas 原生异步 API 不兼容 | 重写 handler：`generateImage` + 轮询 + `uploadMedia` |

### 6.A.2 补丁文件清单

```text
/opt/hermes/mcp-patches/
├── README.md
├── kuaipao-image/handlers.js          # OpenAI 兼容，智能 /v1
├── kuaipao-image/definitions.js
├── atlascloud-seedream-v5-pro/          # 文生图 profile=seedream-t2i
├── atlascloud-seedream-edit/          # 图生图 profile=seedream-edit
├── atlascloud-seedream-edit-sequential/  # profile=seedream-edit-seq + max_images
├── atlascloud-wan-edit/               # profile=wan-edit size=1K|2K
└── atlascloud-wan-edit-pro/           # profile=wan-edit-pro
```

每个 Atlas 补丁 `handlers.js` 内嵌 `PROFILE` 常量，共用逻辑：

1. `POST {API_URL}/api/v1/model/generateImage`
2. `GET {API_URL}/api/v1/model/prediction/{id}` 直到 `completed/succeeded/failed`
3. 本地路径图片：`POST {API_URL}/api/v1/model/uploadMedia` → `data.download_url` → `images[]`
4. **不发送** `moderation`
5. 忽略上游默认 `defaultEditImageModel=gpt-image-1`（避免误用）

### 6.A.3 config.yaml 关键 env（Linux 绝对路径）

```yaml
mcp_servers:
  kuaipao-image:
    command: node
    args: [/opt/hermes/mcp/kuaipao-image/build/index.js]
    timeout: 660
    env:
      API_KEY: <kuaipao key>
      API_URL: https://kuaipao.ai
      DEFAULT_IMAGE_MODEL: gpt-image-2-2k
      DEFAULT_OUTPUT_PATH: /opt/hermes/data/output
      REQUEST_TIMEOUT: "600000"

  atlascloud-seedream-v5-pro:
    command: node
    args: [/opt/hermes/mcp/atlascloud-seedream-v5-pro/build/index.js]
    timeout: 360
    env:
      API_KEY: <atlas key>
      API_URL: https://api.atlascloud.ai
      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/text-to-image
      DEFAULT_OUTPUT_PATH: /opt/hermes/data/output
      REQUEST_TIMEOUT: "600000"

  atlascloud-seedream-edit:
    env:
      API_URL: https://api.atlascloud.ai
      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/edit
      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/edit
      # ... 同上 KEY/OUTPUT/TIMEOUT

  atlascloud-seedream-edit-sequential:
    env:
      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit-sequential
      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit-sequential

  atlascloud-wan-edit:
    env:
      DEFAULT_IMAGE_MODEL: alibaba/wan-2.7/image-edit
      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7/image-edit

  atlascloud-wan-edit-pro:
    env:
      DEFAULT_IMAGE_MODEL: alibaba/wan-2.7-pro/image-edit
      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7-pro/image-edit
```

**硬性规则：**

- Atlas `API_URL` = `https://api.atlascloud.ai`（**禁止** `/api`、`/v1` 后缀）
- Seedream `size` = `WIDTH*HEIGHT`，且像素 ≥ **3686400**（推荐默认 `2048*2048`）
- Wan `size` = `1K` 或 `2K`（**禁止** `2048*2048` 这种 Seedream 格式）
- kuaipao 推荐 `API_URL=https://kuaipao.ai`；若误写 `/v1`，补丁仍可兼容

### 6.A.4 参数对照（写给模型 / 运维）

| 能力 | Seedream | Wan 2.7 |
|------|----------|---------|
| 端点 | 同：generateImage + prediction 轮询 | 同 |
| size | `2048*2048`、`2560*1440`… | `1K` / `2K` |
| 多图输出 | sequential：`max_images` 1–15 | `n` 1–4 |
| 参考图 | `images[]` URL | 最多 9 张（首张主图） |
| thinking | 无 | `thinking_mode` 默认 true |
| output_format | 可选 jpeg/png | 不支持 |
| moderation | 不发送 | 不发送 |

### 6.A.5 运维命令

```bash
# 应用补丁到运行目录 mcp/*/build/tools/
/opt/hermes/hermesctl.sh mcp-apply-patches
/opt/hermes/hermesctl.sh restart

# 连接探测（应 Connected + 工具列表）
/opt/hermes/hermesctl.sh mcp
/opt/hermes/venv/bin/hermes mcp test kuaipao-image
/opt/hermes/venv/bin/hermes mcp test atlascloud-seedream-v5-pro

# 改补丁源文件后重新导出固化
/opt/hermes/hermesctl.sh mcp-export-patches

# 上游重建（会重新 npm build，再自动 apply mcp-patches）
/opt/hermes/hermesctl.sh mcp-rebuild
```

### 6.A.6 移植清单（其它 VPS）

**最小携带：**

1. `/opt/hermes/hermes-deploy.sh`
2. `/opt/hermes/hermesctl.sh`
3. **`/opt/hermes/mcp-patches/` 整个目录**（本修复的核心）
4. （推荐）`/opt/hermes/data/.env` 密钥；或只迁 `mcp_servers` 的 KEY

**新机：**

```bash
mkdir -p /opt/hermes
# 上传上述文件后
FORCE=1 bash /opt/hermes/hermes-deploy.sh
/opt/hermes/hermesctl.sh start
# 若 deploy 时已有 mcp-patches，会自动应用；否则：
/opt/hermes/hermesctl.sh mcp-apply-patches
/opt/hermes/hermesctl.sh restart
```

### 6.A.7 本机已验证（2026-07-13）

- `kuaipao-image` generate → `local_path` + `source_url`（xAI imgen URL）
- `atlascloud-seedream-v5-pro` t2i `size=2048*2048` → poll `completed`
- `atlascloud-seedream-edit` 使用远程 `source_url` 编辑 → `completed`
- `atlascloud-wan-edit` `size=2K` 编辑 → `completed`
- 输出目录：`/opt/hermes/data/output/images/`

更细的补丁说明见：`/opt/hermes/mcp-patches/README.md`


## 7. systemd 服务

### 7.1 单元文件

- `/etc/systemd/system/hermes-gateway.service`
- `/etc/systemd/system/hermes-webui.service`

关键环境：

```ini
Environment=HERMES_HOME=/opt/hermes/data
Environment=HERMES_WEBUI_AGENT_DIR=/opt/hermes/hermes-agent
EnvironmentFile=/opt/hermes/data/.env
```

### 7.2 常用命令

```bash
systemctl status hermes-gateway hermes-webui
systemctl restart hermes-gateway hermes-webui
journalctl -u hermes-gateway -f --no-pager
journalctl -u hermes-webui -f --no-pager
```

或统一用：

```bash
/opt/hermes/hermesctl.sh restart
/opt/hermes/hermesctl.sh logs
```

---




### 默认对话模型

| 项 | 值 |
|----|-----|
| switch 名 | `cc-vibe-gpt-5.6-luna` |
| provider | `cc-vibe-gpt` |
| model | `gpt-5.6-luna` |
| base_url | `https://cc-vibe.com/v1` |

`hermes-deploy.sh` 生成的 `config.yaml` 与本机运行配置均以此为默认；菜单 **[18]** 可切回该默认。

### 对话渠道：`cc-vibe-gpt-5.6-luna`（**系统默认**）

| 项 | 值 |
|----|-----|
| switch 名 | `cc-vibe-gpt-5.6-luna`（菜单 **[18]**） |
| provider | `cc-vibe-gpt` |
| API | `https://cc-vibe.com/v1` |
| model | `gpt-5.6-luna` |
| key_env | `HERMES_CCVIBE_GPT_KEY`（写在 `.env`，勿写进 config 明文） |
| **默认** | **是** — 新装与当前 `model.default` / `model.provider` 均指向此模型 |

```bash
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-luna
```

### 对话渠道：`cc-vibe-gpt-5.6-sol`

| 项 | 值 |
|----|-----|
| switch 名 | `cc-vibe-gpt-5.6-sol`（菜单 **[19]**） |
| provider | `cc-vibe-gpt` |
| API | `https://cc-vibe.com/v1` |
| model | `gpt-5.6-sol` |
| key_env | `HERMES_CCVIBE_GPT_KEY`（写在 `.env`，勿写进 config 明文） |
| **默认** | 否 |

```bash
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-sol
```

### 对话渠道：`cc-vibe-grok`

| 项 | 值 |
|----|-----|
| switch 名 | `cc-vibe-grok`（菜单 **[17]**） |
| provider | `cc-vibe-grok` |
| API | `https://cc-vibe.com/v1` |
| model | `grok-4.5` |
| key_env | `HERMES_CCVIBE_GROK_KEY`（写在 `.env`，勿写进 config 明文） |
| **默认** | 否 |

```bash
/opt/hermes/hermesctl.sh switch cc-vibe-grok
```

cc-vibe 对话渠道 URL 相同，但按模型使用独立 API Key：`HERMES_CCVIBE_GPT_KEY` 用于 gpt-5.6-luna / gpt-5.6-sol，`HERMES_CCVIBE_GROK_KEY` 用于 grok-4.5。`config.yaml` 中的 `providers.cc-vibe-gpt.models` 声明 `gpt-5.6-luna` 与 `gpt-5.6-sol`，供模型选择器和切换校验使用。部署脚本会保留已有 `HERMES_CCVIBE_GROK_KEY` / `HERMES_CCVIBE_GPT_KEY`，不会再用脚本内置值覆盖它们。

### 对话渠道：`kuaipao-gpt-5.6-sol`

| 项 | 值 |
|----|-----|
| switch 名 | `kuaipao-gpt-5.6-sol`（菜单 **[20]**） |
| provider | `kuaipao-gpt` |
| API | `https://kuaipao.ai/v1` |
| model | `gpt-5.6-sol` |
| key_env | `HERMES_KUAIPAO_GPT_KEY`（写在 `.env`，勿写进 config 明文） |

```bash
/opt/hermes/hermesctl.sh switch kuaipao-gpt-5.6-sol
```

### 对话渠道：`kuaipao-gpt-5.6-luna`

| 项 | 值 |
|----|-----|
| switch 名 | `kuaipao-gpt-5.6-luna`（菜单 **[21]**） |
| provider | `kuaipao-gpt` |
| API | `https://kuaipao.ai/v1` |
| model | `gpt-5.6-luna` |
| key_env | `HERMES_KUAIPAO_GPT_KEY`（写在 `.env`，勿写进 config 明文） |

```bash
/opt/hermes/hermesctl.sh switch kuaipao-gpt-5.6-luna
```

### 对话渠道：`atlascloud-gpt-5.6-luna`

| 项 | 值 |
|----|-----|
| switch 名 | `atlascloud-gpt-5.6-luna`（菜单 **[24]**） |
| provider | `atlascloud` |
| API | `https://api.atlascloud.ai/v1` |
| model | `gpt-5.6-luna` |
| key_env | `HERMES_ATLASCLOUD_KEY`（写在 `.env`，勿写进 config 明文） |
| 回退保护 | 已加入 `fallback_providers`，主渠道故障时 Hermes 会回退到该模型 |

```bash
/opt/hermes/hermesctl.sh switch atlascloud-gpt-5.6-luna
```

## 8. 运维控制脚本 `hermesctl.sh`（数字菜单，对齐 start.bat）

Linux 版对应 Windows 的 `notes/start.bat`：**无参数进入数字菜单**；有参数走命令行。

### 8.1 打开菜单（推荐日常用法）

```bash
/opt/hermes/hermesctl.sh
# 或
bash /opt/hermes/hermesctl.sh
```

> **不要**单独敲 `switch` / `start` 当系统命令——那是菜单编号或脚本子命令。  
> 正确：`/opt/hermes/hermesctl.sh` 进菜单，或 `/opt/hermes/hermesctl.sh switch cc-vibe-grok`。

菜单顶部显示：目录、WebUI/API 地址、**当前** `provider` / `model` / `base_url`。  
选完一项后按 **Enter** 返回；`[0]` 退出。

### 8.2 菜单编号一览（连续编号；模型切换放最后）

| 键 | 功能 | 说明 |
|----|------|------|
| **1** | 启动 Gateway + WebUI（systemd 开机自启） | 服务 |
| **2** | 停止全部服务 | 服务 |
| **3** | 重启全部（先 refresh auth.json） | 服务 |
| **4** | 状态 / 端口 / HTTP 健康检查 | 服务 |
| **5** | 跟踪 gateway 日志（Ctrl+C 返回） | 服务 |
| **6** | 测试**当前** config 通道 API，并确认 `model.default` 在 `/models` 列表中 | 诊断 |
| **7** | `hermes doctor` | 诊断 |
| **8** | 检查端口 50001/8787/… | 诊断 |
| **9** | 编辑 `.env`（密钥中心） | 配置 |
| **10** | 编辑 `config.yaml` | 配置 |
| **11** | 刷新 `auth.json` | 配置 |
| **12** | MCP 状态 / `hermes mcp list` / test | MCP |
| **13** | MCP 从公开仓库重建 + 应用补丁 | MCP |
| **14** | 导出运行目录 → `mcp-patches/` | MCP |
| **15** | 应用 `mcp-patches/` → 运行目录 | MCP |
| **16** | WebUI 移动端 Toolsets/MCP 补丁 | MCP |
| **17** | cc-vibe-grok → grok-4.5 | |
| **18** | cc-vibe-gpt-5.6-luna → gpt-5.6-luna | **默认** |
| **19** | cc-vibe-gpt-5.6-sol → gpt-5.6-sol | |
| **20** | kuaipao-gpt-5.6-sol → gpt-5.6-sol | 同 kuaipao API |
| **21** | kuaipao-gpt-5.6-luna → gpt-5.6-luna | |
| **22** | atlascloud-grok-4.3 → xai/grok-4.3 | 同 Atlas API |
| **23** | atlascloud-grok-4.5 → xai/grok-4.5 | 复用 Atlas key |
| **24** | atlascloud-gpt-5.6-luna → gpt-5.6-luna | 复用 Atlas key / 回退保护 |
| **0** | 退出 | |

### 8.3 切换模型时实际做了什么

选 **[17]–[24]**（或 `hermesctl.sh switch <provider>`）会：

1. 校验目标 provider 的 `key_env` 已设置，并改 `config.yaml` 的 `model.default` / `model.provider` / `model.base_url`  
2. 重新解析 YAML，校验三项写入确实成功  
3. 运行 `refresh_auth_json.py` 重生 `auth.json`；刷新失败会立即停止，不会伪报成功  
4. 若 gateway 在跑 → `systemctl restart hermes-gateway`  
5. 打印当前 provider/model  

密钥仍在 `.env` 的 `key_env` 引用里，**不会**写进 config 明文。

实现说明（避免踩坑）：

- 切模型逻辑用 **环境变量** 把 `model/provider/url` 传给 Python（`HERMES_SW_*`）  
- Python 侧用 **引号 heredoc** `<<'PY'` + 字符串拼接写 config  
- **不要**在 heredoc 里直接写 f-string `{model}` 指望 bash 展开，否则会  
  `NameError: name 'model' is not defined`，config 实际未改  

成功示例输出：

```text
ℹ️  切换 → provider=cc-vibe-gpt model=gpt-5.6-luna
已写入 config.yaml: provider=cc-vibe-gpt, model=gpt-5.6-luna, base_url=https://cc-vibe.com/v1
✅ auth.json 已从 .env 刷新
✅ 已切换并重启 gateway
  当前: provider=cc-vibe-gpt  model=gpt-5.6-luna
  base_url=https://cc-vibe.com/v1
```

日常示例：

```text
/opt/hermes/hermesctl.sh
→ 输入 18  # 切到 cc-vibe-gpt-5.6-luna（默认）
→ Enter 回菜单
→ 输入 6   # 测当前通道
→ 输入 0   # 退出
```

### 8.4 命令行模式（脚本 / 自动化）

```bash
# 服务
/opt/hermes/hermesctl.sh start|stop|restart|status|logs

# 切模型
/opt/hermes/hermesctl.sh switch cc-vibe-grok              # grok-4.5
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-luna      # 默认 gpt-5.6-luna
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-sol       # gpt-5.6-sol
/opt/hermes/hermesctl.sh switch kuaipao-gpt-5.6-sol       # kuaipao + gpt-5.6-sol
/opt/hermes/hermesctl.sh switch kuaipao-gpt-5.6-luna      # kuaipao + gpt-5.6-luna
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.3       # xai/grok-4.3
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.5       # xai/grok-4.5
/opt/hermes/hermesctl.sh switch atlascloud-gpt-5.6-luna   # atlascloud + gpt-5.6-luna（复用 Atlas key）

# 配置
/opt/hermes/hermesctl.sh env|config|refresh

# 诊断 / MCP
/opt/hermes/hermesctl.sh test|doctor|ports|mcp
/opt/hermes/hermesctl.sh mcp-rebuild
/opt/hermes/hermesctl.sh mcp-export-patches
/opt/hermes/hermesctl.sh mcp-apply-patches

# 强制进菜单 / 帮助
/opt/hermes/hermesctl.sh menu
/opt/hermes/hermesctl.sh help
```

### 8.5 与 Windows `start.bat` 差异

| 点 | start.bat | hermesctl.sh |
|----|-----------|--------------|
| 进程托管 | 新窗口前台/后台 python | **systemd** 单元 |
| 密钥注入 | bat 内 `set KEY=...` | 读 `/opt/hermes/data/.env` |
| 路径修复 | fix_pyvenv / fix_mcp_paths | 本机绝对路径，一般不需要 |
| 菜单扩展 | 1–14 | 1–24（服务/诊断/配置/MCP + 模型放最后） |
| 无参数 | 直接菜单 | **直接菜单**（已对齐） |

### 8.6 常见误用与故障

```bash
# 错：系统找不到 switch
switch kuaipao

# 对：
/opt/hermes/hermesctl.sh          # 菜单选 18（默认 cc-vibe-gpt-5.6-luna → gpt-5.6-luna）
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-luna
```

| 现象 | 原因 | 处理 |
|------|------|------|
| `NameError: name 'model' is not defined` | 旧版脚本 f-string/heredoc 传参错误 | 更新 `/opt/hermes/hermesctl.sh` 后重开菜单（先 `[0]` 退出再进） |
| 显示“已切换”但 provider 没变 | 同上，写 config 失败仍继续 refresh | 同上；成功时应有一行 `已写入 config.yaml: ...` |
| `.env` source 报括号语法错 | `HERMES_USER_AGENT` 含 `()` | 当前脚本用安全解析加载 `.env`，勿改回 `source .env` |
| 菜单选项无效 / 仍像旧版 | 终端里还在跑旧进程 | `[0]` 退出后重新执行 `/opt/hermes/hermesctl.sh` |

---

## 9. Nginx Proxy Manager 反代（可选）

若 NPM 管理口在 `:81`：

| 项 | 值 |
|----|----|
| Domain Names | 你的域名 |
| Scheme | `http` |
| Forward Hostname | `127.0.0.1` |
| Forward Port | `8787` |
| WebSocket Support | 开启 |
| SSL | 按需 |

> WebUI 默认监听 `127.0.0.1:8787`，外网应走反代，不要直接裸奔公网。
>
> **公网反代必须开启密码保护**，否则任何人可免密使用你的模型额度。

### 9.1 开启 / 修改登录密码

```bash
# 编辑 .env
nano /opt/hermes/data/.env
# 修改或确认：
# HERMES_WEBUI_PASSWORD=你的强密码

systemctl restart hermes-webui

# 验证鉴权已生效（期望 auth_enabled=true）
curl -s http://127.0.0.1:8787/api/auth/status
```

初始密码为 `YOUR_WEBUI_PASSWORD`（由部署脚本写入），**反代上线前请修改**。

密码也可在登录后 **Settings → System → Change Password** 里修改（写入 `data/webui/settings.json`）；  
若 `.env` 同时有 `HERMES_WEBUI_PASSWORD`，**环境变量优先级更高**，以它为准。

---

## 10. 升级 / 重装

```bash
# 默认保留 data/.env 与 data/config.yaml
FORCE=1 bash /opt/hermes/hermes-deploy.sh
# deploy 已自动：mcp-patches + inject-mcp + 移动端 Toolsets 补丁
/opt/hermes/hermesctl.sh restart
# 若只 git pull 了 hermes-webui 而未跑 deploy：
/opt/hermes/hermesctl.sh webui-patch
```

行为摘要：

| 路径 | 升级时 |
|------|--------|
| `hermes-agent/` / `hermes-webui/` | git pull 或重装依赖 |
| `venv/` | 复用；缺 pip 则重建 |
| `data/.env` | **保留**（并补齐缺失变量） |
| `data/config.yaml` | **保留** |
| `mcp/` | 齐全则跳过；`mcp-rebuild` 可强制上游重建 |
| `mcp-patches/` | **VPS 定制补丁，升级务必保留/迁移** |

升级后建议额外检查一次移动端 MCP/Toolsets 入口，避免 WebUI 静态文件被上游覆盖后手机端无法选择 MCP：

```bash
/opt/hermes/hermesctl.sh status
/opt/hermes/hermesctl.sh mcp
# 期望：WebUI 移动端底部 MCP/Toolsets 入口: 已就绪
```

仅重建 MCP（公开仓库 + 补丁）：

```bash
/opt/hermes/hermesctl.sh mcp-rebuild
```

---

## 11. 故障排查

### 11.1 WebUI 调用 MCP 后“没有下文”

按顺序查：

```bash
# 1) Python MCP SDK
/opt/hermes/venv/bin/python -c "import mcp; print(mcp.__version__ if hasattr(mcp,'__version__') else 'ok')"

# 2) MCP 文件
ls /opt/hermes/mcp/*/build/index.js

# 3) 连接测试
/opt/hermes/hermesctl.sh mcp

# 4) platform_toolsets.cli 是否包含 MCP 名
grep -A20 platform_toolsets /opt/hermes/data/config.yaml

# 5) 日志
journalctl -u hermes-gateway -n 100 --no-pager
tail -50 /opt/hermes/data/logs/agent.log
```

常见根因：

1. 未安装 `hermes-agent[mcp]`  
2. `mcp/` 目录为空或没有 `build/index.js`  
3. `config.yaml` 缺少 `platform_toolsets.cli` 中的 MCP 名称  
4. 模型侧超时 / API Key 无效（看 gateway 日志）

### 11.2 gateway 401

`/v1/models` 无 Key 时返回 401 是正常的。用 `API_SERVER_KEY` 再测。

### 11.3 WebUI 起不来

```bash
journalctl -u hermes-webui -n 80 --no-pager
ss -tlnp | grep 8787
```

确认 `HERMES_WEBUI_AGENT_DIR` 指向 `/opt/hermes/hermes-agent`。

### 11.4 图片找不到

```bash
ls -lt /opt/hermes/data/output/ | head
```

### 11.5 菜单切模型报 `NameError: model`

```text
NameError: name 'model' is not defined
```

- **原因**：旧版 `hermesctl.sh` 在 Python heredoc 中误用 f-string `{model}`  
- **处理**：使用当前脚本（环境变量 `HERMES_SW_*` 传参）；`[0]` 退出菜单后重新打开  
- **自检**：切模型成功时必须出现 `已写入 config.yaml: provider=..., model=...`

```bash
# 命令行自检
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-luna
grep -E 'default:|provider:|base_url:' /opt/hermes/data/config.yaml | head -5
```

---

## 12. 从本机复制到另一台服务器

### 12.1 最小（推荐）：只拷两个脚本

```bash
scp /opt/hermes/hermes-deploy.sh /opt/hermes/hermesctl.sh root@目标:/opt/hermes/
scp -r /opt/hermes/mcp-patches /opt/hermes/patches root@目标:/opt/hermes/
ssh root@目标
chmod 700 /opt/hermes/*.sh
FORCE=1 bash /opt/hermes/hermes-deploy.sh
/opt/hermes/hermesctl.sh start
```

新机联网即可；**无需**上传 `mcp/`、`venv/`、源码。

### 12.2 可选：带上已调好的补丁 / 密钥

```bash
# 若已在某台 VPS 调好 Atlas 定制，可额外拷贝补丁（非必须）
scp -r /opt/hermes/mcp-patches root@目标:/opt/hermes/

# 若不想重新填 key，可拷贝 .env（注意权限与安全）
scp /opt/hermes/data/.env root@目标:/opt/hermes/data/.env
```

> 不要打包 `venv/`（目标机重建）。会话库/日志按需迁移。

---

## 13. 安全建议

1. `.env` / `config.yaml` / `auth.json` 权限保持 `600`。  
2. 脚本 `chmod 700`。  
3. 当前以 **root** 运行 gateway（与本机现状一致），生产建议改为非特权用户 + 沙箱终端。  
4. `API_SERVER_HOST=0.0.0.0` 时务必限制防火墙，仅信任网段可访问 `50001`（API 端口**不要反代到公网**）。  
5. 公网只暴露 NPM 反代后的 WebUI（8787），并开启 HTTPS。  
6. **必须在 `.env` 设置 `HERMES_WEBUI_PASSWORD`**，默认初始值 `YOUR_WEBUI_PASSWORD`，上线前修改为强密码并重启 `hermes-webui`。  
7. 通过 `hermesctl.sh status` 或 `curl http://127.0.0.1:8787/api/auth/status` 可随时确认鉴权状态。

---

## 14. 与 Windows 便携部署对照

| 项目 | Windows 便携 | Linux 本机 |
|------|--------------|------------|
| 根目录 | `F:\hermes_ui` | `/opt/hermes` |
| 启动 / 菜单 | `start.bat` 数字菜单 | `/opt/hermes/hermesctl.sh` 数字菜单 + systemd |
| 切模型 | bat 数字菜单 | 菜单 [17]–[24] 或 `hermesctl.sh switch …` |
| Python | 便携 Python / venv | `uv` + 3.12.13 + `/opt/hermes/venv` |
| Node | 便携 Node | NodeSource 最新 Current |
| 密钥 | bat 内 set / `.env` | `/opt/hermes/data/.env`（菜单 [9] 编辑） |
| MCP | `mcp\*\build\index.js` | `/opt/hermes/mcp/*` + 菜单 [12]–[16] |
| 输出 | `output\` | `/opt/hermes/data/output` |
| 配置路径 | Windows 绝对路径 | Linux 绝对路径 |

---

## 15. 一页速查

```bash
# 部署（新机只需两个脚本）
scp hermes-deploy.sh hermesctl.sh root@新机:/opt/hermes/
# 推荐同时带上：mcp-patches/ 与 patches/
FORCE=1 bash /opt/hermes/hermes-deploy.sh
# → 完成后 .env 自动写入 HERMES_WEBUI_PASSWORD=YOUR_WEBUI_PASSWORD
# → 如需 GitHub MCP：nano /opt/hermes/data/.env → 设置 GITHUB_PERSONAL_ACCESS_TOKEN=ghp_...
# → 上线前修改 WebUI 密码并重启：nano /opt/hermes/data/.env → systemctl restart hermes-webui

# 日常：数字菜单
/opt/hermes/hermesctl.sh
#   [1]–[5] 服务  [6]–[8] 诊断
#   [9]–[11] 配置  [12]–[16] MCP / WebUI 补丁
#   [17]–[24] 切模型（kuaipao / atlascloud / cc-vibe…）放最后
#   [0] 退出

# 命令行等价
/opt/hermes/hermesctl.sh start
/opt/hermes/hermesctl.sh status
/opt/hermes/hermesctl.sh test
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-luna  # 默认；成功应打印「已写入 config.yaml」
/opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-sol
/opt/hermes/hermesctl.sh switch cc-vibe-grok
/opt/hermes/hermesctl.sh switch kuaipao-gpt-5.6-sol
/opt/hermes/hermesctl.sh switch kuaipao-gpt-5.6-luna
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.3
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.5
/opt/hermes/hermesctl.sh switch atlascloud-gpt-5.6-luna
/opt/hermes/hermesctl.sh mcp
/opt/hermes/hermesctl.sh mcp-rebuild

# 日志 / 生图
journalctl -u hermes-gateway -f --no-pager
ls /opt/hermes/data/output
```

---

## 16. 本机已验证结论（参考）

在当前 `/opt/hermes` 环境已验证：

- Hermes Agent **v0.18.2** + Python **3.12.13** + Node **v26.x**
- 安装 `mcp` SDK 后 `hermes mcp test kuaipao-image` 成功
- `platform_toolsets.cli` 启用后 WebUI 才能真正调用 MCP
- 图片输出目录：`/opt/hermes/data/output`
- `hermesctl.sh` **数字菜单**可用；切模型 [17]–[24] 放菜单最后；默认 `cc-vibe-gpt/gpt-5.6-luna`
- 切模型：`HERMES_SW_*` 环境变量 + 引号 heredoc，无 `NameError`；
  例：`switch atlascloud-grok-4.3` → `provider=atlascloud-grok-4.3 model=xai/grok-4.3`
- MCP：公开仓库构建 6 个图像 MCP + `/opt/hermes/mcp-patches/` VPS 定制；GitHub MCP 使用 `npx -y @modelcontextprotocol/server-github`，密钥贴 `/opt/hermes/data/.env` 的 `GITHUB_PERSONAL_ACCESS_TOKEN=`
- **WebUI 密码保护**：`HERMES_WEBUI_PASSWORD=YOUR_WEBUI_PASSWORD`（已启用）；`hermesctl.sh status` 可确认 `auth_enabled=true`

---


- **MCP 定制补丁已落地**（2026-07-13）：`/opt/hermes/mcp-patches/` 含 kuaipao 智能 `/v1` + 5 个 AtlasCloud 原生 generateImage/轮询/uploadMedia 补丁；MCP 配置由 shell 函数从 `.env` 动态注入 `config.yaml`；详见 **§6.A** 与 `mcp-patches/README.md`

**文档路径**：`/opt/notes/Hermes Agent Linux本机直装部署教程.md`  
**脚本路径**：`/opt/hermes/hermes-deploy.sh`、`/opt/hermes/hermesctl.sh`
