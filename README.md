# VPS 自动化运维与部署脚本合集 (vps-scripts)

专为 Linux VPS 服务器打造的高可用、高安全性、全自动化部署与初始化脚本仓库。

---

## 目录
- [Debian 12 全自动装机与安全加固 (`debian.sh`)](#debian-12-全自动装机与安全加固-debiansh)
- [核心特性](#核心特性)
- [安全规则说明](#安全规则说明)
- [鸣谢与上游开源项目](#鸣谢与上游开源项目)

---

## Debian 12 全自动装机与安全加固 (`debian.sh`)

专为 VPS 设计的一键重装并全自动初始化环境。执行完毕后**无需手动 SSH 连接**，等待探针上线即可直接使用。

### 一键执行命令

```bash
curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh | bash -s -- \
  --port <SSH自定义端口> \
  --key "<SSH公钥内容>" \
  --endpoint "<Komari探针地址>" \
  --token "<Komari探针Token>"
```

### 完整示例

```bash
curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh | bash -s -- \
  --port 2222 \
  --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePublicKeyForRootAuth" \
  --endpoint "https://komari.example.com" \
  --token "***"
```

### 参数说明（无默认值，全部必填以保障安全）

| 参数 | 缩写 | 必填 | 说明 | 示例 |
| :--- | :--- | :--- | :--- | :--- |
| `--port` | `-p` | **是** | 自定义 SSH 端口 (1-65535) | `2222` |
| `--key` | `-k` | **是** | root 用户的 SSH 公钥内容 | `"ssh-ed25519 AAAA..."` |
| `--endpoint` | `-e` | **是** | Komari 探针面板地址 | `"https://komari.example.com"` |
| `--token` | `-t` | **是** | Komari 探针机器 Token | `"your_probe_token"` |
| `--help` | `-h` | 否 | 查看帮助与使用文档 | - |

---

## 核心特性

1. **底层重装引擎自主托管**：
   - 核心重装文件已全量内置在仓库 `core/` 目录下，不依赖任何第三方外部仓库，防止上游删库或失效。
2. **基础软件全家桶**：
   - 开机自动预装 `vim`, `curl`, `wget`, `unzip`, `sudo`, `git`, `htop`, `net-tools`, `ca-certificates` 等常用运维工具。
3. **严格安全加固**：
   - **纯密钥登录**：彻底禁用密码登录与键盘交互式认证，修改自定义 SSH 端口。
   - **Fail2ban 智能防爆破**：适配 Debian 12 `systemd-journald` 日志，**错误 3 次直接联动 UFW 封禁 1 天**。
   - **Vodafone 拦截规则**：自动执行 hosts 域名拦截规则，防止滥用。
4. **Docker 与防火墙深度联动**：
   - 自动安装官方最新稳定版 **Docker CE & Docker Compose 插件**。
   - 解决 Docker 绕过 UFW 的安全缺陷：外部仅允许通过 80、443 访问容器，杜绝未授权端口随意暴露。
   - **邮件发信拦截**：自动在 `DOCKER-USER` 链拦截 25, 465, 587, 2525 端口，防止容器被挂马对外滥发垃圾邮件导致 VPS 被封号。
5. **Komari 探针静默接入**：
   - 自动安装并连接 Komari Agent，面板点亮即代表全部环境与安全规则初始化完成。

---

## 安全规则说明

- **入站规则 (Inbound)**：
  - 仅放行：`<自定义SSH端口>/tcp`、`80/tcp`、`443/tcp`。
  - 其他所有宿主机及 Docker 容器映射端口默认全阻断。
- **出站规则 (Outbound)**：
  - 默认允许全部正常出站。
  - 显式阻断 Docker 容器对外 25, 465, 587, 2525 端口的发信请求。

---

## 鸣谢与上游开源项目

本仓库的重装核心与安全规则集成、参考并致谢以下优秀开源项目：

- **重装引擎核心**：感谢 [bin456789/reinstall](https://github.com/bin456789/reinstall) 提供的多架构 Linux/BSD 网络重装底层支持（本项目已在 `core/` 目录完成自主托管与适配）。
- **探针监控**：感谢 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent) 提供的轻量服务器监控 Agent。
- **拦截脚本与规则**：参考了 [noevers/AutoScripts](https://github.com/noevers/AutoScripts) 的网络与域名防护逻辑。
- **Docker 防火墙集成**：参考了 Docker 官方 `DOCKER-USER` iptables 规范与 [chaifeng/ufw-docker](https://github.com/chaifeng/ufw-docker) 的安全隔离思路。
