#!/bin/bash
# ==============================================================================
# Script: init.sh (全新/已有 Linux 系统一键初始化加固与部署)
# Description:
#   1. 一键修改 SSH：支持自定义端口、强制公钥登录、彻底禁用密码与键盘交互认证
#   2. 一键配置全套防火墙：UFW + Fail2ban 永久防御 (3次错误永久拉黑)
#   3. 防封号安全策略：出站拦截垃圾邮件 (25/465/587) 与高危矿池/蠕虫端口
#   4. Docker 与 Docker Compose 环境一键安装 + 防火墙联动
#   5. 解除 Docker 出站误杀 (放行 8443 等 API) + 内置 docker-port 便捷管理命令
#   6. 深度网络性能与代理优化 (BBR + FQ + 百万句柄 + 64MB 缓冲区)
#   7. 可选一键挂机部署 (TraffMonetizer / Repocket / EarnFM / PacketStream)
# Supported OS: Debian 11/12+, Ubuntu 20.04/22.04/24.04+
# ==============================================================================

set -e

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[36m"
C_RESET="\033[0m"

# 参数定义
SSH_PORT=""
SSH_KEY=""
SKIP_TUNE=0

# 挂机参数 (默认为空，按需启动)
RP_EMAIL=""
RP_API_KEY=""
TM_TOKEN=""
EARNFM_TOKEN=""
PS_CID=""

usage() {
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
    echo -e "${C_GREEN}   VPS 一键系统初始化、安全加固、Docker 与挂机部署脚本 (init.sh)${C_RESET}"
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
    echo -e "使用方法: curl -sL \"https://raw.githubusercontent.com/noevers/vps-scripts/main/init.sh\" | bash -s -- [选项]"
    echo ""
    echo -e "${C_YELLOW}[ 基础系统与安全参数 (必填) ]${C_RESET}"
    echo "  --port, -p <端口>            自定义 SSH 端口 (如: 20026)"
    echo "  --key, -k <公钥>             SSH 登录公钥 (强制仅公钥登录，禁用密码)"
    echo ""
    echo -e "${C_YELLOW}[ 可选高级调优选项 ]${C_RESET}"
    echo "  --skip-tune                  跳过 BBR + 网络吞吐优化 (默认自动执行优化)"
    echo ""
    echo -e "${C_YELLOW}[ 可选挂机容器参数 (传参则启动，不传则跳过保持纯净) ]${C_RESET}"
    echo "  --rp-email, -m <邮箱>        Repocket 注册账号邮箱"
    echo "  --rp-key, -rk <KEY>          Repocket API Key (需与邮箱同时提供)"
    echo "  --tm-token, -tm <Token>      TraffMonetizer 节点 Token"
    echo "  --earnfm-token, -ef <Token>  EarnFM 节点 API Token"
    echo "  --ps-cid, -ps <CID>          PacketStream 邀请 ID (CID)"
    echo ""
    echo "  --help, -h                   显示本帮助信息"
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
    echo -e "调用示例 (纯净初始化):"
    echo "  bash init.sh --port 20026 --key \"ssh-ed25519 AAAAC3...\""
    echo ""
    echo -e "调用示例 (初始化 + 启动挂机):"
    echo "  bash init.sh --port 20026 --key \"ssh-ed25519 AAAAC3...\" --tm-token \"xxx\" --earnfm-token \"yyy\""
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port|-p)
            SSH_PORT="$2"
            shift 2
            ;;
        --key|-k)
            SSH_KEY="$2"
            shift 2
            ;;
        --skip-tune)
            SKIP_TUNE=1
            shift
            ;;
        --rp-email|-m)
            RP_EMAIL="$2"
            shift 2
            ;;
        --rp-key|-rk)
            RP_API_KEY="$2"
            shift 2
            ;;
        --tm-token|-tm)
            TM_TOKEN="$2"
            shift 2
            ;;
        --earnfm-token|-ef)
            EARNFM_TOKEN="$2"
            shift 2
            ;;
        --ps-cid|-ps)
            PS_CID="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo -e "${C_RED}错误: 未知参数 $1${C_RESET}"
            usage
            ;;
    esac
