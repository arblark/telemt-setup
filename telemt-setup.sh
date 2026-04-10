#!/bin/bash

set -e

# ─────────────────────────────────────────────────────────────
# Telemt MTProxy — автоматическая установка v2
# https://github.com/telemt/telemt
# ─────────────────────────────────────────────────────────────

SCRIPT_VERSION="2.0.0"
TELEMT_VERSION="${TELEMT_VERSION:-latest}"
TELEMT_REPO="${TELEMT_REPO:-telemt/telemt}"
TELEMT_IMAGE="${TELEMT_IMAGE:-ghcr.io/telemt/telemt:latest}"

CONFIG_DIR="/etc/telemt"
CONFIG_FILE="${CONFIG_DIR}/telemt.toml"
SETUP_STATE_FILE="${CONFIG_DIR}/setup.env"

INSTALL_DIR="/usr/local/bin"
WORK_DIR="/opt/telemt"
SERVICE_NAME="telemt"
CONTAINER_NAME="${TM_CONTAINER:-telemt}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

AUTO_MODE=false
INSTALL_METHOD=""

# ═══════════════════════════════════════════════════════════════
#  Утилиты
# ═══════════════════════════════════════════════════════════════

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}  Telemt MTProxy — Автоматическая установка v${SCRIPT_VERSION}       ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║  https://github.com/telemt/telemt                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Ошибка: скрипт нужно запускать от root (sudo)${NC}"
        exit 1
    fi
}

detect_ip() {
    local ip=""
    ip=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null) \
        || ip=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null) \
        || ip=$(curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null) \
        || ip=$(hostname -I 2>/dev/null | awk '{print $1}') \
        || ip="YOUR_SERVER_IP"
    echo "$ip"
}

prompt_value() {
    local varname="$1"
    local description="$2"
    local default="$3"

    if [[ "$AUTO_MODE" == true ]]; then
        eval "$varname=\"$default\""
        return
    fi

    echo -en "  ${YELLOW}${description}${NC} [${GREEN}${default}${NC}]: "
    read -r input
    input="${input:-$default}"
    eval "$varname=\"$input\""
}

prompt_yes_no() {
    local prompt_text="$1"
    local default="${2:-y}"

    if [[ "$AUTO_MODE" == true ]]; then
        [[ "$default" == "y" ]]
        return
    fi

    if [[ "$default" == "y" ]]; then
        echo -en "  ${YELLOW}${prompt_text}${NC} [${GREEN}Y/n${NC}]: "
    else
        echo -en "  ${YELLOW}${prompt_text}${NC} [${GREEN}y/N${NC}]: "
    fi
    read -r answer
    answer="${answer:-$default}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

prompt_choice() {
    local varname="$1"
    local description="$2"
    local default="$3"
    shift 3
    local options=("$@")

    if [[ "$AUTO_MODE" == true ]]; then
        eval "$varname=\"$default\""
        return
    fi

    echo -e "  ${YELLOW}${description}${NC}"
    local i=1
    for opt in "${options[@]}"; do
        if [[ "$opt" == "$default" ]]; then
            echo -e "    ${GREEN}${i})${NC} ${BOLD}${opt}${NC} ${DIM}(по умолч.)${NC}"
        else
            echo -e "    ${GREEN}${i})${NC} ${opt}"
        fi
        ((i++))
    done
    echo -en "  ${YELLOW}Выбор${NC} [${GREEN}${default}${NC}]: "
    read -r input
    input="${input:-$default}"

    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#options[@]} )); then
        input="${options[$((input-1))]}"
    fi

    eval "$varname=\"$input\""
}

# ═══════════════════════════════════════════════════════════════
#  Пресеты конфигурации
# ═══════════════════════════════════════════════════════════════

apply_preset() {
    local preset="$1"
    case "$preset" in
        recommended)
            MODE_CLASSIC="false"
            MODE_SECURE="false"
            MODE_TLS="true"
            MIDDLE_PROXY="true"
            MASK_ENABLED="true"
            TLS_EMULATION="true"
            MASK_HOST=""
            TLS_DOMAIN="${TLS_DOMAIN:-apple.com}"
            LOG_LEVEL="normal"
            API_ENABLED="true"
            METRICS_ENABLED="false"
            USE_IPV6="false"
            FAST_MODE="false"
            AD_TAG=""
            ;;
        secure)
            MODE_CLASSIC="false"
            MODE_SECURE="true"
            MODE_TLS="false"
            MIDDLE_PROXY="true"
            MASK_ENABLED="true"
            TLS_EMULATION="false"
            MASK_HOST=""
            TLS_DOMAIN="${TLS_DOMAIN:-apple.com}"
            LOG_LEVEL="normal"
            API_ENABLED="true"
            METRICS_ENABLED="false"
            USE_IPV6="false"
            FAST_MODE="false"
            AD_TAG=""
            ;;
        simple)
            MODE_CLASSIC="true"
            MODE_SECURE="false"
            MODE_TLS="false"
            MIDDLE_PROXY="false"
            MASK_ENABLED="true"
            TLS_EMULATION="false"
            MASK_HOST=""
            TLS_DOMAIN="${TLS_DOMAIN:-www.cloudflare.com}"
            LOG_LEVEL="normal"
            API_ENABLED="true"
            METRICS_ENABLED="false"
            USE_IPV6="false"
            FAST_MODE="false"
            AD_TAG=""
            ;;
        custom)
            ;;
    esac
}

show_preset_menu() {
    if [[ "$AUTO_MODE" == true ]]; then
        apply_preset "${TM_PRESET:-recommended}"
        return
    fi

    echo -e "${BOLD}Выберите профиль конфигурации:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${BOLD}Рекомендуемый${NC} ${DIM}(по умолч.)${NC}"
    echo -e "     TLS (ee) + Middle Proxy + TLS-эмуляция + маскировка"
    echo -e "     ${DIM}Трафик неотличим от HTTPS — эталонная конфигурация telemt${NC}"
    echo ""
    echo -e "  ${GREEN}2)${NC} ${BOLD}Secure${NC}"
    echo -e "     Secure (dd) + Middle Proxy + маскировка"
    echo -e "     ${DIM}Обфускация без TLS-обёртки — быстрее, но проще для DPI${NC}"
    echo ""
    echo -e "  ${GREEN}3)${NC} ${BOLD}Простой${NC}"
    echo -e "     Classic + прямое подключение + маскировка"
    echo -e "     ${DIM}Без Middle Proxy, без обфускации — проверенная рабочая конфигурация${NC}"
    echo ""
    echo -e "  ${GREEN}4)${NC} ${BOLD}Ручная настройка${NC}"
    echo -e "     ${DIM}Настроить каждый параметр вручную${NC}"
    echo ""
    echo -en "  ${YELLOW}Выбор${NC} [${GREEN}1${NC}]: "
    read -r preset_choice
    preset_choice="${preset_choice:-1}"

    case "$preset_choice" in
        1|recommended)    apply_preset "recommended" ;;
        2|secure)         apply_preset "secure" ;;
        3|simple)         apply_preset "simple" ;;
        4|custom)         apply_preset "custom" ;;
        *)                apply_preset "recommended" ;;
    esac

    SELECTED_PRESET="$preset_choice"
}

# ═══════════════════════════════════════════════════════════════
#  Сохранение / загрузка состояния
# ═══════════════════════════════════════════════════════════════

