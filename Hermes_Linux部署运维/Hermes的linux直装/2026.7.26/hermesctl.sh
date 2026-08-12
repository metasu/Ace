#!/usr/bin/env bash
# hermesctl.sh - Hermes CLI + WebUI 控制台（Linux 版 start.bat 数字菜单）
# 位置：/opt/hermes/hermesctl.sh
# 用法：
#   /opt/hermes/hermesctl.sh              # 数字菜单
#   /opt/hermes/hermesctl.sh start        # 命令行模式
#   /opt/hermes/hermesctl.sh switch cc-vibe-gpt-5.6-luna
# ------------------------------------------------------------------------------

set -u -o pipefail

HERMES_DIR="/opt/hermes"
HERMES_AGENT="${HERMES_DIR}/hermes-agent"
HERMES_WEBUI="${HERMES_DIR}/hermes-webui"
HERMES_DATA="${HERMES_DIR}/data"
HERMES_VENV="${HERMES_DIR}/venv"
PYTHON="${HERMES_VENV}/bin/python"
HERMES_BIN="${HERMES_VENV}/bin/hermes"
CONFIG="${HERMES_DATA}/config.yaml"
ENV_FILE="${HERMES_DATA}/.env"

export HERMES_HOME="${HERMES_DATA}"
export HERMES_WEBUI_AGENT_DIR="${HERMES_AGENT}"
export HERMES_WEBUI_STATE_DIR="${HERMES_DATA}/webui"
export PATH="${HERMES_VENV}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 安全加载 .env（值可含空格/括号，勿直接 source）
load_env_file(){
  local f="$1" line key val
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # 去 CR、跳过空行与注释
    line="${line//$'\r'/}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    # 去掉 key 两侧空白
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # 去掉值两侧成对引号
    if [[ "$val" =~ ^\".*\"$ ]]; then val="${val:1:-1}"; fi
    if [[ "$val" =~ ^\'.*\'$ ]]; then val="${val:1:-1}"; fi
    export "$key=$val"
  done < "$f"
}
load_env_file "$ENV_FILE"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[34m'; C='\033[36m'; NC='\033[0m'
say(){ echo -e "${B}ℹ️  $*${NC}"; }
ok(){  echo -e "${G}✅ $*${NC}"; }
wrn(){ echo -e "${Y}⚠️  $*${NC}"; }
die(){ echo -e "${R}❌ $*${NC}"; exit 1; }

check_venv(){ [[ -x "$PYTHON" ]] || die "虚拟环境不存在，请先运行 /opt/hermes/hermes-deploy.sh"; }

pause(){
  echo
  read -r -p "按 Enter 返回菜单..." _
}

# ---------- 当前模型摘要 ----------
show_current_model(){
  if [[ ! -f "$CONFIG" ]]; then
    echo "  当前模型: (无 config.yaml)"
    return
  fi
  if [[ ! -x "$PYTHON" ]]; then
    echo "  当前模型: (venv 未就绪)"
    return
  fi
  "$PYTHON" - <<'PY' 2>/dev/null || true
import pathlib, re
t = pathlib.Path("/opt/hermes/data/config.yaml").read_text(encoding="utf-8")
def g(k):
    m = re.search(r'^  ' + k + r':\s*["\']?([^"\'\n]+)', t, re.M)
    return m.group(1).strip() if m else "?"
print("  当前: provider=%s  model=%s" % (g("provider"), g("default")))
print("  base_url=%s" % g("base_url"))
PY
}

# ---------- 服务管理 ----------
wait_for_services(){
  local attempt listening
  for attempt in {1..30}; do
    listening="$(ss -H -ltn 2>/dev/null)"
    if systemctl is-active --quiet hermes-gateway \
      && systemctl is-active --quiet hermes-webui \
      && [[ "$listening" =~ :50001[[:space:]] ]] \
      && [[ "$listening" =~ :8787[[:space:]] ]]; then
      return 0
    fi
    sleep 1
  done
  wrn "服务在 30 秒内未全部就绪，以下为当前状态"
}

cmd_start(){
  check_venv
  cmd_refresh
  systemctl enable --now hermes-gateway hermes-webui || die "启动失败"
  wait_for_services
  cmd_status
}

cmd_stop(){
  systemctl stop hermes-gateway hermes-webui || true
  ok "服务已停止"
}

cmd_restart(){
  check_venv
  cmd_refresh
  systemctl restart hermes-gateway hermes-webui || die "重启失败"
  wait_for_services
  cmd_status
}

check_webui_mobile_mcp_entry(){
  local html="${HERMES_WEBUI}/static/index.html"
  local ui="${HERMES_WEBUI}/static/ui.js"
  local boot="${HERMES_WEBUI}/static/boot.js"
  if grep -q 'id="composerMobileToolsetsAction"' "$html" 2>/dev/null     && grep -q 'composerMobileToolsetsAction' "$ui" 2>/dev/null     && grep -q 'Narrow screens hide the footer chip' "$ui" 2>/dev/null     && grep -q 'composerMobileToolsetsAction' "$boot" 2>/dev/null; then
    echo "  WebUI 移动端底部 MCP/Toolsets 入口: 已就绪"
  else
    echo "  WebUI 移动端底部 MCP/Toolsets 入口: 缺失（执行: /opt/hermes/hermesctl.sh webui-patch）"
  fi
}

cmd_webui_patch(){
  say "应用 WebUI 移动端 Toolsets/MCP 补丁"
  local py="${HERMES_DIR}/patches/apply_webui_mobile_toolsets.py"
  [[ -f "$py" ]] || die "缺少 ${py}"
  [[ -d "$HERMES_WEBUI" ]] || die "缺少 hermes-webui 目录"
  python3 "$py" "$HERMES_WEBUI" || die "webui-patch 失败"
  # 注入 MCP 配置（顺带）
  inject_mcp_config
  check_webui_mobile_mcp_entry
  if systemctl is-active --quiet hermes-webui 2>/dev/null; then
    systemctl restart hermes-webui || wrn "重启 hermes-webui 失败"
    ok "已重启 hermes-webui"
  else
    wrn "hermes-webui 未运行；补丁已写入静态文件，启动后生效"
  fi
}

cmd_status(){
  echo "--- 服务状态 ---"
  systemctl is-active hermes-gateway hermes-webui 2>/dev/null || true
  echo "--- 端口监听 ---"
  ss -tlnp 2>/dev/null | grep -E ':(50001|8787)\s' || echo "无监听"
  echo "--- 健康检查 ---"
  curl -s -o /dev/null -w "Hermes:  HTTP %{http_code}\n" http://127.0.0.1:50001/v1/models || true
  curl -s -o /dev/null -w "WebUI:   HTTP %{http_code}\n" http://127.0.0.1:8787/ || true
  echo "--- WebUI 鉴权 ---"
  if grep -q '^HERMES_WEBUI_PASSWORD=.\+' "${ENV_FILE}" 2>/dev/null; then
    echo "  .env HERMES_WEBUI_PASSWORD: 已设置"
  else
    echo "  .env HERMES_WEBUI_PASSWORD: 未设置（公网反代危险）"
  fi
  curl -s --max-time 3 http://127.0.0.1:8787/api/auth/status 2>/dev/null \
    | "${PYTHON}" -c 'import sys,json
try:
  d=json.load(sys.stdin)
  print("  auth_enabled=%s  password_auth=%s" % (d.get("auth_enabled"), d.get("password_auth_enabled")))
except Exception:
  print("  auth status: 无法获取（WebUI 未就绪？）")' 2>/dev/null || echo "  auth status: 无法获取"
  echo "--- WebUI 移动端 ---"
  check_webui_mobile_mcp_entry
  show_current_model
}

cmd_logs(){
  echo "跟踪 hermes-gateway 日志（Ctrl+C 返回）..."
  journalctl -u hermes-gateway -f --no-pager || true
}

# ---------- 配置 ----------
inject_mcp_config(){
  local config="${HERMES_DATA}/config.yaml"
  local root="${HERMES_DIR}"
  [[ -f "$config" ]] || { wrn "config.yaml 不存在，跳过 MCP 注入"; return 0; }
  load_env_file "$ENV_FILE"

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
}

cmd_inject_mcp(){
  inject_mcp_config
  ok "mcp_servers 已注入 config.yaml"
}

cmd_refresh(){
  check_venv
  cmd_inject_mcp
  if [[ -f "${HERMES_DATA}/refresh_auth_json.py" ]]; then
    "$PYTHON" "${HERMES_DATA}/refresh_auth_json.py" || die "刷新 auth.json 失败"
  else
    wrn "refresh_auth_json.py 不存在，跳过"
  fi
}

cmd_env(){ ${EDITOR:-nano} "$ENV_FILE"; }
cmd_config(){ ${EDITOR:-nano} "$CONFIG"; }

# ---------- 模型切换（对齐 start.bat 8-14）----------
switch_provider(){
  local provider="$1" model="${2:-}" url="${3:-}"
  check_venv
  [[ -f "$CONFIG" ]] || die "config.yaml 不存在"

  case "$provider" in
    kuaipao-gpt-5.6-luna)
      provider="kuaipao-gpt"
      model="${model:-gpt-5.6-luna}"
      url="${url:-https://kuaipao.ai/v1}"
      ;;
    kuaipao-gpt-5.6-sol)
      provider="kuaipao-gpt"
      model="${model:-gpt-5.6-sol}"
      url="${url:-https://kuaipao.ai/v1}"
      ;;
    atlascloud-grok-4.3)
      provider="atlascloud-grok-4.3"
      model="${model:-xai/grok-4.3}"
      url="${url:-https://api.atlascloud.ai/v1}"
      ;;
    atlascloud-grok-4.5)
      provider="atlascloud"
      model="${model:-xai/grok-4.5}"
      url="${url:-https://api.atlascloud.ai/v1}"
      ;;
    atlascloud-gpt-5.6-luna)
      provider="atlascloud"
      model="${model:-gpt-5.6-luna}"
      url="${url:-https://api.atlascloud.ai/v1}"
      ;;
    cc-vibe-grok)
      model="${model:-grok-4.5}"
      url="${url:-https://cc-vibe.com/v1}"
      ;;
    cc-vibe-gpt-5.6-luna)
      provider="cc-vibe-gpt"
      model="${model:-gpt-5.6-luna}"
      url="${url:-https://cc-vibe.com/v1}"
      ;;
    cc-vibe-gpt-5.6-sol)
      provider="cc-vibe-gpt"
      model="${model:-gpt-5.6-sol}"
      url="${url:-https://cc-vibe.com/v1}"
      ;;
    *)
      die "未知 provider: $provider"
      ;;
  esac

  say "切换 → provider=${provider} model=${model}"
  # 用环境变量传参 + 引号 heredoc，避免 f-string/展开导致 NameError
  HERMES_SW_MODEL="$model" HERMES_SW_PROVIDER="$provider" HERMES_SW_URL="$url" HERMES_SW_CONFIG="$CONFIG" \
  "$PYTHON" - <<'PY'
