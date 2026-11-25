#!/usr/bin/env python3
"""Local management menu for the installed ShadowsocksR service."""

import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
import time


CONFIG = Path("/etc/shadowsocks-r/config.json")
SERVICE = "shadowsocks-r"
LINK = "/usr/local/bin/ssr-link"


def run(*args, check=True, capture=False):
    return subprocess.run(args, check=check, text=True, capture_output=capture)


def load_config():
    with CONFIG.open(encoding="utf-8") as stream:
        config = json.load(stream)
    if not isinstance(config, dict):
        raise ValueError("配置必须是 JSON 对象。")
    return config


def active():
    return run("systemctl", "is-active", "--quiet", SERVICE, check=False).returncode == 0


def service_action(action):
    run("systemctl", action, SERVICE)
    if action in ("start", "restart"):
        time.sleep(1)
        if not active():
            raise RuntimeError("服务启动失败，请通过菜单查看日志。")
    print("操作成功。")


def atomic_write(data, metadata, destination=None):
    # Replace within the same directory and retain root:ssr ownership and mode.
    destination = CONFIG if destination is None else destination
    fd, name = tempfile.mkstemp(prefix=".config-", dir=destination.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fchown(stream.fileno(), metadata.st_uid, metadata.st_gid)
            os.fchmod(stream.fileno(), stat.S_IMODE(metadata.st_mode))
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def update_config(field, value):
    config = load_config()
    if config.get(field) == value:
        print("配置未变化。")
        return False
    metadata = CONFIG.stat()
    original = CONFIG.read_bytes()
    was_active = active()
    # Keep a persistent backup; the directory and file retain existing permissions.
    backup = CONFIG.with_name("config.json.bak")
    atomic_write(original, metadata, backup)
    config[field] = value
    atomic_write((json.dumps(config, ensure_ascii=False, indent=4) + "\n").encode("utf-8"), metadata)
    try:
        service_action("restart")
    except (OSError, subprocess.CalledProcessError, RuntimeError, KeyboardInterrupt):
        atomic_write(original, metadata)
        print("应用失败，已恢复原配置。")
        # Restore both configuration and the previous running/stopped state.
        try:
            service_action("restart" if was_active else "stop")
        except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
            print("恢复服务状态失败，请查看日志：", error)
        raise
    print("配置已更新，备份：", backup)
    return True


def show_link():
    run(LINK)


def show_config():
    config = load_config()
    print("服务状态：", "运行中" if active() else "未运行")
    for label, key in (("端口", "server_port"), ("密码", "password"),
                       ("加密", "method"), ("协议", "protocol"),
                       ("混淆", "obfs"), ("UDP", "udp_enabled")):
        print(f"{label}：{config.get(key, '')}")
    show_link()


def change_port():
    config = load_config()
    answer = input(f"新端口 [当前 {config['server_port']}，回车取消]: ").strip()
    if not answer:
        return
    if not re.fullmatch(r"[0-9]{1,5}", answer) or not 1 <= int(answer) <= 65535:
        raise ValueError("端口必须是 1-65535 的整数。")
    port = int(answer)
    if port != int(config["server_port"]):
        protocols = ["-ltn"]
        if config.get("udp_enabled", False):
            protocols.append("-lun")
        for protocol in protocols:
            result = run("ss", "-H", protocol, f"sport = :{port}", capture=True)
            if result.stdout.strip():
                raise ValueError(f"端口 {port} 已被占用（{protocol}），请选择其他端口。")
    if update_config("server_port", port):
        print(f"请在云安全组及服务器防火墙放行 TCP {port}。")
        if config.get("udp_enabled", False):
            print(f"同时放行 UDP {port}。")
        print("请更新客户端端口，确认连接后可关闭旧端口的防火墙规则。")
        show_link()


def change_password():
    answer = input("新密码（明文显示，留空自动生成）: ")
    password = answer or secrets.token_hex(16)
    if not re.fullmatch(r"[A-Za-z0-9._-]{12,64}", password):
        raise ValueError("密码须为 12-64 位，只能包含字母、数字、点、下划线和连字符。")
    if update_config("password", password):
        print("密码：", password)
        print("请同步更新客户端密码。")
        show_link()


def menu():
    actions = {
        "1": show_config,
        "2": change_port,
        "3": change_password,
        "4": lambda: service_action("restart"),
        "5": lambda: service_action("start"),
        "6": lambda: service_action("stop"),
        "7": lambda: run("systemctl", "status", SERVICE, "--no-pager", check=False),
        "8": lambda: run("journalctl", "-u", SERVICE, "-n", "50", "--no-pager"),
    }
    while True:
        print("\nSSR 管理菜单\n"
              "  1) 查看配置、明文密码及 SSR 链接\n"
              "  2) 修改端口\n"
              "  3) 修改密码\n"
              "  4) 重启服务\n"
              "  5) 启动服务\n"
              "  6) 停止服务\n"
              "  7) 查看服务状态\n"
              "  8) 查看最近日志\n"
              "  0) 退出")
        try:
            choice = input("请选择 [0-8]: ").strip()
            if choice == "0":
                return
            action = actions.get(choice)
            if action is None:
                print("请输入 0-8。")
                continue
            action()
        except EOFError:
            return
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError, RuntimeError) as error:
            print("[错误]", error)


def main():
    if os.geteuid() != 0:
        raise SystemExit("请使用 root 执行：sudo ssr")
    if not CONFIG.is_file():
        raise SystemExit("未找到 SSR 配置，请先运行安装脚本。")
    if not shutil.which("systemctl"):
        raise SystemExit("未找到 systemctl，此管理工具需要 systemd。")
    try:
        menu()
    except (EOFError, KeyboardInterrupt):
        print("\n已退出。")


if __name__ == "__main__":
    main()
