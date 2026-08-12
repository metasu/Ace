#!/usr/bin/env bash
# hermes-deploy.sh - 本机直装 Hermes CLI + Hermes WebUI + MCP
# 适配：Ubuntu 22.04+ / root / systemd
# 参考：notes/Hermes Agent Windows本地便携部署教程.html
#       notes/Hermes Agent Linux本机直装部署教程.md
# 位置：/opt/hermes/hermes-deploy.sh
# ------------------------------------------------------------------------------
# 新机最小文件（无需上传 mcp/ 或其它目录）：
#   /opt/hermes/hermes-deploy.sh
#   /opt/hermes/hermesctl.sh          # 可选但推荐
# 脚本会自动：装依赖、clone hermes-agent/webui、构建 MCP 上游、写 systemd
#
# 用法：
#   mkdir -p /opt/hermes && cp hermes-deploy.sh hermesctl.sh /opt/hermes/
#   FORCE=1 bash /opt/hermes/hermes-deploy.sh
#   /opt/hermes/hermesctl.sh start
#
# MCP：默认从公开仓库构建；若存在 mcp-patches/ 则自动应用（推荐随脚本携带）
#   MCP_FROM_UPSTREAM=1 / MCP_ONLY=1  强制重建 MCP
#   无补丁时 atlascloud 为上游原版，可在 VPS 改完后 hermesctl.sh mcp-export-patches
#
# 前置补丁（部署时自动）：
#   patches/apply_webui_mobile_toolsets.py  — 移动端圆形按钮 → Toolsets/MCP
#   mcp-patches/<name>/handlers.js         — Atlas 原生 generateImage + 轮询 等
#   step_inject_mcp (shell)                — 从 .env 读取 MCP 密钥/URL，动态注入 config.yaml
# ------------------------------------------------------------------------------

set -u -o pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

# ---------- 可配置变量 ----------
PYTHON_VERSION="3.12.13"
# Node.js 使用 NodeSource current 通道，安装最新 Current 版本
NODE_CHANNEL="current"

HERMES_DIR="/opt/hermes"
HERMES_AGENT="${HERMES_DIR}/hermes-agent"
HERMES_WEBUI="${HERMES_DIR}/hermes-webui"
HERMES_DATA="${HERMES_DIR}/data"
HERMES_VENV="${HERMES_DIR}/venv"
HERMES_MCP="${HERMES_DIR}/mcp"
HERMES_OUTPUT="${HERMES_DATA}/output"
WEBUI_PORT="8787"
HERMES_PORT="50001"

BACKUP_DIR="${HERMES_DIR}/backups"

REPO_HERMES="https://github.com/NousResearch/hermes-agent.git"
REPO_WEBUI="https://github.com/nesquena/hermes-webui.git"

