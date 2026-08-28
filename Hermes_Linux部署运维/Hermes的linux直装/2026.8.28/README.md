# Hermes Ubuntu — 本机直装部署

Hermes Agent CLI + WebUI + MCP Server 在 Ubuntu 22.04+ 上的本机直装部署方案。
包含一键部署脚本、运维控制脚本、MCP 定制补丁和 WebUI 移动端补丁。

> 本仓库为私有部署配置仓库，不含 Hermes Agent / WebUI 源码（部署时自动从公开仓库 clone）。

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
│   └── ...
├── mcp-patches/              # MCP server 定制补丁（跨机必带）
│   ├── kuaipao-image/
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
> `data/output/`、数据库文件、`.env`、`auth.json`、`config.yaml` 等运行时/敏感文件已通过 `.gitignore` 排除。

---

## 快速部署

### 前置条件

- Ubuntu 22.04+ / root 权限
- 可访问 GitHub（部署时 clone 源码）
- 各渠道 API Key（见下方配置说明）

### 步骤

```bash
# 1. 克隆本仓库到 /opt/hermes
git clone https://github.com/metasu/Hermes_Ubuntu.git /opt/hermes
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

### 验证

```bash
/opt/hermes/hermesctl.sh status

# 检查 Gateway API
API_KEY=$(awk -F= '/^API_SERVER_KEY=/{print $2}' data/.env)
curl -s -H "Authorization: Bearer $API_KEY" http://127.0.0.1:50001/v1/models | head -c 200

# 检查 WebUI
curl -s http://127.0.0.1:8787/api/auth/status   # 期望 auth_enabled=true
```

---

## 密钥配置说明

所有密钥通过 `data/.env` 环境变量管理，`config.yaml` 仅通过 `key_env` 引用，不保存明文。

### 对话渠道密钥

| 环境变量 | 渠道 | 用途 |
|---|---|---|
| `HERMES_ATLASCLOUD_KEY` | AtlasCloud | Grok-4.6 / Grok-4.3（回退）|
| `HERMES_XIAOYI_OPUS_KEY` | xiaoyiapi.xyz | claude-opus-5（默认 provider）|
| `HERMES_XIAOYI_SOL_KEY` | xiaoyiapi.xyz | gpt-5.6-sol |

### MCP 服务密钥

| 环境变量 | 用途 |
|---|---|
| `XIAOYI_GROK_IMAGE_KEY` | xiaoyi-grok-image 图像生成 MCP |
| `XIAOYI_GROK_IMAGE_API_URL` | xiaoyi API 地址（默认 `https://xiaoyiapi.xyz/v1`）|
| `MCP_ATLASCLOUD_KEY` | AtlasCloud 图像生成/编辑 MCP |
| `MCP_ATLASCLOUD_API_URL` | AtlasCloud API 地址（默认 `https://api.atlascloud.ai`）|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub MCP（前往 https://github.com/settings/tokens 生成）|

### 其他

| 环境变量 | 说明 |
|---|---|
| `API_SERVER_KEY` | Gateway API 鉴权密钥（部署时自动随机生成）|
| `HERMES_WEBUI_PASSWORD` | WebUI 登录密码（**公网部署务必修改**）|
| `HERMES_USER_AGENT` | 反屏蔽 User-Agent |

> **安全提醒**：本仓库中所有密钥均为 `RRRR...` 红色占位符。请勿将真实密钥提交到仓库。
> `.env`、`auth.json`、`config.yaml` 已在 `.gitignore` 中排除。

---

## 可用模型

通过 `hermesctl.sh` 数字菜单切换（默认 `xiaoyi-claude-opus-5 → claude-opus-5`）：

| 菜单 | Provider | 模型 |
|---|---|---|
| `[17]` | xiaoyi-claude-opus-5 | claude-opus-5（当前生产默认）|
| `[18]` | xiaoyi-gpt-5-6-sol | gpt-5.6-sol |
| `[19]` | atlascloud-grok-4.3 | xai/grok-4.3 |
| `[20]` | atlascloud-grok-4.6 | xai/grok-4.6 |

命令行切换：
```bash
/opt/hermes/hermesctl.sh switch xiaoyi-claude-opus-5
/opt/hermes/hermesctl.sh switch xiaoyi-gpt-5-6-sol
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.3
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.6
```

### 回退保护池

主模型请求失败时自动回退到以下 Provider（按顺序）：

1. kuaipao-gpt / gpt-5.6-sol
2. atlascloud-grok-4.3 / xai/grok-4.3
3. atlascloud / xai/grok-4.6

---

## MCP Server

部署时自动从公开仓库 [slot181/openapi-integrator-mcp](https://github.com/slot181/openapi-integrator-mcp) 构建，复制为 6 个 MCP 目录，再应用 `mcp-patches/` 中的定制补丁。

| MCP Server | 用途 |
|---|---|
| xiaoyi-grok-image | xiaoyi 文生图/图生图（grok-imagine-image）|
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
/opt/hermes/hermesctl.sh env          # 查看环境变量
/opt/hermes/hermesctl.sh config       # 查看当前配置
/opt/hermes/hermesctl.sh test         # 连通性测试
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

---

## WebUI 移动端补丁

`patches/apply_webui_mobile_toolsets.py` 为 WebUI 添加移动端底部 Toolsets/MCP 圆形入口按钮。
部署时自动应用；升级 WebUI 后需重新应用：

```bash
/opt/hermes/hermesctl.sh webui-patch
```

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

### Q: 切换模型后不生效？
切换后需重启 gateway：
```bash
/opt/hermes/hermesctl.sh switch xiaoyi-gpt-5.6-sol
/opt/hermes/hermesctl.sh restart
```

### Q: 如何添加新渠道？
1. 在 `data/.env` 中添加 `HERMES_XXX_KEY=你的密钥`
2. 在 `data/config.yaml` 的 `providers:` 下添加 provider 块
3. 在 `hermesctl.sh` 的 `switch_provider` case 和菜单中添加条目
4. `/opt/hermes/hermesctl.sh refresh && /opt/hermes/hermesctl.sh restart`
