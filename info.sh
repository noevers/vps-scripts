#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件概况 / 内存频率 / 硬盘SMART健康度与TBW / YABS标准双向测速)
# Usage: curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash
# ==============================================================================

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_RESET="\033[0m"

# 1. 忽略旧源过期检测，静默确保 smartctl 和 iperf3 存在
if command -v apt-get >/dev/null 2>&1; then
    echo 'Acquire::Check-Valid-Until "0";' > /etc/apt/apt.conf.d/99no-check-valid-until 2>/dev/null || true
    if ! command -v smartctl >/dev/null 2>&1 || ! command -v iperf3 >/dev/null 2>&1; then
        apt-get update -o Acquire::Check-Valid-Until=false -y >/dev/null 2>&1 || true
        apt-get install -y smartmontools iperf3 >/dev/null 2>&1 || true
    fi
fi

# 若无 iperf3，自动拉取独立静态二进制 (YABS 官方 binary)
IPERF_CMD="iperf3"
if ! command -v iperf3 >/dev/null 2>&1; then
    curl -sLo /tmp/iperf3 https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/iperf/iperf3_x64 || true
    chmod +x /tmp/iperf3 2>/dev/null || true
    [ -f /tmp/iperf3 ] && IPERF_CMD="/tmp/iperf3"
fi

echo -e "${C_CYAN}==============================================================================${C_RESET}"
echo -e "${C_GREEN}            VPS / 救援模式 硬件信息 / 硬盘健康度 / YABS 网络双向测速            ${C_RESET}"
echo -e "${C_CYAN}==============================================================================${C_RESET}"

# CPU & 架构
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
CPU_CORES=$(grep -c 'processor' /proc/cpuinfo)
CPU_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F: '{print $2}' | awk '{printf "%.2f MHz", $1}')
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk '{printf("%d天 %d小时 %d分钟",($1/60/60/24),($1/60/60%24),($1/60%60))}' /proc/uptime)

# 内存 & 频率
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
MEM_FREQ=$(dmidecode -t memory 2>/dev/null | grep -i "Speed:" | grep -iv "Unknown" | head -n 1 | awk -F: '{print $2}' | sed 's/^[ \t]*//' || true)
MEM_TYPE=$(dmidecode -t memory 2>/dev/null | grep -i "Type:" | grep -iv "Unknown" | head -n 1 | awk -F: '{print $2}' | sed 's/^[ \t]*//' || true)
[ -z "$MEM_FREQ" ] && MEM_FREQ="未知"
[ -z "$MEM_TYPE" ] && MEM_TYPE="RAM"

# 网络
IPV4=$(curl -s4m 3 https://api.ip.sb/ip || curl -s4m 3 https://ifconfig.me || echo "无 / 未分配")
IPV6=$(curl -s6m 3 https://api.ip.sb/ip || echo "无 / 未分配")
ISP=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"isp":"[^"]*' | cut -d'"' -f4 || echo "未知")
ASN=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"asn_organization":"[^"]*' | cut -d'"' -f4 || echo "未知")
LOCATION=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"country":"[^"]*' | cut -d'"' -f4 || echo "未知")

VIRT="物理机 (Dedicated / Bare Metal)"
if command -v systemd-detect-virt >/dev/null 2>&1; then
    DETECTED_VIRT=$(systemd-detect-virt 2>/dev/null || true)
    [ -n "$DETECTED_VIRT" ] && [ "$DETECTED_VIRT" != "none" ] && VIRT="$DETECTED_VIRT"
fi

echo -e "${C_YELLOW}[ 基础硬件与系统架构 ]${C_RESET}"
echo -e " CPU 型号       : ${C_CYAN}${CPU_MODEL}${C_RESET}"
echo -e " 核心总数       : ${C_CYAN}${CPU_CORES} 核心 (${ARCH})${C_RESET}"
echo -e " CPU 主频       : ${C_CYAN}${CPU_FREQ}${C_RESET}"
echo -e " 物理内存       : ${C_CYAN}${MEM_USED} MB / ${MEM_TOTAL} MB (${MEM_TYPE} @ ${MEM_FREQ})${C_RESET}"
echo -e " 虚拟内存       : ${C_CYAN}${SWAP_TOTAL} MB${C_RESET}"
echo -e " 虚拟化架构     : ${C_CYAN}${VIRT}${C_RESET}"
echo -e " 系统内核       : ${C_CYAN}${KERNEL}${C_RESET}"
echo -e " 运行时间       : ${C_CYAN}${UPTIME}${C_RESET}"
echo ""

echo -e "${C_YELLOW}[ 网络与地理位置 ]${C_RESET}"
echo -e " IPv4 地址      : ${C_CYAN}${IPV4}${C_RESET}"
echo -e " IPv6 地址      : ${C_CYAN}${IPV6}${C_RESET}"
echo -e " 运营商 (ISP)   : ${C_CYAN}${ISP} (${ASN})${C_RESET}"
echo -e " 所在区域       : ${C_CYAN}${LOCATION}${C_RESET}"
echo ""

