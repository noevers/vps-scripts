#!/bin/bash
# ==============================================================================
# Script Name: debian.sh
# Description: Debian 12 自动化网络重装 + 安全加固 + Docker + Komari 探针
# Source Engine: bin456789/reinstall (self-hosted under ./core)
# ==============================================================================
set -e

# --- 变量初始化 (零默认值，强制参数输入) ---
SSH_PORT=""
SSH_KEY=""
KOMARI_ENDPOINT=""
KOMARI_TOKEN=""
KOMARI_AUTO_DISCOVERY=""

# 打印帮助信息
usage() {
    cat << EOF
==============================================================================
Debian 12 自动化重装与环境初始化脚本 (vps-scripts)
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

# 检查是否传入了任何参数
if [ $# -eq 0 ]; then
    echo "=============================================================================="
    echo "❌ 错误: 未检测到任何输入参数，已拒绝执行。"
    echo "=============================================================================="
    usage
fi

# --- 解析命令行参数 (支持 --key=value 以及空格分隔传参) ---
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        --port=*)
            SSH_PORT="${1#*=}"
            shift 1
            ;;
        -k|--key)
            SSH_KEY="$2"
            shift 2
            ;;
        --key=*)
            SSH_KEY="${1#*=}"
            shift 1
            ;;
        -e|--endpoint)
            KOMARI_ENDPOINT="$2"
            shift 2
            ;;
        --endpoint=*)
            KOMARI_ENDPOINT="${1#*=}"
            shift 1
            ;;
        -t|--token)
            KOMARI_TOKEN="$2"
            shift 2
            ;;
        -a|--auto-discovery)
            KOMARI_AUTO_DISCOVERY="$2"
            shift 2
            ;;
        --token=*)
            KOMARI_TOKEN="${1#*=}"
            shift 1
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

# --- 严格校验输入参数 ---
ERRORS=()

# 1. 端口校验 (必须为 1-65535 的纯数字)
if [ -z "$SSH_PORT" ]; then
    ERRORS+=("缺少必填参数: -p / --port (未指定 SSH 端口)")
elif ! echo "$SSH_PORT" | grep -qE '^[0-9]+$' || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    ERRORS+=("参数错误: --port 必须是 1 到 65535 之间的合法数字端口 (当前值: '$SSH_PORT')")
fi

# 2. 公钥校验 (只要包含标准公钥格式即放行，去除首尾空白)
SSH_KEY="$(echo "$SSH_KEY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ -z "$SSH_KEY" ]; then
    ERRORS+=("缺少必填参数: -k / --key (未指定 SSH 公钥)")
elif ! echo "$SSH_KEY" | grep -qE '^(ssh-ed25519|ssh-rsa|ssh-dss|ssh-ecdsa|ecdsa-sha2-)'; then
    ERRORS+=("参数错误: --key 必须是以 ssh-ed25519 或 ssh-rsa 等标准公钥格式开头的内容 (当前检测值: '$SSH_KEY')")
fi

# 3. 探针 Endpoint 校验
if [ -z "$KOMARI_ENDPOINT" ]; then
    ERRORS+=("缺少必填参数: -e / --endpoint (未指定 Komari 探针地址)")
elif ! echo "$KOMARI_ENDPOINT" | grep -qE '^https?://'; then
    ERRORS+=("参数错误: --endpoint 必须是以 http:// 或 https:// 开头的合法 URL (当前值: '$KOMARI_ENDPOINT')")
fi

# 4. 探针认证校验 (二选一)
if [ -z "$KOMARI_TOKEN" ] && [ -z "$KOMARI_AUTO_DISCOVERY" ]; then
    ERRORS+=("缺少探针认证参数: 必须指定 -a/--auto-discovery 或 -t/--token")
fi

# 如果存在校验错误，拒绝执行并退出
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
echo " 即将开始 Debian 12 自动化网络重装与初始化:"
echo " - SSH 端口:        ${SSH_PORT}"
echo " - SSH 认证:        仅密钥认证 (密码登录将被彻底禁用)"
echo " - Komari 探针:     ${KOMARI_ENDPOINT}"
echo " - 入站防护:        仅放行 ${SSH_PORT}, 80, 443 端口，拦截所有其他入站"
echo " - 出站防护:        阻断邮件端口(25/465/587/2525)、矿池、Windows高危端口"
echo " - 防爆破策略:      Fail2ban 错误 3 次永久封禁"
echo " - 预装环境:        vim, curl, wget, unzip, sudo, Docker 最新稳定版"
echo "=============================================================================="
echo "系统将在 5 秒后开始下载重装引擎..."
sleep 5

