#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件全貌 / 内存频率 / 硬盘SMART健康度与TBW/TBR / YABS原版IPv4与IPv6双栈测速)
# Usage: curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash
# ==============================================================================

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_RESET="\033[0m"

# 1. 忽略旧源过期检测，静默安装 smartctl
if command -v apt-get >/dev/null 2>&1; then
    echo 'Acquire::Check-Valid-Until "0";' > /etc/apt/apt.conf.d/99no-check-valid-until 2>/dev/null || true
    if ! command -v smartctl >/dev/null 2>&1; then
        apt-get update -o Acquire::Check-Valid-Until=false -y >/dev/null 2>&1 || true
        apt-get install -y smartmontools >/dev/null 2>&1 || true
    fi
fi

# 2. 准备 YABS 官方静态 iperf3
IPERF_CMD="iperf3"
mkdir -p /tmp/yabs_bin
if ! command -v iperf3 >/dev/null 2>&1; then
    curl -sLo /tmp/yabs_bin/iperf3 https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/iperf/iperf3_x64 || true
    chmod +x /tmp/yabs_bin/iperf3 2>/dev/null || true
    [ -f /tmp/yabs_bin/iperf3 ] && IPERF_CMD="/tmp/yabs_bin/iperf3"
fi

echo -e "${C_CYAN}==============================================================================${C_RESET}"
echo -e "${C_GREEN}            VPS / 救援模式 硬件信息 / 硬盘健康度 / YABS 双栈测速            ${C_RESET}"
echo -e "${C_CYAN}==============================================================================${C_RESET}"

# 3. 基础硬件与处理器信息
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep 'Model name' | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
CPU_CORES=$(grep -c 'processor' /proc/cpuinfo)
CPU_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F: '{print $2}' | awk '{printf "%.2f MHz", $1}')
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk '{printf("%d天 %d小时 %d分钟",($1/60/60/24),($1/60/60%24),($1/60%60))}' /proc/uptime)

