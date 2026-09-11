#!/usr/bin/env bash
set -Eeuo pipefail

readonly PACKAGE_URL="https://raw.githubusercontent.com/swlei9/shadowsocksr/manyuser/ssr-offline-installer.tar.gz"
readonly PACKAGE_SHA256="6ee4c6b0668325d006aff567ce663d2702d09c8f5faa439527aea351b79e5033"

fail() {
    echo "[错误] $*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || fail "请使用 root 用户执行。"
command -v curl >/dev/null 2>&1 || fail "缺少 curl，请先安装：apt-get update && apt-get install -y curl ca-certificates"
command -v sha256sum >/dev/null 2>&1 || fail "缺少 sha256sum。"

TEMP_DIR=$(mktemp -d)
case "${TEMP_DIR}" in
    /tmp/*) ;;
    *) fail "临时目录路径异常：${TEMP_DIR}" ;;
esac

cleanup() {
    find "${TEMP_DIR}" -mindepth 1 -delete 2>/dev/null || true
    rmdir "${TEMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

PACKAGE_FILE="${TEMP_DIR}/ssr-offline-installer.tar.gz"
echo "[信息] 正在下载安装包……"
curl --proto '=https' --tlsv1.2 -fL "${PACKAGE_URL}" -o "${PACKAGE_FILE}"

ACTUAL_SHA256=$(sha256sum "${PACKAGE_FILE}" | awk '{print $1}')
[[ ${ACTUAL_SHA256} == "${PACKAGE_SHA256}" ]] || fail "安装包校验失败，已停止安装。"

tar -xzf "${PACKAGE_FILE}" -C "${TEMP_DIR}"
[[ -f "${TEMP_DIR}/ssr-offline-installer/install.sh" ]] || fail "安装包结构错误。"

bash "${TEMP_DIR}/ssr-offline-installer/install.sh"
