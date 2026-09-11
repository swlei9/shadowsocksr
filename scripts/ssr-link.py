#!/usr/bin/env python3
"""Generate an SSR URI from the installed server configuration."""

import argparse
import base64
import json
from pathlib import Path


DEFAULT_CONFIG = Path("/etc/shadowsocks-r/config.json")
DEFAULT_ADDRESS = Path("/etc/shadowsocks-r/client-address")


def base64_url(value):
    if not isinstance(value, str):
        value = str(value)
    return base64.urlsafe_b64encode(value.encode("utf-8")).decode("ascii").rstrip("=")


def load_address(argument):
    if argument:
        return argument.strip()
    if not DEFAULT_ADDRESS.is_file():
        raise SystemExit("未保存客户端连接地址，请执行：ssr-link 公网IP或域名")
    return DEFAULT_ADDRESS.read_text(encoding="utf-8").strip()


def main():
    parser = argparse.ArgumentParser(description="生成当前 SSR 配置的 ssr:// 链接")
    parser.add_argument("address", nargs="?", help="服务器公网 IPv4 或域名")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG), help="SSR JSON 配置文件")
    args = parser.parse_args()

    address = load_address(args.address)
    if not address or any(character in address for character in ":/ \t\r\n"):
        raise SystemExit("连接地址格式错误：请填写公网 IPv4 或域名，不要包含协议、端口或路径")

    with open(args.config, "r", encoding="utf-8") as config_file:
        config = json.load(config_file)

    required = ("server_port", "password", "method", "protocol", "obfs")
    missing = [name for name in required if name not in config]
    if missing:
        raise SystemExit("配置缺少字段：" + ", ".join(missing))

    password = base64_url(config["password"])
    protocol_param = base64_url(config.get("protocol_param", ""))
    obfs_param = base64_url(config.get("obfs_param", ""))
    remarks = base64_url("SSR-" + address)

    plain = (
        f"{address}:{int(config['server_port'])}:{config['protocol']}:"
        f"{config['method']}:{config['obfs']}:{password}/?"
        f"obfsparam={obfs_param}&protoparam={protocol_param}&remarks={remarks}"
    )
    print("ssr://" + base64_url(plain))


if __name__ == "__main__":
    main()