# ---------- 彩色输出 ----------
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[34m'; NC='\033[0m'
say(){ echo -e "${B}ℹ️ $*${NC}"; }
ok(){  echo -e "${G}✅ $*${NC}"; }
wrn(){ echo -e "${Y}⚠️ $*${NC}"; }
die(){ echo -e "${R}❌ $*${NC}"; exit 1; }

# ---------- 工具 ----------
have(){ command -v "${1:-}" >/dev/null 2>&1; }
ensure_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "需要 root：sudo $0"; }
rand_hex(){ openssl rand -hex "${1:-16}"; }

# 安全加载 .env（值可含空格/括号，勿直接 source）
load_env_safely(){
  local f="$1" line key val
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "$val" =~ ^\".*\"$ ]]; then val="${val:1:-1}"; fi
    if [[ "$val" =~ ^\'.*\'$ ]]; then val="${val:1:-1}"; fi
    export "$key=$val"
  done < "$f"
}

# ---------- 1. 环境预检 ----------
step_precheck(){
  say "Step 1 · 环境预检"
  ensure_root
  export PATH="${HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates git openssl unzip tar build-essential \
    python3-venv python3-dev >/dev/null || wrn "部分系统包安装失败，继续尝试"

  echo "--- 当前工具 ---"
  for t in uv python3 node git cmake systemctl openssl unzip; do
    printf "%-12s %s\n" "$t" "$(command -v $t 2>/dev/null || echo MISSING)"
  done

  echo "--- 端口占用 ---"
  if ss -tlnp 2>/dev/null | grep -qE ":(${HERMES_PORT}|${WEBUI_PORT})\\b"; then
    if systemctl is-active --quiet hermes-gateway 2>/dev/null \
      || systemctl is-active --quiet hermes-webui 2>/dev/null; then
      wrn "端口已被 Hermes 服务占用（升级/重装场景，继续）"
    else
      die "目标端口 ${HERMES_PORT}/${WEBUI_PORT} 已被其他进程占用"
    fi
  else
    ok "目标端口空闲"
  fi

  echo "--- 目录检查 ---"
  if [[ -d "$HERMES_DIR" ]]; then
    wrn "目标目录已存在：${HERMES_DIR}"
    if [[ "${FORCE:-0}" == "1" ]]; then
      wrn "FORCE=1，跳过确认"
    else
      read -rp "是否继续并更新源码/venv/MCP？（data 配置默认保留）(y/N): " ans
      [[ "$ans" =~ ^[Yy]$ ]] || die "已取消"
    fi
  fi
}

# ---------- 2. 安装 uv ----------
step_uv(){
  say "Step 2 · 安装 uv"
  if ! have uv; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    grep -q '.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  fi
  have uv || die "uv 安装失败"
  ok "uv $(uv --version)"
}

# ---------- 3. 安装 Python 3.12.13 ----------
step_python(){
  say "Step 3 · 安装 Python ${PYTHON_VERSION}"
  UV="$(command -v uv)"
  "$UV" python install "$PYTHON_VERSION"
  PY312="$($UV python find "$PYTHON_VERSION")"
  test -x "$PY312" || die "Python ${PYTHON_VERSION} 不可用"
  ok "Python: $PY312"
}

# ---------- 4. 安装 Node.js ----------
step_node(){
  say "Step 4 · 安装 Node.js 最新版"
  if have node && have npm; then
    ok "Node.js 已存在: $(node --version) / npm $(npm --version)"
    return 0
  fi
  # NodeSource current 通道，始终安装最新 Current 版本
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_CHANNEL}.x" | bash -
  apt-get install -y nodejs || die "Node.js 安装失败"
  have node || die "Node.js 安装后仍不可用"
  ok "Node.js $(node --version) / npm $(npm --version)"
}

# ---------- 5. 创建目录骨架 ----------
step_dirs(){
  say "Step 5 · 创建目录骨架"
  mkdir -p \
    "$HERMES_AGENT" "$HERMES_DATA" "$HERMES_VENV" "$HERMES_MCP" "$HERMES_OUTPUT" \
    "$HERMES_WEBUI" "$BACKUP_DIR" "${HERMES_DATA}/logs" "${HERMES_DATA}/webui"
  chmod 700 "$HERMES_DATA" 2>/dev/null || true
  ok "目录已创建"
  cat <<EOF
目录结构（全部位于 ${HERMES_DIR} 下）：
  hermes-deploy.sh / hermesctl.sh
  hermes-agent/     hermes-agent 源码
  hermes-webui/     hermes-webui 源码
  data/             .env / config.yaml / auth.json / logs / output / webui
  venv/             Python 3.12 虚拟环境
  mcp/              MCP 服务（Node.js 构建产物）
  backups/          配置备份
EOF
}

# ---------- 6. 克隆源码 ----------
step_clone(){
  say "Step 6 · 克隆/更新源码"
  if [[ -d "${HERMES_AGENT}/.git" ]]; then
    wrn "hermes-agent 已存在，尝试 git pull"
    git -C "$HERMES_AGENT" pull --ff-only || wrn "hermes-agent pull 失败，保留现有源码"
  else
    rm -rf "$HERMES_AGENT"
    git clone --depth 1 "$REPO_HERMES" "$HERMES_AGENT" || die "克隆 hermes-agent 失败"
  fi

  if [[ -d "${HERMES_WEBUI}/.git" ]]; then
    wrn "hermes-webui 已存在，尝试 git pull"
    git -C "$HERMES_WEBUI" pull --ff-only || wrn "hermes-webui pull 失败，保留现有源码"
  else
    rm -rf "$HERMES_WEBUI"
    git clone --depth 1 "$REPO_WEBUI" "$HERMES_WEBUI" || die "克隆 hermes-webui 失败"
  fi
  ok "源码就绪"
}

# ---------- 7. 创建 venv 并安装依赖 ----------
step_install(){
  say "Step 7 · 创建 venv 并安装依赖"
  UV="$(command -v uv)"
  PY312="$($UV python find "$PYTHON_VERSION")"

  # hermes venv（与 WebUI 共用），--seed 确保包含 pip/setuptools/wheel
  if [[ ! -x "$HERMES_VENV/bin/python" ]] || [[ ! -x "$HERMES_VENV/bin/pip" ]]; then
    rm -rf "$HERMES_VENV"
    "$UV" venv --seed --python "$PY312" "$HERMES_VENV"
  fi

  # 必须包含 mcp extra，否则 MCP server 无法连接
  "$UV" pip install --python "$HERMES_VENV/bin/python" -e "${HERMES_AGENT}[messaging,anthropic,mcp]" \
    || die "安装 hermes-agent 失败"

  if [[ -f "${HERMES_WEBUI}/requirements.txt" ]]; then
    "$UV" pip install --python "$HERMES_VENV/bin/python" -r "${HERMES_WEBUI}/requirements.txt" \
      || die "安装 hermes-webui 依赖失败"
  fi

  "$UV" pip install --python "$HERMES_VENV/bin/python" pyyaml

  ok "依赖安装完成"
  "$HERMES_VENV/bin/python" -m hermes_cli.main --version 2>/dev/null || true
  "$HERMES_VENV/bin/python" -c "import mcp; print('mcp SDK:', getattr(mcp, '__version__', 'ok'))" \
    || die "mcp Python SDK 未安装成功"
}

# ---------- 8. 生成 .env 模板 ----------
step_env(){
  say "Step 8 · 生成 .env 模板"
  if [[ -f "${HERMES_DATA}/.env" ]]; then
    cp "${HERMES_DATA}/.env" "${BACKUP_DIR}/.env.$(date +%Y%m%d-%H%M%S)"
    wrn ".env 已存在，保留现有文件（备份到 backups/）"
    if ! grep -q '^HERMES_ATLASCLOUD_KEY=' "${HERMES_DATA}/.env"; then
      echo "HERMES_ATLASCLOUD_KEY=apikey-YOUR_ATLASCLOUD_KEY" >> "${HERMES_DATA}/.env"
      wrn "已补齐 HERMES_ATLASCLOUD_KEY"
    fi
    if ! grep -q '^HERMES_WEBUI_AGENT_DIR=' "${HERMES_DATA}/.env"; then
      echo "HERMES_WEBUI_AGENT_DIR=${HERMES_AGENT}" >> "${HERMES_DATA}/.env"
    fi
    if ! grep -q '^HERMES_WEBUI_STATE_DIR=' "${HERMES_DATA}/.env"; then
      echo "HERMES_WEBUI_STATE_DIR=${HERMES_DATA}/webui" >> "${HERMES_DATA}/.env"
    fi
    if ! grep -q '^HERMES_WEBUI_PASSWORD=' "${HERMES_DATA}/.env"; then
      printf '\n# ===== WebUI 登录密码（公网反代必开）=====\nHERMES_WEBUI_PASSWORD=YOUR_WEBUI_PASSWORD\n' >> "${HERMES_DATA}/.env"
      wrn "已补齐 HERMES_WEBUI_PASSWORD（默认 YOUR_WEBUI_PASSWORD，公网务必修改）"
    fi
    for key in HERMES_CCVIBE_GROK_KEY HERMES_CCVIBE_GPT_KEY HERMES_KUAIPAO_GPT_KEY; do
      if ! grep -q "^${key}=" "${HERMES_DATA}/.env"; then
        printf '%s=\n' "${key}" >> "${HERMES_DATA}/.env"
        wrn "已补齐 ${key}，请在 .env 中填入有效密钥"
      fi
    done
    for key in MCP_KUAIPAO_KEY MCP_ATLASCLOUD_KEY MCP_KUAIPAO_API_URL MCP_ATLASCLOUD_API_URL; do
      if ! grep -q "^${key}=" "${HERMES_DATA}/.env"; then
        case "$key" in
          MCP_KUAIPAO_API_URL)   printf '%s=https://kuaipao.ai/v1\n' "$key" >> "${HERMES_DATA}/.env" ;;
          MCP_ATLASCLOUD_API_URL) printf '%s=https://api.atlascloud.ai\n' "$key" >> "${HERMES_DATA}/.env" ;;
          *) printf '%s=\n' "$key" >> "${HERMES_DATA}/.env" ;;
        esac
        wrn "已补齐 ${key}（MCP 服务），请在 .env 中复核"
      fi
    done
    chmod 600 "${HERMES_DATA}/.env"
    ok ".env 已保留"
    return 0
  fi

  HERMES_API_KEY="$(rand_hex 32)"
  cat > "${HERMES_DATA}/.env" <<EOF
