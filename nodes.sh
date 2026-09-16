#!/bin/bash
# ==============================================================================
# Script: nodes.sh (流量挂机容器一键管理脚本)
# Description: 自动化部署与管理流量共享挂机节点 (Repocket, TraffMonetizer, EarnFM, PacketStream)
# Features:
#   - 参数默认为空，支持命令行选项 (-m, -k, -c, -t, -e) 与环境变量传入
#   - 传入对应凭证自动启动对应节点，未传参节点自动跳过
#   - 自动检测并安装 Docker 环境
#   - PacketStream (psclient) 自动进行 15 秒 IP 兼容性探测（机房/数据中心 IP 自动清理卸载）
#   - 自动关联配置 Watchtower 定时更新仅针对已成功运行的容器
# Usage:
#   curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/nodes.sh | bash -s -- [options]
# ==============================================================================

set -e

# ==================== 默认参数 (默认为空，调用时传入) ====================
RP_EMAIL="${RP_EMAIL:-}"
RP_API_KEY="${RP_API_KEY:-}"
PS_CID="${PS_CID:-}"
TM_TOKEN="${TM_TOKEN:-}"
EARNFM_TOKEN="${EARNFM_TOKEN:-}"
# ========================================================================

# 终端彩色高亮
C_RESET="\033[0m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_CYAN="\033[36m"
C_BOLD="\033[1m"

show_help() {
    echo -e "${C_BOLD}==============================================================================${C_RESET}"
    echo -e "                ${C_CYAN}流量挂机容器一键管理脚本 (nodes.sh)${C_RESET}"
    echo -e "${C_BOLD}==============================================================================${C_RESET}"
    echo -e "使用方法:"
    echo -e "  bash nodes.sh [选项]"
    echo -e "  或"
    echo -e "  curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/nodes.sh | bash -s -- [选项]"
    echo ""
    echo -e "${C_YELLOW}命令行参数说明 (所有参数默认为空，按需提供；提供对应参数即启动对应服务):${C_RESET}"
    echo -e "  ${C_GREEN}-m, --rp-email <邮箱>${C_RESET}       Repocket 注册邮箱"
    echo -e "  ${C_GREEN}-k, --rp-key <API密钥>${C_RESET}      Repocket API Key (需与邮箱同时提供)"
    echo -e "  ${C_GREEN}-t, --tm-token <Token>${C_RESET}      TraffMonetizer Application Token"
    echo -e "  ${C_GREEN}-e, --earnfm-token <Token>${C_RESET}  EarnFM API Token"
    echo -e "  ${C_GREEN}-c, --ps-cid <CID>${C_RESET}          PacketStream CID (会自动检测是否支持当前 IP)"
    echo -e "  ${C_GREEN}-h, --help${C_RESET}                  显示本帮助文档"
    echo ""
    echo -e "${C_YELLOW}调用示例:${C_RESET}"
    echo -e "  # 1. 启动所有支持的节点:"
    echo -e "  bash nodes.sh -m user@example.com -k 'RP_KEY' -t 'TM_TOKEN' -e 'EARN_TOKEN' -c '6WQA'"
    echo ""
    echo -e "  # 2. 仅启动部分节点 (例如仅 TraffMonetizer 与 EarnFM):"
    echo -e "  bash nodes.sh -t 'TM_TOKEN' -e 'EARN_TOKEN'"
    echo -e "${C_BOLD}==============================================================================${C_RESET}"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--rp-email)
            RP_EMAIL="$2"
            shift 2
            ;;
        -k|--rp-key)
            RP_API_KEY="$2"
            shift 2
            ;;
        -t|--tm-token)
            TM_TOKEN="$2"
            shift 2
            ;;
        -e|--earnfm-token)
            EARNFM_TOKEN="$2"
            shift 2
            ;;
        -c|--ps-cid)
            PS_CID="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${C_RED}[-] 未知参数: $1${C_RESET}"
            show_help
            ;;
    esac
done

echo -e "${C_BOLD}======================================================${C_RESET}"
echo -e "             ${C_CYAN}流量挂机容器一键管理脚本${C_RESET}                 "
echo -e "${C_BOLD}======================================================${C_RESET}"

# 校验是否至少提供了一个有效的服务参数
if [ -z "$RP_EMAIL" ] && [ -z "$RP_API_KEY" ] && [ -z "$TM_TOKEN" ] && [ -z "$EARNFM_TOKEN" ] && [ -z "$PS_CID" ]; then
    echo -e "${C_YELLOW}[!] 警告: 未提供任何挂机服务凭据参数！${C_RESET}"
    echo -e "请通过命令行参数传入对应服务 Token / CID。"
    echo ""
    show_help
fi

# 1. 检查并安装 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${C_YELLOW}[*] 未检测到 Docker，正在安装 Docker 环境...${C_RESET}"
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
else
    echo -e "${C_GREEN}[+] Docker 环境已就绪${C_RESET}"
fi

# 2. 清理历史旧容器，确保干净启动
echo -e "${C_YELLOW}[*] 清理同名旧容器...${C_RESET}"
for container in repocket psclient tm earnfm-client watchtower; do
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${container}\$"; then
        docker rm -f "$container" >/dev/null 2>&1 || true
    fi
done

ACTIVE_CONTAINERS=()

# 3. 启动 Repocket (需要 Email 和 API Key)
if [ -n "$RP_EMAIL" ] && [ -n "$RP_API_KEY" ]; then
    echo -e "${C_GREEN}[+] 启动 repocket (Repocket)...${C_RESET}"
    docker run -d \
      --name repocket \
      --restart=always \
      -e RP_EMAIL="$RP_EMAIL" \
      -e RP_API_KEY="$RP_API_KEY" \
      repocket/repocket:latest >/dev/null
    ACTIVE_CONTAINERS+=("repocket")
