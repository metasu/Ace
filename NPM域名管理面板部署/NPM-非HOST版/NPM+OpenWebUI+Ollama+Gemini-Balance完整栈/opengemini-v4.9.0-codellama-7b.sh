#!/usr/bin/env bash
# opengemini.sh - v4.9.0（无 WARP 直连版）
# 组件：NPM / OpenWebUI / Gemini-Balance / Ollama
#
# 功能要点：
# 1) 模型目录固定为 /etc/models（支持子目录）
#    - 优先导入本地 GGUF：基于 Modelfile 的 “FROM /models/xxx.gguf -> ollama create”
#    - 若存在 CodeLlama-7B.Q4_K_M*.gguf（或等价命名），固定导入名：codellama-7b-q4_k_m，并预热
#    - 其他 *.gguf 也会批量自动导入（模型名=文件名规范化）
# 2) 若 /etc/models 及其子目录下没有任何 *.gguf：
#    - 自动从官方库拉取：codellama:7b-code-q4_K_M，并预热
#
# 使用说明（增删模型）：
# - 添加模型：把 *.gguf 文件放进 /etc/models 或其子目录；执行：sudo ./opengemini.sh models
# - 删除模型：docker exec -it <ollama容器名> ollama delete <模型名>
#            （或宿主机装了 Ollama CLI：ollama delete <模型名>）
# - 查看模型：sudo ./opengemini.sh models（会列出并尝试导入新增文件）
#
# 参考：
# - Ollama Modelfile/Import：支持 FROM /path/to/*.gguf + ollama create
# - CodeLlama 7B Q4_K_M（官方库型号：codellama:7b-code-q4_K_M）

set -u -o pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

ROOT_DIR="$(dirname "$(readlink -f "${0:-$PWD/opengemini.sh}")")"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"
GB_ENV_FILE="$ROOT_DIR/.env.geminibalance"

# ---------- 项目名 ----------
_san_raw="$(basename "$ROOT_DIR" | tr -c 'a-zA-Z0-9-' '_')"
if [[ -z "$_san_raw" ]]; then PROJECT_NAME="npm"
else first="${_san_raw:0:1}"; [[ "$first" =~ [A-Za-z0-9] ]] && PROJECT_NAME="$_san_raw" || PROJECT_NAME="p$_san_raw"; fi
export COMPOSE_PROJECT_NAME="$PROJECT_NAME"

