#!/bin/bash
# ==============================================================================
# Script Name: debian.sh
# Description: Debian 12 自动化网络重装与安全加固 (无默认值，强制参数校验)
# Repository:  https://github.com/noevers/vps-scripts
# ==============================================================================
set -e

# --- 初始化变量（全部为空，杜绝默认值安全隐患） ---
SSH_PORT=""
SSH_KEY=""
KOMARI_ENDPOINT=""
KOMARI_TOKEN=""

# 打印帮助信息
usage() {
    cat << EOF
--------------------------------------------------------------------------------
【使用说明】
  bash $0 --port <端口> --key "<公钥>" --endpoint "<地址>" --token "<密钥>"

【必填参数列表】(所有参数均为必填，不传或缺失任何一项将拒绝执行):
  -p, --port <端口>            自定义 SSH 端口 (必须为 1-65535 之间的纯数字)
  -k, --key "<公钥>"           SSH 公钥内容 (以 ssh-ed25519 或 ssh-rsa 等开头)
  -e, --endpoint "<地址>"      Komari 探针服务端地址 (如 https://komari.example.com)
  -t, --token "<密钥>"         Komari 探针机器 Token
  -h, --help                   显示帮助信息

【执行示例】:
  curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh | bash -s -- \\
    --port 2222 \\
    --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..." \\
    --endpoint "https://komari.example.com" \\
    --token "***"
--------------------------------------------------------------------------------
EOF
    exit 1
}

# 如果没有传递任何参数，直接显示帮助并退出
if [ $# -eq 0 ]; then
    echo "❌ 错误: 未检测到任何输入参数！为了服务器安全，本脚本拒绝无参数执行。"
    usage
fi

# --- 解析命令行参数 ---
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
            echo "❌ 错误: 未知参数 $1"
            usage
            ;;
    esac
done

# --- 严格校验每个必填参数 ---
MISSING_ARGS=()

# 1. 校验端口
if [ -z "$SSH_PORT" ]; then
    MISSING_ARGS+=("SSH 端口 (--port / -p)")
elif ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -le 0 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo "❌ 错误: SSH 端口必须是 1-65535 之间的合法数字，当前输入为: '$SSH_PORT'"
    exit 1
fi

# 2. 校验公钥
if [ -z "$SSH_KEY" ]; then
    MISSING_ARGS+=("SSH 公钥 (--key / -k)")
elif ! [[ "$SSH_KEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ]]; then
    echo "❌ 错误: SSH 公钥格式不正确！必须以 ssh-ed25519 / ssh-rsa 等标准公钥标识开头。"
    exit 1
fi

# 3. 校验 Komari 面板地址
if [ -z "$KOMARI_ENDPOINT" ]; then
    MISSING_ARGS+=("Komari 探针服务端地址 (--endpoint / -e)")
elif ! [[ "$KOMARI_ENDPOINT" =~ ^https?:// ]]; then
    echo "❌ 错误: Komari 探针服务端地址必须以 http:// 或 https:// 开头。"
    exit 1
fi

# 4. 校验 Komari Token
if [ -z "$KOMARI_TOKEN" ]; then
    MISSING_ARGS+=("Komari 探针机器 Token (--token / -t)")
fi

# 如果有任何缺失项，统一拦截并报错
if [ ${#MISSING_ARGS[@]} -ne 0 ]; then
    echo "❌ 错误: 检测到以下必填参数未提供:"
    for arg in "${MISSING_ARGS[@]}"; do
        echo "   - $arg"
    done
    echo ""
    echo "提示: 本脚本完全禁用密码登录。若缺失公钥或端口等参数会导致机器失联，因此强制全参数校验。"
    usage
fi

echo "========================================================="
echo " ✅ 所有参数校验通过，即将开始 Debian 12 自动化安装与加固:"
echo " -------------------------------------------------------"
echo " • SSH 端口:        ${SSH_PORT}"
echo " • SSH 认证:        仅公钥认证 (已禁用密码)"
echo " • Komari 探针:     ${KOMARI_ENDPOINT}"
echo " • Komari Token:    ${KOMARI_TOKEN}"
echo " • 防火墙与拦截:    UFW (放行 ${SSH_PORT}, 80, 443) / 阻断邮件端口"
echo " • 暴力破解防护:    Fail2ban 错误 3 次封禁"
echo " • 基础运行环境:    Docker CE, Compose, vim, curl, wget 等"
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

# 开机预装软件包
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

  # 3. 配置 UFW 防火墙（放行自定义 SSH + 80 + 443）
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow ${SSH_PORT}/tcp comment 'Custom SSH'
  - ufw allow 80/tcp comment 'HTTP'
  - ufw allow 443/tcp comment 'HTTPS'

  # 4. 注入 Docker 防护与拦截邮件发信规则
  - |
    cat << 'RULES' >> /etc/ufw/after.rules

    # --- DOCKER 安全规则 (防滥发邮件 + 防端口越界暴露) ---
    *filter
    :DOCKER-USER - [0:0]
    # 阻止容器向外发送垃圾邮件 (25, 465, 587, 2525)
    -A DOCKER-USER -p tcp -m multiport --dports 25,465,587,2525 -j DROP
    # 阻止外部通过 Docker 访问除 80, 443 以外的未授权映射
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

  # 6. 安装官方最新 Docker & Docker Compose
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  - systemctl enable docker
  - systemctl start docker

  # 7. 重载 UFW 规则
  - ufw reload

  # 8. 安装并启动 Komari Agent 探针
  - curl -sL https://raw.githubusercontent.com/komari-monitor/komari-agent/main/install.sh | bash -s -- --endpoint "${KOMARI_ENDPOINT}" --token "***}"
EOF

# --- 启动重装 ---
echo ">>> 正在下载官方网络重装工具并启动 Debian 12 安装..."
curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/core/reinstall.sh -o /tmp/reinstall.sh
bash reinstall.sh debian 12 --cloud-data "$SEED_DIR"