save_state() {
    mkdir -p "$CONFIG_DIR"
    cat > "$SETUP_STATE_FILE" <<'STATE_HEADER'
# telemt-setup state file — do not edit manually
STATE_HEADER
    {
        echo "INSTALL_METHOD=\"${INSTALL_METHOD}\""
        echo "CONTAINER_NAME=\"${CONTAINER_NAME}\""
        echo "SERVER_IP=\"${SERVER_IP}\""
        echo "SERVER_PORT=\"${SERVER_PORT}\""
        echo "TLS_DOMAIN=\"${TLS_DOMAIN}\""
        echo "MASK_ENABLED=\"${MASK_ENABLED}\""
        echo "TLS_EMULATION=\"${TLS_EMULATION}\""
        echo "LOG_LEVEL=\"${LOG_LEVEL}\""
        echo "MODE_CLASSIC=\"${MODE_CLASSIC}\""
        echo "MODE_SECURE=\"${MODE_SECURE}\""
        echo "MODE_TLS=\"${MODE_TLS}\""
        echo "METRICS_ENABLED=\"${METRICS_ENABLED}\""
        echo "METRICS_PORT=\"${METRICS_PORT}\""
        echo "API_ENABLED=\"${API_ENABLED}\""
        echo "API_PORT=\"${API_PORT}\""
        echo "API_LISTEN=\"${API_LISTEN}\""
        echo "MIDDLE_PROXY=\"${MIDDLE_PROXY}\""
        echo "MASK_HOST=\"${MASK_HOST}\""
        echo "PUBLIC_HOST=\"${PUBLIC_HOST}\""
        echo "PUBLIC_PORT=\"${PUBLIC_PORT}\""
        echo "USE_IPV6=\"${USE_IPV6}\""
        echo "FAST_MODE=\"${FAST_MODE}\""
        echo "AD_TAG=\"${AD_TAG}\""
        echo "PROXY_PROTOCOL=\"${PROXY_PROTOCOL}\""
        printf 'USERS_CONFIG=%q\n' "$USERS_CONFIG"
    } >> "$SETUP_STATE_FILE"
    chmod 600 "$SETUP_STATE_FILE"
}