import os, pathlib, re, yaml
model = os.environ["HERMES_SW_MODEL"]
provider = os.environ["HERMES_SW_PROVIDER"]
url = os.environ["HERMES_SW_URL"]
path = pathlib.Path(os.environ["HERMES_SW_CONFIG"])
t = path.read_text(encoding="utf-8")
cfg = yaml.safe_load(t) or {}
provider_cfg = (cfg.get("providers") or {}).get(provider)
if isinstance(provider_cfg, dict):
    key_env = str(provider_cfg.get("key_env") or "").strip()
    if key_env and not os.environ.get(key_env, "").strip():
        raise SystemExit("provider %s 的 key_env=%s 未设置" % (provider, key_env))
updates = (
    (r"^  default:.*$", '  default: "' + model + '"'),
    (r"^  provider:.*$", '  provider: "' + provider + '"'),
    (r"^  base_url:.*$", '  base_url: "' + url + '"'),
)
for pattern, replacement in updates:
    t, count = re.subn(pattern, replacement, t, count=1, flags=re.M)
    if count != 1:
        raise SystemExit("config.yaml 缺少待更新字段: %s" % pattern)
updated = yaml.safe_load(t) or {}
updated_model = updated.get("model") if isinstance(updated, dict) else None
if not isinstance(updated_model, dict) or (
    updated_model.get("default") != model
    or updated_model.get("provider") != provider
    or updated_model.get("base_url") != url
):
    raise SystemExit("config.yaml 写入校验失败")