# ===== Hermes Gateway =====
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=${HERMES_PORT}
API_SERVER_KEY=${HERMES_API_KEY}

# ===== 对话渠道密钥（config.yaml key_env 引用）=====
HERMES_ATLASCLOUD_KEY=apikey-YOUR_ATLASCLOUD_KEY
HERMES_CCVIBE_GROK_KEY=sk-YOUR_CCVIBE_GROK_KEY
HERMES_CCVIBE_GPT_KEY=sk-YOUR_CCVIBE_KEY
HERMES_KUAIPAO_GPT_KEY=sk-YOUR_KUAIPAO_KEY

# ===== MCP 服务配置（hermesctl.sh / hermes-deploy.sh 读取，不写入 config.yaml）=====
MCP_KUAIPAO_KEY=sk-YOUR_KUAIPAO_KEY
MCP_KUAIPAO_API_URL=https://kuaipao.ai/v1
MCP_ATLASCLOUD_KEY=apikey-YOUR_MCP_ATLASCLOUD_KEY
MCP_ATLASCLOUD_API_URL=https://api.atlascloud.ai

# GitHub MCP（npx @modelcontextprotocol/server-github）
# 前往 https://github.com/settings/tokens 生成 Personal Access Token（classic），至少勾选 repo / read:org / read:user / gist
GITHUB_PERSONAL_ACCESS_TOKEN=

# ===== 反屏蔽 User-Agent =====
HERMES_USER_AGENT=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36

# ===== 调试与行为 =====
WEB_TOOLS_DEBUG=false
HERMES_HUMAN_DELAY_MODE=off

# ===== WebUI 发现路径 =====
HERMES_WEBUI_AGENT_DIR=${HERMES_AGENT}
HERMES_WEBUI_STATE_DIR=${HERMES_DATA}/webui

# ===== WebUI 登录密码（公网反代必开）=====
# 默认初始密码；上线后请立即修改并 systemctl restart hermes-webui
HERMES_WEBUI_PASSWORD=YOUR_WEBUI_PASSWORD
EOF
  chmod 600 "${HERMES_DATA}/.env"
  ok ".env 已生成（密钥已按 Windows 教程预填，请按需复核）"
  echo "    API_SERVER_KEY=${HERMES_API_KEY}"
  echo "    WebUI 初始密码: YOUR_WEBUI_PASSWORD（公网务必修改）"
}

# ---------- 9. 生成 config.yaml 模板 ----------
step_config(){
  say "Step 9 · 生成 config.yaml 模板"
  if [[ -f "${HERMES_DATA}/config.yaml" ]]; then
    cp "${HERMES_DATA}/config.yaml" "${BACKUP_DIR}/config.yaml.$(date +%Y%m%d-%H%M%S)"
    wrn "config.yaml 已存在，保留现有文件（备份到 backups/）"
    if ! grep -q 'platform_toolsets:' "${HERMES_DATA}/config.yaml"; then
      wrn "现有 config.yaml 缺少 platform_toolsets.cli，MCP 工具可能对 WebUI 不可见"
      wrn "请参考教程补齐，或删除 config.yaml 后重新运行本脚本生成完整模板"
    fi
    # 统一 cc-vibe 标准渠道，并补齐 Atlas Grok 4.3 provider 与回退保护。
    python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/hermes/data/config.yaml")
t = p.read_text(encoding="utf-8")
block = """  atlascloud-grok-4.3:
    base_url: https://api.atlascloud.ai/v1
    key_env: HERMES_ATLASCLOUD_KEY
    model: xai/grok-4.3
  cc-vibe-gpt:
    base_url: https://cc-vibe.com/v1
    key_env: HERMES_CCVIBE_GPT_KEY
    model: gpt-5.6-luna
    models:
      gpt-5.6-luna:
        timeout_seconds: 60
      gpt-5.6-sol:
        timeout_seconds: 60
  cc-vibe-grok:
    base_url: https://cc-vibe.com/v1
    key_env: HERMES_CCVIBE_GROK_KEY
    model: grok-4.5
    models:
      grok-4.5:
        timeout_seconds: 60
"""
# Provider 块均为两空格缩进；移除旧块后统一插入，重复部署不会产生副本。
t2 = re.sub(r"^  cc-vibe-[^:\n]+:\n(?:    .*\n)*", "", t, flags=re.M)
t2 = re.sub(r"^  atlascloud-grok-4\.3:\n(?:    .*\n)*", "", t2, flags=re.M)
t2 = t2.replace("providers:\n", "providers:\n" + block, 1)
# 若当前主模型仍指向已下线的 cc-vibe 渠道，则回落到默认 cc-vibe-gpt-5.6-luna。
m = re.search(r'^  provider:\s*["\']?([^"\'\n]+)', t2, re.M)
known = {"cc-vibe-gpt", "cc-vibe-grok", "kuaipao-gpt", "atlascloud", "atlascloud-grok-4.3", "atlascloud-grok-4.5"}
if m and m.group(1).strip() not in known and m.group(1).strip().startswith("cc-vibe-"):
    t2 = re.sub(r'^  default:.*$', '  default: "gpt-5.6-luna"', t2, count=1, flags=re.M)
    t2 = re.sub(r'^  provider:.*$', '  provider: "cc-vibe-gpt"', t2, count=1, flags=re.M)
    t2 = re.sub(r'^  base_url:.*$', '  base_url: "https://cc-vibe.com/v1"', t2, count=1, flags=re.M)
# 回退链中保留 Atlas GPT-5.6-luna 与 Atlas Grok 4.3 各一条。
fallback_entry = """  - provider: atlascloud
    model: gpt-5.6-luna
    key_env: HERMES_ATLASCLOUD_KEY
  - provider: atlascloud-grok-4.3
    model: xai/grok-4.3
    key_env: HERMES_ATLASCLOUD_KEY
"""
t2 = re.sub(
    r"^  - provider: atlascloud(?:-grok-4\.3)?\n    model: [^\n]+\n    key_env: HERMES_ATLASCLOUD_KEY\n(?:\n)*",
    "",
    t2,
    flags=re.M,
)
if "fallback_providers:\n" in t2:
    t2 = re.sub(r"^terminal:\n", fallback_entry + "\nterminal:\n", t2, count=1, flags=re.M)
p.write_text(t2, encoding="utf-8")
print("normalized cc-vibe providers and atlascloud-grok-4.3 fallback")
PY

    # 现有 config.yaml 的 provider 块已标准化；主模型保留不变，可用 hermesctl.sh switch 切换。
    return 0
  fi

  cat > "${HERMES_DATA}/config.yaml" <<'EOF'
# 本文件不保存明文 API Key，所有 key 通过 key_env 引用 .env 中的环境变量。
# 配置复用自 notes/Hermes Agent Windows本地便携部署教程.html，仅路径改为 Linux。
model:
  default: "gpt-5.6-luna"
  provider: "cc-vibe-gpt"
  base_url: "https://cc-vibe.com/v1"
  default_headers:
    User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML,
      like Gecko) Chrome/124.0.0.0 Safari/537.36