load_state() {
    if [[ -f "$SETUP_STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$SETUP_STATE_FILE"
        return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════
#  Генерация config.toml
# ═══════════════════════════════════════════════════════════════

generate_secret() {
    local secret=""
    if command -v openssl &>/dev/null; then
        secret=$(openssl rand -hex 16 2>/dev/null) || true
    fi
    if [[ -z "$secret" || ${#secret} -ne 32 ]]; then
        secret=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    fi
    if [[ ${#secret} -ne 32 ]]; then
        secret=$(head -c 16 /dev/urandom | xxd -p 2>/dev/null | tr -d '\n')
    fi
    echo "$secret"
}

generate_config() {
    local escaped_domain
    escaped_domain=$(printf '%s' "$TLS_DOMAIN" | sed 's/\\/\\\\/g; s/"/\\"/g')

    cat > "$CONFIG_FILE" <<TOML_EOF
# ═══════════════════════════════════════════════════════════════
# Telemt config.toml — generated by telemt-setup.sh v${SCRIPT_VERSION}
# ═══════════════════════════════════════════════════════════════

# === General Settings ===
[general]
use_middle_proxy = ${MIDDLE_PROXY}
TOML_EOF

    if [[ -n "$AD_TAG" ]]; then
        echo "ad_tag = \"${AD_TAG}\"" >> "$CONFIG_FILE"
    fi

    cat >> "$CONFIG_FILE" <<TOML_EOF

# Log level: debug | verbose | normal | silent
log_level = "${LOG_LEVEL}"

[general.modes]
classic = ${MODE_CLASSIC}
secure = ${MODE_SECURE}
tls = ${MODE_TLS}

[general.links]
show = "*"
TOML_EOF

    if [[ -n "$PUBLIC_HOST" && "$PUBLIC_HOST" != "auto" ]]; then
        echo "public_host = \"${PUBLIC_HOST}\"" >> "$CONFIG_FILE"
    fi
    if [[ -n "$PUBLIC_PORT" && "$PUBLIC_PORT" != "$SERVER_PORT" ]]; then
        echo "public_port = ${PUBLIC_PORT}" >> "$CONFIG_FILE"
    fi

    cat >> "$CONFIG_FILE" <<TOML_EOF

# === Server Binding ===
[server]
port = ${SERVER_PORT}
TOML_EOF

    if [[ "${PROXY_PROTOCOL:-false}" == "true" ]]; then
        echo "proxy_protocol = true" >> "$CONFIG_FILE"
    fi

    if [[ "$METRICS_ENABLED" == "true" ]]; then
        cat >> "$CONFIG_FILE" <<TOML_EOF
metrics_listen = "0.0.0.0:${METRICS_PORT}"
# metrics_whitelist = ["127.0.0.1", "::1", "0.0.0.0/0"]
TOML_EOF
    fi

    if [[ "$API_ENABLED" == "true" ]]; then
        cat >> "$CONFIG_FILE" <<TOML_EOF

[server.api]
enabled = true
listen = "${API_LISTEN}:${API_PORT}"
whitelist = ["127.0.0.0/8"]
minimal_runtime_enabled = false
minimal_runtime_cache_ttl_ms = 1000
TOML_EOF
    else
        cat >> "$CONFIG_FILE" <<TOML_EOF

[server.api]
enabled = false
TOML_EOF
    fi

    cat >> "$CONFIG_FILE" <<TOML_EOF

# Listen on multiple interfaces — IPv4
[[server.listeners]]
ip = "0.0.0.0"
TOML_EOF

    if [[ "$USE_IPV6" == "true" ]]; then
        cat >> "$CONFIG_FILE" <<TOML_EOF

# Listen — IPv6
[[server.listeners]]
ip = "::"
TOML_EOF
    fi

    local escaped_mask_host=""
    if [[ -n "$MASK_HOST" ]]; then
        escaped_mask_host=$(printf '%s' "$MASK_HOST" | sed 's/\\/\\\\/g; s/"/\\"/g')
    fi

    cat >> "$CONFIG_FILE" <<TOML_EOF

# === Anti-Censorship & Masking ===
[censorship]
tls_domain = "${escaped_domain}"
mask = ${MASK_ENABLED}
tls_emulation = ${TLS_EMULATION}
tls_front_dir = "tlsfront"
TOML_EOF

    if [[ -n "$escaped_mask_host" ]]; then
        echo "mask_host = \"${escaped_mask_host}\"" >> "$CONFIG_FILE"
    fi

    cat >> "$CONFIG_FILE" <<TOML_EOF

# === Access / Users ===
# Format: "username" = "32_hex_chars_secret"
[access.users]
TOML_EOF

    while IFS='=' read -r uname usecret; do
        uname=$(echo "$uname" | xargs)
        usecret=$(echo "$usecret" | xargs | tr -d '"')
        if [[ -n "$uname" && -n "$usecret" ]]; then
            echo "${uname} = \"${usecret}\"" >> "$CONFIG_FILE"
        fi
    done <<< "$USERS_CONFIG"

    chmod 644 "$CONFIG_FILE"
    echo -e "${GREEN}✓ Конфигурация сохранена: ${CONFIG_FILE}${NC}"
}

# ═══════════════════════════════════════════════════════════════
#  Проверки
# ═══════════════════════════════════════════════════════════════

check_port_available() {
    local port="$1"
    local pid_info=""

    if command -v ss &>/dev/null; then
        pid_info=$(ss -tulpn 2>/dev/null | grep -E ":${port}([[:space:]]|$)" || true)
    elif command -v netstat &>/dev/null; then
        pid_info=$(netstat -tulpn 2>/dev/null | grep -E ":${port}([[:space:]]|$)" || true)
    fi

    if [[ -n "$pid_info" ]]; then
        if echo "$pid_info" | grep -q "telemt"; then
            echo -e "${YELLOW}⚠ Порт ${port} занят текущим процессом telemt — будет перезапущен${NC}"
            return 0
        fi

        echo -e "${RED}✗ Порт ${port} уже занят:${NC}"
        echo -e "  ${YELLOW}${pid_info}${NC}"
        echo ""
        if [[ "$AUTO_MODE" == true ]]; then
            echo -e "${RED}Ошибка: порт ${port} занят (авто-режим)${NC}"
            exit 1
        fi
        if prompt_yes_no "Продолжить на этот порт?" "n"; then
            return 0
        fi
        echo -en "  ${YELLOW}Введите другой порт: ${NC}"
        read -r new_port
        if [[ -z "$new_port" ]]; then
            echo -e "${RED}Порт не указан, прерываю${NC}"
            exit 1
        fi
        SERVER_PORT="$new_port"
        check_port_available "$SERVER_PORT"
    fi
}

validate_domain() {
    local domain="$1"
    if command -v dig &>/dev/null; then
        if dig +short "$domain" A 2>/dev/null | grep -qE '^[0-9]+\.'; then
            echo -e "${GREEN}✓ Домен '${domain}' резолвится${NC}"
            return
        fi
    elif command -v nslookup &>/dev/null; then
        if nslookup "$domain" 8.8.8.8 &>/dev/null; then
            echo -e "${GREEN}✓ Домен '${domain}' резолвится${NC}"
            return
        fi
    elif command -v host &>/dev/null; then
        if host "$domain" &>/dev/null; then
            echo -e "${GREEN}✓ Домен '${domain}' резолвится${NC}"
            return
        fi
    fi
    echo -e "${YELLOW}⚠ Домен '${domain}' не резолвится — TLS-маскировка может работать некорректно${NC}"
    if [[ "$AUTO_MODE" == false ]]; then
        if ! prompt_yes_no "Продолжить с этим доменом?" "y"; then
            prompt_value TLS_DOMAIN "Введите другой домен" "apple.com"
            validate_domain "$TLS_DOMAIN"
        fi
    fi
}

verify_connection() {
    local port="$1"
    local max_attempts=5
    local attempt=0

    echo -e "${CYAN}➜ Проверка доступности порта ${port}...${NC}"
    while (( attempt < max_attempts )); do
        if (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
            echo -e "${GREEN}✓ Порт ${port} отвечает — прокси работает${NC}"
            return 0
        fi
        ((attempt++))
        sleep 1
    done
    echo -e "${YELLOW}⚠ Порт ${port} не отвечает локально (может быть нормально при NAT)${NC}"
}

open_firewall_port() {
    local port="$1"
    if command -v ufw &>/dev/null; then
        echo -e "${CYAN}➜ Открываю порт ${port} в UFW...${NC}"
        ufw allow "${port}/tcp" &>/dev/null
        echo -e "${GREEN}✓ Порт ${port}/tcp открыт в UFW${NC}"
    fi
    if command -v firewall-cmd &>/dev/null; then
        echo -e "${CYAN}➜ Открываю порт ${port} в firewalld...${NC}"
        firewall-cmd --permanent --add-port="${port}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        echo -e "${GREEN}✓ Порт ${port}/tcp открыт в firewalld${NC}"
    fi
}

close_firewall_port() {
    local port="$1"
    if command -v ufw &>/dev/null; then
        ufw delete allow "${port}/tcp" &>/dev/null || true
    fi
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --remove-port="${port}/tcp" &>/dev/null || true
        firewall-cmd --reload &>/dev/null
    fi
}

install_qrencode() {
    if command -v qrencode &>/dev/null; then
        return 0
    fi
    if command -v apt-get &>/dev/null; then
        apt-get install -y -qq qrencode &>/dev/null && return 0
    elif command -v yum &>/dev/null; then
        yum install -y -q qrencode &>/dev/null && return 0
    elif command -v dnf &>/dev/null; then
        dnf install -y -q qrencode &>/dev/null && return 0
    elif command -v apk &>/dev/null; then
        apk add --no-cache qrencode &>/dev/null && return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════
#  Docker: установка / управление
# ═══════════════════════════════════════════════════════════════

install_docker() {
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}✓ Docker уже установлен: $(docker --version)${NC}"
        return
    fi

    echo -e "${CYAN}➜ Установка Docker...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq docker.io
    elif command -v yum &>/dev/null; then
        yum install -y docker
        systemctl start docker
    elif command -v dnf &>/dev/null; then
        dnf install -y docker
        systemctl start docker
    elif command -v apk &>/dev/null; then
        apk add --no-cache docker
        rc-update add docker boot 2>/dev/null || true
        service docker start 2>/dev/null || true
    else
        echo -e "${YELLOW}➜ Пакетный менеджер не найден, ставлю через официальный скрипт Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
    fi

    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    echo -e "${GREEN}✓ Docker установлен: $(docker --version)${NC}"
}

stop_docker_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
        echo -e "${YELLOW}➜ Останавливаю контейнер '${name}'...${NC}"
        docker rm -f "$name" &>/dev/null || true
    fi
}

wait_for_container() {
    local name="$1"
    local max_attempts=15
    local attempt=0

    echo -e "${CYAN}➜ Ожидание запуска контейнера...${NC}"
    while (( attempt < max_attempts )); do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
            echo -e "${GREEN}✓ Контейнер '${name}' запущен${NC}"
            return 0
        fi
        ((attempt++))
        sleep 1
    done

    echo -e "${RED}✗ Контейнер не запустился за ${max_attempts} секунд. Логи:${NC}"
    docker logs "$name" 2>&1 || true
    return 1
}

build_docker_run_args() {
    local name="$1"
    local -n _args=$2

    _args=(
        -d
        --name "$name"
        --restart unless-stopped
        -p "${SERVER_PORT}:443"
    )

    if [[ "$METRICS_ENABLED" == "true" ]]; then
        _args+=(-p "127.0.0.1:${METRICS_PORT}:${METRICS_PORT}")
    fi
    if [[ "$API_ENABLED" == "true" ]]; then
        _args+=(-p "127.0.0.1:${API_PORT}:${API_PORT}")
    fi

    _args+=(
        -w /etc/telemt
        -v "${CONFIG_FILE}:/etc/telemt/config.toml:ro"
        --tmpfs /etc/telemt:rw,mode=1777,size=4m
        --cap-drop ALL
        --cap-add NET_BIND_SERVICE
        --cap-add NET_ADMIN
        --read-only
        --security-opt no-new-privileges:true
        --ulimit nofile=65536:262144
    )
}

run_docker_install() {
    install_docker

    echo -e "${CYAN}➜ Загрузка образа ${TELEMT_IMAGE}...${NC}"
    docker pull "$TELEMT_IMAGE"
    echo -e "${GREEN}✓ Образ загружен${NC}"

    mkdir -p "$CONFIG_DIR"
    generate_config

    stop_docker_container "$CONTAINER_NAME"

    echo -e "${CYAN}➜ Запуск контейнера...${NC}"

    local docker_args=()
    build_docker_run_args "$CONTAINER_NAME" docker_args

    docker run "${docker_args[@]}" "$TELEMT_IMAGE" config.toml

    if ! wait_for_container "$CONTAINER_NAME"; then
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Binary: установка / управление
# ═══════════════════════════════════════════════════════════════

detect_arch() {
    local sys_arch
    sys_arch=$(uname -m)
    case "$sys_arch" in
        x86_64|amd64)
            if [[ -r /proc/cpuinfo ]] && grep -q "avx2" /proc/cpuinfo 2>/dev/null && grep -q "bmi2" /proc/cpuinfo 2>/dev/null; then
                echo "x86_64-v3"
            else
                echo "x86_64"
            fi
            ;;
        aarch64|arm64) echo "aarch64" ;;
        *) echo -e "${RED}Неподдерживаемая архитектура: ${sys_arch}${NC}"; exit 1 ;;
    esac
}

detect_libc() {
    for f in /lib/ld-musl-*.so.* /lib64/ld-musl-*.so.*; do
        if [[ -e "$f" ]]; then echo "musl"; return; fi
    done
    if grep -qE '^ID="?alpine"?' /etc/os-release 2>/dev/null; then echo "musl"; return; fi
    if command -v ldd &>/dev/null && (ldd --version 2>&1 || true) | grep -qi musl; then echo "musl"; return; fi
    echo "gnu"
}

ensure_telemt_user() {
    local nologin_bin
    nologin_bin=$(command -v nologin 2>/dev/null || command -v false 2>/dev/null || echo /bin/false)

    if ! getent group telemt &>/dev/null 2>&1; then
        if command -v groupadd &>/dev/null; then
            groupadd -r telemt
        elif command -v addgroup &>/dev/null; then
            addgroup -S telemt
        fi
    fi

    if ! getent passwd telemt &>/dev/null 2>&1; then
        if command -v useradd &>/dev/null; then
            useradd -r -g telemt -d "$WORK_DIR" -s "$nologin_bin" -c "Telemt Proxy" telemt
        elif command -v adduser &>/dev/null; then
            if adduser --help 2>&1 | grep -q -- '-S'; then
                adduser -S -D -H -h "$WORK_DIR" -s "$nologin_bin" -G telemt telemt
            else
                adduser --system --home "$WORK_DIR" --shell "$nologin_bin" --no-create-home --ingroup telemt --disabled-password telemt
            fi
        fi
    fi
}

get_svc_mgr() {
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif command -v rc-service &>/dev/null; then
        echo "openrc"
    else
        echo "none"
    fi
}

install_systemd_service() {
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<UNIT_EOF
[Unit]
Description=Telemt MTProxy
Documentation=https://github.com/telemt/telemt
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=${WORK_DIR}
ExecStart=${INSTALL_DIR}/telemt ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=262144

ProtectSystem=strict
ProtectHome=true
NoNewPrivileges=true
PrivateTmp=true
ReadWritePaths=${WORK_DIR} ${CONFIG_DIR}

AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
UNIT_EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    echo -e "${GREEN}✓ Systemd-сервис установлен и запущен${NC}"
}

install_openrc_service() {
    cat > "/etc/init.d/${SERVICE_NAME}" <<'OPENRC_HEADER'
#!/sbin/openrc-run

description="Telemt MTProxy"
OPENRC_HEADER

    cat >> "/etc/init.d/${SERVICE_NAME}" <<OPENRC_EOF

command="${INSTALL_DIR}/telemt"
command_args="${CONFIG_FILE}"
command_user="telemt:telemt"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
directory="${WORK_DIR}"

depend() {
    need net
    after firewall
}
OPENRC_EOF

    chmod +x "/etc/init.d/${SERVICE_NAME}"
    rc-update add "$SERVICE_NAME" default 2>/dev/null || true
    rc-service "$SERVICE_NAME" start 2>/dev/null || true
    echo -e "${GREEN}✓ OpenRC-сервис установлен и запущен${NC}"
}

install_setcap() {
    if ! command -v setcap &>/dev/null; then
        if command -v apk &>/dev/null; then
            apk add --no-cache libcap-utils libcap 2>/dev/null || true
        elif command -v apt-get &>/dev/null; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y -q libcap2-bin 2>/dev/null || {
                apt-get update -q 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get install -y -q libcap2-bin 2>/dev/null || true
            }
        elif command -v dnf &>/dev/null; then
            dnf install -y -q libcap 2>/dev/null || true
        elif command -v yum &>/dev/null; then
            yum install -y -q libcap 2>/dev/null || true
        fi
    fi
}

fetch_file() {
    if command -v curl &>/dev/null; then
        curl -fsSL "$1" -o "$2"
    else
        wget -q -O "$2" "$1"
    fi
}

run_binary_install() {
    echo -e "${CYAN}➜ Установка бинарника telemt...${NC}"

    command -v curl &>/dev/null || command -v wget &>/dev/null || {
        echo -e "${RED}Ошибка: нужен curl или wget${NC}"; exit 1
    }

    install_setcap

    local arch libc file_name dl_url base_url
    arch=$(detect_arch)
    libc=$(detect_libc)
    file_name="telemt-${arch}-linux-${libc}.tar.gz"

    if [[ "$TELEMT_VERSION" == "latest" ]]; then
        base_url="https://github.com/${TELEMT_REPO}/releases/latest/download"
    else
        base_url="https://github.com/${TELEMT_REPO}/releases/download/${TELEMT_VERSION}"
    fi
    dl_url="${base_url}/${file_name}"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    echo -e "${CYAN}➜ Скачиваю ${file_name}...${NC}"

    if ! fetch_file "$dl_url" "${tmp_dir}/${file_name}" 2>/dev/null; then
        if [[ "$arch" == "x86_64-v3" ]]; then
            echo -e "${YELLOW}⚠ Сборка x86_64-v3 не найдена, откат к стандартной x86_64...${NC}"
            arch="x86_64"
            file_name="telemt-${arch}-linux-${libc}.tar.gz"
            dl_url="${base_url}/${file_name}"
            fetch_file "$dl_url" "${tmp_dir}/${file_name}"
        else
            echo -e "${RED}Ошибка загрузки архива${NC}"
            exit 1
        fi
    fi

    local checksum_file="${file_name}.sha256"
    if fetch_file "${base_url}/${checksum_file}" "${tmp_dir}/${checksum_file}" 2>/dev/null; then
        echo -e "${CYAN}➜ Проверка контрольной суммы...${NC}"
        if (cd "$tmp_dir" && sha256sum -c "$checksum_file" &>/dev/null); then
            echo -e "${GREEN}✓ SHA256 совпадает${NC}"
        else
            echo -e "${RED}✗ Контрольная сумма не совпадает!${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ SHA256 файл недоступен, пропускаю верификацию${NC}"
    fi

    echo -e "${GREEN}✓ Скачано${NC}"

    echo -e "${CYAN}➜ Распаковка...${NC}"
    tar -xzf "${tmp_dir}/${file_name}" -C "$tmp_dir"

    local extracted_bin
    extracted_bin=$(find "$tmp_dir" -type f -name "telemt" -print -quit 2>/dev/null)
    if [[ -z "$extracted_bin" ]]; then
        echo -e "${RED}Ошибка: бинарник 'telemt' не найден в архиве${NC}"
        exit 1
    fi

    ensure_telemt_user

    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$WORK_DIR"
    chown telemt:telemt "$WORK_DIR"
    chmod 750 "$WORK_DIR"
    chown telemt:telemt "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"

    local svc_mgr
    svc_mgr=$(get_svc_mgr)

    if [[ "$svc_mgr" == "systemd" ]] && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
    elif [[ "$svc_mgr" == "openrc" ]] && rc-service "$SERVICE_NAME" status &>/dev/null; then
        rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    fi

    install -m 0755 "$extracted_bin" "${INSTALL_DIR}/telemt"

    if command -v setcap &>/dev/null; then
        setcap cap_net_bind_service,cap_net_admin=+ep "${INSTALL_DIR}/telemt" 2>/dev/null || true
    fi
    echo -e "${GREEN}✓ Бинарник установлен: ${INSTALL_DIR}/telemt${NC}"

    generate_config
    chown root:telemt "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"

    case "$svc_mgr" in
        systemd)
            install_systemd_service
            ;;
        openrc)
            install_openrc_service
            ;;
        *)
            echo -e "${YELLOW}Менеджер служб не найден. Запустите вручную:${NC}"
            echo -e "  sudo -u telemt ${INSTALL_DIR}/telemt ${CONFIG_FILE}"
            ;;
    esac

    rm -rf "$tmp_dir"
    trap - EXIT
}

# ═══════════════════════════════════════════════════════════════
#  Вывод результата
# ═══════════════════════════════════════════════════════════════

build_link_secret() {
    local user_secret="$1"
    local hex_domain=""

    if command -v xxd &>/dev/null; then
        hex_domain=$(printf '%s' "$TLS_DOMAIN" | xxd -p | tr -d '\n')
    elif command -v hexdump &>/dev/null; then
        hex_domain=$(printf '%s' "$TLS_DOMAIN" | hexdump -v -e '/1 "%02x"')
    elif command -v od &>/dev/null; then
        hex_domain=$(printf '%s' "$TLS_DOMAIN" | od -A n -t x1 | tr -d ' \n')
    fi

    if [[ "$MODE_TLS" == "true" ]]; then
        echo "ee${user_secret}${hex_domain}"
    elif [[ "$MODE_SECURE" == "true" ]]; then
        echo "dd${user_secret}"
    else
        echo "${user_secret}"
    fi
}

get_link_mode_label() {
    if [[ "$MODE_TLS" == "true" ]]; then
        echo "TLS/ee"
    elif [[ "$MODE_SECURE" == "true" ]]; then
        echo "Secure/dd"
    else
        echo "Classic"
    fi
}

print_user_links() {
    local user_name="$1"
    local user_secret="$2"
    local host="${PUBLIC_HOST:-$SERVER_IP}"
    local port="${PUBLIC_PORT:-$SERVER_PORT}"

    if [[ "$host" == "auto" || -z "$host" ]]; then
        host="$SERVER_IP"
    fi

    local link_secret
    link_secret=$(build_link_secret "$user_secret")
    local tme_link="https://t.me/proxy?server=${host}&port=${port}&secret=${link_secret}"
    local tg_link="tg://proxy?server=${host}&port=${port}&secret=${link_secret}"

    echo -e "  ${BOLD}${user_name}:${NC}"
    echo -e "    ${GREEN}${tme_link}${NC}"
    echo -e "    ${DIM}${tg_link}${NC}"
    echo ""
}

print_result() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}  Установка завершена!                                    ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Метод:${NC}         ${INSTALL_METHOD}"
    echo -e "  ${BOLD}Сервер:${NC}        ${SERVER_IP}"
    echo -e "  ${BOLD}Порт:${NC}          ${SERVER_PORT}"
    echo -e "  ${BOLD}TLS-домен:${NC}     ${TLS_DOMAIN}"
    if [[ -n "$MASK_HOST" && "$MASK_HOST" != "$TLS_DOMAIN" ]]; then
        echo -e "  ${BOLD}Mask-хост:${NC}     ${MASK_HOST}"
    fi
    echo -e "  ${BOLD}Маскировка:${NC}    ${MASK_ENABLED}"
    echo -e "  ${BOLD}TLS-эмуляция:${NC}  ${TLS_EMULATION}"
    echo -e "  ${BOLD}Логирование:${NC}   ${LOG_LEVEL}"
    echo -e "  ${BOLD}Режимы:${NC}        classic=${MODE_CLASSIC}, secure=${MODE_SECURE}, tls=${MODE_TLS}"
    if [[ -n "$AD_TAG" ]]; then
        echo -e "  ${BOLD}Ad Tag:${NC}        ${AD_TAG}"
    fi
    if [[ "$METRICS_ENABLED" == "true" ]]; then
        echo -e "  ${BOLD}Метрики:${NC}       0.0.0.0:${METRICS_PORT}"
    fi
    if [[ "$API_ENABLED" == "true" ]]; then
        echo -e "  ${BOLD}API:${NC}           ${API_LISTEN}:${API_PORT}"
    fi
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Ссылки для подключения в Telegram ($(get_link_mode_label)):${NC}"
    echo ""

    while IFS='=' read -r name secret; do
        name=$(echo "$name" | xargs)
        secret=$(echo "$secret" | xargs | tr -d '"')
        if [[ -n "$name" && -n "$secret" ]]; then
            print_user_links "$name" "$secret"
        fi
    done <<< "$USERS_CONFIG"

    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

    local first_name first_secret
    first_name=$(echo "$USERS_CONFIG" | head -1 | cut -d= -f1 | xargs)
    first_secret=$(echo "$USERS_CONFIG" | head -1 | cut -d= -f2 | xargs | tr -d '"')
    if [[ -n "$first_name" && -n "$first_secret" ]]; then
        local host="${PUBLIC_HOST:-$SERVER_IP}"
        local port="${PUBLIC_PORT:-$SERVER_PORT}"
        [[ "$host" == "auto" || -z "$host" ]] && host="$SERVER_IP"
        local link_secret
        link_secret=$(build_link_secret "$first_secret")
        local tme_link="https://t.me/proxy?server=${host}&port=${port}&secret=${link_secret}"

        if install_qrencode; then
            echo -e "  ${BOLD}QR-код (${first_name}):${NC}"
            echo ""
            qrencode -t ANSIUTF8 "$tme_link"
            echo ""
        fi
    fi

    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Полезные команды:${NC}"
    echo -e "    Статус:     ${GREEN}$0 --status${NC}"
    echo -e "    Ссылки:     ${GREEN}$0 --show${NC}"
    echo -e "    Обновить:   ${GREEN}$0 --update${NC}"
    echo -e "    Удалить:    ${GREEN}$0 --uninstall${NC}"
    echo -e "    Справка:    ${GREEN}$0 --help${NC}"

    if [[ "$API_ENABLED" == "true" ]]; then
        echo ""
        echo -e "  ${BOLD}API (получить ссылки):${NC}"
        echo -e "    ${DIM}curl -s http://127.0.0.1:${API_PORT}/v1/users | jq .${NC}"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════
#  Команды: --status, --show, --update, --uninstall
# ═══════════════════════════════════════════════════════════════

do_status() {
    check_root
    if ! load_state; then
        echo -e "${RED}Telemt не установлен (конфигурация не найдена)${NC}"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Telemt MTProxy — Статус${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

    if [[ "$INSTALL_METHOD" == "docker" ]]; then
        local name="${CONTAINER_NAME:-telemt}"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
            local status_line
            status_line=$(docker ps --format 'table {{.Status}}\t{{.Ports}}' --filter "name=^${name}$" | tail -1)
            echo -e "  ${BOLD}Состояние:${NC}  ${GREEN}работает${NC}"
            echo -e "  ${BOLD}Детали:${NC}     ${status_line}"
        elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
            local status_line
            status_line=$(docker ps -a --format '{{.Status}}' --filter "name=^${name}$" | tail -1)
            echo -e "  ${BOLD}Состояние:${NC}  ${RED}остановлен${NC}"
            echo -e "  ${BOLD}Детали:${NC}     ${status_line}"
        else
            echo -e "  ${BOLD}Состояние:${NC}  ${RED}контейнер не найден${NC}"
        fi
    else
        local svc_mgr
        svc_mgr=$(get_svc_mgr)
        if [[ "$svc_mgr" == "systemd" ]]; then
            if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                echo -e "  ${BOLD}Состояние:${NC}  ${GREEN}работает${NC}"
                systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -5 || true
            else
                echo -e "  ${BOLD}Состояние:${NC}  ${RED}не работает${NC}"
            fi
        elif [[ "$svc_mgr" == "openrc" ]]; then
            if rc-service "$SERVICE_NAME" status &>/dev/null; then
                echo -e "  ${BOLD}Состояние:${NC}  ${GREEN}работает${NC}"
            else
                echo -e "  ${BOLD}Состояние:${NC}  ${RED}не работает${NC}"
            fi
        else
            echo -e "  ${BOLD}Состояние:${NC}  ${YELLOW}неизвестно (нет менеджера служб)${NC}"
        fi
    fi

    echo ""
    echo -e "  ${BOLD}Метод:${NC}       ${INSTALL_METHOD}"
    echo -e "  ${BOLD}Сервер:${NC}      ${SERVER_IP}"
    echo -e "  ${BOLD}Порт:${NC}        ${SERVER_PORT}"
    echo -e "  ${BOLD}TLS-домен:${NC}   ${TLS_DOMAIN}"
    echo -e "  ${BOLD}Маскировка:${NC}  ${MASK_ENABLED}"
    if [[ -n "$MASK_HOST" && "$MASK_HOST" != "$TLS_DOMAIN" ]]; then
        echo -e "  ${BOLD}Mask-хост:${NC}  ${MASK_HOST}"
    fi
    echo ""

    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Ссылки ($(get_link_mode_label)):${NC}"
    while IFS='=' read -r name secret; do
        name=$(echo "$name" | xargs)
        secret=$(echo "$secret" | xargs | tr -d '"')
        if [[ -n "$name" && -n "$secret" ]]; then
            local host="${PUBLIC_HOST:-$SERVER_IP}"
            local port="${PUBLIC_PORT:-$SERVER_PORT}"
            [[ "$host" == "auto" || -z "$host" ]] && host="$SERVER_IP"
            local link_secret
            link_secret=$(build_link_secret "$secret")
            echo -e "  ${BOLD}${name}:${NC} ${GREEN}https://t.me/proxy?server=${host}&port=${port}&secret=${link_secret}${NC}"
        fi
    done <<< "$USERS_CONFIG"
    echo ""
    exit 0
}

do_show() {
    check_root
    if ! load_state; then
        echo -e "${RED}Telemt не установлен (конфигурация не найдена)${NC}"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Telemt MTProxy — Ссылки для подключения${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    echo ""

    while IFS='=' read -r name secret; do
        name=$(echo "$name" | xargs)
        secret=$(echo "$secret" | xargs | tr -d '"')
        if [[ -n "$name" && -n "$secret" ]]; then
            print_user_links "$name" "$secret"
        fi
    done <<< "$USERS_CONFIG"

    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

    local first_name first_secret
    first_name=$(echo "$USERS_CONFIG" | head -1 | cut -d= -f1 | xargs)
    first_secret=$(echo "$USERS_CONFIG" | head -1 | cut -d= -f2 | xargs | tr -d '"')
    if [[ -n "$first_name" && -n "$first_secret" ]]; then
        local host="${PUBLIC_HOST:-$SERVER_IP}"
        local port="${PUBLIC_PORT:-$SERVER_PORT}"
        [[ "$host" == "auto" || -z "$host" ]] && host="$SERVER_IP"
        local link_secret
        link_secret=$(build_link_secret "$first_secret")
        local tme_link="https://t.me/proxy?server=${host}&port=${port}&secret=${link_secret}"
        if install_qrencode; then
            qrencode -t ANSIUTF8 "$tme_link"
            echo ""
        fi
    fi
    exit 0
}

do_update() {
    print_header
    check_root

    if ! load_state; then
        echo -e "${RED}Telemt не установлен. Сначала выполните установку.${NC}"
        exit 1
    fi

    if [[ "$INSTALL_METHOD" == "docker" ]]; then
        local name="${CONTAINER_NAME:-telemt}"
        echo -e "${CYAN}➜ Обновление образа ${TELEMT_IMAGE}...${NC}"
        docker pull "$TELEMT_IMAGE"
        echo -e "${GREEN}✓ Образ обновлён${NC}"

        stop_docker_container "$name"

        echo -e "${CYAN}➜ Перезапуск контейнера...${NC}"

        local docker_args=()
        build_docker_run_args "$name" docker_args

        docker run "${docker_args[@]}" "$TELEMT_IMAGE" config.toml

        if wait_for_container "$name"; then
            verify_connection "$SERVER_PORT"
        fi
    else
        echo -e "${CYAN}➜ Обновление бинарника telemt...${NC}"

        install_setcap

        local arch libc file_name dl_url base_url
        arch=$(detect_arch)
        libc=$(detect_libc)
        file_name="telemt-${arch}-linux-${libc}.tar.gz"

        if [[ "$TELEMT_VERSION" == "latest" ]]; then
            base_url="https://github.com/${TELEMT_REPO}/releases/latest/download"
        else
            base_url="https://github.com/${TELEMT_REPO}/releases/download/${TELEMT_VERSION}"
        fi
        dl_url="${base_url}/${file_name}"

        local tmp_dir
        tmp_dir=$(mktemp -d)

        if ! fetch_file "$dl_url" "${tmp_dir}/${file_name}" 2>/dev/null; then
            if [[ "$arch" == "x86_64-v3" ]]; then
                echo -e "${YELLOW}⚠ Сборка x86_64-v3 не найдена, откат к x86_64...${NC}"
                arch="x86_64"
                file_name="telemt-${arch}-linux-${libc}.tar.gz"
                dl_url="${base_url}/${file_name}"
                fetch_file "$dl_url" "${tmp_dir}/${file_name}"
            else
                echo -e "${RED}Ошибка загрузки${NC}"
                rm -rf "$tmp_dir"
                exit 1
            fi
        fi

        local checksum_file="${file_name}.sha256"
        if fetch_file "${base_url}/${checksum_file}" "${tmp_dir}/${checksum_file}" 2>/dev/null; then
            if ! (cd "$tmp_dir" && sha256sum -c "$checksum_file" &>/dev/null); then
                echo -e "${RED}✗ SHA256 не совпадает!${NC}"
                rm -rf "$tmp_dir"
                exit 1
            fi
            echo -e "${GREEN}✓ SHA256 совпадает${NC}"
        fi

        tar -xzf "${tmp_dir}/${file_name}" -C "$tmp_dir"
        local extracted_bin
        extracted_bin=$(find "$tmp_dir" -type f -name "telemt" -print -quit 2>/dev/null)

        if [[ -z "$extracted_bin" ]]; then
            echo -e "${RED}Бинарник не найден в архиве${NC}"
            rm -rf "$tmp_dir"
            exit 1
        fi

        local svc_mgr
        svc_mgr=$(get_svc_mgr)

        if [[ "$svc_mgr" == "systemd" ]]; then
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        elif [[ "$svc_mgr" == "openrc" ]]; then
            rc-service "$SERVICE_NAME" stop 2>/dev/null || true
        fi

        install -m 0755 "$extracted_bin" "${INSTALL_DIR}/telemt"
        if command -v setcap &>/dev/null; then
            setcap cap_net_bind_service,cap_net_admin=+ep "${INSTALL_DIR}/telemt" 2>/dev/null || true
        fi

        if [[ "$svc_mgr" == "systemd" ]]; then
            systemctl start "$SERVICE_NAME"
        elif [[ "$svc_mgr" == "openrc" ]]; then
            rc-service "$SERVICE_NAME" start
        fi

        rm -rf "$tmp_dir"
        echo -e "${GREEN}✓ Бинарник обновлён и сервис перезапущен${NC}"
        verify_connection "$SERVER_PORT"
    fi

    echo -e "${GREEN}✓ Обновление завершено${NC}"
    exit 0
}

do_uninstall() {
    print_header
    check_root

    local port=""
    if load_state; then
        port="${SERVER_PORT}"
    fi

    echo -e "${YELLOW}➜ Удаление Telemt MTProxy...${NC}"

    if [[ "${INSTALL_METHOD:-docker}" == "docker" ]]; then
        local name="${CONTAINER_NAME:-telemt}"
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$name"; then
            docker rm -f "$name" &>/dev/null || true
            echo -e "${GREEN}✓ Контейнер '${name}' удалён${NC}"
        else
            echo -e "${YELLOW}  Контейнер '${name}' не найден${NC}"
        fi

        if prompt_yes_no "Удалить Docker-образ ${TELEMT_IMAGE}?" "n"; then
            docker rmi "$TELEMT_IMAGE" &>/dev/null || true
            echo -e "${GREEN}✓ Образ удалён${NC}"
        fi
    else
        local svc_mgr
        svc_mgr=$(get_svc_mgr)

        if [[ "$svc_mgr" == "systemd" ]]; then
            systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            systemctl daemon-reload 2>/dev/null || true
            echo -e "${GREEN}✓ Systemd-сервис удалён${NC}"
        elif [[ "$svc_mgr" == "openrc" ]]; then
            rc-service "$SERVICE_NAME" stop 2>/dev/null || true
            rc-update del "$SERVICE_NAME" 2>/dev/null || true
            rm -f "/etc/init.d/${SERVICE_NAME}"
            echo -e "${GREEN}✓ OpenRC-сервис удалён${NC}"
        fi

        rm -f "${INSTALL_DIR}/telemt"
        echo -e "${GREEN}✓ Бинарник удалён${NC}"

        if prompt_yes_no "Удалить пользователя telemt?" "n"; then
            if command -v pkill &>/dev/null; then
                pkill -u telemt 2>/dev/null || true
                sleep 1
                pkill -9 -u telemt 2>/dev/null || true
            fi
            userdel telemt 2>/dev/null || deluser telemt 2>/dev/null || true
            groupdel telemt 2>/dev/null || delgroup telemt 2>/dev/null || true
            echo -e "${GREEN}✓ Пользователь удалён${NC}"
        fi

        if [[ -d "$WORK_DIR" ]]; then
            rm -rf "$WORK_DIR"
            echo -e "${GREEN}✓ Рабочая директория удалена${NC}"
        fi
    fi

    if [[ -n "$port" ]]; then
        close_firewall_port "$port"
    fi

    if prompt_yes_no "Удалить конфигурацию (${CONFIG_DIR})?" "n"; then
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}✓ Конфигурация удалена${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ Telemt MTProxy полностью удалён${NC}"
    exit 0
}

do_edit_config() {
    check_root
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}Конфигурация не найдена: ${CONFIG_FILE}${NC}"
        exit 1
    fi

    local editor="${EDITOR:-nano}"
    if ! command -v "$editor" &>/dev/null; then
        editor="vi"
    fi

    echo -e "${CYAN}Открываю ${CONFIG_FILE} в ${editor}...${NC}"
    "$editor" "$CONFIG_FILE"

    echo ""
    if load_state; then
        if [[ "$INSTALL_METHOD" == "docker" ]]; then
            if prompt_yes_no "Перезапустить контейнер для применения изменений?" "y"; then
                local name="${CONTAINER_NAME:-telemt}"
                docker restart "$name" 2>/dev/null || true
                echo -e "${GREEN}✓ Контейнер перезапущен${NC}"
            fi
        else
            local svc_mgr
            svc_mgr=$(get_svc_mgr)
            if prompt_yes_no "Перезапустить сервис для применения изменений?" "y"; then
                if [[ "$svc_mgr" == "systemd" ]]; then
                    systemctl restart "$SERVICE_NAME"
                elif [[ "$svc_mgr" == "openrc" ]]; then
                    rc-service "$SERVICE_NAME" restart
                fi
                echo -e "${GREEN}✓ Сервис перезапущен${NC}"
            fi
        fi
    fi
    exit 0
}

do_logs() {
    check_root
    if ! load_state; then
        echo -e "${RED}Telemt не установлен${NC}"
        exit 1
    fi

    if [[ "$INSTALL_METHOD" == "docker" ]]; then
        local name="${CONTAINER_NAME:-telemt}"
        echo -e "${BOLD}Логи контейнера '${name}' (Ctrl+C для выхода):${NC}"
        docker logs -f --tail 50 "$name"
    else
        echo -e "${BOLD}Логи сервиса telemt (Ctrl+C для выхода):${NC}"
        if [[ "$(get_svc_mgr)" == "systemd" ]]; then
            journalctl -u "$SERVICE_NAME" -f --no-pager -n 50
        else
            tail -f /var/log/messages 2>/dev/null | grep telemt || echo -e "${YELLOW}Логи не найдены${NC}"
        fi
    fi
    exit 0
}

# ═══════════════════════════════════════════════════════════════
#  Настройка пользователей
# ═══════════════════════════════════════════════════════════════

configure_users() {
    if [[ "$AUTO_MODE" == true ]]; then
        if [[ -z "${USERS_CONFIG:-}" ]]; then
            local secret
            secret=$(generate_secret)
            USERS_CONFIG="user = \"${secret}\""
        fi
        return
    fi

    echo ""
    echo -e "${BOLD}Настройка пользователей прокси:${NC}"
    echo -e "${DIM}  Каждый пользователь получает уникальный секрет (32 hex).${NC}"
    echo -e "${DIM}  Имена используются для идентификации в ссылках/метриках.${NC}"
    echo ""

    local saved_users=""
    if [[ -n "${USERS_CONFIG:-}" ]]; then
        saved_users="$USERS_CONFIG"
        echo -e "${CYAN}Найдены существующие пользователи:${NC}"
        while IFS='=' read -r name secret; do
            name=$(echo "$name" | xargs)
            secret=$(echo "$secret" | xargs | tr -d '"')
            [[ -n "$name" ]] && echo -e "  ${GREEN}${name}${NC} = ${DIM}${secret}${NC}"
        done <<< "$saved_users"
        echo ""
        if prompt_yes_no "Использовать существующих пользователей?" "y"; then
            return
        fi
    fi

    USERS_CONFIG=""
    local adding=true
    local user_num=1

    while [[ "$adding" == true ]]; do
        local default_name="user${user_num}"
        prompt_value user_name "Имя пользователя #${user_num}" "$default_name"

        local secret
        secret=$(generate_secret)
        echo -e "  ${DIM}Сгенерирован секрет: ${secret}${NC}"

        if [[ -n "$USERS_CONFIG" ]]; then
            USERS_CONFIG="${USERS_CONFIG}"$'\n'"${user_name} = \"${secret}\""
        else
            USERS_CONFIG="${user_name} = \"${secret}\""
        fi

        ((user_num++))
        if ! prompt_yes_no "Добавить ещё пользователя?" "n"; then
            adding=false
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
#  Обработка аргументов
# ═══════════════════════════════════════════════════════════════

case "${1:-}" in
    --uninstall|-u)
        do_uninstall ;;
    --update|-U)
        do_update ;;
    --status|-s)
        do_status ;;
    --show)
        do_show ;;
    --edit|-e)
        do_edit_config ;;
    --logs|-l)
        do_logs ;;
    --auto|-a)
        AUTO_MODE=true ;;
    --version|-v)
        echo "telemt-setup v${SCRIPT_VERSION}"
        exit 0
        ;;
    --help|-h)
        echo "Использование: $0 [ОПЦИЯ]"
        echo ""
        echo "  (без опций)         Интерактивная установка / переустановка"
        echo "  --auto, -a          Установка без вопросов (значения по умолч. или env)"
        echo "  --update, -U        Обновить telemt и перезапустить"
        echo "  --uninstall, -u     Удалить telemt (контейнер/бинарник и конфиг)"
        echo "  --status, -s        Показать статус прокси"
        echo "  --show              Показать ссылки для подключения и QR-код"
        echo "  --edit, -e          Открыть config.toml в редакторе"
        echo "  --logs, -l          Просмотр логов в реальном времени"
        echo "  --version, -v       Показать версию скрипта"
        echo "  --help, -h          Показать эту справку"
        echo ""
        echo "Переменные окружения (для --auto):"
        echo "  TM_PRESET           Профиль: recommended|secure|simple|custom"
        echo "  TM_METHOD           Метод установки: docker | binary (по умолч.: docker)"
        echo "  TM_IP               IP сервера (по умолч.: автоопределение)"
        echo "  TM_PORT             Порт прокси (по умолч.: 443)"
        echo "  TM_TLS_DOMAIN       Домен маскировки (по умолч.: apple.com)"
        echo "  TM_MASK_HOST        Хост маскировки mask_host (по умолч.: пусто)"
        echo "  TM_MASK             Включить маскировку: true | false (по умолч.: true)"
        echo "  TM_TLS_EMULATION   TLS-эмуляция: true | false (по умолч.: true)"
        echo "  TM_LOG_LEVEL        Уровень логов: debug|verbose|normal|silent"
        echo "  TM_MODE_CLASSIC     Режим classic: true | false (по умолч.: false)"
        echo "  TM_MODE_SECURE      Режим secure: true | false (по умолч.: false)"
        echo "  TM_MODE_TLS         Режим tls: true | false (по умолч.: true)"
        echo "  TM_METRICS          Включить метрики: true | false (по умолч.: false)"
        echo "  TM_METRICS_PORT     Порт метрик (по умолч.: 9090)"
        echo "  TM_API              Включить API: true | false (по умолч.: true)"
        echo "  TM_API_PORT         Порт API (по умолч.: 9091)"
        echo "  TM_MIDDLE_PROXY     Middle proxy: true | false (по умолч.: true)"
        echo "  TM_IPV6             Слушать IPv6: true | false (по умолч.: false)"
        echo "  TM_AD_TAG           Глобальный ad_tag (32 hex от @MTProxybot)"
        echo "  TM_PROXY_PROTOCOL   PROXY protocol: true | false (по умолч.: false)"
        echo "  TM_CONTAINER        Имя Docker-контейнера (по умолч.: telemt)"
        echo "  TM_PUBLIC_HOST      Хост для ссылок (по умолч.: IP сервера)"
        echo "  TM_PUBLIC_PORT      Порт для ссылок (по умолч.: порт сервера)"
        echo "  TELEMT_VERSION      Версия telemt (по умолч.: latest)"
        exit 0
        ;;
