# Linux 自动化运维与部署脚本合集 (Linux Auto Scripts)

收集和维护各类 Linux / VPS 高效自动化运维、系统重装、安全加固、容器与监控部署脚本。

---

## 📂 脚本目录清单

### 1. Debian 12 自动化网络重装与安全加固 (`debian.sh`)
专为 VPS / 云服务器设计的一键重装与初始化脚本。支持全自动扩容、SSH 密钥认证、UFW 防火墙配置、Fail2ban 防爆破、Docker 容器部署与邮件防滥发规则、Komari 探针无感接入。

**快速使用**：
```bash
curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh | bash -s -- \
  --port 2222 \
  --key "你的SSH公钥" \
  --endpoint "https://komari.example.com" \
  --token "***"
```

| 参数 | 说明 | 是否必填 | 默认值 |
| :--- | :--- | :---: | :---: |
| `-p`, `--port` | 自定义 SSH 端口 | 否 | `2222` |
| `-k`, `--key` | SSH 公钥 (如 `ssh-ed25519 AAAA...`) | **是** | 无 |
| `-e`, `--endpoint` | Komari 探针面板地址 (带 http/https) | **是** | 无 |
| `-t`, `--token` | Komari 探针机器 Token | **是** | 无 |

---

## 🛠️ 后续规划与添加中的脚本
- [x] Debian 12 自动化网络重装 (带 Docker / 安全规则 / Komari 探针)
- [ ] 常用网络测速与流媒体解锁检测
- [ ] 一键 BBR / 常用网络拥塞算法优化
- [ ] 自动化证书申请与反向代理部署
- [ ] 更多实用 Linux 运维与安全脚本...

---

## 📄 开源协议
MIT License.
