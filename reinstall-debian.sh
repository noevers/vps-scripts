#!/bin/bash
# ==============================================================================
# Script: reinstall-debian.sh
# Author: noevers
# Description: Debian 12 自动化网络重装 + 安全加固 + Docker + Komari 探针一键初始化
# ==============================================================================
set -e

# --- 默认参数 ---
SSH_PORT="2222"
SSH_KEY=""
KOMARI_ENDPOINT=""
KOMARI_TOKEN=""

# 打印帮助信息
usage() {
    cat << EOF
================================================================================
Debian 12 自动化重装与初始化部署脚本
================================================================================
用法:
  curl -sL https://raw.githubusercontent.com/noevers/debian-auto-reinstall/main/reinstall-debian.sh | bash -s -- [选项]

选项:
  -p, --port <端口>            设置自定义 SSH 端口 (默认: 2222)
  -k, --key "<公钥内容>"       SSH 公钥 (如 ssh-ed25519 AAAA... 或 ssh-rsa AAAA...) [必填]
  -e, --endpoint <地址>        Komari 探针面板地址 (如 https://komari.example.com) [必填]
  -t, --token ***          Komari 探针机器 Token [必填]
  -h, --help                   显示帮助信息

使用示例:
  curl -sL https://raw.githubusercontent.com/noevers/debian-auto-reinstall/main/reinstall-debian.sh | bash -s -- \\
    --port 2222 \\
    --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..." \\
    --endpoint "https://komari.example.com" \\
    --token "***"
================================================================================
EOF
    exit 0
}

# --- 解析参数 ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY="***"
            shift 2
            ;;
        -e|--endpoint)
            KOMARI_ENDPOINT="$2"
            shift 2
            ;;
        -t|--token)
            KOMARI_TOKEN="***"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "[错误] 未知参数: $1"
            usage
            ;;
    esac
done

# --- 校验必填项 ---
if [ -z "$SSH_KEY" ]; then
    echo "[错误] 必须提供 SSH 公钥 (--key 或 -k)！"
    echo "提示: 本脚本完全禁用密码登录，不配置公钥将导致无法通过 SSH 连接。"
    exit 1
fi

if [ -z "$KOMARI_ENDPOINT" ] || [ -z "$KOMARI_TOKEN" ]; then
    echo "[错误] 必须提供 Komari 探针地址 (--endpoint) 与 Token (--token)！"
    exit 1
fi

echo "========================================================="
echo " 即将开始 Debian 12 自动化网络重装与初始化:"
echo " - SSH 端口:        ${SSH_PORT}"
echo " - 认证方式:        仅密钥认证 (禁用密码登录)"
echo " - Komari 探针地址: ${KOMARI_ENDPOINT}"
echo " - 基础软件:        vim, curl, wget, unzip, sudo, git, htop 等"
echo " - 安全防护:        UFW 防火墙 (80/443/SSH) + Fail2ban (3次即封)"
echo " - 容器与规则:      Docker CE 最新版 + 拦截容器滥发邮件 + 阻断未授权端口"
echo " - 拦截规则:        屏蔽 Vodafone 域名解析"
echo "========================================================="
sleep 3

# --- 准备 Cloud-Init 配置 ---
SEED_DIR="/tmp/cloud-seed"
rm -rf "$SEED_DIR"
mkdir -p "$SEED_DIR"

cat << EOF > "$SEED_DIR/user-data"
#cloud-config
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys:
      - ${SSH_KEY}

# 开机自动安装基础工具
package_update: true
package_upgrade: true
packages:
  - vim
  - curl
  - wget
  - unzip
  - sudo
  - git
  - htop
  - net-tools
  - ca-certificates
  - gnupg
  - lsb-release
  - ufw
  - fail2ban

write_files:
  # SSH 仅密钥认证与自定义端口配置
  - path: /etc/ssh/sshd_config.d/custom.conf
    permissions: '0644'
    content: |
      Port ${SSH_PORT}
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin prohibit-password

  # Fail2ban 联动 UFW，错误 3 次直接封禁
  - path: /etc/fail2ban/jail.local
    permissions: '0644'
    content: |
      [DEFAULT]
      bantime = 1d
      findtime = 10m
      maxretry = 3
      banaction = ufw

      [sshd]
      enabled = true
      port = ${SSH_PORT}
      maxretry = 3
      backend = systemd

runcmd:
  # 1. 生效 SSH 配置
  - systemctl restart ssh || systemctl restart sshd

  # 2. 运行 Vodafone 域名拦截脚本
  - |
    wget -O /root/block_vodafone.sh https://raw.githubusercontent.com/noevers/AutoScripts/refs/heads/main/block_vodafone.sh
    chmod +x /root/block_vodafone.sh
    bash /root/block_vodafone.sh

  # 3. 配置 UFW 防火墙（宿主机仅放行自定义 SSH + 80 + 443）
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow ${SSH_PORT}/tcp comment 'Custom SSH'
  - ufw allow 80/tcp comment 'HTTP'
  - ufw allow 443/tcp comment 'HTTPS'

  # 4. 注入 Docker 安全规则（防滥发邮件 + 阻断外部越界访问容器端口）
  - |
    cat << 'RULES' >> /etc/ufw/after.rules

    # --- DOCKER 安全规则 (防滥发邮件 + 防端口越界暴露) ---
    *filter
    :DOCKER-USER - [0:0]
    # 阻止容器通过 25, 465, 587, 2525 端口向外发垃圾邮件
    -A DOCKER-USER -p tcp -m multiport --dports 25,465,587,2525 -j DROP
    # 阻止外部通过 Docker 访问除 80, 443 以外的任何未授权映射
    -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    -A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
    -A DOCKER-USER -p tcp -m multiport --dports 80,443 -j ACCEPT
    -A DOCKER-USER -i docker0 -j ACCEPT
    -A DOCKER-USER -j DROP
    COMMIT
    RULES

  - ufw --force enable
  - systemctl enable ufw

  # 5. 启动 Fail2ban 防爆破
  - systemctl enable fail2ban
  - systemctl restart fail2ban

  # 6. 安装官方最新稳定版 Docker & Docker Compose
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  - systemctl enable docker
  - systemctl start docker

  # 7. 重新加载 UFW 让 Docker 链生效
  - ufw reload

  # 8. 安装并启动 Komari Agent 探针
  - curl -sL https://raw.githubusercontent.com/komari-monitor/komari-agent/main/install.sh | bash -s -- --endpoint "${KOMARI_ENDPOINT}" --token "***}"
EOF

# --- 启动重装 ---
echo ">>> 正在下载底层网络重装工具并启动 Debian 12 安装..."
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
bash reinstall.sh debian 12 --cloud-data "$SEED_DIR"
