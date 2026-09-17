#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_DIR="/usr/local/shadowsocks"
readonly CONFIG_DIR="/etc/shadowsocks-r"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly ADDRESS_FILE="${CONFIG_DIR}/client-address"
readonly SERVICE_FILE="/etc/systemd/system/shadowsocks-r.service"
readonly SERVICE_NAME="shadowsocks-r"
readonly SERVICE_USER="ssr"
readonly PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PAYLOAD="${PACKAGE_DIR}/payload/shadowsocksr-3.2.2-py3.tar.gz"
readonly PAYLOAD_SHA256="8e59b55336281d53b0b3bb7265b175da6be0f80285ae53f4c52f4dce83fc4baf"
readonly UNIT_SOURCE="${PACKAGE_DIR}/systemd/shadowsocks-r.service"
readonly LINK_SOURCE="${PACKAGE_DIR}/scripts/ssr-link.py"

fail() {
    echo "[错误] $*" >&2
    exit 1
}

info() {
    echo "[信息] $*"
}

is_ipv4() {
    local candidate=$1
    local octet
    local -a octets
    [[ ${candidate} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "${candidate}"
    for octet in "${octets[@]}"; do
        (( 10#${octet} <= 255 )) || return 1
    done
}

is_ipv6() {
    python3 - "${1}" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if address.version == 6 else 1)
PY
}

normalize_client_address() {
    python3 - "${1}" <<'PY'
import ipaddress
import re
import sys

address = sys.argv[1].strip()
if address.startswith("[") and address.endswith("]"):
    address = address[1:-1]

try:
    print(ipaddress.ip_address(address).compressed)
    raise SystemExit(0)
except ValueError:
    pass

address = address.rstrip(".").lower()
if len(address) > 253 or not address or address.replace(".", "").isdigit():
    raise SystemExit(1)
labels = address.split(".")
if any(
    not label
    or len(label) > 63
    or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label)
    for label in labels
):
    raise SystemExit(1)
print(address)
PY
}

detect_public_ipv4() {
    local endpoint
    local candidate
    for endpoint in \
        "https://api.ipify.org" \
        "https://ipv4.icanhazip.com" \
        "https://ifconfig.me/ip"; do
        candidate=$(curl -4 -fsS --connect-timeout 4 --max-time 8 "${endpoint}" 2>/dev/null | tr -d '[:space:]') || true
        if is_ipv4 "${candidate}"; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

detect_public_ipv6() {
    local endpoint
    local candidate
    for endpoint in \
        "https://api6.ipify.org" \
        "https://ipv6.icanhazip.com" \
        "https://ifconfig.co/ip"; do
        candidate=$(curl -6 -fsS --connect-timeout 4 --max-time 8 "${endpoint}" 2>/dev/null | tr -d '[:space:]') || true
        if is_ipv6 "${candidate}"; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

[[ ${EUID} -eq 0 ]] || fail "请使用 root 用户执行此脚本。"
[[ -f /etc/os-release ]] || fail "无法识别操作系统。"

# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
    debian|ubuntu) ;;
    *) fail "当前只支持 Debian/Ubuntu，检测到：${ID:-unknown}" ;;
esac

command -v apt-get >/dev/null 2>&1 || fail "没有找到 apt-get。"
command -v systemctl >/dev/null 2>&1 || fail "当前系统没有 systemd/systemctl。"
[[ -d /run/systemd/system ]] || fail "当前环境未运行 systemd，不能注册 SSR 服务。"
[[ -f "${PAYLOAD}" ]] || fail "缺少程序包：${PAYLOAD}"
[[ -f "${UNIT_SOURCE}" ]] || fail "缺少 systemd 服务文件：${UNIT_SOURCE}"
[[ -f "${LINK_SOURCE}" ]] || fail "缺少 SSR 链接生成程序：${LINK_SOURCE}"

ACTUAL_SHA256=$(sha256sum "${PAYLOAD}" | awk '{print $1}')
[[ ${ACTUAL_SHA256} == "${PAYLOAD_SHA256}" ]] || fail "程序包校验失败，文件可能损坏或被修改。"

info "安装 Python 3 和 libsodium 依赖……"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 libsodium23 openssl ca-certificates iproute2 curl

read -r -p "SSR 端口 [443]: " SSR_PORT
SSR_PORT=${SSR_PORT:-443}
[[ ${SSR_PORT} =~ ^[0-9]+$ ]] || fail "端口只能填写数字。"
(( SSR_PORT >= 1 && SSR_PORT <= 65535 )) || fail "端口范围必须是 1-65535。"

PUBLIC_IPV4=$(detect_public_ipv4 || true)
PUBLIC_IPV6=$(detect_public_ipv6 || true)

if [[ -n ${PUBLIC_IPV4} ]]; then
    SSR_ADDRESS=${PUBLIC_IPV4}
    DNS_IPV6=false
    info "用于生成客户端链接的公网 IPv4：${SSR_ADDRESS}"
elif [[ -n ${PUBLIC_IPV6} ]]; then
    SSR_ADDRESS=${PUBLIC_IPV6}
    DNS_IPV6=true
    info "未检测到公网 IPv4，已切换为纯 IPv6 模式。"
    info "用于生成客户端链接的公网 IPv6：${SSR_ADDRESS}"
else
    DNS_IPV6=false
    read -r -p "未能自动检测公网地址，请填写服务器公网 IPv4、IPv6 或域名: " SSR_ADDRESS
fi

SSR_ADDRESS=$(normalize_client_address "${SSR_ADDRESS}") || \
    fail "连接地址格式错误，请填写 IPv4、IPv6 或域名，不要包含协议、端口或路径。"

if [[ -z ${PUBLIC_IPV4} ]] && {
    [[ -n ${PUBLIC_IPV6} ]] \
        || is_ipv6 "${SSR_ADDRESS}" \
        || { ! ip -4 route get 1.1.1.1 >/dev/null 2>&1 \
             && ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1; }
}; then
    DNS_IPV6=true
fi

read -r -s -p "SSR 密码（留空则自动生成）: " SSR_PASSWORD
echo
if [[ -z ${SSR_PASSWORD} ]]; then
    SSR_PASSWORD=$(openssl rand -hex 16)
    GENERATED_PASSWORD=true
else
    GENERATED_PASSWORD=false
fi

[[ ${SSR_PASSWORD} =~ ^[A-Za-z0-9._-]{12,64}$ ]] || \
    fail "密码必须为 12-64 位，只能包含字母、数字、点、下划线和连字符。"

read -r -p "启用 UDP 转发？[y/N]: " UDP_ANSWER
case "${UDP_ANSWER:-n}" in
    y|Y) UDP_ENABLED=true ;;
    *) UDP_ENABLED=false ;;
