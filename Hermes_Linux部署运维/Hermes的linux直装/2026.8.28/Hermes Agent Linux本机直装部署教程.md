# Hermes Agent Linux 本机直装部署教程（2026.8.28）

> 本教程基于 `/opt/hermes` 实际部署环境编写，适用于 Ubuntu 22.04+ / Debian 12。

---

## 1. 环境要求

- Linux 服务器 / VPS（推荐 Ubuntu 22.04 / 24.04、Debian 12）
- systemd 可用
- 能访问 GitHub、pip、npm 源
- root 或 sudo 权限

必须预先安装的软件：

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip nodejs npm curl
```

---

## 2. 准备目录

```bash
sudo mkdir -p /opt/hermes
sudo chown $(whoami):$(whoami) /opt/hermes
cd /opt/hermes
```

将本仓库 `2026.8.28/` 目录下的所有文件复制到 `/opt/hermes/`：

```bash
# 假设你 clone 了 Ace 仓库到 ~/Ace
cp -r ~/Ace/Hermes_Linux部署运维/Hermes的linux直装/2026.8.28/* /opt/hermes/
```

复制后目录结构：

```
/opt/hermes/
├── hermes-deploy.sh          # 一键部署脚本
├── hermesctl.sh              # 运维控制脚本（数字菜单）
├── .gitignore
├── README.md
├── 部署前准备.md
├── patches/                  # WebUI 补丁
│   ├── apply_webui_mobile_toolsets.py
│   ├── fix_media_regex_asterisk.py
│   ├── fix_session_visit_models_swr.py
│   └── ...
├── mcp-patches/              # MCP server 定制补丁
│   ├── atlascloud-seedream-edit/
│   ├── atlascloud-seedream-edit-sequential/
│   ├── atlascloud-seedream-v5-pro/
│   ├── atlascloud-wan-edit/
│   ├── atlascloud-wan-edit-pro/
│   ├── xiaoyi-grok-image/
│   └── README.md
└── data/                     # 配置模板（密钥已脱敏）
    ├── .env.example
    ├── config.yaml.example
    ├── auth.json.example
    ├── refresh_auth_json.py
    └── SOUL.md
```

---

## 3. 填入真实密钥

所有模板中的 key 都已用 `sk-RRRRRR...` / `ghp_RRRRRRR...` 占位，**必须先替换为真实值**。

### 3.1 `.env`

```bash
cp data/.env.example data/.env
nano data/.env
```

至少填写：

| 变量 | 说明 |
|------|------|
| `HERMES_XIAOYI_KEY` | xiaoyi provider key |
| `HERMES_ATLASCLOUD_KEY` | atlascloud provider key |
| `XIAOYI_GROK_IMAGE_KEY` | 图片生成 MCP key |
| `HERMES_WEBUI_PASSWORD` | WebUI 登录密码（**上线前必须修改**） |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub MCP（可选） |

### 3.2 `config.yaml`

```bash
cp data/config.yaml.example data/config.yaml
nano data/config.yaml
```

确认 `provider` 和 `model` 与你使用的 API 通道匹配。也可部署后用 `hermesctl.sh switch` 切换。

### 3.3 `auth.json`（可选）

```bash
cp data/auth.json.example data/auth.json
# 如需自动刷新 auth.json：
python3 data/refresh_auth_json.py
```

---

## 4. 一键部署

```bash
cd /opt/hermes
FORCE=1 bash hermes-deploy.sh
```

部署脚本会自动完成：

1. 安装系统依赖（git, python3, nodejs, npm, build-essential 等）
2. 用 `uv` 安装 Python 3.12.13 到 `/opt/hermes/venv`
3. 安装 Node.js Current（NodeSource）
4. 克隆 `hermes-agent`（NousResearch/hermes-agent）
5. 克隆 `hermes-webui`（nesquena/hermes-webui）
6. 构建 MCP server（从公开仓库 + 应用 `mcp-patches/` 补丁）
7. 应用 WebUI 补丁：
   - `apply_webui_mobile_toolsets.py` — 移动端圆形按钮 → Toolsets/MCP 入口
   - `fix_media_regex_asterisk.py` — 修复 markdown `**加粗**` 被吞入图片路径
   - `fix_session_visit_models_swr.py` — session_visit 过期缓存立即返回（SWR），避免会话加载卡 4s
8. 从 `.env` 读取密钥，动态注入 MCP 配置到 `config.yaml`
9. 写入 systemd 服务（`hermes-gateway`、`hermes-webui`）
10. 启动服务

> `FORCE=1` 会重新拉取子仓库并重新打补丁，但默认保留 `data/.env` 和 `data/config.yaml`。

---

## 5. 部署后验证

```bash
# 查看服务状态
sudo systemctl status hermes-gateway
sudo systemctl status hermes-webui

# 或用控制脚本
/opt/hermes/hermesctl.sh status
```

打开浏览器访问：

```
http://<服务器IP>:8787
```

使用 `data/.env` 中设置的 `HERMES_WEBUI_PASSWORD` 登录。

---

## 6. 日常运维：hermesctl.sh

### 6.1 数字菜单

```bash
/opt/hermes/hermesctl.sh
```

菜单选项：

```
  [1]  启动 Gateway + WebUI（systemd）
  [2]  停止全部服务
  [3]  重启全部服务
  [4]  查看状态 / 端口
  [5]  跟踪 Gateway 日志
  [6]  测试当前 API 通道（config.yaml）
  [7]  hermes doctor
  [8]  检查端口占用
  [9]  编辑 .env（密钥）
  [10] 编辑 config.yaml
  [11] 刷新 auth.json + 注入 MCP 配置
  [12] MCP 状态 / list / test
  [13] MCP 从公开仓库重建 + 打补丁
  [14] 导出补丁 mcp-patches/
  [15] 应用补丁到运行目录
  [16] WebUI 移动端 Toolsets/MCP 补丁
  [17] xiaoyi-claude-opus-5       → claude-opus-5  (默认)
  [18] xiaoyi-gpt-5-6-sol         → gpt-5.6-sol
  [19] atlascloud-grok-4.3        → xai/grok-4.3
  [20] atlascloud-grok-4.6        → xai/grok-4.6
  [0]  退出
```

### 6.2 命令行等价

```bash
/opt/hermes/hermesctl.sh start          # 启动
/opt/hermes/hermesctl.sh stop           # 停止
/opt/hermes/hermesctl.sh restart        # 重启
/opt/hermes/hermesctl.sh status         # 状态
/opt/hermes/hermesctl.sh test           # 测试 API 通道
/opt/hermes/hermesctl.sh switch xiaoyi-claude-opus-5   # 切模型
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.3
/opt/hermes/hermesctl.sh mcp            # MCP 状态
/opt/hermes/hermesctl.sh mcp-rebuild    # 重建 MCP
/opt/hermes/hermesctl.sh webui-patch    # 应用 WebUI 补丁
```

---

## 7. MCP 定制补丁

`mcp-patches/` 目录包含 VPS 定制的 MCP server 补丁：

| 补丁 | 说明 |
|------|------|
| `atlascloud-seedream-v5-pro` | AtlasCloud Seedream v5 Pro 原生 generateImage |
| `atlascloud-seedream-edit` | Seedream 图片编辑 |
| `atlascloud-seedream-edit-sequential` | Seedream 顺序编辑 |
| `atlascloud-wan-edit` | Wan 图片编辑 |
| `atlascloud-wan-edit-pro` | Wan Pro 图片编辑 |
| `xiaoyi-grok-image` | xiaoyi Grok 图片生成 |

每个补丁目录包含：
- `definitions.js` — MCP tool 定义
- `handlers.js` — API 调用逻辑
- `config.index.js` — 配置注入（从 `.env` 读取 key/URL）

重建 MCP：

```bash
/opt/hermes/hermesctl.sh mcp-rebuild
```

---

## 8. WebUI 补丁

`patches/` 目录包含 WebUI 补丁，部署时自动应用，也可手动重新应用：

```bash
/opt/hermes/hermesctl.sh webui-patch
```

| 补丁 | 说明 |
|------|------|
| `apply_webui_mobile_toolsets.py` | 移动端圆形按钮 → Toolsets/MCP 入口 |
| `fix_media_regex_asterisk.py` | 修复 `**加粗**` 被吞入图片路径 |
| `fix_session_visit_models_swr.py` | session_visit 过期缓存立即返回（SWR），避免会话加载卡 4s |

---

## 9. 更新 / 重新部署

```bash
# 拉取最新代码后重新部署
cd /opt/hermes
git pull
FORCE=1 bash hermes-deploy.sh

# 仅重新应用 WebUI 补丁
/opt/hermes/hermesctl.sh webui-patch

# 仅重建 MCP
/opt/hermes/hermesctl.sh mcp-rebuild
```

---

## 10. 日志与输出

```bash
# Gateway 日志
journalctl -u hermes-gateway -f --no-pager

# WebUI 日志
journalctl -u hermes-webui -f --no-pager

# 图片 / 文件输出
ls /opt/hermes/data/output
```

---

## 11. 安全注意事项

1. **必须修改 `HERMES_WEBUI_PASSWORD`**，默认占位符 `YOUR_WEBUI_PASSWORD`，上线前改为强密码。
2. `data/.env`、`data/config.yaml`、`data/auth.json` 包含真实密钥，**不应提交到 GitHub**（`.gitignore` 已排除）。
3. 如需暴露到公网，建议配合 Nginx 反向代理 + HTTPS + 防火墙限制 8787 端口。
4. 定期更新系统依赖和 Hermes 子仓库。

---

## 12. 一页速查

```bash
# === 首次部署 ===
sudo mkdir -p /opt/hermes && cd /opt/hermes
# 复制 2026.8.28/ 下所有文件到此处
cp data/.env.example data/.env && nano data/.env       # 填密钥
cp data/config.yaml.example data/config.yaml            # 填配置
FORCE=1 bash hermes-deploy.sh

# === 日常运维 ===
/opt/hermes/hermesctl.sh          # 数字菜单
/opt/hermes/hermesctl.sh status   # 查状态
/opt/hermes/hermesctl.sh switch atlascloud-grok-4.3  # 切模型

# === 重新部署 ===
FORCE=1 bash hermes-deploy.sh
/opt/hermes/hermesctl.sh webui-patch
/opt/hermes/hermesctl.sh mcp-rebuild
```