path.write_text(t, encoding="utf-8")
print("已写入 config.yaml: provider=%s, model=%s, base_url=%s" % (provider, model, url))
PY
  cmd_refresh
  if systemctl is-active --quiet hermes-gateway 2>/dev/null; then
    systemctl restart hermes-gateway || die "重启 hermes-gateway 失败"
    ok "已切换并重启 gateway"
  else
    ok "已切换（gateway 未运行，启动后生效）"
  fi
  show_current_model
}

cmd_switch(){
  local provider="" model="" url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model) model="$2"; shift 2 ;;
      --url)   url="$2";   shift 2 ;;
      --*)     die "未知选项: $1" ;;
      *)
        if [[ -z "$provider" ]]; then provider="$1"; else die "只能指定一个 provider"; fi
        shift ;;
    esac
  done
  [[ -n "$provider" ]] || die "用法: $0 switch <provider> [--model m] [--url u]"
  switch_provider "$provider" "$model" "$url"
}

# ---------- 诊断 ----------
cmd_test(){
  check_venv
  echo "==================================================="
  echo " 测试当前 config.yaml 配置的 API 通道"
  echo "==================================================="
  "$PYTHON" - <<'PY'
import pathlib, yaml, urllib.request, json, os
p = pathlib.Path('/opt/hermes/data/config.yaml')
cfg = yaml.safe_load(p.read_text(encoding='utf-8')) or {}
m = cfg.get('model', {}) if isinstance(cfg, dict) else {}
prov_name = m.get('provider', '') if isinstance(m, dict) else ''
model_name = m.get('default', '') if isinstance(m, dict) else ''
url = (m.get('base_url') or '').rstrip('/') + '/models' if isinstance(m, dict) else ''
prov = (cfg.get('providers') or {}).get(prov_name, {}) if isinstance(cfg, dict) else {}
key_var = prov.get('key_env', '') if isinstance(prov, dict) else ''
key = os.environ.get(key_var, '') if key_var else ''
print('Provider:', prov_name)
print('Model:', model_name)
print('URL:', url)
print('Key Env:', key_var)
print('Key Present:', bool(key))
print('Key Length:', len(key))
try:
    req = urllib.request.Request(url)
    if key:
        req.add_header('Authorization', f'Bearer {key}')
    r = urllib.request.urlopen(req, timeout=15)
    data = json.loads(r.read().decode('utf-8'))
    models = [x.get('id') for x in data.get('data', []) if isinstance(x, dict)]
    print('HTTP Status:', r.status)
    print('Models:', models[:8])
    if model_name and model_name not in models:
        print('ERROR: 当前模型不在 provider 返回的模型列表中')
        print('[FAIL] 请检查 model.default 与 provider 的模型 ID')
    else:
        print('[SUCCESS] 当前通道与模型可用')
except Exception as e:
    print('ERROR:', e)
    print('[FAIL] 请检查 base_url 与 API key')
PY
}