done

# 权限与参数校验
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${C_RED}错误: 必须以 root 权限执行此初始化脚本！${C_RESET}"
    exit 1
fi

if [ -z "$SSH_PORT" ]; then
    echo -e "${C_RED}错误: 必须通过 --port 指定自定义 SSH 端口！${C_RESET}"
    exit 1
fi

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo -e "${C_RED}错误: SSH 端口必须在 1-65535 之间！${C_RESET}"
    exit 1
fi

if [ -z "$SSH_KEY" ]; then
    echo -e "${C_RED}错误: 必须通过 --key 传入 SSH 登录公钥 (拒绝密码登录以防爆破)！${C_RESET}"
    exit 1
fi

echo -e "${C_BLUE}==============================================================================${C_RESET}"
echo -e "${C_GREEN}>>> 开始执行系统一键初始化加固流程...${C_RESET}"
echo -e "  - 自定义 SSH 端口: ${C_YELLOW}${SSH_PORT}${C_RESET}"
echo -e "  - SSH 公钥: ${C_YELLOW}${SSH_KEY:0:30}...${C_RESET}"
echo -e "${C_BLUE}==============================================================================${C_RESET}"

# 1. 基础环境与源更新
echo -e "${C_GREEN}>>> [1/7] 更新系统软件源并安装必备工具...${C_RESET}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    curl wget sudo ufw fail2ban ca-certificates gnupg lsb-release iptables net-tools iproute2 procps dnsutils

# 2. SSH 加固 (修改端口、仅公钥认证、禁用密码)
echo -e "${C_GREEN}>>> [2/7] 配置 SSH 仅密钥认证与换端口 (${SSH_PORT})...${C_RESET}"
mkdir -p /etc/ssh/sshd_config.d
cat << SSH_CONF > /etc/ssh/sshd_config.d/custom.conf
Port ${SSH_PORT}
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
SSH_CONF

# 确保主 sshd_config 包含配置目录
if ! grep -q "Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config 2>/dev/null; then
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config || true
fi

# 写入公钥
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if ! grep -Fxq "${SSH_KEY}" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "${SSH_KEY}" >> /root/.ssh/authorized_keys
fi
chmod 600 /root/.ssh/authorized_keys

# 3. 安装配置 Fail2ban (永久防御)
echo -e "${C_GREEN}>>> [3/7] 配置 Fail2ban 永久封禁暴力破解 (3次拉黑)...${C_RESET}"
mkdir -p /etc/fail2ban
cat << F2B > /etc/fail2ban/jail.local
[DEFAULT]
bantime = -1
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ${SSH_PORT}
mode = aggressive
F2B

systemctl enable fail2ban || true
systemctl restart fail2ban || true

# 4. 自动检测外网网卡与防火墙配置 (UFW + 防封号规则)
echo -e "${C_GREEN}>>> [4/7] 配置 UFW 防火墙与防封号阻断规则...${C_RESET}"
WAN_IF=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n1)
[ -z "$WAN_IF" ] && WAN_IF=$(ip link | awk -F: '$0 !~ "lo|docker|br-|veth" && $2 ~ "^ [a-z]" {print $2; exit}' | tr -d ' ')
[ -z "$WAN_IF" ] && WAN_IF="eth0"

ufw --force reset || true
ufw default deny incoming
ufw default allow outgoing

