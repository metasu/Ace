#!/usr/bin/env bash
# opengemini.sh - v4.6.9（NPM Only）
# 组件：Nginx Proxy Manager（管理面板） + MariaDB
# 特性：自动创建 external 网络 proxy；生成 .env；一键 up/down/logs/status；适配 Docker Compose v2
# ------------------------------------------------------------------------------

set -u -o pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

ROOT_DIR="$(dirname "$(readlink -f "${0:-$PWD/opengemini.sh}")")"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"

# ---------- 项目名（用于 Compose project name） ----------
_san_raw="$(basename "$ROOT_DIR" | tr -c 'a-zA-Z0-9-' '_' )"
if [[ -z "$_san_raw" ]]; then
  PROJECT_NAME="npm"
else
  first="${_san_raw:0:1}"
  [[ "$first" =~ [A-Za-z0-9] ]] && PROJECT_NAME="$_san_raw" || PROJECT_NAME="p$_san_raw"
fi
export COMPOSE_PROJECT_NAME="$PROJECT_NAME"

# ---------- 彩色输出 ----------
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[34m'; NC='\033[0m'
say(){ echo -e "${B}ℹ️ $*${NC}"; }
ok(){  echo -e "${G}✅ $*${NC}"; }
wrn(){ echo -e "${Y}⚠️ $*${NC}"; }
die(){ echo -e "${R}❌ $*${NC}"; exit 1; }

# ---------- 工具 ----------
have(){ command -v "${1:-}" >/dev/null 2>&1; }
ensure_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "需要 root：sudo $0"; }
rand_b64(){ head -c 24 /dev/urandom | base64; }

detect_ip(){
  curl -fsS --max-time 2 ifconfig.me 2>/dev/null && return 0
  hostname -I 2>/dev/null | awk '{print $1}' && return 0
  echo 127.0.0.1
}
detect_tz(){
  cat /etc/timezone 2>/dev/null && return 0
  echo UTC
}

compose(){
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

# ---------- 默认端口 ----------
declare -A DEFAULT_PORTS=(
  [NPM_ADMIN_PORT]=40002
  [NPM_HTTP_PORT]=80
  [NPM_HTTPS_PORT]=443
)

# ---------- 行尾/BOM 清理 ----------
fixlf(){
  find "$ROOT_DIR" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.yml" -o -name ".env*" \) \
    -exec sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' {} \; 2>/dev/null || true
}

# ---------- Docker / Compose v2 ----------
install_docker_if_missing(){
  if ! have docker; then
    say "安装 Docker..."
    apt-get update -y && apt-get install -y docker.io docker-compose-plugin || true
    systemctl enable --now docker || true
  fi
  docker compose version >/dev/null 2>&1 || die "需要 Docker Compose v2（docker compose）"
}

# ---------- .env 读写 ----------
get_env_kv(){
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}
set_env_kv(){
  local k="$1" v="$2"
  awk -v K="$k" -v V="$v" 'BEGIN{r=0} $0~("^"K"="){print K"="V; r=1; next} {print} END{if(!r)print K"="V}' \
    "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
}
reload_env(){
  set -o allexport
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +o allexport
}

create_env(){
  [[ -f "$ENV_FILE" ]] && return 0
  cat > "$ENV_FILE" <<EOF
PUBLIC_IP=$(detect_ip)
TZ=$(detect_tz)

# NPM 端口
NPM_HTTP_PORT=${DEFAULT_PORTS[NPM_HTTP_PORT]}
NPM_HTTPS_PORT=${DEFAULT_PORTS[NPM_HTTPS_PORT]}
NPM_ADMIN_PORT=${DEFAULT_PORTS[NPM_ADMIN_PORT]}

# 数据库
MYSQL_ROOT_PASSWORD=$(rand_b64)
MYSQL_PASSWORD=$(rand_b64)
MYSQL_DATABASE=npm
MYSQL_USER=npm

# 镜像标签
TAG_NPM=latest
TAG_MARIADB=10.11
EOF
  chmod 600 "$ENV_FILE"
}

# ---------- 写 compose ----------
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
    depends_on:
      npm-db:
        condition: service_healthy
    networks:
      - npm_internal
      - proxy

  npm-db:
    image: mariadb:${TAG_MARIADB}
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${MYSQL_DATABASE}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
      TZ: "${TZ}"
    volumes:
      - ./npm_db:/var/lib/mysql
    networks:
      - npm_internal
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 10

networks:
  npm_internal:
    driver: bridge
  proxy:
    external: true
YAML
}

# ---------- 核心 ----------
ensure_proxy_network(){
  if docker network inspect proxy >/dev/null 2>&1; then
    ok "已存在外部网络：proxy"
  else
    say "创建外部网络：proxy"
    docker network create proxy >/dev/null 2>&1 || true
  fi
}

do_up(){
  ensure_root
  install_docker_if_missing

  mkdir -p "$ROOT_DIR"/{npm_data,npm_letsencrypt,npm_db}

  create_env
  fixlf
  reload_env
  create_compose
  ensure_proxy_network

  say "拉取镜像..."
  compose pull || true

  say "启动服务..."
  compose up -d

  echo
  echo "================= 🚀 部署完成（NPM Only）🚀 ================="
  echo "NPM 管理面板: http://${PUBLIC_IP}:${NPM_ADMIN_PORT}"
  echo "HTTP 代理端口: ${NPM_HTTP_PORT}    HTTPS 代理端口: ${NPM_HTTPS_PORT}"
  echo "============================================================"
  compose ps || true
}

do_down(){
  ensure_root
  compose down --remove-orphans
  ok "已停止并清理（保留数据卷目录）"
}

do_logs(){
  ensure_root
  compose logs -f --tail=200 "${@:-}"
}

do_status(){
  ensure_root
  compose ps "${@:-}"
}

menu(){
  clear
  echo -e "${G}=== NPM 一键部署 v4.6.9（仅网络 + NPM）===${NC}"
  echo "1) 安装/更新（up）"
  echo "2) 查看状态（status）"
  echo "3) 实时日志（logs）"
  echo "4) 停止服务（down）"
  echo "0) 退出"
  echo
  read -rp "请选择: " ans || true
  case "$ans" in
    1) do_up; read -rp "回车继续..." _ ;;
    2) do_status; read -rp "回车继续..." _ ;;
    3) do_logs; read -rp "回车继续..." _ ;;
    4) do_down; read -rp "回车继续..." _ ;;
    0) exit 0 ;;
  esac
}

main(){
  case "${1:-menu}" in
    menu)   while true; do menu; done ;;
    up)     do_up ;;
    down)   do_down ;;
    logs)   shift || true; do_logs "$@" ;;
    status) shift || true; do_status "$@" ;;
    *)      wrn "未知参数：$1"; echo "用法：$0 [menu|up|down|logs|status]"; exit 1 ;;
  esac
}

main "$@"