esac

# ═══════════════════════════════════════════════════════════════
#  Основной поток: интерактивная установка
# ═══════════════════════════════════════════════════════════════

print_header
check_root

SERVER_IP=$(detect_ip)

if [[ "$AUTO_MODE" == true ]]; then
    echo -e "${CYAN}Режим автоматической установки (--auto)${NC}"
fi

echo -e "${CYAN}Обнаруженный IP сервера: ${GREEN}${SERVER_IP}${NC}"

if load_state; then
    echo -e "${CYAN}Найдена предыдущая конфигурация (${SETUP_STATE_FILE})${NC}"
fi

echo ""

# ─── Метод установки ──────────────────────────────────────────

prompt_choice INSTALL_METHOD "Метод установки:" "${TM_METHOD:-${INSTALL_METHOD:-docker}}" "docker" "binary"

# ─── Профиль конфигурации ────────────────────────────────────

echo ""
SELECTED_PRESET=""
show_preset_menu

# ─── Основные параметры ──────────────────────────────────────

if [[ "$AUTO_MODE" == false ]]; then
    echo ""
    echo -e "${BOLD}Основные параметры (Enter — значение по умолчанию):${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
fi

prompt_value SERVER_IP     "IP сервера"                    "${TM_IP:-$SERVER_IP}"
prompt_value SERVER_PORT   "Порт прокси"                   "${TM_PORT:-${SERVER_PORT:-443}}"

