#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件概况 / 硬盘SMART通电与读写量 / YABS 经典多节点 iperf3 上下行双向测速)
# Usage: curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash
# ==============================================================================
set -e

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_RESET="\033[0m"

echo -e "${C_CYAN}==============================================================================${C_RESET}"
echo -e "${C_GREEN}         VPS / 救援模式 硬件信息、硬盘健康与 YABS 标准网络测速          ${C_RESET}"
echo -e "${C_CYAN}==============================================================================${C_RESET}"

# 1. 基础系统与处理器信息
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | sed -e 's/^[ \t]*//' || echo "未知")
CPU_CORES=$(grep -c 'processor' /proc/cpuinfo 2>/dev/null || echo "1")
CPU_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | awk '{printf "%.2f MHz", $1}' || echo "未知")
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk '{printf("%d天 %d小时 %d分钟",($1/60/60/24),($1/60/60%24),($1/60%60))}' /proc/uptime 2>/dev/null || echo "未知")
MEM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0")
MEM_USED=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}' || echo "0")
SWAP_TOTAL=$(free -m 2>/dev/null | awk '/Swap:/ {print $2}' || echo "0")

# 2. 网络与地理位置
IPV4=$(curl -s4m 3 https://api.ip.sb/ip || curl -s4m 3 https://ifconfig.me || echo "无 / 未分配")
IPV6=$(curl -s6m 3 https://api.ip.sb/ip || echo "无 / 未分配")
ISP=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"isp":"[^"]*' | cut -d'"' -f4 || echo "未知")
LOCATION=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"country":"[^"]*' | cut -d'"' -f4 || echo "未知")

echo -e "${C_YELLOW}[ 基础硬件与系统架构 ]${C_RESET}"
echo -e " CPU 型号       : ${C_CYAN}${CPU_MODEL}${C_RESET}"
echo -e " 核心总数       : ${C_CYAN}${CPU_CORES} 核心 (${ARCH})${C_RESET}"
echo -e " CPU 主频       : ${C_CYAN}${CPU_FREQ}${C_RESET}"
echo -e " 物理内存       : ${C_CYAN}${MEM_USED} MB / ${MEM_TOTAL} MB${C_RESET}"
echo -e " 虚拟内存       : ${C_CYAN}${SWAP_TOTAL} MB${C_RESET}"
echo -e " 系统内核       : ${C_CYAN}${KERNEL}${C_RESET}"
echo -e " 运行时间       : ${C_CYAN}${UPTIME}${C_RESET}"
echo ""
echo -e "${C_YELLOW}[ 网络与地理位置 ]${C_RESET}"
echo -e " IPv4 地址      : ${C_CYAN}${IPV4}${C_RESET}"
echo -e " IPv6 地址      : ${C_CYAN}${IPV6}${C_RESET}"
echo -e " 运营商 (ISP)   : ${C_CYAN}${ISP}${C_RESET}"
echo -e " 所在区域       : ${C_CYAN}${LOCATION}${C_RESET}"
echo ""

# 3. 硬盘 SMART 健康信息（通电时间 / 累计读写量）
echo -e "${C_YELLOW}[ 硬盘 SMART 状态与累计读写量 ]${C_RESET}"
if ! command -v smartctl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq smartmontools >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q smartmontools >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache smartmontools >/dev/null 2>&1 || true
    fi
fi

DISKS=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}' || echo "sda")
FOUND_SMART=false

for d in $DISKS; do
    DEV="/dev/$d"
    if [ -b "$DEV" ] && command -v smartctl >/dev/null 2>&1; then
        SMART_INFO=$(smartctl -a "$DEV" 2>/dev/null || true)
        if echo "$SMART_INFO" | grep -qE "Power_On_Hours|Power_On_Time|Data Units Written|Data Units Read"; then
            FOUND_SMART=true
            echo -e " 盘符: ${C_GREEN}${DEV}${C_RESET}"
            POWER_ON=$(echo "$SMART_INFO" | awk '/Power_On_Hours|Power_On_Time/ {print $10}' | head -n1)
            [ -z "$POWER_ON" ] && POWER_ON=$(echo "$SMART_INFO" | grep -i "Power On Hours:" | awk -F: '{print $2}' | tr -d ' ')
            if [ -n "$POWER_ON" ]; then
                DAYS=$(awk -v h="$POWER_ON" 'BEGIN {printf "%.1f", h/24}')
                echo -e " - 通电时间     : ${C_CYAN}${POWER_ON} 小时 (约 ${DAYS} 天)${C_RESET}"
            fi
            POWER_COUNT=$(echo "$SMART_INFO" | awk '/Power_Cycle_Count/ {print $10}' | head -n1)
            [ -z "$POWER_COUNT" ] && POWER_COUNT=$(echo "$SMART_INFO" | grep -i "Power Cycles:" | awk -F: '{print $2}' | tr -d ' ')
            [ -n "$POWER_COUNT" ] && echo -e " - 通电次数     : ${C_CYAN}${POWER_COUNT} 次${C_RESET}"
            WRITTEN_UNITS=$(echo "$SMART_INFO" | grep -i "Data Units Written:" | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',')
            if [ -n "$WRITTEN_UNITS" ]; then
                WRITTEN_TB=$(awk -v u="$WRITTEN_UNITS" 'BEGIN {printf "%.2f", (u * 512 * 1000) / (1024*1024*1024*1024)}')
                echo -e " - 累计写入量   : ${C_CYAN}${WRITTEN_TB} TB${C_RESET}"
            fi
            READ_UNITS=$(echo "$SMART_INFO" | grep -i "Data Units Read:" | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',')
            if [ -n "$READ_UNITS" ]; then
                READ_TB=$(awk -v u="$READ_UNITS" 'BEGIN {printf "%.2f", (u * 512 * 1000) / (1024*1024*1024*1024)}')
                echo -e " - 累计读取量   : ${C_CYAN}${READ_TB} TB${C_RESET}"
            fi
        fi
    fi
