#!/usr/bin/env bash
# opengemini.sh - v4.8.0（无 WARP 直连版）
# 组件：NPM / OpenWebUI / Gemini-Balance / Ollama
# 变更：
#   - 默认模型：phi3:mini-4k（Phi‑3 Mini 3.8B，4K上下文）
#   - 强制使用 Ollama 最新镜像（latest）
#   - 新增“模型管理”：新增/拉取、删除、列出（菜单 + 非交互命令）
#   - 保留 CodeLlama 仅检测，不自动安装

set -u -o pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x
ROOT_DIR="$(dirname "$(readlink -f "${0:-$PWD/opengemini.sh}")")"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"
GB_ENV_FILE="$ROOT_DIR/.env.geminibalance"

# ---- 项目名 ----
_san_raw="$(basename "$ROOT_DIR" | tr -c 'a-zA-Z0-9-' '_')"
if [[ -z "$_san_raw" ]]; then PROJECT_NAME="npm"
else first="${_san_raw:0:1}"; [[ "$first" =~ [A-Za-z0-9] ]] && PROJECT_NAME="$_san_raw" || PROJECT_NAME="p$_san_raw"; fi
export COMPOSE_PROJECT_NAME="$PROJECT_NAME"

# ---- 彩色 ----
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[34m'; NC='\033[0m'
say(){ echo -e "${B}ℹ️ $*${NC}"; }
ok(){ echo -e "${G}✅ $*${NC}"; }
wrn(){ echo -e "${Y}⚠️ $*${NC}"; }
die(){ echo -e "${R}❌ $*${NC}"; exit 1; }

# ---- 工具 ----
have(){ command -v "${1:-}" >/dev/null 2>&1; }
ensure_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "需要 root: sudo $0"; }
rand_b64(){ head -c 24 /dev/urandom | base64; }
detect_ip(){ curl -fsS --max-time 2 ifconfig.me || { hostname -I | awk '{print $1}' || echo 127.0.0.1; }; }
detect_tz(){ cat /etc/timezone 2>/dev/null || echo UTC; }
compose(){ docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }
compose_exec(){ local svc="$1"; shift; compose exec -T "$svc" sh -lc "$*"; }

# ---- 端口默认 ----
declare -A DEFAULT_PORTS=(
  [WEBUI_PORT]=40001
  [NPM_ADMIN_PORT]=40002
  [GEMINI_BALANCE_PORT]=40003
  [OLLAMA_PORT]=11434
  [NPM_HTTP_PORT]=80
  [NPM_HTTPS_PORT]=443
)

# ---- 行尾/BOM 清理 ----
fixlf(){
  find "$ROOT_DIR" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.yml" -o -name ".env*" \) \
    -exec sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' {} \; 2>/dev/null || true
}

install_docker_if_missing(){
  if ! have docker; then
    say "安装 Docker..."
    apt-get update -y && apt-get install -y docker.io docker-compose-plugin || true
    systemctl enable --now docker || true
  fi
  docker compose version >/dev/null 2>&1 || die "需要 Docker Compose v2"
}

# ---- .env 管理 ----
get_env_kv(){ grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true; }
set_env_kv(){ local k="$1" v="$2"; awk -v K="$k" -v V="$v" 'BEGIN{r=0} $0~("^"K"="){print K"="V; r=1; next} {print} END{if(!r)print K"="V}' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"; }
reload_env(){ set -o allexport; source "$ENV_FILE"; set +o allexport; }

create_env(){
  [[ -f "$ENV_FILE" ]] && return 0
  cat > "$ENV_FILE" <<EOF
PUBLIC_IP=$(detect_ip)
WEBUI_PORT=${DEFAULT_PORTS[WEBUI_PORT]}
GEMINI_BALANCE_PORT=${DEFAULT_PORTS[GEMINI_BALANCE_PORT]}
OLLAMA_PORT=${DEFAULT_PORTS[OLLAMA_PORT]}
NPM_HTTP_PORT=${DEFAULT_PORTS[NPM_HTTP_PORT]}
NPM_HTTPS_PORT=${DEFAULT_PORTS[NPM_HTTPS_PORT]}
NPM_ADMIN_PORT=${DEFAULT_PORTS[NPM_ADMIN_PORT]}
TZ=$(detect_tz)
MYSQL_ROOT_PASSWORD=$(rand_b64)
MYSQL_PASSWORD=$(rand_b64)
MYSQL_DATABASE=npm
MYSQL_USER=npm
TAG_NPM=latest
TAG_MARIADB=10.11
TAG_OPENWEBUI=main
TAG_OLLAMA=latest
TAG_GB=latest
# 默认预拉取模型（可改为 phi3:mini 或 phi3:mini-128k）
PHI3_MODEL=phi3:mini-4k
EOF
  chmod 600 "$ENV_FILE"
}

create_gb_env(){
  [[ -f "$GB_ENV_FILE" ]] && return 0
  reload_env || true
  local token="sk-imfine1234567"
  cat > "$GB_ENV_FILE" <<EOF
DATABASE_TYPE=sqlite
SQLITE_DATABASE=/app/data/gb.sqlite
API_KEYS=["REPLACE_WITH_YOUR_GOOGLE_API_KEY"]
AUTH_TOKEN=${token}
ALLOWED_TOKENS=["${token}"]
TIMEZONE=${TZ}
LOG_LEVEL=INFO
TRUST_PROXY=true
COOKIE_SECURE=false
SESSION_COOKIE_SECURE=false
SESSION_COOKIE_SAMESITE=lax
PREFERRED_URL_SCHEME=http
# 直连，不走代理
EOF
}

# ---- 写 docker-compose ----
create_compose(){
  cat > "$COMPOSE_FILE" <<'YAML'
services:
  npm-app:
    image: jc21/nginx-proxy-manager:${TAG_NPM}
    restart: unless-stopped
    ports:
      - "${NPM_HTTP_PORT}:80"
      - "${NPM_HTTPS_PORT}:443"
      - "${NPM_ADMIN_PORT}:81"
    environment:
      DB_MYSQL_HOST: "npm-db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "${MYSQL_USER}"
      DB_MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
      DB_MYSQL_NAME: "${MYSQL_DATABASE}"
      TZ: "${TZ}"
    volumes:
      - ./npm_data:/data
      - ./npm_letsencrypt:/etc/letsencrypt
    depends_on: { npm-db: { condition: service_healthy } }
    networks: [npm_internal, proxy]

  npm-db:
    image: mariadb:${TAG_MARIADB}
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${MYSQL_DATABASE}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
    volumes: ["./npm_db:/var/lib/mysql"]
    networks: [npm_internal]
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]

  ollama:
    image: ollama/ollama:${TAG_OLLAMA}
    restart: unless-stopped
    ports: ["${OLLAMA_PORT}:11434"]
    environment:
      OLLAMA_HOST: "0.0.0.0"
    volumes: ["./ollama_data:/root/.ollama"]
    networks: [appnet]

  open-webui:
    image: ghcr.io/open-webui/open-webui:${TAG_OPENWEBUI}
    restart: unless-stopped
    ports: ["${WEBUI_PORT}:8080"]
    environment: ["OLLAMA_BASE_URL=http://ollama:11434"]
    volumes: ["./webui_data:/app/backend/data"]
    depends_on: [ollama]
    networks: [appnet, proxy]

  gemini-balance:
    image: ghcr.io/snailyp/gemini-balance:${TAG_GB}
    restart: unless-stopped
    ports: ["${GEMINI_BALANCE_PORT}:8000"]
    env_file: [".env.geminibalance"]
    volumes: ["./gb_data:/app/data"]
    networks: [proxy]

networks:
  npm_internal: { driver: bridge }
  appnet: { driver: bridge }
  proxy: { external: true }
YAML
}

# ---- Ollama/模型就绪与检测 ----
wait_for_ollama(){
  say "等待 Ollama 服务就绪..."
  local tries=60
  for i in $(seq 1 $tries); do
    if compose_exec ollama "ollama list >/dev/null 2>&1"; then
      ok "Ollama 已就绪"
      return 0
    fi
    sleep 2
  done
  die "Ollama API 未在预期时间内响应"
}

print_ollama_version(){
  local v
  v="$(compose_exec ollama "ollama --version 2>/dev/null" || true)"
  [[ -n "$v" ]] && ok "Ollama 版本：$v" || wrn "无法获取 Ollama 版本信息"
}

ensure_model_present(){
  local model="${1:-phi3:mini-4k}"
  if compose_exec ollama "ollama list | awk 'NR>1{print \$1}' | grep -E '^${model//\//\\/}(:|$)' -q"; then
    ok "已安装模型：$model"
  else
    say "拉取模型：$model ..."
    compose_exec ollama "ollama pull '$model'" || die "拉取 $model 失败"
    ok "模型 $model 已就绪"
  fi
}

detect_codellama_only(){
  if compose_exec ollama "ollama list | awk 'NR>1{print tolower(\$1)}' | grep -E '(^|/)codellama(:|$)' -q"; then
    ok "检测到 CodeLlama（仅检测，不自动安装）"
  else
    wrn "未检测到 CodeLlama（仅检测，不自动安装）"
  fi
}

# ---- 模型管理：新增/删除/列出 ----
model_list(){
  ensure_root; reload_env; wait_for_ollama
  say "当前已安装模型："
  compose_exec ollama "printf '%-28s %-8s %-10s %-20s\n' NAME TAG SIZE MODIFIED; ollama list"
}

model_add(){ # $1: model name (optional)
  ensure_root; reload_env; wait_for_ollama
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    read -rp "输入要拉取/新增的模型名（如 phi3:mini-4k）： " name
  fi
  [[ -z "$name" ]] && die "模型名不能为空"
  say "拉取模型：$name ..."
  compose_exec ollama "ollama pull '$name'" || die "拉取 $name 失败"
  ok "模型 $name 已就绪"
}

model_rm(){ # $1: model name (optional)
  ensure_root; reload_env; wait_for_ollama
  model_list || true
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    read -rp "输入要删除的模型名（如 phi3:mini-4k）： " name
  fi
  [[ -z "$name" ]] && die "模型名不能为空"
  read -rp "确认删除模型 [$name] ? (y/N): " yesno
  [[ "${yesno:-N}" =~ ^[Yy]$ ]] || { wrn "已取消删除"; return 0; }
  compose_exec ollama "ollama rm '$name'" || die "删除 $name 失败（模型名或标签不存在）"
  ok "模型 $name 已删除"
}

# ---- 核心流程 ----
do_up(){
  ensure_root; install_docker_if_missing
  mkdir -p "$ROOT_DIR"/{npm_data,npm_letsencrypt,npm_db,webui_data,ollama_data,gb_data}
  create_env; create_gb_env; fixlf; reload_env
  create_compose

  docker network inspect proxy >/dev/null 2>&1 || docker network create proxy || true

  say "拉取最新 Ollama 镜像：ollama/ollama:${TAG_OLLAMA}"
  docker pull "ollama/ollama:${TAG_OLLAMA}" || true

  compose pull || true
  compose up -d

  wait_for_ollama
  print_ollama_version
  ensure_model_present "${PHI3_MODEL:-phi3:mini-4k}"
  detect_codellama_only

  echo
  echo "================= 🚀 部署完成 🚀 ================="
  echo "NPM:            http://${PUBLIC_IP}:${NPM_ADMIN_PORT}"
  echo "OpenWebUI:      http://${PUBLIC_IP}:${WEBUI_PORT}"
  echo "Gemini-Balance: http://${PUBLIC_IP}:${GEMINI_BALANCE_PORT}"
  echo "=================================================="
  compose ps || true
}

do_down(){ ensure_root; compose down --remove-orphans; }
do_logs(){ ensure_root; compose logs -f --tail=200 "${@:--}"; }
do_status(){ ensure_root; compose ps "${@:--}"; }

# ---- 交互菜单 ----
menu_models(){
  while true; do
    clear
    echo -e "${G}=== 模型管理 ===${NC}"
    echo "1) 新增/拉取模型（ollama pull）"
    echo "2) 删除模型（ollama rm）"
    echo "3) 列出模型（ollama list）"
    echo "0) 返回上级菜单"
    echo
    read -rp "请选择: " ans || true
    case "$ans" in
      1) read -rp "模型名（如 phi3:mini-4k）： " m; model_add "$m"; read -rp "回车继续..." _ ;;
      2) read -rp "模型名（如 phi3:mini-4k）： " m; model_rm "$m"; read -rp "回车继续..." _ ;;
      3) model_list; read -rp "回车继续..." _ ;;
      0) break ;;
    esac
  done
}