providers:
  atlascloud:
    base_url: https://api.atlascloud.ai/v1
    key_env: HERMES_ATLASCLOUD_KEY
    model: gpt-5.6-luna
    models:
      gpt-5.6-luna:
        timeout_seconds: 60
      xai/grok-4.5:
        timeout_seconds: 60
  atlascloud-grok-4.3:
    base_url: https://api.atlascloud.ai/v1
    key_env: HERMES_ATLASCLOUD_KEY
    model: xai/grok-4.3
  cc-vibe-grok:
    base_url: https://cc-vibe.com/v1
    key_env: HERMES_CCVIBE_GROK_KEY
    model: grok-4.5
    models:
      grok-4.5:
        timeout_seconds: 60
  cc-vibe-gpt:
    base_url: https://cc-vibe.com/v1
    key_env: HERMES_CCVIBE_GPT_KEY
    model: gpt-5.6-luna
    models:
      gpt-5.6-luna:
        timeout_seconds: 60
      gpt-5.6-sol:
        timeout_seconds: 60
  kuaipao-gpt:
    base_url: https://kuaipao.ai/v1
    key_env: HERMES_KUAIPAO_GPT_KEY
    model: gpt-5.6-luna
    models:
      gpt-5.6-luna:
        timeout_seconds: 60
      gpt-5.6-sol:
        timeout_seconds: 60
    discover_models: true

agent:
  reasoning_effort: none
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

terminal:
  backend: local
  cwd: .
  timeout: 180

compression:
  enabled: true
  threshold: 0.5
  target_ratio: 0.2
  protect_last_n: 20

memory:
  memory_enabled: true
  user_profile_enabled: true

command_allowlist:
- execute_code
- recursive delete

streaming: true

# 为 CLI/TUI/WebUI 平台启用所有 MCP server 工具集
# （TUI/WebUI 实际按 cli 平台解析工具集）
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

_config_version: 33

# mcp_servers: 由 hermesctl.sh / hermes-deploy.sh 在启动时从 .env（密钥 + API_URL）+ 动态路径生成，不在此文件中硬编码。
# 如需修改 MCP 配置，编辑 .env 中的 MCP_KUAIPAO_KEY / MCP_KUAIPAO_API_URL / MCP_ATLASCLOUD_KEY / MCP_ATLASCLOUD_API_URL。

# security:
#   redact_secrets: true
#   tirith_enabled: true
#   tirith_path: "tirith"
#   tirith_timeout: 5
#   tirith_fail_open: true
#
# fallback_model:
#   provider: openrouter
#   model: anthropic/claude-sonnet-4
EOF
  chmod 600 "${HERMES_DATA}/config.yaml"
  ok "config.yaml 已生成"
}

# ---------- 9b. 注入 MCP 配置到 config.yaml ----------
step_inject_mcp(){
  say "Step 9b · 注入 MCP 配置（shell，从 .env 读取）"
  local config="${HERMES_DATA}/config.yaml"
  local root="${HERMES_DIR}"
  [[ -f "$config" ]] || { wrn "config.yaml 不存在，跳过"; return 0; }

  load_env_safely "${HERMES_DATA}/.env"
  local kuaipao_key="${MCP_KUAIPAO_KEY:-}"
  local kuaipao_url="${MCP_KUAIPAO_API_URL:-https://kuaipao.ai/v1}"
  local atlascloud_key="${MCP_ATLASCLOUD_KEY:-}"
  local atlascloud_url="${MCP_ATLASCLOUD_API_URL:-https://api.atlascloud.ai}"
  local github_token="${GITHUB_PERSONAL_ACCESS_TOKEN:-}"
  local out="${root}/data/output"

  local mcp_yaml
  mcp_yaml=$(cat <<EOF
mcp_servers:
  kuaipao-image:
    command: node
    args:
      - ${root}/mcp/kuaipao-image/build/index.js
    timeout: 660
    env:
      API_KEY: ${kuaipao_key}
      API_URL: ${kuaipao_url}
      DEFAULT_IMAGE_MODEL: gpt-image-2-2k
      DEFAULT_OUTPUT_PATH: ${out}
      REQUEST_TIMEOUT: '600000'
  atlascloud-seedream-v5.0-pro:
    command: node
    args:
      - ${root}/mcp/atlascloud-seedream-v5-pro/build/index.js
    timeout: 360
    env:
      API_KEY: ${atlascloud_key}
      API_URL: ${atlascloud_url}
      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/text-to-image
      DEFAULT_OUTPUT_PATH: ${out}
      REQUEST_TIMEOUT: '600000'
  atlascloud-seedream-v5.0-pro-edit:
    command: node
    args:
      - ${root}/mcp/atlascloud-seedream-edit/build/index.js
    timeout: 660
    env:
      API_KEY: ${atlascloud_key}
      API_URL: ${atlascloud_url}
      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/edit
      DEFAULT_OUTPUT_PATH: ${out}
      REQUEST_TIMEOUT: '600000'
  atlascloud-seedream-v5.0-lite-sequential:
    command: node
    args:
      - ${root}/mcp/atlascloud-seedream-edit-sequential/build/index.js
    timeout: 660
    env:
      API_KEY: ${atlascloud_key}
      API_URL: ${atlascloud_url}
      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit-sequential
      DEFAULT_OUTPUT_PATH: ${out}
      REQUEST_TIMEOUT: '600000'
  atlascloud-wan-edit:
    command: node
    args:
      - ${root}/mcp/atlascloud-wan-edit/build/index.js
    timeout: 660
    env:
      API_KEY: ${atlascloud_key}
      API_URL: ${atlascloud_url}
      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7/image-edit
      DEFAULT_OUTPUT_PATH: ${out}
      REQUEST_TIMEOUT: '600000'
  atlascloud-wan-edit-pro:
    command: node
    args:
      - ${root}/mcp/atlascloud-wan-edit-pro/build/index.js
    timeout: 660
    env:
      API_KEY: ${atlascloud_key}
      API_URL: ${atlascloud_url}
      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7-pro/image-edit
      DEFAULT_OUTPUT_PATH: ${out}
      REQUEST_TIMEOUT: '600000'
  github:
    command: npx
    args:
      - -y
      - '@modelcontextprotocol/server-github'
    timeout: 120
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: ${github_token}
EOF
)

  if grep -q '^mcp_servers:' "$config"; then
    awk '/^mcp_servers:/{skip=1;next} skip&&/^[^ \t]/{skip=0} !skip' "$config" > "${config}.tmp"
  else
    cp "$config" "${config}.tmp"
  fi
  printf '\n%s\n' "$mcp_yaml" >> "${config}.tmp"
  mv "${config}.tmp" "$config"
  ok "mcp_servers 已注入 config.yaml"
}

