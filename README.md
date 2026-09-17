# VPS Scripts 自动化运维与部署脚本合集

专为 VPS 服务器定制的高性能、开箱即用自动化脚本库。

---

## 📜 脚本目录清单

| 脚本名称 | 功能概述 | 适用系统 | 详细介绍 |
| :--- | :--- | :--- | :--- |
| **`init.sh`** | **原生系统一键初始化加固**（改 SSH 端口/仅公钥、UFW 防封号防火墙、Docker 环境、BBR 调优、可选挂机） | Debian 11/12+, Ubuntu 20.04/22.04+ 等 | [👉 查看详情](#-initsh---原生系统一键初始化加固与-docker-部署) |
| **`debian.sh`** | **纯净版**：Debian 12 自动化网络重装 + 安全加固 + Komari 探针 | Debian / Ubuntu / CentOS 等 | [👉 点击查看详情](#-debiansh---debian-12-自动化网络重装纯净版) |
| **`debian-nodes.sh`** | **挂机版**：Debian 12 重装 + 安全加固 + 自动部署多平台流量挂机 | Debian / Ubuntu / CentOS 等 | [👉 点击查看详情](#-debian-nodessh---debian-12-网络重装--流量挂机集成版) |
| **`nodes.sh`** | **独立挂机**：TraffMonetizer / EarnFM / Repocket / PacketStream 节点管理 | Debian / Ubuntu (已装 Docker) | [👉 点击查看详情](#-nodessh---多平台流量共享挂机管理脚本) |
| **`tune.sh`** | **节点优化**：BBR+FQ / 百万文件句柄 / TCP与UDP(QUIC)缓冲区吞吐调优 | Linux (推荐 Debian 12 / Ubuntu) | [👉 点击查看详情](#-tunesh---debian-12-代理节点与高并发网络优化) |
| **`info.sh`** | 硬件配置、内存频率、硬盘 SMART 健康度/读写量、YABS 双栈测速 | Linux (支持常见发行版与救援模式) | [👉 点击查看详情](#-infosh---系统硬件配置与网络全景检测) |

---

## 🚀 脚本详情与使用指南

### 🛡️ `init.sh` - 原生系统一键初始化加固与 Docker 部署

<details open>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

适用于**已有的干净 Linux 系统（Debian / Ubuntu 等）**，无需全盘网络重装，一键完成全套生产级安全加固、Docker 环境就绪与网络优化。

#### 💡 核心特性
1. **SSH 深度加固**：一键自定义 SSH 端口，强制仅允许公钥认证（`PasswordAuthentication no`），彻底杜绝密码爆破；
2. **生产级防御体系**：自动安装并配置 `Fail2ban`（3 次错误直接永久拉黑 `bantime = -1`）；
3. **出站防封号策略**：强制阻断垃圾邮件发信（`25, 465, 587, 2525`）与高危矿池/蠕虫端口，保护 VPS 账号安全；
4. **开箱即用 Docker 与防火墙联动**：自动安装 Docker，写入专属 `DOCKER-USER` 规则（放行 8443 等容器出站，杜绝外部端口裸奔）；
5. **专属端口管理命令**：系统内置 `docker-port` 命令，支持 `docker-port open <端口>` 一键精准放行容器端口；
6. **网络性能与代理调优**：默认自动执行 `tune.sh`，开启 BBR + FQ、扩容 100 万文件句柄与 64MB 缓冲区；
7. **可选一键挂机**：支持传入 TraffMonetizer / Repocket / EarnFM / PacketStream 参数，按需一键拉起容器。

#### 💻 常用调用命令

- **场景 1：纯净初始化（加固 + UFW + Docker + BBR，不挂机）**
  ```bash
  curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/init.sh" | bash -s -- \
    --port 20026 \
    --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOjkaEFKxmHz194omW679VPz6jvATK9F5ycv0/+qK34X servers"
  ```

- **场景 2：初始化加固 + 一键启动挂机容器**
  ```bash
  curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/init.sh" | bash -s -- \
    --port 20026 \
    --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOjkaEFKxmHz194omW679VPz6jvATK9F5ycv0/+qK34X servers" \
    --tm-token "你的TraffMonetizer_Token" \
    --earnfm-token "你的EarnFM_Token"
  ```

#### 📋 命令行参数对照表

| 参数名 | 缩写 | 是否必填 | 作用说明 |
| :--- | :--- | :--- | :--- |
| `--port` | `-p` | **必填** | 自定义 SSH 端口 (如 `20026`) |
| `--key` | `-k` | **必填** | SSH 登录公钥 (强制仅公钥登录，禁用密码认证) |
| `--skip-tune` | 无 | 可选 | 跳过 BBR 与网络性能优化 |
| `--rp-email` | `-m` | 可选 | Repocket 账号邮箱 |
| `--rp-key` | `-rk` | 可选 | Repocket API Key |
| `--tm-token` | `-tm` | 可选 | TraffMonetizer 节点 Token |
| `--earnfm-token` | `-ef` | 可选 | EarnFM 节点 API Token |
| `--ps-cid` | `-ps` | 可选 | PacketStream 邀请 ID (CID) |

</details>

---

### 📦 `debian.sh` - Debian 12 自动化网络重装（纯净版）

<details open>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

一键将当前服务器网络重装为最纯净的 **Debian 12 (Bookworm)**，开机自动完成：
- **SSH 安全加固**：强制修改自定义 SSH 端口，**只允许密钥认证**，禁止密码登录；
- **Fail2ban 永久防御**：适配 systemd 后端，密码/密钥错误 3 次永久拉黑（`bantime = -1`）；
- **UFW 防火墙与防封号规则**：
  - 入站默认全关，仅放行自定义 SSH 端口、`80/tcp` 与 `443/tcp`；
  - 强制阻断垃圾邮件外发（`25, 465, 587, 2525`）、勒索病毒与高危矿池端口；
  - 开机自动屏蔽 Vodafone 滥用域名；
- **Docker 环境与一键端口管理**：预装 Docker，并提供 `docker-port open/close/list` 命令，按需一键放通容器端口；
- **Komari 探针自动上线**：系统就绪后自动启动并接入探针面板。

#### 💻 纯净版一键运行命令：

```bash
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh" | bash -s -- \
  --port 20026 \
  --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOjkaEFKxmHz194omW679VPz6jvATK9F5ycv0/+qK34X servers" \
  --endpoint "https://km.666889.xyz" \
  --auto-discovery "RDMOJXrUL4kQNsgnu7KPlNSq"
```

#### 📋 参数说明：
| 参数名 | 简写 | 是否必填 | 说明 |
| :--- | :--- | :--- | :--- |
| `--port` | `-p` | **必填** | 自定义 SSH 端口 (范围: 1-65535) |
| `--key` | `-k` | **必填** | root 用户的 SSH 公钥内容 |
| `--endpoint` | `-e` | **必填** | Komari 探针面板地址 (如 `https://km.666889.xyz`) |
| `--auto-discovery` | `-a` | **二选一** | **Komari 自动发现 Key** (推荐) |
| `--token` | `-t` | **二选一** | **Komari 单机 Token** |

</details>

---

### 📦 `debian-nodes.sh` - Debian 12 网络重装 + 流量挂机集成版

<details>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

在 `debian.sh` 纯净版完整功能（重装 + 加固 + 探针）的基础上，**额外集成多平台流量共享挂机容器**。开机完成基础加固与探针上线后，自动拉取并启动指定平台的挂机节点！

#### 💻 挂机集成版一键运行命令示例：

```bash
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/debian-nodes.sh" | bash -s -- \
  --port 20026 \
  --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOjkaEFKxmHz194omW679VPz6jvATK9F5ycv0/+qK34X servers" \
  --endpoint "https://km.666889.xyz" \
  --auto-discovery "RDMOJXrUL4kQNsgnu7KPlNSq" \
  --rp-email "lovedsser@foxmail.com" \
  --rp-key "your_repocket_key" \
  --tm-token "your_traffmonetizer_token" \
  --earnfm-token "your_earnfm_token" \
  --ps-cid "6WQA"
```

#### 📋 额外可选挂机参数（按需传入，不传不启动）：
| 参数名 | 缩写 | 默认值 | 作用说明 |
| :--- | :--- | :--- | :--- |
| `--rp-email` | `-m` | 空 | Repocket 注册账号邮箱 |
| `--rp-key` | `-k` | 空 | Repocket API Key（需与邮箱配合使用） |
| `--tm-token` | `-tm` | 空 | TraffMonetizer 应用 Token |
| `--earnfm-token` | `-ef` | 空 | EarnFM 节点 API Token |
| `--ps-cid` | `-ps` | 空 | PacketStream 邀请 ID (CID) |

</details>

---

### 📦 `nodes.sh` - 多平台流量共享挂机管理脚本

<details>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

适合在**已有系统**（无需重装）上随时部署、管理或更新流量挂机容器。
- 自动检测并安装 Docker；
- 支持 **Repocket**、**TraffMonetizer**、**EarnFM**、**PacketStream**；
- 自动配置 **Watchtower** 保持挂机镜像持续自动更新；
- 智能探测 PacketStream 机房 IP 兼容性，遭遇拦截自动清理。

#### 💻 独立运行命令：
```bash
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/nodes.sh" | bash -s -- \
  --rp-email "your_email@example.com" \
  --rp-key "your_repocket_api_key" \
  --tm-token "your_traffmonetizer_token" \
  --earnfm-token "your_earnfm_token" \
  --ps-cid "your_packetstream_cid"
```

</details>

---

### 📦 `info.sh` - 系统硬件配置与网络全景检测

<details>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

一键检测服务器的硬件体质、真实读写寿命与全球双栈网络性能：
- **硬件配置**：CPU 型号与主频、架构、AES-NI 支持、物理内存频率与类型、开机运行时间；
- **硬盘健康与寿命**：
  - 读取 NVMe / SATA 固态硬盘型号与通电时间；
  - 精准解析 **终生总写入 (TBW)** 与 **终生/累计总读取 (TBR)**；
  - 磁盘 1GB 顺序写入 I/O 速率测试；
- **全球节点双栈网络测速**：
  - 官方原版 YABS IPv4 与 IPv6 测速逻辑；
  - 多端口自动探测防忙碌重试；
  - 测速伦敦、阿姆斯特丹、法兰克福、洛杉矶等多地节点双向速率与延迟。

#### 💻 一键检测命令：
```bash
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh?nocache=$(date +%s%N)" | bash
```

</details>\n

---

### 📦 `tune.sh` - Debian 12 代理节点与高并发网络优化

<details>
<summary><b>🔍 点击折叠 / 展开详细参数与使用说明</b></summary>

<br>

专门针对 **科学上网代理节点 (Xray / Sing-box / V2Ray / Shadowsocks)** 以及 **基于 UDP 的新型协议 (Hysteria 2 / TUIC / QUIC / WireGuard)** 深度定制的系统与网络吞吐优化脚本。

#### 🚀 核心优化项目：
1. **拥塞控制**：自动启用 **BBR + FQ**（Fair Queueing），大幅降低越洋长途链路的丢包抖动，跑满跨境网络带宽；
2. **高并发连接与句柄**：将系统级、用户级与 systemd 最大文件描述符限制直接扩容至 **1,000,000**，彻底杜绝 `too many open files` 错误；
3. **TCP 缓冲区深度优化**：将核心收发缓冲区最大限制提升至 **64MB**，优化 `tcp_rmem` 与 `tcp_wmem`，提升大延迟高带宽（BDP）链路下的单线程吞吐能力；
4. **UDP / QUIC 吞吐防丢包**：专门调整 `udp_rmem_min` 与 `udp_wmem_min`，解决 Hysteria 2 / TUIC 在大流量爆发传输时被系统内核静默限速或丢包的痛点；
5. **长连接保活与回收**：开启 `tcp_tw_reuse`，加速释放 TIME_WAIT 套接字；缩短 `tcp_fin_timeout` 至 15s；优化 TCP Keepalive 防止代理连接被运营商 NAT 静默拆除；
6. **降低 Swappiness**：设置 `vm.swappiness = 10`，优先使用物理内存，避免频繁读写 Swap 引起卡顿。

#### 💻 一键运行命令：
```bash
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/tune.sh" | bash
```

</details>