menu(){
  clear
  echo -e "${G}=== OpenGemini 一键部署 v4.8.0（无 WARP 直连版）===${NC}"
  echo "1) 安装/更新"
  echo "2) 查看状态"
  echo "3) 实时日志"
  echo "4) 停止服务"
  echo "5) 模型管理"
  echo "0) 退出"
  echo
  read -rp "请选择: " ans || true
  case "$ans" in
    1) do_up; read -rp "回车继续..." _ ;;
    2) do_status; read -rp "回车继续..." _ ;;
    3) do_logs; read -rp "回车继续..." _ ;;
    4) do_down; read -rp "回车继续..." _ ;;
    5) menu_models ;;
    0) exit 0 ;;
  esac
}

# ---- 主入口（含非交互命令） ----
main(){
  case "${1:-menu}" in
    menu) while true; do menu; done ;;
    up) do_up ;;
    down) do_down ;;
    logs) shift; do_logs "$@" ;;
    status) shift; do_status "$@" ;;

    # 非交互模型管理
    model) case "${2:-}" in
             add) shift 2; model_add "${1:-}";;
             rm|remove|delete) shift 2; model_rm "${1:-}";;
             ls|list) shift 2; model_list;;
             *) echo "用法: $0 model {add <name>|rm <name>|list}"; exit 2;;
           esac ;;
  esac
}
main "$@"