# --- 准备 Cloud-Init 配置目录 ---
SEED_DIR="/tmp/cloud-seed"
rm -rf "$SEED_DIR"
mkdir -p "$SEED_DIR"

cat << EOF > "$SEED_DIR/user-data"
#!/bin/bash
set -x
exec > /var/log/firstboot-setup.log 2>&1

echo ">>> 开始首次开机自动化配置..."

# 1. 设置 SSH 仅密钥认证与换端口
mkdir -p /etc/ssh/sshd_config.d
cat << 'SSH_CONF' > /etc/ssh/sshd_config.d/custom.conf
Port ${SSH_PORT}
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
SSH_CONF

# 确保 authorized_keys 写入
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "${SSH_KEY}" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
systemctl restart ssh || systemctl restart sshd

# 2. 刷新 apt 并安装基础工具全家桶
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y vim curl wget unzip sudo git htop net-tools ca-certificates gnupg lsb-release ufw fail2ban

# 3. 运行 Vodafone 域名拦截
wget -O /root/block_vodafone.sh https://raw.githubusercontent.com/noevers/AutoScripts/refs/heads/main/block_vodafone.sh || true
if [ -f /root/block_vodafone.sh ]; then
    chmod +x /root/block_vodafone.sh
    bash /root/block_vodafone.sh || true
fi

# 4. 配置 Fail2ban 永久封禁
cat << 'F2B' > /etc/fail2ban/jail.local
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
F2B
systemctl enable fail2ban
systemctl restart fail2ban

# 5. 配置 UFW 防火墙与高危出站拦截
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp comment 'Custom SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 8065/tcp comment 'Mattermost/Web 8065'

# 拦截高危出站
ufw reject out 25/tcp comment 'Block SMTP Out' || true
ufw reject out 465/tcp comment 'Block SMTPS Out' || true
ufw reject out 587/tcp comment 'Block Submission Out' || true
ufw reject out 2525/tcp comment 'Block Alternate SMTP Out' || true
ufw reject out 135/tcp comment 'Block SMB Out' || true
ufw reject out 137/udp comment 'Block NetBIOS Out' || true
ufw reject out 138/udp comment 'Block NetBIOS Out' || true
ufw reject out 139/tcp comment 'Block NetBIOS Out' || true
ufw reject out 445/tcp comment 'Block SMB Out' || true
ufw reject out 3333,4444,5555,7777,9000,14444/tcp comment 'Block Stratum Mining Out' || true

# Docker 安全规则
cat << 'RULES' >> /etc/ufw/after.rules

# --- DOCKER 安全规则 (防滥发邮件 + 防端口越界暴露) ---
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -p tcp -m multiport --dports 25,465,587,2525,135,139,445,3333,4444,5555,7777,9000,14444 -j DROP
-A DOCKER-USER -p udp -m multiport --dports 135,137,138,445 -j DROP
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
-A DOCKER-USER -p tcp -m multiport --dports 80,443,8065 -j ACCEPT
-A DOCKER-USER -i docker0 -j ACCEPT
-A DOCKER-USER -j DROP
COMMIT
RULES

ufw --force enable
systemctl enable ufw

# 6. 安装官方最新 Docker & Docker Compose
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
ufw reload

# 7. 安装并启动 Komari Agent 探针
if [ -n "${KOMARI_AUTO_DISCOVERY}" ]; then
    curl -sL https://raw.githubusercontent.com/komari-monitor/komari-agent/main/install.sh | bash -s -- --endpoint "${KOMARI_ENDPOINT}" --auto-discovery "${KOMARI_AUTO_DISCOVERY}"
else
    curl -sL https://raw.githubusercontent.com/komari-monitor/komari-agent/main/install.sh | bash -s -- --endpoint "${KOMARI_ENDPOINT}" --token "${KOMARI_TOKEN}"
fi

echo ">>> 首次开机配置全部完成！"
EOF

# --- 修复旧系统源过期 & 准备环境 ---
echo ">>> 正在准备基础运行环境..."
if command -v apt-get >/dev/null 2>&1; then
    # 忽略 apt 仓库 Release 文件过期报错 (如旧系统 bullseye-security expired)
    echo 'Acquire::Check-Valid-Until "0";' > /etc/apt/apt.conf.d/99no-check-valid-until 2>/dev/null || true
    apt-get update -o Acquire::Check-Valid-Until=false -y || true
fi

# --- 启动自托管重装引擎 ---
echo ">>> 正在启动自托管重装引擎 (core/reinstall.sh)..."
curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/core/reinstall.sh" -o /tmp/reinstall.sh
bash /tmp/reinstall.sh debian 12 --username root --ssh-port "$SSH_PORT" --ssh-key "$SSH_KEY" --cloud-data "$SEED_DIR"
