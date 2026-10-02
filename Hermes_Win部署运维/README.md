# Hermes Agent Windows 便携部署版

> Hermes Agent + WebUI 的 Windows 本地便携部署方案，无需安装 Python/Node.js/Git，解压即用。

## 目录结构

```
hermes_ui/
├── start.bat                    # 主启动脚本（一键启动 Gateway + WebUI）
├── data/                        # 配置与运行时数据
│   ├── .env                     # 环境变量配置（API Key 在此填写）
│   ├── config.yaml              # 核心配置文件（模型/Provider/MCP/Failover）
│   ├── auth.json                # 凭据池配置
│   ├── channel_directory.json   # 渠道目录
│   ├── SOUL.md                  # Agent 人格提示词
│   └── webui/                   # WebUI 运行时状态
├── hermes-agent/                # Hermes Agent 核心源码
├── hermes-webui/                # Hermes WebUI 前端服务
├── mcp/                         # MCP Server 插件目录
│   ├── kuaipao-image/               # Kuaipao 图片生成 (gpt-image-2.5-2k)
│   ├── atlascloud-seedream-v5-pro/   # Seedream v5 Pro 文生图
│   ├── atlascloud-seedream-edit/     # Seedream v5 Pro 编辑
│   ├── atlascloud-seedream-edit-sequential/  # Seedream v5 Lite 连续编辑
│   ├── atlascloud-wan-edit/     # Wan 2.7 图片编辑
│   └── atlascloud-wan-edit-pro/ # Wan 2.7 Pro 图片编辑
├── configure_failover.py        # Provider 故障转移链自动配置
├── inject_mcp_config.py         # MCP 配置动态注入脚本
├── refresh_auth_json.py         # auth.json 凭据池刷新
├── fix_pyvenv.py                # venv 路径修复（防盘符漂移）
├── fix_editable_finder.py       # editable install 路径修复
├── patches/                     # WebUI 补丁
│   └── apply_webui_mobile_toolsets.py  # 移动端 Toolsets/MCP 入口补丁
└── output/                      # 图片输出目录（不包含在仓库中）
```

## 前置要求

本部署方案需要配套的 **rely 依赖目录**（与 `hermes_ui` 同级），包含：

```
rely/
├── python/          # 便携版 Python 3.12+
├── venv/            # 虚拟环境（已安装 hermes-agent + 依赖）
├── node/            # 便携版 Node.js 18+
└── git/             # 便携版 Git（含 bash.exe）
```

> rely 目录不包含在仓库中，需另行准备或从发行包获取。

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/metasu/Hermes_win.git hermes_ui
```

### 2. 准备 rely 依赖目录

将 rely 目录放在 `hermes_ui` 的上级目录，使结构如下：

```
F:\
├── hermes_ui\      ← 本仓库
└── rely\           ← 便携依赖
```

### 3. 填写 API Key

所有密钥已脱敏为占位符，使用前必须替换为真实密钥。

#### 3.1 编辑 `data/.env`

```env
HERMES_ATLASCLOUD_KEY=你的AtlasCloud对话统一密钥
HERMES_KUAIPAO_KEY=你的Kuaipao密钥
```

#### 3.2 编辑 `start.bat`

在 `start.bat` 的对话渠道密钥段，将占位符替换为真实密钥：

```bat
set "HERMES_ATLASCLOUD_KEY=你的AtlasCloud对话统一密钥"
set "HERMES_KUAIPAO_KEY=你的Kuaipao密钥"
set "KUAIPAO_IMAGE_KEY=你的Kuaipao图片生成密钥"
set "MCP_ATLASCLOUD_KEY=你的AtlasCloud-MCP密钥"
set "GITHUB_PERSONAL_ACCESS_TOKEN=你的GitHub令牌"
```

> **安全提示**：`start.bat` 中的密钥仅以环境变量形式注入，`config.yaml` 中只引用 `key_env` 变量名而非明文密钥。请勿将含真实密钥的版本提交到仓库。

### 4. 启动

双击运行 `start.bat`，选择菜单：

| 选项 | 功能 |
|------|------|
| **[1]** | 启动 Hermes Gateway（后台） |
| **[2]** | 启动 Hermes WebUI（前台，端口 8787） |
| **[3]** | 同时启动 Gateway + WebUI |
| **[4]** | 停止所有 Hermes 进程 |
| **[5]** | 测试 API 连接 |
| **[6]** | 测试当前配置的渠道 API |
| **[7]** | 应用 WebUI 移动端 Toolsets/MCP 补丁 |
| **[8]** | 从 .env 刷新 auth.json |
| **[9]** | 退出 |
| **[10]** | 切换到 kuaipao (gpt-6.1-sol) [默认] |
| **[11]** | 切换到 atlascloud (xai/grok-4.3) |
| **[12]** | 切换到 atlascloud (xai/grok-4.6) |
| **[13]** | 切换到 atlascloud (openai/gpt-6-sol-codex) |

模型切换项集中在菜单末尾（[10]-[13]）。

推荐选择 **[3]** 同时启动 Gateway + WebUI。

### 5. 访问 WebUI

浏览器打开 `http://localhost:8787`

