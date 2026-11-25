# SSR 3.2.2 一键安装包

这是从秋水逸冰（Teddysun）老版 `shadowsocks-all.sh` 部署出的 SSR 3.2.2
程序整理而成的可重复安装包，适用于 Debian 12，也兼容使用 `apt` 和 `systemd`
的 Debian/Ubuntu 系统。

程序源码已包含在包内；安装系统依赖时仍需能够访问 Debian/Ubuntu 软件源。

## 默认参数

- 加密：`chacha20-ietf`
- 协议：`auth_sha1_v4`
- 混淆：`plain`
- 端口：默认 `443`，安装时可以修改
- 安装时可选择加密方式和协议，直接回车使用默认值
- UDP：默认关闭，安装时可以开启

安装脚本内置的加密方式选项：

```text
chacha20-ietf, chacha20, aes-256-cfb, aes-128-cfb, aes-256-ctr, aes-128-ctr, salsa20
```

安装脚本内置的协议选项：

```text
auth_sha1_v4, auth_aes128_md5, auth_aes128_sha1, auth_chain_a, auth_chain_b, origin
```

## 安装

### 在线一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/swlei9/shadowsocksr/manyuser/install-online.sh)
```

如果新系统没有 `curl`，先执行：

```bash
apt-get update && apt-get install -y curl ca-certificates
```

### 下载压缩包安装

上传压缩包到新服务器并以 root 身份执行：

```bash
tar -xzf ssr-offline-installer.tar.gz
cd ssr-offline-installer
bash install.sh
```

SSR 服务始终监听 `0.0.0.0`（所有 IPv4 网卡），不需要把公网 IP 写进服务配置。
安装脚本会自动检测公网 IPv4，仅用于生成客户端 `ssr://` 链接；只有检测失败时，
才会要求手动填写公网 IPv4 或域名。脚本还会询问端口、加密方式、协议、密码及
是否开启 UDP。密码输入时明文显示，留空时会自动生成；安装完成后也会显示密码。

安装成功后会自动输出完整的 `ssr://` 链接，可以直接复制到支持 SSR 链接导入的客户端。

## 常用命令

安装完成后，以 root 身份运行以下命令打开管理菜单：

```bash
ssr
```

菜单支持查看配置、明文密码和 SSR 链接，修改端口、修改密码，重启、启动、停止服务，
以及查看服务状态和最近日志。修改端口或密码后会自动重启并输出新的 SSR 链接；
配置备份保存在 `/etc/shadowsocks-r/config.json.bak`（每次修改覆盖上一次备份）。
重启失败时会恢复原配置及原来的服务启停状态。输入不合法时会提示并返回菜单。
密码规则与安装时一致：12-64 位字母、数字、点、下划线或连字符。
修改端口后需放行云安全组和服务器防火墙的新端口，并同步更新客户端。

已经安装旧版的服务器，可以从新版解压目录单独安装管理命令，无需重新安装服务：

```bash
install -o root -g root -m 0755 scripts/ssr.py /usr/local/bin/ssr
ssr
```

也可以继续使用以下命令：

```bash
systemctl status shadowsocks-r --no-pager
systemctl restart shadowsocks-r
systemctl stop shadowsocks-r
journalctl -u shadowsocks-r -n 50 --no-pager
ss -lntup | grep ':443'
ssr-link
```

如果安装时选择了其他端口，请把端口检查命令中的 `443` 替换为实际端口。

配置文件位于：

```text
/etc/shadowsocks-r/config.json
```

修改 JSON 并重启服务后，执行以下命令即可重新生成链接：

```bash
python3 -m json.tool /etc/shadowsocks-r/config.json >/dev/null
systemctl restart shadowsocks-r
ssr-link
```

如果服务器公网 IP 或域名发生变化，可以临时指定新地址：

```bash
ssr-link 新公网IP或新域名
```

`ssr://` 链接中包含经过编码但未加密的密码。不要把链接发到公开群聊、网页或公开仓库。

配置文件权限为 `0640`，只有 root 和专用 `ssr` 服务账户可以读取。

## 安全说明

- 安装包不包含任何真实服务器密码或历史配置。
- 已修复 Python 3.10+ 中 `collections.MutableMapping` 的兼容问题。
- 已移除启动日志中的密码明文输出。
- 安装完成后自动生成标准 `ssr://` 客户端链接。
- SSR 使用独立的低权限 `ssr` 账户运行。
- 默认关闭 UDP。仅确实需要时才同时开放 UDP 端口。
- 不要把带有真实密码的配置文件提交到 Git 仓库。
- SSR 3.2.2 是停止维护的旧软件，仅建议用于兼容已有客户端。
- 安装脚本不会自动修改防火墙；请在云服务商控制台只放行实际使用的端口。

## 备份

重复执行安装脚本时，如检测到旧程序、配置或服务文件，会先备份到：

```text
/root/shadowsocks-r-backup-日期时间/
```

## 来源与修改

原始程序：ShadowsocksR SSRR 3.2.2（2018-05-22）。

为现代系统加入了以下修改：

1. Python 3.10+ `collections.abc.MutableMapping` 兼容修复；
2. 修复旧代码的 Python `is` 字面量比较警告；
3. 启动日志对密码进行脱敏；
4. 新增 `udp_enabled` 配置，默认不启动 UDP 转发；
5. 安装时可选择 SSR 加密方式和协议；
6. 使用 systemd 和低权限服务账户运行。