echo -e "${C_YELLOW}[ 硬盘 SMART 健康度与终生累计读写 (TBW) ]${C_RESET}"
DISKS=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1!~/^(ram|loop)/ {print $1}')

for d in $DISKS; do
    DEV="/dev/$d"
    MODEL=$(lsblk -d -n -o MODEL "$DEV" 2>/dev/null | sed 's/^[ \t]*//' || echo "$d")
    SIZE=$(lsblk -d -n -o SIZE "$DEV" 2>/dev/null || echo "未知")
    echo -e " 硬盘设备       : ${C_CYAN}${DEV} (${MODEL} - ${SIZE})${C_RESET}"
    
    if command -v smartctl >/dev/null 2>&1; then
        SMART_INFO=$(smartctl -a "$DEV" 2>/dev/null || true)
        
        # 1. 硬盘健康度 (Health / Wearout Percentage)
        HEALTH_STATUS="100%"
        PERCENT_USED=$(echo "$SMART_INFO" | grep -i "Percentage Used:" | awk '{print $NF}' | tr -d '%' || true)
        if [ -n "$PERCENT_USED" ] && [ "$PERCENT_USED" -ge 0 ] 2>/dev/null; then
            REMAINING=$((100 - PERCENT_USED))
            [ $REMAINING -lt 0 ] && REMAINING=0
            HEALTH_STATUS="${REMAINING}% (已磨损 ${PERCENT_USED}%)"
        else
            WEAR_INDICATOR=$(echo "$SMART_INFO" | grep -E "Media_Wearout_Indicator|Wear_Range_Delta|Remaining_Lifetime_Perc|SSD_Life_Left" | awk '{print $4}' | head -n 1 || true)
            if [ -n "$WEAR_INDICATOR" ] && [ "$WEAR_INDICATOR" -gt 0 ] 2>/dev/null; then
                HEALTH_STATUS="${WEAR_INDICATOR}%"
            elif echo "$SMART_INFO" | grep -q "SMART overall-health self-assessment test result: PASSED"; then
                HEALTH_STATUS="100% (SMART PASSED 良好)"
            fi
        fi
        echo -e "   - 硬盘健康度  : ${C_GREEN}${HEALTH_STATUS}${C_RESET}"

        # 2. 通电时间
        HOURS=$(echo "$SMART_INFO" | grep -i "Power_On_Hours" | awk '{print $NF}' || true)
        [ -z "$HOURS" ] && HOURS=$(echo "$SMART_INFO" | grep -i "Power On Hours:" | awk '{print $NF}' | tr -d ',' || true)
        if [ -n "$HOURS" ] && [ "$HOURS" -gt 0 ] 2>/dev/null; then
            DAYS=$(awk -v h="$HOURS" 'BEGIN {printf "%.1f", h/24}')
            echo -e "   - 通电时间    : ${C_GREEN}${HOURS} 小时 (约 ${DAYS} 天)${C_RESET}"
        fi
        
        # 3. 通电次数
        COUNT=$(echo "$SMART_INFO" | grep -i "Power_Cycle_Count" | awk '{print $NF}' || true)
        [ -z "$COUNT" ] && COUNT=$(echo "$SMART_INFO" | grep -i "Power Cycles:" | awk '{print $NF}' | tr -d ',' || true)
        [ -n "$COUNT" ] && echo -e "   - 通电次数    : ${C_GREEN}${COUNT} 次${C_RESET}"
        
        # 4. 终生累计写入量 (TBW)
        NVME_WRITE=$(echo "$SMART_INFO" | grep -i "Data Units Written:" | awk '{print $4}' | tr -d ',' || true)
        if [ -n "$NVME_WRITE" ]; then
            TBW=$(awk -v w="$NVME_WRITE" 'BEGIN {printf "%.2f", (w*512*1000)/1000/1000/1000/1000}')
            echo -e "   - 终生总写入  : ${C_GREEN}${TBW} TB (TBW)${C_RESET}"
        else
            LBA_W=$(echo "$SMART_INFO" | grep -E "Total_LBAs_Written|Host_Writes_GiB|Host_Writes" | awk '{print $NF}' || true)
            if [ -n "$LBA_W" ] && [ "$LBA_W" -gt 0 ] 2>/dev/null; then
                if echo "$MODEL" | grep -qi "Micron"; then
                    TBW=$(awk -v lba="$LBA_W" 'BEGIN {printf "%.2f", (lba*32)/1024/1024}')
                else
                    TBW=$(awk -v lba="$LBA_W" 'BEGIN {printf "%.2f", (lba*512)/1024/1024/1024/1024}')
                fi
                echo -e "   - 终生总写入  : ${C_GREEN}${TBW} TB (TBW)${C_RESET}"
            fi
        fi
        
        # 5. 终生累计读取量
        NVME_READ=$(echo "$SMART_INFO" | grep -i "Data Units Read:" | awk '{print $4}' | tr -d ',' || true)
        if [ -n "$NVME_READ" ]; then
            TBR=$(awk -v r="$NVME_READ" 'BEGIN {printf "%.2f", (r*512*1000)/1000/1000/1000/1000}')
            echo -e "   - 终生总读取  : ${C_GREEN}${TBR} TB${C_RESET}"
        fi
    fi
    echo ""