done

if [ "$FOUND_SMART" = false ]; then
    echo -e " ${C_YELLOW}当前为虚拟磁盘 (KVM/QEMU Disk) 或云厂商禁用了物理 SMART 直通，无底层通电记录。${C_RESET}"
fi
echo ""

# 4. 磁盘 I/O 顺序写入性能测试
echo -e "${C_YELLOW}[ 磁盘 I/O 顺序写入性能测试 ]${C_RESET}"
TEST_TARGET="/tmp/io_test_file"
IO_SPEED=$(dd if=/dev/zero of=${TEST_TARGET} bs=64k count=16k conv=fdatasync 2>&1 | awk -F, '{print $NF}' | sed 's/^[ \t]*//')
rm -f ${TEST_TARGET}
echo -e " 1GB 顺序写入速率: ${C_GREEN}${IO_SPEED}${C_RESET}"
echo ""

# 5. YABS 经典标准：iperf3 全球节点上传与下载双向测速
echo -e "${C_YELLOW}[ YABS 经典标准：全球节点上下行双向测速 (iperf3) ]${C_RESET}"

# 确保环境有 iperf3 (优先使用独立免依赖二进制)
IPERF_BIN="/tmp/iperf3"
if ! command -v iperf3 >/dev/null 2>&1 && [ ! -f "$IPERF_BIN" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        curl -sL "https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/iperf3_x86" -o "$IPERF_BIN" && chmod +x "$IPERF_BIN" 2>/dev/null || true
    elif [ "$ARCH" = "aarch64" ]; then
        curl -sL "https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/iperf3_arm" -o "$IPERF_BIN" && chmod +x "$IPERF_BIN" 2>/dev/null || true
    fi
fi
[ -x "$IPERF_BIN" ] && IPERF_CMD="$IPERF_BIN" || IPERF_CMD="iperf3"

echo -e "----------------------------------------------------------------------------------"
printf "%-18s %-20s %-14s %-14s %-10s\n" "测试节点" "所在区域" "发送 (上传)" "接收 (下载)" "延迟"
echo -e "----------------------------------------------------------------------------------"

test_yabs_node() {
    local provider="$1"
    local loc="$2"
    local host="$3"
    local port="$4"
    local flags="$5"

    local ping_val=$(ping -c 2 -W 2 "$host" 2>/dev/null | awk -F"/" 'END {if (NF>4) printf "%.1f ms", $5; else echo "超时"}')
    [ -z "$ping_val" ] && ping_val="N/A"

    if ! command -v "$IPERF_CMD" >/dev/null 2>&1 && [ ! -x "$IPERF_BIN" ]; then
        printf "%-18s %-20s %-14s %-14s %-10s\n" "$provider" "$loc" "环境无iperf3" "环境无iperf3" "$ping_val"
        return
    fi

    # 测试上传 (Client -> Server)
    local up_json=$($IPERF_CMD -c "$host" -p "$port" -t 5 -P 2 -J $flags 2>/dev/null || true)
    local up_speed=$(echo "$up_json" | grep -o '"bits_per_second":[^,]*' | tail -n1 | awk -F: '{print $2}' || echo "0")
    local up_mbps="繁忙/失败"
    if [ -n "$up_speed" ] && [ "$up_speed" != "0" ]; then
        up_mbps=$(awk -v s="$up_speed" 'BEGIN {printf "%.2f Mbps", s/1000/1000}')
    fi

    # 测试下载 (Server -> Client 反向模式 -R)
    local down_json=$($IPERF_CMD -c "$host" -p "$port" -t 5 -P 2 -R -J $flags 2>/dev/null || true)
    local down_speed=$(echo "$down_json" | grep -o '"bits_per_second":[^,]*' | tail -n1 | awk -F: '{print $2}' || echo "0")
    local down_mbps="繁忙/失败"
    if [ -n "$down_speed" ] && [ "$down_speed" != "0" ]; then
        down_mbps=$(awk -v s="$down_speed" 'BEGIN {printf "%.2f Mbps", s/1000/1000}')
    fi

    printf "%-18s %-20s %-14s %-14s %-10s\n" "$provider" "$loc" "$up_mbps" "$down_mbps" "$ping_val"
}

# 经典的 YABS 测速服务器节点列表 (亚太、北美、欧洲)
test_yabs_node "Clouvider"     "英国 伦敦"        "lon.speedtest.clouvider.net" "5201" ""
test_yabs_node "Clouvider"     "德国 法兰克福"    "fra.speedtest.clouvider.net" "5201" ""
test_yabs_node "Clouvider"     "美国 纽约"        "nyc.speedtest.clouvider.net" "5201" ""
test_yabs_node "Clouvider"     "美国 洛杉矶"      "la.speedtest.clouvider.net"  "5201" ""
test_yabs_node "fdcservers"    "日本 东京"        "lg-tok.fdcservers.net"       "5201" ""
test_yabs_node "fdcservers"    "新加坡"          "lg-sin.fdcservers.net"       "5201" ""
test_yabs_node "Online.net"    "法国 巴黎"        "ping.online.net"             "5201" ""

echo -e "----------------------------------------------------------------------------------"
echo -e "${C_GREEN}====================== 全部测试流程已顺利完成 ======================${C_RESET}"
