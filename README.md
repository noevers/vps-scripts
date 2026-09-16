# VPS Scripts 自动化运维与部署脚本合集

专为 VPS 服务器定制的高性能、开箱即用自动化脚本库。

---

## 📜 脚本目录清单

| 脚本名称 | 功能概述 | 适用系统 | 详细介绍 |
| :--- | :--- | :--- | :--- |
| **`debian.sh`** | Debian 12 自动化网络重装 + 安全加固 + Docker + Komari 探针 | Debian / Ubuntu / CentOS 等 | [👉 点击查看详情](#-debiansh---debian-12-自动化网络重装与安全加固) |
| **`nodes.sh`** | 流量共享挂机容器一键管理 (Repocket / TM / EarnFM / PacketStream) | Linux (含 Docker 环境) | [👉 点击查看详情](#-nodessh---流量挂机容器一键管理) |
| **`info.sh`** | 硬件全貌 / 内存频率 / 硬盘 SMART 健康度与读写统计 / YABS 测速 | Linux (通用) | 综合性能及网络测速工具 |

---

## 🚀 脚本详情与使用指南

### 📦 `debian.sh` - Debian 12 自动化网络重装与安全加固

<details open>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

一键将当前服务器网络重装为纯净的 **Debian 12 (Bookworm)**，开机自动完成安全加固、防火墙策略、Docker 环境与 Komari 探针上线。

#### 🌟 核心特性
- **全自动无人值守**：自托管重装引擎，重启后自动完成分区扩容、系统安装与静默初始化。
- **SSH 深度加固**：自定义 SSH 端口，**仅允许密钥认证**，彻底禁用密码登录。
- **探针免操作上线**：完美支持 Komari 探针 **自动发现（Auto Discovery）** 与 **单机 Token** 双模式，探针点亮即代表机器完全就绪。
- **防火墙严格白名单 (UFW)**：
  - **入站**：默认拦截所有端口，仅放行自定义 SSH 端口、`80 (HTTP)`、`443 (HTTPS)`。
  - **Docker 隔离**：原生 `DOCKER-USER` 链防护，严防 Docker 端口映射绕过 UFW 暴露。
  - **防封号出站拦截**：全系统（宿主机 + 容器）阻断垃圾邮件发信（`25/465/587/2525`）、挖矿矿池端口（`3333/4444/5555/7777/9000/14444`）与 SMB/勒索蠕虫端口（`135/139/445`）。
- **暴力破解永久封禁 (Fail2ban)**：失败 3 次直接通过 UFW 永久拉黑 IP（`bantime = -1`），对接 `systemd-journald` 日志源。
- **预装基础全家桶**：`vim`, `curl`, `wget`, `unzip`, `sudo`, `git`, `htop`, `net-tools`，以及官方最新稳定版 **Docker & Docker Compose**。

---

#### 💻 一键运行命令

##### 方式 A：使用「自动发现 Key」（推荐，无需在面板提前添加机器）
```bash
curl -sL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh?t=$(date +%s%N)" | bash -s -- \
  --port <SSH端口> \
  --key "<SSH公钥内容>" \
  --endpoint "<Komari面板地址>" \
  --auto-discovery "<自动发现Key>"
```

##### 方式 B：使用「单机固定 Token」（在面板手动添加机器后获得的 Token）
```bash
curl -sL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh?t=$(date +%s%N)" | bash -s -- \
  --port <SSH端口> \
  --key "<SSH公钥内容>" \
  --endpoint "<Komari面板地址>" \
  --token "***"
```

---

#### 📋 命令行参数详解

| 参数项 | 缩写 | 是否必填 | 参数说明与取值规范 |
| :--- | :--- | :--- | :--- |
| `--port` | `-p` | **必填** | 自定义 SSH 端口（如 `20026`，必须为 1-65535 纯数字） |
| `--key` | `-k` | **必填** | SSH 公钥（以 `ssh-ed25519` 或 `ssh-rsa` 开头，支持带注释） |
| `--endpoint` | `-e` | **必填** | Komari 探针面板地址（以 `http://` 或 `https://` 开头） |
| `--auto-discovery` | `-a` | **二选一** | **Komari 自动发现密钥（推荐）**：在 Komari 面板「设置」中开启自动发现后获取的全局 Key，**安装时面板会自动新建并上架此机器** |
| `--token` | `-t` | **二选一** | **Komari 单机 Token**：在 Komari 面板手动点击「添加节点」后分配给该特定机器的专属 Token |
| `--help` | `-h` | 可选 | 查看脚本帮助文档与完整参数格式 |

---

#### 🛡️ 防火墙进出站安全防护矩阵

| 方向 | 端口 / 协议 | 策略 | 作用与防护说明 |
| :--- | :--- | :--- | :--- |
| **入站** | `自定义 SSH` | ✅ 允许 (ALLOW) | 仅允许密钥登录的管理端口 |
| **入站** | `80 / 443 (TCP)` | ✅ 允许 (ALLOW) | 网站 Web / 证书申请 / 反代流量 |
| **入站** | `其他所有端口` | ❌ 默认拒绝 (DENY) | 宿主机与 Docker 映射端口均受 UFW 白名单严格保护 |
| **出站** | `25, 465, 587, 2525 (TCP)` | 🚫 强制拦截 (DROP/REJECT) | 阻断容器/木马对外发垃圾邮件，防 VPS 商家滥用封机 |
| **出站** | `135, 137, 138, 139, 445` | 🚫 强制拦截 (DROP/REJECT) | 阻断 Windows SMB/NetBIOS 勒索蠕虫向外广播传播 |
| **出站** | `3333, 4444, 5555, 7777, 9000, 14444` | 🚫 强制拦截 (DROP/REJECT) | 阻断被黑后连接主流门罗币等 Stratum 矿池 |


---

#### 🐳 Docker 端口一键安全管理命令 (`docker-port`)

由于系统重装后开启了**深度安全防护**（防止 Docker 容器绕过防火墙私自暴露未授权端口到公网），重装系统已内置专属的 `docker-port` 命令，方便你随时一键安全开放或关闭任意容器端口：

```bash
# 开放指定的 Docker 端口 (支持任意内外端口映射，例如 8065)
docker-port open 8065

# 关闭指定的 Docker 端口并恢复严密防护
docker-port close 8065

# 查看当前已开放的所有自定义 Docker 端口
docker-port list
```

> 💡 **核心优势**：
> - 底层使用 `conntrack --ctorigdstport` 原始目的端口追踪技术，无论是 `-p 8065:8065` 还是 `-p 8065:8045` 都能**一键穿透直通**。
> - 未通过 `docker-port open` 显式放行的其他 Docker 端口（如 Redis 6379 / MySQL 3306）依然被严密阻断，绝无被公网爆破风险。

</details>

---


---

### 🌐 `nodes.sh` - 流量挂机容器一键管理

<details open>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

一键部署和管理多平台流量共享挂机容器（Repocket、TraffMonetizer、EarnFM、PacketStream），内置 IP 智能兼容检测与 Watchtower 自动化更新。

#### 🌟 核心特性
- **纯净参数化调用**：所有服务 Token / API Key **默认为空**，仅在命令行传入对应参数时才启动对应服务，未传参的节点自动跳过。
- **环境自愈检测**：自动检测环境，若未安装 Docker 则全自动拉取安装并启动。
- **干净幂等启动**：每次启动自动检测并清理同名旧容器，避免端口与名称冲突。
- **PacketStream 智能 IP 兼容探测**：启动 `psclient` 后自动等待并检测当前网络 IP 是否被支持。若被机房/数据中心拦截，自动清退卸载 `psclient`，保留其余可用节点。
- **Watchtower 动态关联更新**：仅对本次成功启动运行的挂机容器配置 Watchtower 自动凌晨 03:00 更新，不干扰其他无关容器。

---

#### 💻 一键运行命令

##### 1. 启动所有支持的挂机节点
```bash
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/nodes.sh" | bash -s --   --rp-email "your_email@example.com"   --rp-key "your_repocket_api_key"   --tm-token "your_traffmonetizer_token"   --earnfm-token "your_earnfm_token"   --ps-cid "your_packetstream_cid"
```

##### 2. 仅启动部分节点 (例如仅 TraffMonetizer 与 EarnFM)
```bash
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/nodes.sh" | bash -s --   --tm-token "your_traffmonetizer_token"   --earnfm-token "your_earnfm_token"
```

---

#### 📋 命令行参数详解

| 参数项 | 缩写 | 是否必填 | 参数说明 |
| :--- | :--- | :--- | :--- |
| `--rp-email` | `-m` | 可选 | Repocket 注册账号邮箱 |
| `--rp-key` | `-k` | 可选 | Repocket 用户的 API Key (需与邮箱同时提供) |
| `--tm-token` | `-t` | 可选 | TraffMonetizer 应用 Token |
| `--earnfm-token` | `-e` | 可选 | EarnFM 节点 API Token |
| `--ps-cid` | `-c` | 可选 | PacketStream 用户的 CID (自动检测机房 IP 兼容性) |
| `--help` | `-h` | 可选 | 查看脚本帮助信息与调用示例 |

</details>

---

## 鸣谢与上游开源项目

- **重装引擎核心**：感谢 [bin456789/reinstall](https://github.com/bin456789/reinstall) 提供的底层网络重装支持（本项目已在 `core/` 目录完成自主托管与自建源适配，无删库风险）。
- **探针监控**：感谢 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent) 提供的轻量服务器监控 Agent。
- **安全与防护规则**：参考了 [noevers/AutoScripts](https://github.com/noevers/AutoScripts) 的网络防护逻辑。