# 放行基础服务入站
ufw allow ${SSH_PORT}/tcp comment 'Custom SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# 拦截高危出站 (防封号)
ufw reject out 25/tcp comment 'Block SMTP Out' || true
ufw reject out 465/tcp comment 'Block SMTPS Out' || true
ufw reject out 587/tcp comment 'Block Submission Out' || true
ufw reject out 2525/tcp comment 'Block Alternate SMTP' || true
ufw reject out 135 comment 'Block RPC' || true
ufw reject out 137 comment 'Block NetBIOS' || true
ufw reject out 138 comment 'Block NetBIOS' || true
ufw reject out 139 comment 'Block NetBIOS' || true
ufw reject out 445 comment 'Block SMB' || true
ufw reject out 3333/tcp comment 'Block Monero Stratum' || true
ufw reject out 4444/tcp comment 'Block Mining Stratum' || true
ufw reject out 5555/tcp comment 'Block Mining Pool' || true
ufw reject out 7777/tcp comment 'Block Mining Pool' || true
ufw reject out 9000/tcp comment 'Block Mining Pool' || true
ufw reject out 14444/tcp comment 'Block Mining Stratum' || true

# 5. 安装 Docker 与 Docker Compose
echo -e "${C_GREEN}>>> [5/7] 安装 Docker 与 Docker Compose 官方最新环境...${C_RESET}"
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker || true
    systemctl start docker || true
fi

# 写入精准 DOCKER-USER 防火墙规则 (出站全放行解除误杀，入站白名单保护)
cat << RULES >> /etc/ufw/after.rules

# --- DOCKER 安全规则 (仅拦截主动高危出站 + 容器出站全放行 + 入站白名单保护) ---
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -p tcp -m multiport --dports 25,465,587,2525,135,139,445,3333,4444,5555,7777,9000,14444 -j DROP
-A DOCKER-USER -p udp -m multiport --dports 135,137,138,445 -j DROP
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
-A DOCKER-USER -i docker0 -j ACCEPT
-A DOCKER-USER -i br-+ -j ACCEPT
-A DOCKER-USER -o ${WAN_IF} -j ACCEPT
-A DOCKER-USER -p tcp -m multiport --dports 80,443 -j ACCEPT
-A DOCKER-USER -j DROP
COMMIT
RULES

ufw --force enable
systemctl restart docker || true

# 6. 生成便捷的 docker-port 命令行管理工具
echo -e "${C_GREEN}>>> [6/7] 生成 Docker 端口管理命令: docker-port ...${C_RESET}"
cat << 'TOOL_EOF' > /usr/local/bin/docker-port
#!/bin/bash
set -e

RULES_FILE="/etc/ufw/after.rules"

usage() {
    echo "=================================================="
    echo "   Docker 端口防火墙管理工具 (精准白名单)"
    echo "=================================================="
    echo "用法:"
    echo "  docker-port open <端口> [协议 tcp/udp]    - 开放指定的 Docker 端口"
    echo "  docker-port close <端口> [协议 tcp/udp]   - 关闭指定的 Docker 端口"
    echo "  docker-port list                          - 列出当前已开放的自定义端口"
    echo "=================================================="
    exit 1
}

ACTION="$1"
PORT="$2"
PROTO="${3:-tcp}"

[ -z "$ACTION" ] && usage

case "$ACTION" in
    open)
        [ -z "$PORT" ] && usage
        if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            echo "错误: 端口必须在 1-65535 之间！"
            exit 1
        fi
        
        ufw allow $PORT/$PROTO comment "Docker $PORT" >/dev/null 2>&1 || true
        
        if grep -q "ctorigdstport $PORT " "$RULES_FILE" 2>/dev/null; then
            echo "提示: Docker 端口 $PORT/$PROTO 之前已在放行规则中！"
        else
            sed -i "/-A DOCKER-USER -j DROP/i -A DOCKER-USER -p $PROTO -m conntrack --ctorigdstport $PORT -j ACCEPT\n-A DOCKER-USER -p $PROTO --dport $PORT -j ACCEPT" "$RULES_FILE"
            echo "✅ 成功将端口 $PORT/$PROTO 加入 Docker 防火墙白名单！"
        fi
        ufw reload >/dev/null 2>&1 || true
        systemctl restart docker >/dev/null 2>&1 || true
        echo "✅ 防火墙规则已重载，外部现在可以直接访问 $PORT 端口！"
        ;;
    close)
        [ -z "$PORT" ] && usage
        ufw delete allow $PORT/$PROTO >/dev/null 2>&1 || true
        sed -i "/--ctorigdstport $PORT /d" "$RULES_FILE"
        sed -i "/--dport $PORT /d" "$RULES_FILE"
        ufw reload >/dev/null 2>&1 || true
        systemctl restart docker >/dev/null 2>&1 || true
        echo "✅ 成功关闭 Docker 端口 $PORT/$PROTO 并恢复严格拦截！"
        ;;
    list)
        echo "当前在 Docker 防火墙中额外开放的自定义端口:"
        PORTS=$(grep -oP "(?<=--ctorigdstport )[0-9]+" "$RULES_FILE" 2>/dev/null | sort -u || true)
        if [ -z "$PORTS" ]; then
            echo "  (仅默认的 80 和 443 端口)"
        else
            for p in $PORTS; do
                echo "  - 端口: $p"
            done
        fi
        ;;
    *)
        usage
        ;;