esac

umask 077
BACKUP_DIR="/root/shadowsocks-r-backup-$(date +%Y%m%d-%H%M%S)"
if [[ -d ${INSTALL_DIR} || -f ${CONFIG_FILE} || -f ${SERVICE_FILE} ]]; then
    install -d -m 0700 "${BACKUP_DIR}"
    [[ ! -d ${INSTALL_DIR} ]] || cp -a "${INSTALL_DIR}" "${BACKUP_DIR}/program"
    [[ ! -f ${CONFIG_FILE} ]] || cp -a "${CONFIG_FILE}" "${BACKUP_DIR}/config.json"
    [[ ! -f ${ADDRESS_FILE} ]] || cp -a "${ADDRESS_FILE}" "${BACKUP_DIR}/client-address"
    [[ ! -f ${SERVICE_FILE} ]] || cp -a "${SERVICE_FILE}" "${BACKUP_DIR}/shadowsocks-r.service"
    info "旧文件已备份到 ${BACKUP_DIR}"
fi

if systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1; then
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
fi

if ss -H -ltn "sport = :${SSR_PORT}" | grep -q .; then
    fail "TCP 端口 ${SSR_PORT} 已被其他程序占用。"
fi

if ! getent group "${SERVICE_USER}" >/dev/null; then
    groupadd --system "${SERVICE_USER}"