done

# 磁盘 I/O 测试
echo -e "${C_YELLOW}[ 磁盘 I/O 顺序写入性能测试 ]${C_RESET}"
TEST_TARGET="/tmp/io_test_file"
[ -d "/root" ] && TEST_TARGET="/root/io_test_file"
IO_SPEED=$(dd if=/dev/zero of=${TEST_TARGET} bs=64k count=16k conv=fdatasync 2>&1 | awk -F, 'END {print $NF}' | sed 's/^[ \t]*//')
rm -f ${TEST_TARGET}
echo -e " 1GB 顺序写入速率: ${C_GREEN}${IO_SPEED}${C_RESET}"
echo ""

# YABS 官方多节点 iperf3 测速模块 (1:1 原版逻辑)
echo -e "${C_YELLOW}[ 全球节点上传与下载双向测速 (YABS 官方 iperf3 测速矩阵) ]${C_RESET}"
echo -e "----------------------------------------------------------------------------------"
printf "%-16s | %-24s | %-16s | %-16s | %-10s\n" "提供商" "所在区域" "发送/上传速率" "接收/下载速率" "网络延迟"
echo -e "----------------------------------------------------------------------------------"

yabs_iperf() {
    local host="$1"
    local port_range="$2"
    local provider="$3"
    local location="$4"

    local start_p=$(echo "$port_range" | awk -F- '{print $1}')
    local end_p=$(echo "$port_range" | awk -F- '{print $2}')
    [ -z "$end_p" ] && end_p=$start_p

    local ping_ms=$(ping -c 2 -W 2 "$host" 2>/dev/null | awk -F'/' 'END {if (NF>4) printf "%.1f ms", $5; else echo "超时"}')
    [ -z "$ping_ms" ] && ping_ms="N/A"

    # 上传 (Send)
    local send_res="繁忙/不可达"
    for try in 1 2 3; do
        local port=$(( start_p + RANDOM % (end_p - start_p + 1) ))
        local run_send=$(timeout 10 $IPERF_CMD -c "$host" -p "$port" -P 4 2>/dev/null || true)
        if echo "$run_send" | grep -q "receiver"; then
            send_res=$(echo "$run_send" | grep "SUM" | grep "receiver" | awk '{printf "%.2f %s", $6, $7}')
            [ -n "$send_res" ] && break
        elif echo "$run_send" | grep -q "0.00-"; then
            send_res=$(echo "$run_send" | tail -n 3 | awk '{printf "%.2f %s", $7, $8}' | head -n 1)
            [ -n "$send_res" ] && break
        fi
    done

    # 下载 (Receive, -R)
    local recv_res="繁忙/不可达"
    for try in 1 2 3; do
        local port=$(( start_p + RANDOM % (end_p - start_p + 1) ))
        local run_recv=$(timeout 10 $IPERF_CMD -c "$host" -p "$port" -P 4 -R 2>/dev/null || true)
        if echo "$run_recv" | grep -q "sender"; then
            recv_res=$(echo "$run_recv" | grep "SUM" | grep "sender" | awk '{printf "%.2f %s", $6, $7}')
            [ -n "$recv_res" ] && break
        elif echo "$run_recv" | grep -q "0.00-"; then
            recv_res=$(echo "$run_recv" | tail -n 3 | awk '{printf "%.2f %s", $7, $8}' | head -n 1)
            [ -n "$recv_res" ] && break
        fi
    done

    printf "%-16s | %-24s | %-16s | %-16s | %-10s\n" "$provider" "$location" "$send_res" "$recv_res" "$ping_ms"
}

yabs_iperf "lon.speedtest.clouvider.net" "5200-5209" "Clouvider" "英国 伦敦 (10G)"
yabs_iperf "iperf-ams-nl.eranium.net" "5201-5210" "Eranium" "荷兰 阿姆斯特丹 (100G)"
yabs_iperf "speedtest.sin1.sg.leaseweb.net" "5201-5210" "Leaseweb" "新加坡 (10G)"
yabs_iperf "la.speedtest.clouvider.net" "5200-5209" "Clouvider" "美国 洛杉矶 (10G)"
yabs_iperf "speedtest.nyc1.us.leaseweb.net" "5201-5210" "Leaseweb" "美国 纽约 (10G)"
yabs_iperf "speedtest.sao1.edgoo.net" "9204-9240" "Edgoo" "巴西 圣保罗 (1G)"

echo -e "----------------------------------------------------------------------------------"
echo -e "${C_GREEN}测试完成！${C_RESET}"