# ---------- 10. 生成 auth.json 刷新脚本 ----------
step_auth(){
  say "Step 10 · 生成 auth.json 刷新脚本"
  cat > "${HERMES_DATA}/refresh_auth_json.py" <<'PY'
import json
import pathlib
import re
from datetime import datetime, timezone

env_path = pathlib.Path('/opt/hermes/data/.env')
auth_path = pathlib.Path('/opt/hermes/data/auth.json')

env = {}
if env_path.exists():
    for line in env_path.read_text().splitlines():
        m = re.match(r'^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$', line)
        if m:
            env[m.group(1)] = m.group(2).strip().strip('"').strip("'")

def resolve(val):
    # 支持 ${VAR} 或 $VAR 形式的 .env 变量引用
    if not val:
        return val
    def _repl(m):
        name = m.group(1) or m.group(2)
        return env.get(name, '')
    return re.sub(r'\$\{([A-Z0-9_]+)\}|\$([A-Z0-9_]+)', _repl, val)

def cred(provider, label, key_var, base_url_var, default_base_url):
    access_token = env.get(key_var, '') if key_var else ''
    # 兼容 key_env 命名：HERMES_ATLASCLOUD_KEY 也允许读 ATLASCLOUD_API_KEY
    if not access_token and key_var and key_var.startswith('HERMES_'):
        alt = key_var.replace('HERMES_', '').replace('_KEY', '_API_KEY')
        access_token = env.get(alt, '')
    return {
        'id': provider,
        'label': label,
        'auth_type': 'api_key',
        'priority': 0,
        'source': f'env:{key_var}' if key_var else 'config',
        'access_token': access_token,
        'base_url': resolve(env.get(base_url_var, default_base_url)),
        'request_count': 0,
        'last_status': None, 'last_status_at': None,
        'last_error_code': None, 'last_error_reason': None,
        'last_error_message': None, 'last_error_reset_at': None,
    }

# 从 config.yaml 读取 providers 并自动解析 key_env / base_url
cfg_providers = {}
try:
    import yaml
    cfg = yaml.safe_load(pathlib.Path('/opt/hermes/data/config.yaml').read_text())
    cfg_providers = cfg.get('providers', {}) if cfg else {}
except Exception as e:
    print(f'[warn] 读取 config.yaml 失败: {e}', file=__import__('sys').stderr)

def provider_cred(name, info):
    if not isinstance(info, dict):
        return None
    key_var = str(info.get('key_env') or '').strip()
    raw_key = str(info.get('api_key') or '').strip()
    # 如果 config.yaml 里直接写 api_key（不推荐），优先解析为 key_env 形式
    if not key_var and raw_key:
        m = re.match(r'^\$\{([A-Z0-9_]+)\}$', raw_key)
        if m:
            key_var = m.group(1)
    base_url = str(info.get('base_url') or '').strip()
    if not base_url or (not key_var and not raw_key):
        return None
    base_var = ''
    m = re.match(r'^\$\{([A-Z0-9_]+)\}$', base_url)
    if m:
        base_var = m.group(1)
    result = cred(name, name, key_var, base_var, resolve(base_url))
    if not key_var and raw_key:
        result['access_token'] = raw_key
    return result if result.get('access_token') else None

credential_pool = {
    'anthropic': [cred('newapi-anthropic', 'ANTHROPIC_API_KEY', 'ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL', 'http://127.0.0.1:50006')],
    'gemini':    [cred('newapi-gemini', 'GOOGLE_API_KEY', 'GOOGLE_API_KEY', 'GEMINI_BASE_URL', 'http://127.0.0.1:50006/v1')],
    'openai':    [cred('openai-compatible', 'OPENAI_API_KEY', 'OPENAI_API_KEY', 'OPENAI_BASE_URL', '')],
    'openrouter': [],
}

# 自动加入 config.yaml 中所有 custom provider
for name, info in cfg_providers.items():
    cred_info = provider_cred(name, info)
    if cred_info:
        credential_pool.setdefault(f'custom:{name}', []).append(cred_info)

data = {
    'version': 1,
    'providers': {},
    'credential_pool': credential_pool,
    'updated_at': datetime.now(timezone.utc).isoformat(),
}

auth_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
auth_path.chmod(0o600)
print('✅ auth.json 已从 .env 刷新')
PY
  chmod 700 "${HERMES_DATA}/refresh_auth_json.py"
  "$HERMES_VENV/bin/python" "${HERMES_DATA}/refresh_auth_json.py"
  ok "auth.json 已生成"
}

# ---------- 11. systemd 服务 ----------
step_systemd(){
  say "Step 11 · 写入 systemd 服务"

  cat > /etc/systemd/system/hermes-gateway.service <<EOF
[Unit]
Description=Hermes Agent Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment="HERMES_HOME=${HERMES_DATA}"
Environment="HERMES_WEBUI_AGENT_DIR=${HERMES_AGENT}"
Environment="PATH=${HERMES_VENV}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=${HERMES_DATA}/.env
WorkingDirectory=${HERMES_DATA}
ExecStartPre=/bin/bash ${HERMES_DIR}/hermesctl.sh inject-mcp
ExecStartPre=${HERMES_VENV}/bin/python ${HERMES_DATA}/refresh_auth_json.py
ExecStart=${HERMES_VENV}/bin/hermes gateway run --replace
Restart=always
RestartSec=10
TimeoutStopSec=240
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/hermes-webui.service <<EOF
[Unit]
Description=Hermes WebUI
After=network-online.target hermes-gateway.service
Wants=network-online.target hermes-gateway.service

[Service]
Type=simple
User=root
Environment="HERMES_HOME=${HERMES_DATA}"
Environment="HERMES_WEBUI_AGENT_DIR=${HERMES_AGENT}"
Environment="HERMES_WEBUI_STATE_DIR=${HERMES_DATA}/webui"
Environment="PATH=${HERMES_VENV}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=${HERMES_DATA}/.env
WorkingDirectory=${HERMES_WEBUI}
ExecStart=${HERMES_VENV}/bin/python ${HERMES_WEBUI}/server.py
Restart=always
RestartSec=10
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemd-analyze verify /etc/systemd/system/hermes-gateway.service /etc/systemd/system/hermes-webui.service || die "systemd 配置校验失败"
  ok "systemd 服务已写入"
}

