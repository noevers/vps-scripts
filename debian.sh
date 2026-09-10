#!/bin/bash
# ==============================================================================
# Script Name: debian.sh
# Repository:  https://github.com/noevers/vps-scripts
# Description: Debian 12 自动化网络重装与安全加固 (无默认值 / 严格校验 / 全自托管)
# ==============================================================================
set -e

# --- 变量初始化 (零默认值，保障安全) ---
SSH_PORT=""
SSH_KEY=""
KOMARI_ENDPOINT=""
KOMARI_TOKEN=""

# 打印帮助信息
usage() {
    cat << EOF
==============================================================================
Debian 12 自动化网络重装与安全加固一键脚本 (vps-scripts)
==============================================================================
用法:
  curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh | bash -s -- [选项]

必填参数 (无默认值，必须全部指定):
  -p, --port <端口>            自定义 SSH 端口 (范围: 1-65535)
  -k, --key "<公钥内容>"       SSH 公钥内容 (以 ssh-ed25519 或 ssh-rsa 等开头)
  -e, --endpoint <地址>        Komari 探针面板地址 (以 http:// 或 https:// 开头)
  -t, --token ***          Komari 探针机器 Token

可选参数:
  -h, --help                   显示此帮助信息

示例:
  curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/debian.sh | bash -s -- \\
    --port 2222 \\
    --key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePublicKeyForRootAuth" \\
    --endpoint "https://komari.example.com" \\
    --token "***"
==============================================================================
EOF
    exit 0
}

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
            echo "❌ 错误: 未知参数 '$1'"
            usage
            ;;
    esac
done

# --- 严格安全校验逻辑 ---
ERRORS=()

# 1. 端口校验 (必须为 1-65535 整数)
if [ -z "$SSH_PORT" ]; then
    ERRORS+=("缺少必填参数: -p / --port (未指定 SSH 端口)")
elif ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    ERRORS+=("参数错误: --port 必须是 1 到 65535 之间的合法端口号 (当前输入: $SSH_PORT)")
fi

# 2. 公钥校验 (非空且符合 OpenSSH 公钥格式)
if [ -z "$SSH_KEY" ]; then
    ERRORS+=("缺少必填参数: -k / --key (未指定 SSH 公钥)")
elif ! [[ "$SSH_KEY" =~ ^(ssh-(ed25519|rsa|dss|ecdsa)|ecdsa-sha2-) ]]; then
    ERRORS+=("参数错误: --key 必须是以 ssh-ed25519 或 ssh-rsa 等标准公钥格式开头的内容")
fi

# 3. 探针 Endpoint 校验
if [ -z "$KOMARI_ENDPOINT" ]; then
    ERRORS+=("缺少必填参数: -e / --endpoint (未指定 Komari 探针地址)")
elif ! [[ "$KOMARI_ENDPOINT" =~ ^https?:// ]]; then
    ERRORS+=("参数错误: --endpoint 必须以 http:// 或 https:// 开头 (当前输入: $KOMARI_ENDPOINT)")
fi

# 4. 探针 Token 校验
if [ -z "$KOMARI_TOKEN" ]; then
    ERRORS+=("缺少必填参数: -t / --token *** Komari 探针机器 Token)")
fi

# 如果有任何错误，直接终止执行
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "=============================================================================="
    echo "❌ 参数校验失败，拒绝执行安装："
    for err in "${ERRORS[@]}"; do
        echo "   - $err"
    done
    echo "=============================================================================="
    echo "请使用 --help 查看完整使用说明。"
    exit 1
fi

echo "=============================================================================="
echo "✅ 参数校验通过，即将开始自动化装机与加固流程："
echo "   - SSH 端口:        ${SSH_PORT}"
echo "   - SSH 认证:        仅密钥认证 (公钥已校验)"
echo "   - Komari 探针:     ${KOMARI_ENDPOINT}"
echo "   - Fail2ban 规则:   失败 3 次永久封禁 (bantime = -1)"
echo "   - 入站防火墙:      白名单放行 ${SSH_PORT}/tcp, 80/tcp, 443/tcp"
echo "   - 出站防火墙:      阻断邮件滥发 (25/465/587/2525)、SMB蠕虫、矿池等高危端口"
echo "   - Docker 防护:     UFW 统一纳管 + 拦截未授权端口 + 出站防封号"
echo "   - 基础软件预装:    vim, curl, wget, unzip, sudo, git, htop, docker-ce"
echo "=============================================================================="
sleep 3

# --- 准备 Cloud-Init 注入配置 ---
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

# 1. 开机自动更新并安装基础软件
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
  # SSH 仅密钥认证与自定义端口
  - path: /etc/ssh/sshd_config.d/custom.conf
    permissions: '0644'
    content: |
      Port ${SSH_PORT}
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin prohibit-password

  # Fail2ban 联动 UFW，错误 3 次直接永久封禁 (-1)
  - path: /etc/fail2ban/jail.local
    permissions: '0644'
    content: |
      [DEFAULT]
      bantime = -1
      findtime = 10m
      maxretry = 3
      banaction = ufw

      [sshd]
      enabled = true
      port = ${SSH_PORT}
      maxretry = 3
      backend = systemd

runcmd:
  # 2. 生效 SSH 配置
  - systemctl restart ssh || systemctl restart sshd

  # 3. 运行 Vodafone 域名拦截脚本
  - |
    wget -O /root/block_vodafone.sh https://raw.githubusercontent.com/noevers/AutoScripts/refs/heads/main/block_vodafone.sh
    chmod +x /root/block_vodafone.sh
    bash /root/block_vodafone.sh

  # 4. 配置宿主机 UFW 防火墙（入站白名单 + 出站高危拦截）
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow ${SSH_PORT}/tcp comment 'Custom SSH'
  - ufw allow 80/tcp comment 'HTTP'
  - ufw allow 443/tcp comment 'HTTPS'

  # 宿主机出站高危端口阻断 (防发邮件、防蠕虫扩散、防肉鸡挖矿滥用)
  - ufw reject out 25/tcp comment 'Block SMTP Out'
  - ufw reject out 465/tcp comment 'Block SMTPS Out'
  - ufw reject out 587/tcp comment 'Block Submission Out'
  - ufw reject out 2525/tcp comment 'Block Alternate SMTP Out'
  - ufw reject out 135,139,445/tcp comment 'Block SMB Out'
  - ufw reject out 137,138/udp comment 'Block NetBIOS Out'
  - ufw reject out 3333,4444,5555,7777,9000,14444/tcp comment 'Block Stratum Mining Out'

  # 5. 注入 Docker 安全规则 (入站防越界 + 容器出站防滥用)
  - |
    cat << 'RULES' >> /etc/ufw/after.rules

    # --- DOCKER 安全规则 ---
    *filter
    :DOCKER-USER - [0:0]
    # 阻止容器向外发送垃圾邮件 (25, 465, 587, 2525)
    -A DOCKER-USER -p tcp -m multiport --dports 25,465,587,2525 -j DROP
    # 阻止容器向外传播 SMB 蠕虫 (135, 137, 138, 139, 445)
    -A DOCKER-USER -p tcp -m multiport --dports 135,139,445 -j DROP
    -A DOCKER-USER -p udp -m multiport --dports 135,137,138 -j DROP
    # 阻止容器对外连接主流矿池 (3333, 4444, 5555, 7777, 9000, 14444)
    -A DOCKER-USER -p tcp -m multiport --dports 3333,4444,5555,7777,9000,14444 -j DROP
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

  # 6. 启动 Fail2ban 防爆破
  - systemctl enable fail2ban
  - systemctl restart fail2ban

  # 7. 安装官方最新 Docker & Docker Compose
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  - systemctl enable docker
  - systemctl start docker

  # 8. 重载 UFW 规则
  - ufw reload

  # 9. 安装并启动 Komari Agent 探针
  - curl -sL https://raw.githubusercontent.com/komari-monitor/komari-agent/main/install.sh | bash -s -- --endpoint "${KOMARI_ENDPOINT}" --token "***}"
EOF

# --- 启动重装 (调用仓库自托管的 core/reinstall.sh) ---
echo ">>> 正在启动自托管重装引擎..."
curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/core/reinstall.sh -o /tmp/reinstall.sh
bash /tmp/reinstall.sh debian 12 --cloud-data "$SEED_DIR"