prompt_value TLS_DOMAIN    "Домен маскировки (tls_domain)"  "${TM_TLS_DOMAIN:-${TLS_DOMAIN:-apple.com}}"
MASK_HOST="${TM_MASK_HOST:-${MASK_HOST:-}}"

# ─── Расширенные настройки (только для ручного режима) ────────

if [[ "$SELECTED_PRESET" == "4" || "$SELECTED_PRESET" == "custom" ]]; then
    echo ""
    echo -e "${BOLD}Маскировка и TLS:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_choice MASK_ENABLED    "Маскировка трафика (forward нераспознанных):" "${TM_MASK:-${MASK_ENABLED:-true}}" "true" "false"
    prompt_choice TLS_EMULATION   "TLS-эмуляция (копия реальных сертификатов):" "${TM_TLS_EMULATION:-${TLS_EMULATION:-true}}" "true" "false"
    prompt_value  MASK_HOST       "Хост маскировки (mask_host, пусто = tls_domain):" "${TM_MASK_HOST:-${MASK_HOST:-}}"

    echo ""
    echo -e "${BOLD}Режимы протокола:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_choice MODE_CLASSIC  "Режим classic (без обфускации):"  "${TM_MODE_CLASSIC:-${MODE_CLASSIC:-false}}" "true" "false"
    prompt_choice MODE_SECURE   "Режим secure (dd-префикс):"      "${TM_MODE_SECURE:-${MODE_SECURE:-false}}"   "true" "false"
    prompt_choice MODE_TLS      "Режим TLS (ee-префикс + SNI):"   "${TM_MODE_TLS:-${MODE_TLS:-true}}"          "true" "false"

    echo ""
    echo -e "${BOLD}Middle Proxy и сеть:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_choice MIDDLE_PROXY    "Использовать Middle Proxy:"       "${TM_MIDDLE_PROXY:-${MIDDLE_PROXY:-true}}"  "true" "false"
    prompt_choice USE_IPV6        "Слушать IPv6:"                     "${TM_IPV6:-${USE_IPV6:-false}}"             "true" "false"
    prompt_choice PROXY_PROTOCOL  "PROXY protocol (HAProxy/nginx):"   "${TM_PROXY_PROTOCOL:-${PROXY_PROTOCOL:-false}}" "true" "false"

    echo ""
    echo -e "${BOLD}Логирование:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_choice LOG_LEVEL  "Уровень логирования:" "${TM_LOG_LEVEL:-${LOG_LEVEL:-normal}}" "normal" "verbose" "debug" "silent"

    echo ""
    echo -e "${BOLD}Метрики (Prometheus):${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_choice METRICS_ENABLED  "Включить метрики:" "${TM_METRICS:-${METRICS_ENABLED:-false}}" "true" "false"
    if [[ "$METRICS_ENABLED" == "true" ]]; then
        prompt_value METRICS_PORT  "Порт метрик" "${TM_METRICS_PORT:-${METRICS_PORT:-9090}}"
    fi

    echo ""
    echo -e "${BOLD}API управления:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_choice API_ENABLED  "Включить API:" "${TM_API:-${API_ENABLED:-true}}" "true" "false"
    if [[ "$API_ENABLED" == "true" ]]; then
        prompt_value API_PORT    "Порт API"              "${TM_API_PORT:-${API_PORT:-9091}}"
        prompt_value API_LISTEN  "Адрес прослушивания API" "${TM_API_LISTEN:-${API_LISTEN:-0.0.0.0}}"
    fi

    echo ""
    echo -e "${BOLD}Рекламные теги:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_value AD_TAG  "Глобальный ad_tag (32 hex от @MTProxybot, пусто = нет):" "${TM_AD_TAG:-${AD_TAG:-}}"

    echo ""
    echo -e "${BOLD}Ссылки:${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    prompt_value PUBLIC_HOST  "Хост для ссылок (IP или домен)" "${TM_PUBLIC_HOST:-${PUBLIC_HOST:-auto}}"
    prompt_value PUBLIC_PORT  "Порт для ссылок"                "${TM_PUBLIC_PORT:-${PUBLIC_PORT:-$SERVER_PORT}}"

    if [[ "$INSTALL_METHOD" == "docker" ]]; then
        prompt_value CONTAINER_NAME  "Имя Docker-контейнера"  "${TM_CONTAINER:-${CONTAINER_NAME:-telemt}}"
    fi