fi
if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
    useradd --system --gid "${SERVICE_USER}" --home-dir /nonexistent \
        --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

TEMP_DIR=$(mktemp -d)
cleanup() {
    find "${TEMP_DIR}" -mindepth 1 -delete 2>/dev/null || true
    rmdir "${TEMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

tar -xzf "${PAYLOAD}" -C "${TEMP_DIR}"
[[ -f "${TEMP_DIR}/shadowsocks/server.py" ]] || fail "程序包结构不正确。"

install -d -o root -g root -m 0755 "${INSTALL_DIR}"
cp -a "${TEMP_DIR}/shadowsocks/." "${INSTALL_DIR}/"
find "${INSTALL_DIR}" -type f -name '*.pyc' -delete
chown -R root:root "${INSTALL_DIR}"
chmod -R a+rX "${INSTALL_DIR}"

install -d -o root -g "${SERVICE_USER}" -m 0750 "${CONFIG_DIR}"
printf '%s\n' \
    '{' \
    '    "server": "0.0.0.0",' \
    '    "server_ipv6": "::",' \
    "    \"server_port\": ${SSR_PORT}," \
    '    "local_address": "127.0.0.1",' \
    '    "local_port": 1080,' \
    "    \"password\": \"${SSR_PASSWORD}\"," \
    '    "timeout": 120,' \
    '    "method": "chacha20-ietf",' \
    '    "protocol": "auth_sha1_v4",' \
    '    "protocol_param": "",' \
    '    "obfs": "plain",' \
    '    "obfs_param": "",' \
    '    "redirect": "",' \
    "    \"dns_ipv6\": ${DNS_IPV6}," \
    '    "fast_open": false,' \
    "    \"udp_enabled\": ${UDP_ENABLED}," \
    '    "workers": 1' \
    '}' > "${CONFIG_FILE}"
chown root:"${SERVICE_USER}" "${CONFIG_FILE}"
chmod 0640 "${CONFIG_FILE}"
printf '%s\n' "${SSR_ADDRESS}" > "${ADDRESS_FILE}"
chown root:"${SERVICE_USER}" "${ADDRESS_FILE}"
chmod 0640 "${ADDRESS_FILE}"

python3 -m json.tool "${CONFIG_FILE}" >/dev/null
python3 "${INSTALL_DIR}/server.py" -h >/dev/null
install -o root -g root -m 0644 "${UNIT_SOURCE}" "${SERVICE_FILE}"
install -o root -g root -m 0755 "${LINK_SOURCE}" /usr/local/bin/ssr-link

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"
sleep 1

if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    journalctl -u "${SERVICE_NAME}" -n 50 --no-pager >&2 || true
    fail "SSR 启动失败。"
fi

info "SSR 安装成功。"
echo "服务状态：$(systemctl is-active "${SERVICE_NAME}")"
echo "服务监听：0.0.0.0:${SSR_PORT}（所有 IPv4 网卡）"
echo "服务监听：[::]:${SSR_PORT}（所有 IPv6 网卡）"
echo "客户端链接地址：${SSR_ADDRESS}（仅用于生成链接）"
echo "端口：${SSR_PORT}"
echo "加密：chacha20-ietf"
echo "协议：auth_sha1_v4"
echo "混淆：plain"
echo "UDP：${UDP_ENABLED}"
if [[ ${GENERATED_PASSWORD} == true ]]; then
    echo "自动生成的密码：${SSR_PASSWORD}"
    echo "请立即保存该密码；配置文件不会向其他用户开放。"
else
    echo "密码：使用你刚才输入的密码（此处不回显）"
fi
echo "SSR 链接："
/usr/local/bin/ssr-link
echo
echo "请仅在云服务商防火墙中放行 TCP ${SSR_PORT}；只有启用 UDP 时才放行 UDP ${SSR_PORT}。"