# 4. 内存与物理频率
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
MEM_SPEED="未知 / 虚拟化未暴露"
if command -v dmidecode >/dev/null 2>&1; then
    SPEED_DETECT=$(dmidecode -t memory 2>/dev/null | grep -i "Speed:" | grep -v "Unknown" | head -n 1 | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
    TYPE_DETECT=$(dmidecode -t memory 2>/dev/null | grep -i "Type:" | grep -E "DDR[0-9]" | head -n 1 | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
    [ -n "$SPEED_DETECT" ] && MEM_SPEED="${TYPE_DETECT} ${SPEED_DETECT}"
fi

# 5. 网络与 IP 信息 (双栈自动探测)
IPV4_CHECK=$(curl -s4m 3 https://api.ip.sb/ip || curl -s4m 3 https://ifconfig.me || true)
IPV6_CHECK=$(curl -s6m 3 https://api.ip.sb/ip || true)
IPV4=${IPV4_CHECK:-"无 / 未分配"}
IPV6=${IPV6_CHECK:-"无 / 未分配"}
ISP=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"isp":"[^"]*' | cut -d'"' -f4 || echo "未知")
ASN=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"asn_organization":"[^"]*' | cut -d'"' -f4 || echo "未知")
LOCATION=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"country":"[^"]*' | cut -d'"' -f4 || echo "未知")

VIRT="物理机 (Dedicated / Bare Metal)"
if command -v systemd-detect-virt >/dev/null 2>&1; then
    DETECTED_VIRT=$(systemd-detect-virt)
    [ "$DETECTED_VIRT" != "none" ] && VIRT="$DETECTED_VIRT"
elif [ -f /.dockerenv ]; then
    VIRT="Docker Container"
elif grep -qa 'KVM' /sys/class/dmi/id/product_name 2>/dev/null; then
    VIRT="KVM"
fi

echo -e "${C_YELLOW}[ 基础硬件与系统架构 ]${C_RESET}"
echo -e " CPU 型号       : ${C_CYAN}${CPU_MODEL}${C_RESET}"
echo -e " 核心总数       : ${C_CYAN}${CPU_CORES} 核心 (${ARCH})${C_RESET}"
echo -e " CPU 主频       : ${C_CYAN}${CPU_FREQ}${C_RESET}"
echo -e " 物理内存       : ${C_CYAN}${MEM_USED} MB / ${MEM_TOTAL} MB (频率: ${MEM_SPEED})${C_RESET}"
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

# 6. 硬盘 SMART 状态检测 (精准适配 NVMe 与全厂商 SATA SSD)
echo -e "${C_YELLOW}[ 硬盘 SMART 健康度与真实累计读写量 ]${C_RESET}"
DISKS=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1!~/^loop/ && $1!~/^ram/ {print $1}')

for d in $DISKS; do
    DEV="/dev/$d"
    MODEL=$(lsblk -d -n -o MODEL "$DEV" 2>/dev/null | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    SIZE=$(lsblk -d -n -o SIZE "$DEV" 2>/dev/null | sed -e 's/^[ \t]*//')
    [ -z "$MODEL" ] && MODEL="Unknown Disk"
    
    echo -e " 硬盘设备       : ${C_CYAN}${DEV} (${MODEL} - ${SIZE})${C_RESET}"
    
    if command -v smartctl >/dev/null 2>&1; then
        SMART_INFO=$(smartctl -a "$DEV" 2>/dev/null || true)
        
        # 通电时间
        POH=$(echo "$SMART_INFO" | grep -iE "Power_On_Hours|Power On Hours" | awk '{print $NF}' | tr -d ',')
        if [[ "$POH" =~ ^[0-9]+$ ]]; then
            DAYS=$(awk -v h="$POH" 'BEGIN {printf "%.1f", h/24}')
            echo -e "   - 通电时间    : ${C_GREEN}${POH} 小时 (约 ${DAYS} 天)${C_RESET}"
        fi
        
        # 通电次数
        CYCLE=$(echo "$SMART_INFO" | grep -iE "Power_Cycle_Count|Power Cycles" | awk '{print $NF}' | tr -d ',')
        [[ "$CYCLE" =~ ^[0-9]+$ ]] && echo -e "   - 通电次数    : ${C_GREEN}${CYCLE} 次${C_RESET}"
        
        # 健康度
        HEALTH="100%"
        PERCENT_USED=$(echo "$SMART_INFO" | grep -i "Percentage Used" | awk '{print $NF}' | tr -d '%')
        if [[ "$PERCENT_USED" =~ ^[0-9]+$ ]]; then
            REM=$((100 - PERCENT_USED))
            [ $REM -lt 0 ] && REM=0
            HEALTH="${REM}% (已磨损 ${PERCENT_USED}%)"
        else
            WEAR=$(echo "$SMART_INFO" | grep -E "Media_Wearout_Indicator|Wear_Range_Delta" | awk '{print $4}')
            [ -n "$WEAR" ] && HEALTH="${WEAR}%"
        fi
        echo -e "   - 硬盘健康度  : ${C_GREEN}${HEALTH}${C_RESET}"
        
        # 终生总写入 (TBW) 与 终生总读取 (TBR)
        if [[ "$d" =~ ^nvme ]]; then
            WRITTEN_RAW=$(echo "$SMART_INFO" | grep -i "Data Units Written" | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',')
            if [[ "$WRITTEN_RAW" =~ ^[0-9]+$ ]]; then
                TBW=$(awk -v w="$WRITTEN_RAW" 'BEGIN {printf "%.2f", (w * 1000 * 512) / (1024^4)}')
                echo -e "   - 终生总写入  : ${C_GREEN}${TBW} TB (TBW)${C_RESET}"
            fi
            READ_RAW=$(echo "$SMART_INFO" | grep -i "Data Units Read" | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',')
            if [[ "$READ_RAW" =~ ^[0-9]+$ ]]; then
                TBR=$(awk -v r="$READ_RAW" 'BEGIN {printf "%.2f", (r * 1000 * 512) / (1024^4)}')
                echo -e "   - 终生总读取  : ${C_GREEN}${TBR} TB (TBR)${C_RESET}"
            fi
        else
            # SATA 匹配: 提取 ID 241/242
            LBA_W=$(echo "$SMART_INFO" | awk '$1=="241" || /Total_LBAs_Written/ || /Host_Writes/ {print $NF; exit}')
            if [[ "$LBA_W" =~ ^[0-9]+$ ]] && [ "$LBA_W" != "0" ]; then
                TBW=$(awk -v lba="$LBA_W" 'BEGIN {printf "%.2f", (lba * 512) / (1024^4)}')
                echo -e "   - 终生总写入  : ${C_GREEN}${TBW} TB (TBW)${C_RESET}"
            fi
            
            LBA_R=$(echo "$SMART_INFO" | awk '$1=="242" || /Total_LBAs_Read/ || /Host_Reads/ {print $NF; exit}')
            if [[ "$LBA_R" =~ ^[0-9]+$ ]] && [ "$LBA_R" != "0" ]; then
                TBR=$(awk -v lba="$LBA_R" 'BEGIN {printf "%.2f", (lba * 512) / (1024^4)}')
                echo -e "   - 终生总读取  : ${C_GREEN}${TBR} TB (TBR)${C_RESET}"
            fi
        fi
    fi
    echo ""
done

# 7. 磁盘 I/O 顺序写入性能
echo -e "${C_YELLOW}[ 磁盘 I/O 顺序写入性能测试 ]${C_RESET}"
TEST_TARGET="/tmp/io_test_file"
[ -d "/root" ] && TEST_TARGET="/root/io_test_file"
IO_SPEED=$(dd if=/dev/zero of=${TEST_TARGET} bs=64k count=16k conv=fdatasync 2>&1 | awk -F, '{print $NF}' | sed 's/^[ \t]*//')
rm -f ${TEST_TARGET}
echo -e " 1GB 顺序写入速率: ${C_GREEN}${IO_SPEED}${C_RESET}"
echo ""

# 8. YABS 官方双栈 iperf3 测速
IPERF_LOCS_4=(
    "Clouvider" "lon.speedtest.clouvider.net" "5200-5209" "英国 (伦敦 10G)"
    "Eranium" "ams.speedtest.clouvider.net" "5200-5209" "荷兰 (阿姆斯特丹 100G)"
    "Clouvider" "fra.speedtest.clouvider.net" "5200-5209" "德国 (法兰克福 10G)"
    "Clouvider" "la.speedtest.clouvider.net" "5200-5209" "美国 (洛杉矶 10G)"
    "Leaseweb" "speedtest.sin1.sg.leaseweb.net" "5201" "亚太 (新加坡 10G)"
    "Leaseweb" "speedtest.tyo1.jp.leaseweb.net" "5201" "亚太 (日本 东京 10G)"
)

IPERF_LOCS_6=(
    "Clouvider" "lon.speedtest.clouvider.net" "5200-5209" "英国 (伦敦 10G)"
    "Eranium" "ams.speedtest.clouvider.net" "5200-5209" "荷兰 (阿姆斯特丹 100G)"
    "Clouvider" "fra.speedtest.clouvider.net" "5200-5209" "德国 (法兰克福 10G)"
    "Clouvider" "la.speedtest.clouvider.net" "5200-5209" "美国 (洛杉矶 10G)"
)

extract_speed() {
    local raw="$1"
    local res=$(echo "$raw" | grep -E "SUM|receiver|sender" | tail -n 1 | awk '{for(k=1;k<=NF;k++) if($k ~ /bits\/sec/) print $(k-1), $k}')
    echo "$res"
}

run_yabs_suite() {
    local IP_VER="$1"
    local -n LOCS="$2"
    local IP_FLAG=""
    [ "$IP_VER" = "IPv4" ] && IP_FLAG="-4"
    [ "$IP_VER" = "IPv6" ] && IP_FLAG="-6"

    echo -e "${C_YELLOW}[ 全球节点上传与下载双向测速 (YABS 原版 ${IP_VER}) ]${C_RESET}"
    echo -e "----------------------------------------------------------------------------------"
    printf "%-12s | %-24s | %-13s | %-13s | %-8s\n" "提供商" "所在区域" "发送/上传速率" "接收/下载速率" "网络延迟"
    echo -e "----------------------------------------------------------------------------------"

    local total_nodes=$((${#LOCS[@]} / 4))
    for ((i=0; i<total_nodes; i++)); do
        local provider="${LOCS[i*4]}"
        local host="${LOCS[i*4+1]}"
        local port_range="${LOCS[i*4+2]}"
        local region="${LOCS[i*4+3]}"

        local ping_ms="N/A"
        if [ "$IP_VER" = "IPv4" ]; then
            ping_ms=$(ping -c 2 -W 2 "$host" 2>/dev/null | awk -F'/' 'END {if (NF>4) printf "%.1f ms", $5; else echo "超时"}')
        else
            ping_ms=$(ping6 -c 2 -W 2 "$host" 2>/dev/null | awk -F'/' 'END {if (NF>4) printf "%.1f ms", $5; else echo "超时"}')
        fi
        [ -z "$ping_ms" ] && ping_ms="超时"

        local send_res="超时/不可达"
        local recv_res="超时/不可达"

        local chosen_port="5201"
        if [[ "$port_range" =~ - ]]; then
            local p_min=$(echo "$port_range" | cut -d- -f1)
            local p_max=$(echo "$port_range" | cut -d- -f2)
            chosen_port=$(shuf -i ${p_min}-${p_max} -n 1 2>/dev/null || echo "$p_min")
        else
            chosen_port="$port_range"
        fi

        # 1. 发送/上传测试 (4 线程并发)
        local raw_send=$(timeout 8 "$IPERF_CMD" $IP_FLAG -c "$host" -p "$chosen_port" -t 3 -P 4 2>&1 || true)
        local val_send=$(extract_speed "$raw_send")
        [ -n "$val_send" ] && send_res="$val_send"

        # 2. 接收/下载测试 (单流反向推流，防止被公共节点并发拦截)
        local raw_recv=$(timeout 10 "$IPERF_CMD" $IP_FLAG -c "$host" -p "$chosen_port" -t 3 -R 2>&1 || true)
        local val_recv=$(extract_speed "$raw_recv")
        [ -n "$val_recv" ] && recv_res="$val_recv"

        printf "%-12s | %-24s | %-13s | %-13s | %-8s\n" "$provider" "$region" "$send_res" "$recv_res" "$ping_ms"
    done
    echo -e "----------------------------------------------------------------------------------"
    echo ""
}

# 双栈判断并输出
if [ "$IPV4" != "无 / 未分配" ]; then
    run_yabs_suite "IPv4" IPERF_LOCS_4
fi

if [ "$IPV6" != "无 / 未分配" ]; then
    run_yabs_suite "IPv6" IPERF_LOCS_6
else
    echo -e "${C_YELLOW}[ 全球节点上传与下载双向测速 (YABS 原版 IPv6) ]${C_RESET}"
    echo -e " 当前主机未检测到可用公网 IPv6 地址，已自动跳过 IPv6 测速。\n"
fi

echo -e "${C_GREEN}测试完成！${C_RESET}"