else
    MASK_ENABLED="${MASK_ENABLED:-true}"
    TLS_EMULATION="${TLS_EMULATION:-true}"
    MODE_CLASSIC="${MODE_CLASSIC:-false}"
    MODE_SECURE="${MODE_SECURE:-false}"
    MODE_TLS="${MODE_TLS:-true}"
    MIDDLE_PROXY="${MIDDLE_PROXY:-true}"
    USE_IPV6="${TM_IPV6:-${USE_IPV6:-false}}"
    LOG_LEVEL="${TM_LOG_LEVEL:-${LOG_LEVEL:-normal}}"
    METRICS_ENABLED="${TM_METRICS:-${METRICS_ENABLED:-false}}"
    METRICS_PORT="${TM_METRICS_PORT:-${METRICS_PORT:-9090}}"
    API_ENABLED="${TM_API:-${API_ENABLED:-true}}"
    API_PORT="${TM_API_PORT:-${API_PORT:-9091}}"
    API_LISTEN="${TM_API_LISTEN:-${API_LISTEN:-0.0.0.0}}"
    PUBLIC_HOST="${TM_PUBLIC_HOST:-${PUBLIC_HOST:-auto}}"
    PUBLIC_PORT="${TM_PUBLIC_PORT:-${PUBLIC_PORT:-$SERVER_PORT}}"
    CONTAINER_NAME="${TM_CONTAINER:-${CONTAINER_NAME:-telemt}}"
    FAST_MODE="${TM_FAST_MODE:-${FAST_MODE:-false}}"
    AD_TAG="${TM_AD_TAG:-${AD_TAG:-}}"
    PROXY_PROTOCOL="${TM_PROXY_PROTOCOL:-${PROXY_PROTOCOL:-false}}"