cmd_doctor(){
  check_venv
  "$HERMES_BIN" doctor
}

cmd_ports(){
  ss -tlnp 2>/dev/null | grep -E ':(50001|8787|50006|81)\s' || echo "端口均空闲"
}

# ---------- MCP ----------
cmd_mcp(){
  check_venv
  local mcp_dir="${HERMES_DIR}/mcp"
  local patch_dir="${HERMES_DIR}/mcp-patches"
  local servers=(
    kuaipao-image
    atlascloud-seedream-v5-pro
    atlascloud-seedream-edit
    atlascloud-seedream-edit-sequential
    atlascloud-wan-edit
    atlascloud-wan-edit-pro
  )
  echo "--- MCP：公开仓库构建 + VPS 补丁 ---"
  echo "  上游: https://github.com/slot181/openapi-integrator-mcp"
  echo "  补丁: ${patch_dir}/"
  echo
  echo "--- MCP 目录 ---"
  local n okc=0 pc=0
  for n in "${servers[@]}"; do
    if [[ -f "${mcp_dir}/${n}/build/index.js" ]]; then
      local extra=""
      if [[ -f "${patch_dir}/${n}/handlers.js" ]]; then
        extra=" [patch]"
        pc=$((pc + 1))
      fi
      echo "  ✓ ${n}${extra}"
      okc=$((okc + 1))
    else
      echo "  ✗ ${n}"
    fi
  done
  echo "就绪: ${okc}/6，补丁: ${pc}/6"
  # GitHub MCP 为 npx 运行，不依赖本地 build 目录
  if command -v npx >/dev/null 2>&1; then
    if [[ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
      echo "  ✓ github（npx @modelcontextprotocol/server-github，GITHUB_PERSONAL_ACCESS_TOKEN 已设置）"
    else
      echo "  ✗ github（npx @modelcontextprotocol/server-github，GITHUB_PERSONAL_ACCESS_TOKEN 未设置）"
    fi
  else
    echo "  ✗ npx 未安装，无法运行 GitHub MCP"
  fi
  echo "输出: ${HERMES_DATA}/output"
  echo
  echo "--- WebUI 移动端 ---"
  check_webui_mobile_mcp_entry
  echo "  手机端入口：底部输入区点圆形配置按钮（带 0/上下文环）→ Toolsets/MCP"
  echo
  echo "--- hermes mcp list ---"
  "$HERMES_BIN" mcp list 2>&1 || true
  echo
  if [[ -f "${mcp_dir}/kuaipao-image/build/index.js" ]]; then
    echo "--- hermes mcp test kuaipao-image ---"
    "$HERMES_BIN" mcp test kuaipao-image 2>&1 || true
  fi
}

cmd_mcp_export_patches(){
  local mcp_dir="${HERMES_DIR}/mcp"
  local patch_dir="${HERMES_DIR}/mcp-patches"
  local servers=(
    kuaipao-image atlascloud-seedream-v5-pro atlascloud-seedream-edit
    atlascloud-seedream-edit-sequential atlascloud-wan-edit atlascloud-wan-edit-pro
  )
  mkdir -p "$patch_dir"
  say "从运行目录导出补丁 → ${patch_dir}"
  local n
  for n in "${servers[@]}"; do
    local src="${mcp_dir}/${n}/build/tools"
    [[ -f "${src}/handlers.js" ]] || { wrn "跳过 ${n}"; continue; }
    mkdir -p "${patch_dir}/${n}"
    cp -a "${src}/handlers.js" "${patch_dir}/${n}/handlers.js"
    cp -a "${src}/definitions.js" "${patch_dir}/${n}/definitions.js" 2>/dev/null || true
    if [[ -f "${mcp_dir}/${n}/build/config/index.js" ]]; then
      cp -a "${mcp_dir}/${n}/build/config/index.js" "${patch_dir}/${n}/config.index.js"
    fi
    ok "exported ${n}"
  done
}

cmd_mcp_apply_patches(){
  local mcp_dir="${HERMES_DIR}/mcp"
  local patch_dir="${HERMES_DIR}/mcp-patches"
  local servers=(
    kuaipao-image atlascloud-seedream-v5-pro atlascloud-seedream-edit
    atlascloud-seedream-edit-sequential atlascloud-wan-edit atlascloud-wan-edit-pro
  )
  say "应用补丁 ${patch_dir} → 运行目录"
  local n
  for n in "${servers[@]}"; do
    local dest="${mcp_dir}/${n}/build/tools"
    local pdir="${patch_dir}/${n}"
    [[ -d "$dest" ]] || { wrn "跳过 ${n}"; continue; }
    local okp=0
    if [[ -f "${pdir}/handlers.js" ]]; then
      cp -a "${pdir}/handlers.js" "${dest}/handlers.js"; okp=1
    fi
    if [[ -f "${pdir}/definitions.js" ]]; then
      cp -a "${pdir}/definitions.js" "${dest}/definitions.js"; okp=1
    fi
    if [[ -f "${pdir}/config.index.js" && -d "${mcp_dir}/${n}/build/config" ]]; then
      cp -a "${pdir}/config.index.js" "${mcp_dir}/${n}/build/config/index.js"; okp=1
    fi
    [[ $okp -eq 1 ]] && ok "patched ${n}" || wrn "no patch for ${n}"
  done
  inject_mcp_config
  # 升级 WebUI 后 MCP 入口常被覆盖，apply 时一并确保
  if [[ -f "${HERMES_DIR}/patches/apply_webui_mobile_toolsets.py" ]]; then
    python3 "${HERMES_DIR}/patches/apply_webui_mobile_toolsets.py" "$HERMES_WEBUI" || true
  fi
  check_webui_mobile_mcp_entry
  wrn "建议: 菜单选 [3] 重启服务（或 hermesctl.sh restart）"
}

cmd_mcp_rebuild(){
  say "从公开仓库重建 MCP 并应用补丁"
  MCP_ONLY=1 MCP_FROM_UPSTREAM=1 bash "${HERMES_DIR}/hermes-deploy.sh" || die "mcp-rebuild 失败"
  inject_mcp_config
  if [[ -f "${HERMES_DIR}/patches/apply_webui_mobile_toolsets.py" && -d "$HERMES_WEBUI" ]]; then
    python3 "${HERMES_DIR}/patches/apply_webui_mobile_toolsets.py" "$HERMES_WEBUI" || true
  fi
  ok "完成。可用菜单 [12] 验证 MCP；[16] 检查移动端入口"
}


# ---------- 帮助（CLI）----------
usage(){
  cat <<EOF
用法: $0                  数字菜单（推荐，对齐 start.bat）
      $0 <命令>           命令行模式

服务: start | stop | restart | status | logs
切换: switch <provider> [--model m] [--url u]
      provider: cc-vibe-grok |
                cc-vibe-gpt-5.6-sol | cc-vibe-gpt-5.6-luna |
                kuaipao-gpt-5.6-sol | kuaipao-gpt-5.6-luna |
                atlascloud-gpt-5.6-luna | atlascloud-grok-4.3 | atlascloud-grok-4.5
      （默认 cc-vibe-gpt-5.6-luna）
配置: refresh | inject-mcp | env | config
MCP:  mcp | mcp-rebuild | mcp-export-patches | mcp-apply-patches | webui-patch
诊断: test | doctor | ports
EOF
}

# ---------- 数字菜单（对齐 notes/start.bat）----------
show_menu(){
  clear 2>/dev/null || true
  echo -e "${C}========================================${NC}"
  echo -e "${C} Hermes Agent CLI + WebUI 控制台 (Linux)${NC}"
  echo -e "${C}========================================${NC}"
  echo
  echo "  目录: ${HERMES_DIR}"
  echo "  WebUI: http://127.0.0.1:8787"
  echo "  API:   http://127.0.0.1:50001"
  show_current_model
  echo
  echo -e "${G}  服务${NC}"
  echo "  [1]  启动 Gateway + WebUI（systemd）"
  echo "  [2]  停止全部服务"
  echo "  [3]  重启全部服务"
  echo "  [4]  查看状态 / 端口"
  echo "  [5]  跟踪 Gateway 日志"
  echo
  echo -e "${G}  诊断${NC}"
  echo "  [6]  测试当前 API 通道（config.yaml）"
  echo "  [7]  hermes doctor"
  echo "  [8]  检查端口占用"
  echo
  echo -e "${G}  配置${NC}"
  echo "  [9]  编辑 .env（密钥）"
  echo "  [10] 编辑 config.yaml"
  echo "  [11] 刷新 auth.json + 注入 MCP 配置"
  echo
  echo -e "${G}  MCP${NC}"
  echo "  [12] MCP 状态 / list / test"
  echo "  [13] MCP 从公开仓库重建 + 打补丁"
  echo "  [14] 导出补丁 mcp-patches/"
  echo "  [15] 应用补丁到运行目录"
  echo "  [16] WebUI 移动端 Toolsets/MCP 补丁"
  echo
  echo -e "${G}  切换主模型（默认: cc-vibe-gpt-5.6-luna → gpt-5.6-luna）${NC}"
  echo "  [17] cc-vibe-grok              → grok-4.5"
  echo "  [18] cc-vibe-gpt-5.6-luna      → gpt-5.6-luna  (默认)"
  echo "  [19] cc-vibe-gpt-5.6-sol       → gpt-5.6-sol"
  echo "  [20] kuaipao-gpt-5.6-sol       → gpt-5.6-sol"
  echo "  [21] kuaipao-gpt-5.6-luna      → gpt-5.6-luna"
  echo "  [22] atlascloud-grok-4.3        → xai/grok-4.3  (同 atlas API)"
  echo "  [23] atlascloud-grok-4.5        → xai/grok-4.5  (复用 atlas key)"
  echo "  [24] atlascloud-gpt-5.6-luna    → gpt-5.6-luna  (复用 atlas key)"
  echo
  echo "  [0]  退出"
  echo
}

menu_loop(){
  local choice
  while true; do
    show_menu
    read -r -p "请选择 [0-24]: " choice || choice="0"
    choice="${choice// /}"
    echo
    case "$choice" in
      1)  cmd_start; pause ;;
      2)  cmd_stop; pause ;;
      3)  cmd_restart; pause ;;
      4)  cmd_status; pause ;;
      5)  cmd_logs; pause ;;
      6)  cmd_test; pause ;;
      7)  cmd_doctor; pause ;;
      8)  cmd_ports; pause ;;
      9)  cmd_env; pause ;;
      10) cmd_config; pause ;;
      11) cmd_refresh; ok "auth.json 已刷新 + MCP 配置已注入"; pause ;;
      12) cmd_mcp; pause ;;
      13) cmd_mcp_rebuild; pause ;;
      14) cmd_mcp_export_patches; pause ;;
      15) cmd_mcp_apply_patches; pause ;;
      16) cmd_webui_patch; pause ;;
      17) switch_provider cc-vibe-grok; pause ;;
      18) switch_provider cc-vibe-gpt-5.6-luna; pause ;;
      19) switch_provider cc-vibe-gpt-5.6-sol; pause ;;
      20) switch_provider kuaipao-gpt-5.6-sol; pause ;;
      21) switch_provider kuaipao-gpt-5.6-luna; pause ;;
      22) switch_provider atlascloud-grok-4.3; pause ;;
      23) switch_provider atlascloud-grok-4.5; pause ;;
      24) switch_provider atlascloud-gpt-5.6-luna; pause ;;
      0|q|Q|exit) ok "再见"; exit 0 ;;
      "")
        wrn "未输入，返回菜单"
        sleep 1
        ;;
      *)
        wrn "无效选项: ${choice}"
        sleep 1
        ;;
    esac
  done
}

# ---------- 入口 ----------
if [[ $# -eq 0 ]]; then
  menu_loop
fi

case "$1" in
  start)    cmd_start ;;
  stop)     cmd_stop ;;
  restart)  cmd_restart ;;
  status)   cmd_status ;;
  logs)     cmd_logs ;;
  refresh)     cmd_refresh ;;
  inject-mcp)   cmd_inject_mcp ;;
  env)      cmd_env ;;
  config)   cmd_config ;;
  switch)   shift; cmd_switch "$@" ;;
  mcp)      cmd_mcp ;;
  mcp-rebuild)        cmd_mcp_rebuild ;;
  mcp-export-patches) cmd_mcp_export_patches ;;
  mcp-apply-patches)  cmd_mcp_apply_patches ;;
  webui-patch)        cmd_webui_patch ;;
  test)     cmd_test ;;
  doctor)   cmd_doctor ;;
  ports)    cmd_ports ;;
  menu)     menu_loop ;;
  -h|--help|help) usage ;;
  *)        die "未知命令: $1（无参数进入菜单，或 $0 help）" ;;
esac