esac
TOOL_EOF
chmod +x /usr/local/bin/docker-port

# 7. 执行网络与代理专项优化 (tune.sh)
if [ "$SKIP_TUNE" -eq 0 ]; then
    echo -e "${C_GREEN}>>> [7/7] 执行 BBR 与高吞吐代理优化 (tune.sh)...${C_RESET}"
    curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/tune.sh" | bash || true
else
    echo -e "${C_YELLOW}>>> [7/7] 跳过网络优化调优 (--skip-tune)${C_RESET}"
fi

# 8. (可选) 挂机平台按需部署
NODES_ARGS=()
[ -n "${RP_EMAIL}" ] && NODES_ARGS+=(--rp-email "${RP_EMAIL}")
[ -n "${RP_API_KEY}" ] && NODES_ARGS+=(--rp-key "${RP_API_KEY}")
[ -n "${TM_TOKEN}" ] && NODES_ARGS+=(--tm-token "${TM_TOKEN}")
[ -n "${EARNFM_TOKEN}" ] && NODES_ARGS+=(--earnfm-token "${EARNFM_TOKEN}")
[ -n "${PS_CID}" ] && NODES_ARGS+=(--ps-cid "${PS_CID}")

if [ ${#NODES_ARGS[@]} -gt 0 ]; then
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
    echo -e "${C_GREEN}>>> 检测到挂机参数，正在启动挂机节点容器...${C_RESET}"
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
    curl -sL "https://raw.githubusercontent.com/noevers/vps-scripts/main/nodes.sh" | bash -s -- "${NODES_ARGS[@]}" || true
fi

# 重启 SSH 服务生效新端口与仅公钥模式
systemctl restart ssh || systemctl restart sshd

echo -e "${C_BLUE}==============================================================================${C_RESET}"
echo -e "${C_GREEN}🎉 系统初始化与安全加固已全部完成！${C_RESET}"
echo -e "  - 新 SSH 端口: ${C_YELLOW}${SSH_PORT}${C_RESET}"
echo -e "  - 登录认证: ${C_YELLOW}仅公钥认证 (已禁用密码登录)${C_RESET}"
echo -e "  - 防火墙状态: ${C_YELLOW}UFW 已开启 (放行 ${SSH_PORT}/80/443，阻断垃圾邮件与矿池)${C_RESET}"
echo -e "  - Docker 状态: ${C_YELLOW}已就绪 (输入 docker-port open <端口> 可随时放行新容器)${C_RESET}"
echo -e "  - 网络状态: ${C_YELLOW}已启用 BBR+FQ 并扩容百万并发句柄${C_RESET}"
echo -e "${C_BLUE}==============================================================================${C_RESET}"
echo -e "${C_RED}⚠️ 重要提示: 请切勿关闭当前终端窗口！${C_RESET}"
echo -e "请新开一个终端窗口，执行以下命令测试公钥连接:"
echo -e "${C_YELLOW}ssh -p ${SSH_PORT} root@<你的IP>${C_RESET}"
echo -e "${C_BLUE}==============================================================================${C_RESET}"