API Server 地址：`http://localhost:50001`

## 配置说明

### 模型与 Provider

`data/config.yaml` 中的 `model` 段定义当前使用的默认模型和 Provider：

```yaml
model:
  default: "gpt-6.1-sol"
  provider: "kuaipao"
  base_url: "https://kuaipao.ai/v1"
```

已配置的 Provider 渠道：

| Provider 名称 | 平台 | 模型（WebUI 显示名） | 密钥环境变量 |
|--------------|------|------|-------------|
| `kuaipao` | Kuaipao | gpt-6.1-sol | `HERMES_KUAIPAO_KEY` |
| `atlascloud` | AtlasCloud | xai/grok-4.3 (grok-4.3)<br>xai/grok-4.6 (grok-4.6)<br>openai/gpt-6-sol-codex (gpt-sol-codex6) | `HERMES_ATLASCLOUD_KEY` |

### 故障转移（Failover）

`configure_failover.py` 在每次启动时自动维护故障转移链。当主 Provider 不可用时，按以下顺序回退：

1. `atlascloud` / xai/grok-4.3
2. `atlascloud` / xai/grok-4.6
3. `atlascloud` / openai/gpt-6-sol-codex
4. `kuaipao` / gpt-6.1-sol

### MCP Server 配置

`inject_mcp_config.py` 在启动时自动将 MCP 配置注入 `config.yaml`。MCP Server 列表：

| MCP Server | 功能 | 密钥环境变量 |
|-----------|------|-------------|
| `kuaipao-image` | Kuaipao 图片生成 (gpt-image-2.5-2k) | `KUAIPAO_IMAGE_KEY` |
| `atlascloud-seedream-v5.0-pro` | Seedream v5 Pro 文生图 | `MCP_ATLASCLOUD_KEY` |
| `atlascloud-seedream-v5.0-pro-edit` | Seedream v5 Pro 图片编辑 | `MCP_ATLASCLOUD_KEY` |
| `atlascloud-seedream-v5.0-lite-sequential` | Seedream v5 Lite 连续编辑 | `MCP_ATLASCLOUD_KEY` |
| `atlascloud-wan-edit` | Wan 2.7 图片编辑 | `MCP_ATLASCLOUD_KEY` |
| `atlascloud-wan-edit-pro` | Wan 2.7 Pro 图片编辑 | `MCP_ATLASCLOUD_KEY` |
| `github` | GitHub MCP Server | `GITHUB_PERSONAL_ACCESS_TOKEN` |