# ---------- MCP：公开仓库构建 + VPS 定制补丁 ----------
# 流程：
#   1) git clone 公开仓库 slot181/openapi-integrator-mcp
#   2) npm install && npm run build
#   3) 复制为 6 个 MCP 目录
#   4) 用 /opt/hermes/mcp-patches/<name>/{handlers,definitions}.js 覆盖 build/tools/
# 在 VPS 上改定制：编辑 mcp-patches/ 后执行 hermesctl.sh mcp-rebuild
#
# 环境变量：
#   MCP_FROM_UPSTREAM=1   强制从上游重建并应用补丁（默认：缺文件时自动）
#   MCP_GIT_URL=...       上游 git（默认 slot181）
#   MCP_SKIP_PATCH=1      只构建上游，不应用补丁（调试用）
#   MCP_ZIP=...           可选：先解压现成包（仍会再应用补丁，除非 MCP_SKIP_PATCH=1）
#   FORCE_MCP_REBUILD=1   同 MCP_FROM_UPSTREAM=1

MCP_GIT_URL_DEFAULT="https://github.com/slot181/openapi-integrator-mcp.git"
HERMES_MCP_PATCHES="${HERMES_DIR}/mcp-patches"

_mcp_server_list(){
  echo kuaipao-image
  echo atlascloud-seedream-v5-pro
  echo atlascloud-seedream-edit
  echo atlascloud-seedream-edit-sequential
  echo atlascloud-wan-edit
  echo atlascloud-wan-edit-pro
}

_mcp_ensure_deps(){
  local dir="$1"
  [[ -d "$dir" && -f "${dir}/package.json" ]] || return 1
  [[ -d "${dir}/node_modules" ]] && return 0
  (
    cd "$dir" || exit 1
    npm install --omit=dev 2>/dev/null || npm install || exit 1
  )
}

# 将补丁目录应用到某个 MCP 运行目录
_mcp_apply_one_patch(){
  local name="$1"
  local dest="${HERMES_MCP}/${name}"
  local pdir="${HERMES_MCP_PATCHES}/${name}"
  [[ -d "$dest/build/tools" ]] || return 1
  local applied=0
  if [[ -f "${pdir}/handlers.js" ]]; then
    cp -a "${pdir}/handlers.js" "${dest}/build/tools/handlers.js"
    applied=1
  fi
  if [[ -f "${pdir}/definitions.js" ]]; then
    cp -a "${pdir}/definitions.js" "${dest}/build/tools/definitions.js"
    applied=1
  fi
  if [[ -f "${pdir}/config.index.js" && -d "${dest}/build/config" ]]; then
    cp -a "${pdir}/config.index.js" "${dest}/build/config/index.js"
    applied=1
  fi
  [[ $applied -eq 1 ]]
}

# 从运行目录导出补丁到 mcp-patches（VPS 上改完后固化）
_mcp_export_patches(){
  local name
  mkdir -p "$HERMES_MCP_PATCHES"
  for name in $(_mcp_server_list); do
    local src="${HERMES_MCP}/${name}/build/tools"
    local pdir="${HERMES_MCP_PATCHES}/${name}"
    [[ -f "${src}/handlers.js" ]] || continue
    mkdir -p "$pdir"
    cp -a "${src}/handlers.js" "${pdir}/handlers.js"
    cp -a "${src}/definitions.js" "${pdir}/definitions.js" 2>/dev/null || true
    if [[ -f "${HERMES_MCP}/${name}/build/config/index.js" ]]; then
      cp -a "${HERMES_MCP}/${name}/build/config/index.js" "${pdir}/config.index.js"
    fi
    echo "  exported ${name}"
  done
}

# 上游构建一次，复制到 6 目录，再打补丁
_mcp_build_upstream_and_patch(){
  local url="${MCP_GIT_URL:-$MCP_GIT_URL_DEFAULT}"
  local tmp base name
  tmp="$(mktemp -d)"
  say "1/4 克隆公开仓库: ${url}"
  git clone --depth 1 "$url" "${tmp}/repo" || { rm -rf "$tmp"; return 1; }

  say "2/4 npm install + build"
  (
    cd "${tmp}/repo" || exit 1
    npm install || exit 1
    npm run build || exit 1
  ) || { rm -rf "$tmp"; return 1; }
  [[ -f "${tmp}/repo/build/index.js" ]] || { rm -rf "$tmp"; return 1; }

  base="${tmp}/base"
  mkdir -p "$base"
  # 运行所需最小集合
  cp -a "${tmp}/repo/package.json" "$base/" 2>/dev/null || true
  cp -a "${tmp}/repo/package-lock.json" "$base/" 2>/dev/null || true
  cp -a "${tmp}/repo/README.md" "$base/" 2>/dev/null || true
  cp -a "${tmp}/repo/LICENSE" "$base/" 2>/dev/null || true
  cp -a "${tmp}/repo/build" "$base/"
  cp -a "${tmp}/repo/node_modules" "$base/" 2>/dev/null || true
  if [[ ! -d "${base}/node_modules" ]]; then
    ( cd "$base" && npm install --omit=dev ) || true
  fi

  say "3/4 复制为 6 个 MCP 目录"
  mkdir -p "$HERMES_MCP"
  for name in $(_mcp_server_list); do
    rm -rf "${HERMES_MCP}/${name}"
    cp -a "$base" "${HERMES_MCP}/${name}"
  done

  say "4/4 应用 VPS 定制补丁: ${HERMES_MCP_PATCHES}"
  if [[ "${MCP_SKIP_PATCH:-0}" == "1" ]]; then
    wrn "MCP_SKIP_PATCH=1，跳过补丁（全部为上游原版）"
  else
    mkdir -p "$HERMES_MCP_PATCHES"
    local patched=0 missing=0
    for name in $(_mcp_server_list); do
      if _mcp_apply_one_patch "$name"; then
        echo "  ✓ patched ${name}"
        patched=$((patched + 1))
      else
        echo "  · no patch for ${name}（保持上游原版）"
        missing=$((missing + 1))
      fi
    done
    ok "已应用补丁 ${patched}/6（无补丁 ${missing}）"
    if [[ ! -f "${HERMES_MCP_PATCHES}/atlascloud-seedream-v5-pro/handlers.js" ]]; then
      wrn "缺少 atlascloud 补丁：请在 VPS 修改后执行 /opt/hermes/hermesctl.sh mcp-export-patches"
      wrn "AtlasCloud 需适配 /api/v1/model/generateImage + 异步轮询，否则易 ECONNRESET"
    fi
  fi

  rm -rf "$tmp"
  return 0
}