fi

echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

# ─── Проверки ─────────────────────────────────────────────────

check_port_available "$SERVER_PORT"
validate_domain "$TLS_DOMAIN"
if [[ -n "$MASK_HOST" && "$MASK_HOST" != "$TLS_DOMAIN" ]]; then
    validate_domain "$MASK_HOST"
fi

# ─── Пользователи ────────────────────────────────────────────

configure_users

# ─── Обновление системы ──────────────────────────────────────

echo ""
echo -e "${CYAN}➜ Обновление системы...${NC}"
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get upgrade -y -qq 2>/dev/null
elif command -v yum &>/dev/null; then
    yum update -y -q 2>/dev/null
elif command -v dnf &>/dev/null; then
    dnf upgrade -y -q 2>/dev/null
elif command -v apk &>/dev/null; then
    apk update &>/dev/null && apk upgrade &>/dev/null
fi
echo -e "${GREEN}✓ Система обновлена${NC}"

# ─── Установка ────────────────────────────────────────────────

if [[ "$INSTALL_METHOD" == "docker" ]]; then
    run_docker_install
else
    run_binary_install
fi

# ─── Проверка соединения ─────────────────────────────────────

verify_connection "$SERVER_PORT"

# ─── Файрвол ─────────────────────────────────────────────────

open_firewall_port "$SERVER_PORT"

# ─── Сохранение состояния ────────────────────────────────────

save_state
echo -e "${GREEN}✓ Состояние установки сохранено${NC}"

# ─── Результат ────────────────────────────────────────────────

print_result
