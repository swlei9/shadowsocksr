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
- UDP：默认关闭，安装时可以开启

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

SSR 服务同时监听 `0.0.0.0`（所有 IPv4 网卡）和 `::`（所有 IPv6 网卡），不需要
把公网 IP 写进服务配置。安装脚本会先检测公网 IPv4；没有公网 IPv4 时自动检测并
使用公网 IPv6，同时开启 IPv6 DNS 解析。两者都检测失败时，才会要求手动填写
公网 IPv4、IPv6 或域名。脚本还会询问端口、密码及是否开启 UDP，密码留空时会
自动生成。

安装成功后会自动输出完整的 `ssr://` 链接，可以直接复制到支持 SSR 链接导入的客户端。

### 纯 IPv6 VPS

纯 IPv6 VPS 可以使用同一条安装命令。请先确认系统能够通过 IPv6 访问软件源，
以及 GitHub Raw 或下方的备用 CDN。脚本会自动识别纯 IPv6 网络并生成使用
`[IPv6]:端口` 格式的标准 SSR 链接。考虑到部分旧客户端不能正确解析 IPv6
字面量，更推荐给 VPS 配置一个 AAAA 域名，然后执行 `ssr-link 你的域名` 生成
兼容性更好的链接。

如果纯 IPv6 网络无法访问 `raw.githubusercontent.com`，可以通过备用 CDN 启动：

```bash
bash <(curl -6 -fsSL https://cdn.jsdelivr.net/gh/swlei9/shadowsocksr@manyuser/install-online.sh)
```

入口脚本下载离线包时也会自动在 GitHub Raw 和备用 CDN 之间切换。

## 常用命令

```bash
systemctl status shadowsocks-r --no-pager
systemctl restart shadowsocks-r
systemctl stop shadowsocks-r
journalctl -u shadowsocks-r -n 50 --no-pager
ss -lntup | grep ':443'
ssr-link
```

如果安装时选择了其他端口，请把最后一条命令中的 `443` 替换为实际端口。

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
ssr-link 新公网IPv4或新公网IPv6或新域名
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
5. 使用 systemd 和低权限服务账户运行。