# ---------- 12. 安装 / 构建 MCP server ----------
step_build_mcp(){
  say "Step 12 · MCP：公开仓库构建 + VPS 定制补丁"
  have node || die "Node.js 未安装"
  have npm  || die "npm 未安装"
  have git  || die "git 未安装"
  mkdir -p "$HERMES_MCP" "$HERMES_OUTPUT" "$HERMES_MCP_PATCHES"

  local ready=0 name
  for name in $(_mcp_server_list); do
    [[ -f "${HERMES_MCP}/${name}/build/index.js" ]] && ready=$((ready + 1))
  done

  cat <<EOF
MCP 策略（VPS 定制）：
  1. 下载公开仓库并 Node 构建：${MCP_GIT_URL_DEFAULT}
  2. 复制为 6 个目录
  3. 用 ${HERMES_MCP_PATCHES}/<name>/handlers.js|definitions.js 覆盖定制
  在 VPS 修改：编辑补丁或运行目录 → hermesctl.sh mcp-export-patches / mcp-rebuild
  API_URL/API_KEY 仍为运行时 env（config.yaml），改 URL 无需重编
EOF

  # 可选：先解压现成包（兼容旧流程），随后仍可被上游重建覆盖
  local zip_path="${MCP_ZIP:-}"
  if [[ -z "$zip_path" && -f "${HERMES_MCP}/mcp.zip" ]]; then
    zip_path="${HERMES_MCP}/mcp.zip"
  fi
  if [[ -n "$zip_path" && -f "$zip_path" && "${MCP_FROM_UPSTREAM:-0}" != "1" && "${FORCE_MCP_REBUILD:-0}" != "1" ]]; then
    say "解压 MCP 包：${zip_path}"
    have unzip || die "需要 unzip"
    local ztmp
    ztmp="$(mktemp -d)"
    unzip -oq "$zip_path" -d "$ztmp" || die "解压失败"
    if [[ -d "${ztmp}/kuaipao-image" ]]; then
      cp -a "${ztmp}/." "$HERMES_MCP/"
    else
      local sub
      sub="$(find "$ztmp" -maxdepth 2 -type d -name kuaipao-image | head -1)"
      [[ -n "$sub" ]] || die "zip 中无 kuaipao-image"
      cp -a "$(dirname "$sub")/." "$HERMES_MCP/"
    fi
    rm -rf "$ztmp"
    [[ "${KEEP_MCP_ZIP:-0}" == "1" ]] || rm -f "${HERMES_MCP}/mcp.zip" 2>/dev/null || true
    # 若 zip 带来的是完整定制，导出为补丁以便后续上游重建可复现
    if [[ ! -f "${HERMES_MCP_PATCHES}/atlascloud-seedream-v5-pro/handlers.js" ]]; then
      say "从解压结果导出补丁到 mcp-patches/"
      _mcp_export_patches
    else
      # 有补丁则再应用一遍，保证与补丁目录一致
      for name in $(_mcp_server_list); do
        _mcp_apply_one_patch "$name" 2>/dev/null || true
      done
    fi
    ok "MCP zip 已处理"
  fi

  # 重新统计
  ready=0
  for name in $(_mcp_server_list); do
    [[ -f "${HERMES_MCP}/${name}/build/index.js" ]] && ready=$((ready + 1))
  done

  local need_upstream=0
  if [[ "${MCP_FROM_UPSTREAM:-0}" == "1" || "${FORCE_MCP_REBUILD:-0}" == "1" ]]; then
    need_upstream=1
  elif [[ $ready -lt 6 ]]; then
    need_upstream=1
  fi

  if [[ $need_upstream -eq 1 ]]; then
    _mcp_build_upstream_and_patch || die "上游构建 MCP 失败"
  else
    ok "MCP 已齐全（${ready}/6），跳过上游重建；确保依赖并刷新补丁"
    for name in $(_mcp_server_list); do
      _mcp_ensure_deps "${HERMES_MCP}/${name}" 2>/dev/null || true
      if [[ "${MCP_SKIP_PATCH:-0}" != "1" ]]; then
        _mcp_apply_one_patch "$name" 2>/dev/null || true
      fi
    done
  fi

  ready=0
  local patched=0
  echo "--- MCP 状态 ---"
  for name in $(_mcp_server_list); do
    if [[ -f "${HERMES_MCP}/${name}/build/index.js" ]]; then
      local mark=""
      if [[ -f "${HERMES_MCP_PATCHES}/${name}/handlers.js" ]]; then
        mark=" [patched]"
        patched=$((patched + 1))
      fi
      echo "  ✓ ${name}${mark}"
      ready=$((ready + 1))
    else
      echo "  ✗ ${name}"
    fi
  done
  ok "MCP 就绪 ${ready}/6，补丁 ${patched}/6 → ${HERMES_MCP_PATCHES}"
  echo "VPS 定制：编辑 ${HERMES_MCP_PATCHES}/<name>/handlers.js 后执行："
  echo "  /opt/hermes/hermesctl.sh mcp-rebuild"
}


# ---------- WebUI / MCP 前置补丁（可移植，升级后自动重打）----------
step_webui_mobile_patch(){
  say "Step 12b · WebUI 移动端 Toolsets/MCP 入口补丁"
  local py="${HERMES_DIR}/patches/apply_webui_mobile_toolsets.py"
  if [[ ! -f "$py" ]]; then
    wrn "缺少 ${py}，跳过 WebUI 移动端补丁（请随仓库携带 patches/）"
    return 0
  fi
  if [[ ! -d "$HERMES_WEBUI" ]]; then
    wrn "hermes-webui 未就绪，跳过移动端补丁"
    return 0
  fi
  python3 "$py" "$HERMES_WEBUI" || wrn "WebUI 移动端补丁执行失败（可稍后 hermesctl.sh webui-patch）"
  check_webui_mobile_mcp_entry
}

step_reapply_mcp_patches(){
  say "Step 12c · 重新应用 mcp-patches（若已有运行目录）"
  if [[ -d "$HERMES_MCP" && "${MCP_SKIP_PATCH:-0}" != "1" ]]; then
    local name
    for name in $(_mcp_server_list); do
      _mcp_apply_one_patch "$name" 2>/dev/null || true
    done
  fi
}