# ---------- 彩色 ----------
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[34m'; NC='\033[0m'
say(){ echo -e "${B}ℹ️ $*${NC}"; }
ok(){  echo -e "${G}✅ $*${NC}"; }
wrn(){ echo -e "${Y}⚠️ $*${NC}"; }
die(){ echo -e "${R}❌ $*${NC}"; exit 1; }

# ---------- 工具 ----------
have(){ command -v "${1:-}" >/dev/null 2>&1; }
ensure_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "需要 root：sudo $0"; }
rand_b64(){ head -c 24 /dev/urandom | base64; }
detect_ip(){ curl -fsS --max-time 2 ifconfig.me || hostname -I | awk '{print $1}' || echo 127.0.0.1; }
detect_tz(){ cat /etc/timezone 2>/dev/null || echo UTC; }
compose(){ docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }
fixlf(){ find "$ROOT_DIR" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.yml" -o -name ".env*" \) -exec sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' {} \; 2>/dev/null || true; }

install_docker_if_missing(){
  if ! have docker; then
    say "安装 Docker..."
    apt-get update -y && apt-get install -y docker.io docker-compose-plugin || true
    systemctl enable --now docker || true
  fi
  docker compose version >/dev/null 2>&1 || die "需要 Docker Compose v2"
}

# ---------- .env ----------
reload_env(){ set -o allexport; source "$ENV_FILE"; set +o allexport; }

create_env(){
  [[ -f "$ENV_FILE" ]] && return 0
  cat > "$ENV_FILE" <<EOF
PUBLIC_IP=$(detect_ip)
WEBUI_PORT=40001
GEMINI_BALANCE_PORT=40003
OLLAMA_PORT=11434
NPM_HTTP_PORT=80
NPM_HTTPS_PORT=443
NPM_ADMIN_PORT=40002
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

# === 模型目录（固定） ===
MODEL_DIR=/etc/models

# 优先匹配的 CodeLlama Q4_K_M 名称关键字（按顺序；分号分隔；大小写不敏感）
PREFERRED_CODELLAMA_KEYS="CodeLlama-7B.Q4_K_M;codellama-7b.Q4_K_M;CodeLlama-7B-Instruct.Q4_K_M;codellama-7b-instruct.Q4_K_M"

# 无本地模型时是否自动 pull 官方库 CodeLlama（1=是，0=否）
AUTO_PULL_DEFAULT_CODELLAMA=1
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
EOF
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
    depends_on: {npm-db: {condition: service_healthy}}
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
    # /root/.ollama 为 Ollama 默认数据；/models 挂载宿主 /etc/models（只读）
    volumes:
      - ./ollama_data:/root/.ollama
      - ${MODEL_DIR}:/models:ro
      - ./modelfiles:/modelfiles
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
  npm_internal: {driver: bridge}
  appnet: {driver: bridge}
  proxy: {external: true}
YAML
}

# ---------- 目录与就绪 ----------
ensure_dirs(){
  reload_env || true
  mkdir -p "$ROOT_DIR"/{npm_data,npm_letsencrypt,npm_db,webui_data,ollama_data,gb_data,modelfiles}
  # 创建宿主机模型目录（如不存在）
  mkdir -p "${MODEL_DIR:-/etc/models}" || true
}

wait_ollama_ready(){
  reload_env || true
  say "等待 Ollama API 就绪 (http://127.0.0.1:${OLLAMA_PORT}) ..."
  for i in {1..120}; do
    if curl -fsS "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1; then
      ok "Ollama 已就绪。"
      return 0
    fi
    sleep 2
  done
  wrn "等待 Ollama 超时，请检查端口 ${OLLAMA_PORT} 或容器日志。"
}

# ---------- 模型导入（本地 GGUF） ----------
# 归一化模型名：小写、空格->-、点->-
_norm_model_name(){
  local base="$1"; local name="${base%.gguf}"
  name="${name,,}"; name="${name// /-}"; name="${name//./-}"
  echo "$name"
}

# 扫描 /etc/models 并导入 *.gguf（容器内挂载路径为 /models）
scan_import_dir(){
  reload_env || true
  local host_dir="${MODEL_DIR:-/etc/models}"
  shopt -s nullglob
  local files=()
  while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$host_dir" -maxdepth 2 -type f -name "*.gguf" -print0 2>/dev/null)
  [[ ${#files[@]} -eq 0 ]] && return 0
  mkdir -p "$ROOT_DIR/modelfiles"
  for f in "${files[@]}"; do
    local base="$(basename "$f")"
    local model="$(_norm_model_name "$base")"
    if compose exec -T ollama sh -lc "ollama list | awk '{print \$1}' | grep -E '^${model}(:|$)'" >/dev/null 2>&1; then
      say "模型已存在，跳过：$model"
      continue
    fi
    say "导入本地 GGUF：$base -> 模型名：$model"
    echo "FROM /models/${base}" > "$ROOT_DIR/modelfiles/${model}.Modelfile"
    compose exec -T ollama sh -lc "ollama create '$model' -f '/modelfiles/${model}.Modelfile' || true"
  done
}

# 优先寻找 CodeLlama 7B Q4_K_M*.gguf
detect_codellama_file(){
  reload_env || true
  local host_dir="${MODEL_DIR:-/etc/models}"
  local keys="${PREFERRED_CODELLAMA_KEYS:-CodeLlama-7B.Q4_K_M;codellama-7b.Q4_K_M}"
  IFS=';' read -r -a arr <<< "$keys"
  for k in "${arr[@]}"; do
    local f
    while IFS= read -r -d '' f; do
      echo "$f"; return 0
    done < <(find "$host_dir" -maxdepth 2 -type f -iname "${k}*.gguf" -print0 2>/dev/null)
  done
  return 1
}

# 若找到本地 CodeLlama GGUF，则以固定名 codellama-7b-q4_k_m 导入并预热
import_priority_codellama(){
  local f="$1"
  local name="codellama-7b-q4_k_m"
  if compose exec -T ollama sh -lc "ollama list | awk '{print \$1}' | grep -E '^${name}(:|$)'" >/dev/null 2>&1; then
    ok "本地 CodeLlama 已存在（$name），跳过导入。"
    return 0
  fi
  say "检测到本地 CodeLlama Q4_K_M：$(basename "$f") -> 导入为模型名：$name"
  echo "FROM /models/$(basename "$f")" > "$ROOT_DIR/modelfiles/${name}.Modelfile"
  compose exec -T ollama sh -lc "ollama create '$name' -f '/modelfiles/${name}.Modelfile' || true"
  say "预热模型 $name ..."
  compose exec -T ollama sh -lc "ollama run '$name' -p 'hello' >/dev/null || true"
}

# ---------- 无本地模型时的兜底（自动 pull 官方库） ----------
auto_pull_default(){
  reload_env || true
  [[ "${AUTO_PULL_DEFAULT_CODELLAMA:-1}" == "1" ]] || { wrn "已关闭自动拉取默认模型，跳过。"; return 0; }
  say "未发现本地 GGUF，开始从官方库拉取：codellama:7b-code-q4_K_M"
  compose exec -T ollama sh -lc "ollama pull 'codellama:7b-code-q4_K_M' || true"
  say "预热 codellama:7b-code-q4_K_M ..."
  compose exec -T ollama sh -lc "ollama run 'codellama:7b-code-q4_K_M' -p 'hello' >/dev/null || true"
  ok "默认模型已就绪：codellama:7b-code-q4_K_M"
}

# ---------- 核心流程 ----------
do_up(){
  ensure_root; install_docker_if_missing
  create_env; create_gb_env; fixlf; reload_env
  ensure_dirs
  create_compose
  docker network inspect proxy >/dev/null 2>&1 || docker network create proxy || true
  compose pull || true
  compose up -d

  wait_ollama_ready

  # 1) 优先导入本地 CodeLlama（若存在）
  local code_path=""
  if code_path="$(detect_codellama_file)"; then
    import_priority_codellama "$code_path"
  fi

  # 2) 扫描并导入所有 GGUF
  scan_import_dir

  # 3) 若完全没有任何模型，则自动拉取默认 CodeLlama
  if ! compose exec -T ollama sh -lc "ollama list | tail -n +2 | wc -l" | grep -qE '^[1-9]'; then
    wrn "未在本地发现可用模型，执行默认拉取。"
    auto_pull_default
  fi

  echo
  echo "================= 🚀 部署完成 🚀 ================="
  echo "NPM:            http://${PUBLIC_IP}:${NPM_ADMIN_PORT}"
  echo "OpenWebUI:      http://${PUBLIC_IP}:${WEBUI_PORT}"
  echo "Gemini-Balance: http://${PUBLIC_IP}:${GEMINI_BALANCE_PORT}"
  echo "模型目录(宿主)： ${MODEL_DIR}"
  echo "=================================================="
  compose ps || true
}

do_down(){ ensure_root; compose down --remove-orphans; }
do_logs(){ ensure_root; compose logs -f --tail=200 "${@:-}"; }
do_status(){ ensure_root; compose ps "${@:-}"; }

# 独立执行：重新扫描并导入（你新增或移除 .gguf 后可用）
do_models(){
  ensure_root; reload_env
  wait_ollama_ready
  local code_path=""
  if code_path="$(detect_codellama_file)"; then
    import_priority_codellama "$code_path"
  fi
  scan_import_dir
  compose exec -T ollama sh -lc "ollama list || true"
}

menu(){
  clear
  echo -e "${G}=== OpenGemini 一键部署 v4.9.0（无 WARP 直连版）===${NC}"
  echo "1) 安装/更新（含模型导入/兜底拉取）"
  echo "2) 查看状态"
  echo "3) 实时日志"
  echo "4) 停止服务"
  echo "5) 模型管理（重新扫描 /etc/models）"
  echo "0) 退出"
  echo
  read -rp "请选择: " ans || true
  case "$ans" in
    1) do_up; read -rp "回车继续..." _ ;;
    2) do_status; read -rp "回车继续..." _ ;;
    3) do_logs; read -rp "回车继续..." _ ;;
    4) do_down; read -rp "回车继续..." _ ;;
    5) do_models; read -rp "回车继续..." _ ;;
    0) exit 0 ;;
  esac
}

main(){ case "${1:-menu}" in
  menu) while true; do menu; done ;;
  up) do_up ;;
  down) do_down ;;
  logs) do_logs ;;
  status) do_status ;;
  models) do_models ;;
esac; }
main "$@"