#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件概况 / 硬盘SMART通电与读写量 / Geekbench 5 / 上传下载双向测速)
# ==============================================================================
set -e

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_RESET="\033[0m"

echo -e "${C_CYAN}==============================================================================${C_RESET}"
echo -e "${C_GREEN}            VPS / 救援模式 硬件信息、硬盘健康、GB5 与双向带宽测试            ${C_RESET}"
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
            # 通电时间
            POWER_ON=$(echo "$SMART_INFO" | awk '/Power_On_Hours|Power_On_Time/ {print $10}' | head -n1)
            [ -z "$POWER_ON" ] && POWER_ON=$(echo "$SMART_INFO" | grep -i "Power On Hours:" | awk -F: '{print $2}' | tr -d ' ')
            if [ -n "$POWER_ON" ]; then
                DAYS=$(awk -v h="$POWER_ON" 'BEGIN {printf "%.1f", h/24}')
                echo -e " - 通电时间     : ${C_CYAN}${POWER_ON} 小时 (约 ${DAYS} 天)${C_RESET}"
            fi
            # 通电次数
            POWER_COUNT=$(echo "$SMART_INFO" | awk '/Power_Cycle_Count/ {print $10}' | head -n1)
            [ -z "$POWER_COUNT" ] && POWER_COUNT=$(echo "$SMART_INFO" | grep -i "Power Cycles:" | awk -F: '{print $2}' | tr -d ' ')
            [ -n "$POWER_COUNT" ] && echo -e " - 通电次数     : ${C_CYAN}${POWER_COUNT} 次${C_RESET}"
            # 读写量 (NVMe / SSD)
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
            # 传统 SATA 写入统计 (LBAs Written)
            LBA_W=$(echo "$SMART_INFO" | awk '/Total_LBAs_Written/ {print $10}' | head -n1)
            if [ -n "$LBA_W" ]; then
                LBA_TB=$(awk -v l="$LBA_W" 'BEGIN {printf "%.2f", (l * 512) / (1024*1024*1024*1024)}')
                echo -e " - 累计写入量   : ${C_CYAN}${LBA_TB} TB${C_RESET}"
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

# 5. 上传与下载 双向带宽测速 (集成 Ookla 官方独立客户端)
echo -e "${C_YELLOW}[ 全球节点上传与下载双向带宽测速 ]${C_RESET}"
if ! command -v speedtest >/dev/null 2>&1; then
    if [ "$ARCH" = "x86_64" ]; then SP_ARCH="x86_64"; elif [ "$ARCH" = "aarch64" ]; then SP_ARCH="aarch64"; elif [ "$ARCH" = "i386" ]; then SP_ARCH="i386"; else SP_ARCH="x86_64"; fi
    curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${SP_ARCH}.tgz" | tar -xz -C /tmp speedtest 2>/dev/null || true
fi

if [ -f /tmp/speedtest ]; then
    echo -e " 正在运行 Ookla 官方测速 (测量延迟 / 真实下载 / 真实上传)..."
    /tmp/speedtest --accept-license --accept-gdpr -f human-readable 2>/dev/null | grep -E "Latency|Download|Upload|Packet Loss|Result URL" || echo "测速节点连接繁忙"
    rm -f /tmp/speedtest
else
    echo -e "------------------------------------------------------------------------------"
    printf "%-18s %-22s %-16s %-12s\n" "测试节点" "所在区域" "下载速度" "网络延迟"
    echo -e "------------------------------------------------------------------------------"
    test_speed() {
        local node_name="$1"; local region="$2"; local url="$3"
        local host=$(echo "$url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
        local ping_ms=$(ping -c 2 -W 2 "$host" 2>/dev/null | awk -F"/" 'END {if (NF>4) printf "%.1f ms", $5; else echo "超时"}')
        [ -z "$ping_ms" ] && ping_ms="N/A"
        local speed=$(curl -k -m 6 -sLo /dev/null -w "%{speed_download}" "$url" 2>/dev/null || echo 0)
        local speed_mbps=$(awk -v s="$speed" 'BEGIN {printf "%.2f Mbps", s*8/1024/1024}')
        printf "%-18s %-22s %-16s %-12s\n" "$node_name" "$region" "$speed_mbps" "$ping_ms"
    }
    test_speed "Cloudflare" "全球 CDN Anycast" "https://speed.cloudflare.com/__down?bytes=50000000"
    test_speed "Hetzner" "欧洲 (德国 纽伦堡)" "https://fsn1-speed.hetzner.com/100MB.bin"
    test_speed "Linode" "亚太 (日本 东京)" "http://speedtest.tokyo2.linode.com/100MB-tokyo2.bin"
    test_speed "Linode" "北美 (美国 弗里蒙特)" "http://speedtest.fremont.linode.com/100MB-fremont.bin"
    echo -e "------------------------------------------------------------------------------"
fi
echo ""

# 6. Geekbench 5 CPU 综合跑分测试 (采用 YABS / GB5 经典标准)
echo -e "${C_YELLOW}[ Geekbench 5 性能基准测试 (借用 YABS / GB5 引擎) ]${C_RESET}"
read -r -t 15 -p "是否运行 Geekbench 5 跑分测试？[y/N] (默认 15 秒后跳过): " RUN_GB5 || RUN_GB5="n"
if [[ "$RUN_GB5" =~ ^[Yy]$ ]]; then
    echo ">>> 正在准备 Geekbench 5 测试组件..."
    GB5_DIR="/tmp/geekbench5"
    rm -rf "$GB5_DIR" && mkdir -p "$GB5_DIR"
    if [ "$ARCH" = "x86_64" ]; then
        curl -sL "https://cdn.geekbench.com/Geekbench-5.5.1-Linux.tar.gz" | tar -xz -C "$GB5_DIR" --strip-components=1
    elif [ "$ARCH" = "aarch64" ]; then
        curl -sL "https://cdn.geekbench.com/Geekbench-5.5.1-LinuxARM.tar.gz" | tar -xz -C "$GB5_DIR" --strip-components=1
    fi
    if [ -f "$GB5_DIR/geekbench5" ]; then
        "$GB5_DIR/geekbench5" --upload 2>&1 | tee /tmp/gb5_result.log | grep -E "Single-Core Score|Multi-Core Score|https://browser.geekbench.com" || true
        rm -rf "$GB5_DIR"
    else
        echo "当前系统或架构不支持 Geekbench 5"
    fi
else
    echo "已跳过 Geekbench 5 测试。"
fi

echo ""
echo -e "${C_GREEN}====================== 全部测试流程已顺利完成 ======================${C_RESET}"