elif [ -n "$RP_EMAIL" ] || [ -n "$RP_API_KEY" ]; then
    echo -e "${C_RED}[!] 跳过 repocket: 必须同时提供 --rp-email 与 --rp-key${C_RESET}"
else
    echo -e "${C_CYAN}[i] 未配置 Repocket 凭据，已跳过${C_RESET}"
fi

# 4. 启动 TraffMonetizer
if [ -n "$TM_TOKEN" ]; then
    echo -e "${C_GREEN}[+] 启动 tm (TraffMonetizer)...${C_RESET}"
    docker run -d \
      --name tm \
      --restart=always \
      traffmonetizer/cli_v2:latest start accept --token "$TM_TOKEN" >/dev/null
    ACTIVE_CONTAINERS+=("tm")
else
    echo -e "${C_CYAN}[i] 未配置 TraffMonetizer Token，已跳过${C_RESET}"
fi

# 5. 启动 EarnFM
if [ -n "$EARNFM_TOKEN" ]; then
    echo -e "${C_GREEN}[+] 启动 earnfm-client (EarnFM)...${C_RESET}"
    docker run -d \
      --name earnfm-client \
      --restart=always \
      -e EARNFM_TOKEN="$EARNFM_TOKEN" \
      earnfm/earnfm-client:latest >/dev/null
    ACTIVE_CONTAINERS+=("earnfm-client")
else
    echo -e "${C_CYAN}[i] 未配置 EarnFM Token，已跳过${C_RESET}"
fi

# 6. 启动并检测 psclient (PacketStream) IP 兼容性
if [ -n "$PS_CID" ]; then
    echo -e "${C_GREEN}[+] 启动 psclient (PacketStream)...${C_RESET}"
    docker run -d \
      --name psclient \
      --restart=always \
      -e CID="$PS_CID" \
      packetstream/psclient:latest >/dev/null

    echo -e "${C_YELLOW}[*] 正在检测当前 IP 是否受 PacketStream 支持（等待 15 秒）...${C_RESET}"
    sleep 15

    # 获取 psclient 当前状态及最新日志
    PS_STATUS=$(docker inspect -f '{{.State.Status}}' psclient 2>/dev/null || echo "not_found")
    PS_LOGS=$(docker logs --tail 30 psclient 2>&1 || true)

    # 判断条件：容器非 running、处于 restarting 循环、或者日志明确出现 IP 不受支持/机房 IP 拦截关键字
    IP_NOT_SUPPORTED=false
    if [ "$PS_STATUS" != "running" ]; then
        IP_NOT_SUPPORTED=true
    elif echo "$PS_LOGS" | grep -Ei "(not supported|unsupported|datacenter|invalid ip|blocked|banned|failed to connect)" >/dev/null 2>&1; then
        IP_NOT_SUPPORTED=true
    fi

    if [ "$IP_NOT_SUPPORTED" = true ]; then
        echo -e "${C_RED}------------------------------------------------------${C_RESET}"
        echo -e "${C_RED}[!] 警告：当前 IP 不支持 PacketStream（机房/非住宅 IP 或连接被拒）！${C_RESET}"
        echo -e "[*] 日志片段："
        echo "$PS_LOGS" | head -n 5
        echo -e "[*] 正在卸载 psclient 容器..."
        docker rm -f psclient >/dev/null 2>&1 || true
        echo -e "${C_GREEN}[✓] psclient 已成功卸载，保留其他支持该 IP 的节点。${C_RESET}"
        echo -e "${C_RED}------------------------------------------------------${C_RESET}"
    else
        echo -e "${C_GREEN}[✓] PacketStream (psclient) 握手成功，当前 IP 受到支持！${C_RESET}"
        ACTIVE_CONTAINERS+=("psclient")
    fi
else
    echo -e "${C_CYAN}[i] 未配置 PacketStream CID，已跳过${C_RESET}"
fi

# 7. 配置最新版 Watchtower 自动定时更新已激活容器
if [ ${#ACTIVE_CONTAINERS[@]} -gt 0 ]; then
    echo -e "${C_YELLOW}[*] 配置最新版 Watchtower 定时自动更新 (监控: ${ACTIVE_CONTAINERS[*]})...${C_RESET}"
    docker pull containrrr/watchtower:latest >/dev/null 2>&1 || true

    # 使用 Watchtower 官方最新环境变量配置：
    # - WATCHTOWER_CLEANUP: 更新后自动清理无用的旧镜像
    # - WATCHTOWER_SCHEDULE: 每天凌晨 03:00 检查更新 (cron 表达式)
    # - TZ: 保持本地时区一致
    docker run -d \
      --name watchtower \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e TZ="Asia/Shanghai" \
      -e WATCHTOWER_CLEANUP=true \
      -e WATCHTOWER_SCHEDULE="0 0 3 * * *" \
      containrrr/watchtower:latest \
      "${ACTIVE_CONTAINERS[@]}" >/dev/null
else
    echo -e "${C_YELLOW}[!] 没有成功运行的挂机节点，跳过配置 Watchtower。${C_RESET}"
fi

echo -e "${C_BOLD}======================================================${C_RESET}"
echo -e "${C_GREEN}[✓] 全部服务处理完成！当前运行的容器列表：${C_RESET}"
echo -e "${C_BOLD}======================================================${C_RESET}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