图片输出路径：`hermes_ui\output\`（已 gitignore，不会上传）

WebUI 会话里勾选 MCP（如 github）是**叠加**到默认工具集上，不会关掉终端 / 文件 / 网页等内置工具。

### Kuaipao compact 请求

`start.bat` 对 Kuaipao 渠道设置了 `HERMES_COMPACT_REQUEST_PROVIDERS`，用来压缩过大的 system prompt / 历史，避免网关超时。**工具定义不会被裁剪**（`write_file` / `terminal` / MCP 始终保留）。若模型只回文字不改文件，请重启 WebUI 使本修复生效。

## 维护速查（下次修改先看这里）

### 密钥位置

| 用途 | 变量名 | 存放位置 | 说明 |
|------|--------|---------|------|
| AtlasCloud **对话统一密钥** | `HERMES_ATLASCLOUD_KEY` | `data/.env` 和 `start.bat` **两处都要改** | 供 `config.yaml` 的 `key_env` 引用 |
| AtlasCloud **MCP 统一密钥** | `MCP_ATLASCLOUD_KEY` | 仅 `start.bat` | 启动时由 `inject_mcp_config.py` 注入 `config.yaml` 的 `mcp_servers` 段 |
| Kuaipao 对话密钥 | `HERMES_KUAIPAO_KEY` | `data/.env` 和 `start.bat` 两处 | |
| Kuaipao 图片生成密钥 | `KUAIPAO_IMAGE_KEY` | 仅 `start.bat` | 注入 `mcp_servers.kuaipao-image` |
| GitHub PAT | `GITHUB_PERSONAL_ACCESS_TOKEN` | 仅 `start.bat` | 注入 `mcp_servers.github` |

当前真实密钥值见 `data/.env` 与 `start.bat`（本 README 保持脱敏，勿提交真实密钥）。

### config.yaml 中自动生成的区块（不要只改 yaml）

- **`mcp_servers:` 段** —— 每次启动被 `inject_mcp_config.py` 整段重写。改 MCP 密钥/服务器要改 `start.bat` 的环境变量或该脚本本身，手改 yaml 会在下次启动时被覆盖。
- **`fallback_providers:` 段** —— 每次启动被 `configure_failover.py` 重写。加/删/调回退模型要改脚本顶部的 `FALLBACK_CANDIDATES` 元组（顺序即回退优先级，当前激活的主渠道会被自动跳过）。
- **`auth.json`** —— 可手动在 `credential_pool` 加 `"custom:<provider名>": []` 槽位，或用菜单 **[8]** 从 `.env` + `config.yaml` 整体重建（重建会把真实 token 写入该文件）。

### 新增一个对话模型的完整步骤

在已有渠道下新增模型（以 atlascloud 为例），只需 3 处：

1. **`data/config.yaml` `providers.atlascloud.models:`**：加一条列表项。`label` 即 WebUI 模型下拉的显示名（**统一小写**）：

   ```yaml
   - id: openai/new-model-id
     label: new-model-name
     timeout_seconds: 60
   ```

   > `models` 写成列表 `- id:/label:` 时 `label` 是显示名；写成字典 `id: {…}` 时显示名自动取 id 第一段 `/` 之后的小写原文（如 `grok-4.3`）。当前显示名：`gpt-6.1-sol`（kuaipao）、`grok-4.3` / `grok-4.6` / `gpt-sol-codex6`（atlascloud）。
2. **`configure_failover.py`**：`FALLBACK_CANDIDATES` 加 `("atlascloud", "openai/new-model-id")`。同一 provider 可贡献多个回退条目，元组顺序即回退优先级。
3. **本 README**：更新 Provider 表、菜单表、回退链列表。

可选：**`start.bat`** 菜单加切换项（仿 `:switch_atlascloud_sol_codex`，注意同时改 `Select [1-N]` 范围和 `if "%choice%"=="N"` 分派行）。切到 atlascloud 下任意模型时 `provider` 都写 `atlascloud`、`default` 写模型 id。

> 只有新增**渠道**（而非模型）时才需要：`.env`/`start.bat` 加 `HERMES_<NAME>_KEY`、config.yaml 加整个 provider 块、`auth.json` `credential_pool` 加 `"custom:<provider名>": []`。

### 更换密钥的最小步骤

- **AtlasCloud 对话密钥**：改 `data/.env` 1 行 + `start.bat` 1 行 `HERMES_ATLASCLOUD_KEY`
- **Kuaipao 密钥**：改 `data/.env` 1 行 `HERMES_KUAIPAO_KEY` + `start.bat` 2 行 `HERMES_KUAIPAO_KEY` / `KUAIPAO_IMAGE_KEY`（对话和画图同 key 时一起改）
- **AtlasCloud MCP 密钥**：只改 `start.bat` 的 `MCP_ATLASCLOUD_KEY` 一行（`config.yaml` 里 `mcp_servers` 段的明文 `API_KEY` 会在下次启动时自动同步；如要立即生效也可顺手改 yaml）

改完用菜单 **[6]** 测当前渠道、**[5]** 跑 `hermes doctor`。

## 便携部署原理

### 防盘符漂移

当便携包被解压到不同盘符（如从 `F:\` 变为 `D:\`）时：

- `fix_pyvenv.py` — 重写 `venv/pyvenv.cfg` 中的 `home =` 路径，指向当前盘符的便携 Python
- `fix_editable_finder.py` — 重写 `site-packages` 中的 `__editable___hermes_agent_*_finder.py` 路径

### 动态配置注入

- `inject_mcp_config.py` — 根据当前 `%ROOT_DIR%` 动态生成 MCP 配置段并注入 `config.yaml`，路径始终匹配当前盘符
- `configure_failover.py` — 根据 `config.yaml` 中已有的 Provider 自动生成故障转移链
- `refresh_auth_json.py` — 从 `.env` 和 `config.yaml` 刷新 `auth.json` 凭据池

以上脚本在 `start.bat` 启动时自动执行，无需手动干预。

## 详细教程

完整的图文部署教程请参阅仓库根目录的 HTML 文件：

```
Hermes Agent Windows本地便携部署教程.html
```

用浏览器打开即可查看完整教程（含截图、步骤详解、常见问题排查）。

## 常见问题

### Q: 启动后 WebUI 界面不出现？

检查 `start.bat` 是否使用了 CRLF 换行（非 LF）。在 VS Code 右下角切换为 CRLF 后重新保存。

### Q: 提示 "rely directory not found"？

确保 `rely` 目录与 `hermes_ui` 同级。如 `hermes_ui` 在 `D:\hermes_ui`，则 `rely` 应在 `D:\rely`。

### Q: API 测试失败？

1. 检查 `data/.env` 和 `start.bat` 中的密钥是否已替换为真实值
2. 使用菜单 [6] 测试当前渠道
3. 使用菜单 [5] 运行 `hermes doctor` 诊断

### Q: 如何切换模型？

使用 `start.bat` 菜单 [10] / [11] / [12] / [13] 一键切换，或直接编辑 `data/config.yaml` 中的 `model.default` 和 `model.provider`。

### Q: MCP Server 不工作？

1. 确认 `mcp/*/build/index.js` 存在（需在 `mcp/*/` 下执行 `npm install && npm run build`）
2. 确认 `start.bat` 中对应的 `*_KEY` 环境变量已填入真实密钥
3. 检查 `config.yaml` 中 `mcp_servers` 段是否被正确注入（启动时会自动注入）

## 技术栈

- **Agent Core**: Python 3.12+ (Hermes Agent)
- **WebUI**: Python + HTML/CSS/JS (端口 8787)
- **MCP Servers**: Node.js 18+ (TypeScript)
- **Gateway**: Python (端口 50001)

## License

请参阅 `hermes-agent/LICENSE` 和 `hermes-webui/LICENSE`。
