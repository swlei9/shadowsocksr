#!/usr/bin/env bash
set -Eeuo pipefail

readonly PACKAGE_SHA256="fe06f12ec7207709a65f245c2250a8a2ede8e3ac6462a69248c58bd38d42571f"
readonly -a PACKAGE_URLS=(
    "https://raw.githubusercontent.com/swlei9/shadowsocksr/manyuser/ssr-offline-installer.tar.gz"
    "https://cdn.jsdelivr.net/gh/swlei9/shadowsocksr@manyuser/ssr-offline-installer.tar.gz"
)

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
DOWNLOAD_OK=false
for PACKAGE_URL in "${PACKAGE_URLS[@]}"; do
    if curl --proto '=https' --tlsv1.2 -fL \
        --connect-timeout 10 --retry 2 "${PACKAGE_URL}" -o "${PACKAGE_FILE}"; then
        ACTUAL_SHA256=$(sha256sum "${PACKAGE_FILE}" | awk '{print $1}')
        if [[ ${ACTUAL_SHA256} == "${PACKAGE_SHA256}" ]]; then
            DOWNLOAD_OK=true
            break
        fi
        echo "[警告] 下载文件校验失败，正在尝试其他地址：${PACKAGE_URL}" >&2
        continue
    fi
    echo "[警告] 下载失败，正在尝试其他地址：${PACKAGE_URL}" >&2
done
[[ ${DOWNLOAD_OK} == true ]] || fail "所有安装包下载地址均不可用。"

tar -xzf "${PACKAGE_FILE}" -C "${TEMP_DIR}"
[[ -f "${TEMP_DIR}/ssr-offline-installer/install.sh" ]] || fail "安装包结构错误。"

bash "${TEMP_DIR}/ssr-offline-installer/install.sh"
