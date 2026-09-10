# Debian 12 自动化网络重装与安全初始化脚本 (Auto Reinstall & Hardening)

专为 VPS / 云服务器设计的 **Debian 12 自动化网络重装与安全加固脚本**。

一键命令启动重装，开机自动完成所有安全策略加固、Docker 与 Komari 探针部署，**全程无需手动登录 SSH**，探针亮起即代表生产环境就绪！

---

## ✨ 核心特性

- **纯净系统**：基于官方源网络重装 Debian 12 (Bookworm)，自动扩容根分区至全盘容量。
- **SSH 深度加固**：
  - 支持自定义 SSH 端口。
  - **彻底禁用密码认证** (`PasswordAuthentication no`)，仅允许 SSH 密钥登录。
- **防火墙与防护**：
  - **UFW 防火墙**：默认拦截所有入站，仅严格放行 `自定义 SSH`、`80 (HTTP)`、`443 (HTTPS)`。
  - **Fail2ban**：适配 Debian 12 `systemd-journald`，**SSH 密码/认证错误 3 次直接联动 UFW 封禁**。
  - **Vodafone 域名拦截**：自动配置 hosts 屏蔽 Vodafone 扫网与滥用域名。
- **Docker 生产级支持与安全**：
  - 官方最新稳定版 **Docker CE** + **Docker Compose Plugin**。
  - **容器邮件发信拦截**：自动注入 `DOCKER-USER` 链，阻断容器向外访问 `25, 465, 587, 2525` 端口，严防木马垃圾邮件导致 VPS 被商家封机 (TOS Abuse)。
  - **Docker 端口防越界**：彻底解决 Docker 自动映射绕过 UFW 的隐患，外部只能访问 80/443。
- **基础软件全家桶**：预装 `vim`, `curl`, `wget`, `unzip`, `sudo`, `git`, `htop`, `net-tools`, `ca-certificates` 等。
- **Komari 探针全自动上线**：无需连接 SSH，机器装完探针自动亮绿灯上线。

---

## 🚀 快速开始

在需要重装的 VPS 终端中，**以 root 身份**运行以下一行命令：

```bash
curl -sL https://raw.githubusercontent.com/noevers/debian-auto-reinstall/main/reinstall-debian.sh | bash -s -- \
  --port 2222 \
  --key "你的SSH公钥 (ssh-ed25519 或 ssh-rsa 开头)" \
  --endpoint "https://komari.example.com" \
  --token "***"
```

> **注意**：脚本运行后服务器会自动重启进行系统安装与初始化，过程通常持续 **2~5 分钟**。安装完成后无需连接 SSH，直接在 Komari 面板查看节点上线即可。

---

## ⚙️ 命令行参数说明

| 参数 | 长参数 | 是否必填 | 默认值 | 说明 |
| :--- | :--- | :---: | :---: | :--- |
| `-p` | `--port` | 否 | `2222` | 设置自定义 SSH 端口 |
| `-k` | `--key` | **是** | 无 | SSH 公钥字符串（如 `ssh-ed25519 AAAA...`） |
| `-e` | `--endpoint` | **是** | 无 | Komari 探针服务端 Web 地址（带 http/https） |
| `-t` | `--token` | **是** | 无 | Komari 探针添加节点时生成的 Token |
| `-h` | `--help` | 否 | 无 | 显示帮助信息与用法示例 |

---

## 🔒 默认开放端口与规则

- **入站规则 (Inbound)**：
  - `自定义 SSH 端口` (TCP)
  - `80` (HTTP)
  - `443` (HTTPS)
  - 其余所有宿主机及 Docker 容器端口默认**全部拦截**。
- **出站规则 (Outbound)**：
  - 允许常规所有出站连接。
  - Docker 容器禁止访问外部 `25, 465, 587, 2525` 邮件端口。

---

## 📄 开源协议

MIT License.