# ---------- WebUI 静态入口检查 ----------
check_webui_mobile_mcp_entry(){
  local html="${HERMES_WEBUI}/static/index.html"
  local ui="${HERMES_WEBUI}/static/ui.js"
  local boot="${HERMES_WEBUI}/static/boot.js"
  if grep -q 'id="composerMobileToolsetsAction"' "$html" 2>/dev/null \
    && grep -q 'composerMobileToolsetsAction' "$ui" 2>/dev/null \
    && grep -q 'Narrow screens hide the footer chip' "$ui" 2>/dev/null \
    && grep -q 'composerMobileToolsetsAction' "$boot" 2>/dev/null; then
    echo "  WebUI 移动端底部 MCP/Toolsets 入口: 已就绪"
  else
    echo "  WebUI 移动端底部 MCP/Toolsets 入口: 缺失（升级覆盖后需重新应用 WebUI 补丁）"
  fi
}

# ---------- 13. 可选：NPM 反代提示 ----------
step_npm_hint(){
  say "Step 13 · NPM 反代提示"
  if ss -tlnp 2>/dev/null | grep -qE ':(81)\\b'; then
    ok "检测到 Nginx Proxy Manager 管理界面 (:81)"
    cat <<EOF
请在 NPM 后台添加反向代理：
  Domain Names      : 你的域名（如 hermes.example.com）
  Scheme            : http
  Forward Hostname  : 127.0.0.1
  Forward Port      : ${WEBUI_PORT}
  WebSocket Support : 开启
EOF
  else
    wrn "未检测到 NPM 管理界面 (:81)，可稍后手动配置反代到 127.0.0.1:${WEBUI_PORT}"
  fi
}

# ---------- 主流程 ----------
main(){
  # 仅重建 MCP：MCP_ONLY=1 bash hermes-deploy.sh
  if [[ "${MCP_ONLY:-0}" == "1" ]]; then
    ensure_root
    export PATH="${HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
    have node || die "需要 Node.js"
    have npm || die "需要 npm"
    have git || die "需要 git"
    mkdir -p "$HERMES_MCP" "$HERMES_OUTPUT" "$HERMES_MCP_PATCHES" "$BACKUP_DIR"
    # MCP_ONLY 默认强制上游重建
    MCP_FROM_UPSTREAM="${MCP_FROM_UPSTREAM:-1}"
    export MCP_FROM_UPSTREAM
    step_build_mcp
    step_reapply_mcp_patches
    step_inject_mcp
    # WebUI 可能已存在：一并确保移动端入口
    if [[ -d "$HERMES_WEBUI" ]]; then step_webui_mobile_patch; fi
    exit 0
  fi

  step_precheck
  step_uv
  step_python
  step_node
  step_dirs
  step_clone
  step_install
  step_env
  step_config
  step_inject_mcp
  step_auth
  step_systemd
  step_build_mcp
  step_reapply_mcp_patches
  step_inject_mcp
  step_webui_mobile_patch
  step_npm_hint

  chmod 700 "${HERMES_DIR}/hermes-deploy.sh" 2>/dev/null || true
  chmod 700 "${HERMES_DIR}/hermesctl.sh" 2>/dev/null || true

  cat <<EOF

${G}========================================${NC}
${G}  Hermes 直装部署准备完成${NC}
${G}========================================${NC}

目录：${HERMES_DIR}
  hermes-agent/   CLI 源码
  hermes-webui/   WebUI 源码
  data/           .env / config.yaml / auth.json / output
  venv/           Python 3.12 + hermes-agent[mcp]
  mcp/            MCP server（Node.js）
  mcp-patches/    MCP 定制 handlers/definitions（跨机必带）
  patches/        WebUI 移动端 + config 规范化脚本

重要文件：
  .env     : ${HERMES_DATA}/.env
  config   : ${HERMES_DATA}/config.yaml
  auth     : ${HERMES_DATA}/auth.json
  MCP 注入 : ${HERMES_DIR}/hermesctl.sh inject-mcp（shell 函数，从 .env 读取）
  服务文件 : /etc/systemd/system/hermes-gateway.service
           /etc/systemd/system/hermes-webui.service

下一步：
  1. 复核 ${HERMES_DATA}/.env 密钥与 HERMES_WEBUI_PASSWORD
  2. 确认 MCP：ls ${HERMES_MCP}/*/build/index.js
  3. 启动：
       systemctl enable --now hermes-gateway hermes-webui
     或：
       /opt/hermes/hermesctl.sh start

验证：
  /opt/hermes/hermesctl.sh status
  /opt/hermes/hermesctl.sh mcp
  API_KEY=\$(awk -F= '/^API_SERVER_KEY=/{print \$2}' ${HERMES_DATA}/.env)
  curl -s -H "Authorization: Bearer \$API_KEY" \
    http://127.0.0.1:${HERMES_PORT}/v1/models | head -c 200
  curl -s http://127.0.0.1:${WEBUI_PORT}/api/auth/status   # 期望 auth_enabled=true

WebUI 移动端 MCP/Toolsets：
$(check_webui_mobile_mcp_entry)
  手机端入口：底部输入区点圆形配置按钮（带 0/上下文环）→ Toolsets/MCP

访问：
  WebUI  : http://$(hostname -I 2>/dev/null | awk '{print $1}' | head -1):${WEBUI_PORT}
           登录密码见 .env 的 HERMES_WEBUI_PASSWORD（默认 YOUR_WEBUI_PASSWORD）
  Hermes : http://127.0.0.1:${HERMES_PORT}  （API，无网页；勿对公网裸奔）

图片输出目录：
  ${HERMES_OUTPUT}

控制脚本：
  /opt/hermes/hermesctl.sh          # 数字菜单（模型切换 [17]–[24] 在最后；默认 [18] cc-vibe-gpt-5.6-luna）
  /opt/hermes/hermesctl.sh {start|stop|restart|status|mcp|switch|test}
  # switch 示例: cc-vibe-gpt-5.6-luna（默认）| cc-vibe-gpt-5.6-sol | cc-vibe-grok | kuaipao-gpt-5.6-sol | kuaipao-gpt-5.6-luna | atlascloud-grok-4.3 | atlascloud-grok-4.5 | atlascloud-gpt-5.6-luna

升级：
  FORCE=1 bash /opt/hermes/hermes-deploy.sh
  （默认保留 data/.env 与 data/config.yaml）

教程：
  /opt/notes/Hermes Agent Linux本机直装部署教程.md
EOF
}

main "$@"
