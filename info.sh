#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件概况 / 内存频率 / 硬盘读写与通电时间 / 全球双向测速)
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
echo -e "${C_GREEN}    VPS / 救援模式 硬件信息、内存频率、硬盘读写/通电与网络双向测速     ${C_RESET}"
echo -e "${C_CYAN}==============================================================================${C_RESET}"

# 1. 基础硬件与处理器信息
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | sed -e 's/^[ \t]*//' || echo "未知")
CPU_CORES=$(grep -c 'processor' /proc/cpuinfo 2>/dev/null || echo "1")
CPU_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | awk '{printf "%.2f MHz", $1}' || echo "未知")
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk '{printf("%d天 %d小时 %d分钟",($1/60/60/24),($1/60/60%24),($1/60%60))}' /proc/uptime 2>/dev/null || echo "未知")

# 2. 内存与内存频率
MEM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0")
MEM_USED=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}' || echo "0")
SWAP_TOTAL=$(free -m 2>/dev/null | awk '/Swap:/ {print $2}' || echo "0")

# 尝试安全安装 dmidecode (忽略 apt 源过期报错)
if ! command -v dmidecode >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -o Acquire::Check-Valid-Until=false -qq >/dev/null 2>&1 || true
        apt-get install -y -qq dmidecode >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q dmidecode >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache dmidecode >/dev/null 2>&1 || true
    fi
fi

MEM_SPEED="未知 (虚拟化未透传)"
MEM_TYPE=""
if command -v dmidecode >/dev/null 2>&1; then
    DMI_SPEED=$(dmidecode -t memory 2>/dev/null | grep -E "Configured Clock Speed:|Speed:" | grep -vi "Unknown" | grep -vi "No Module" | head -n1 | awk -F: '{print $2}' | sed 's/^[ \t]*//' || true)
    DMI_TYPE=$(dmidecode -t memory 2>/dev/null | grep -E "Type:" | grep -vi "Unknown" | grep -vi "Error" | head -n1 | awk -F: '{print $2}' | sed 's/^[ \t]*//' || true)
    [ -n "$DMI_SPEED" ] && MEM_SPEED="$DMI_SPEED"
    [ -n "$DMI_TYPE" ] && MEM_TYPE=" ($DMI_TYPE)"
fi

# 3. 网络与地理位置
IPV4=$(curl -s4m 3 https://api.ip.sb/ip || curl -s4m 3 https://ifconfig.me || echo "无 / 未分配")
IPV6=$(curl -s6m 3 https://api.ip.sb/ip || echo "无 / 未分配")
ISP=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"isp":"[^"]*' | cut -d'"' -f4 || echo "未知")
LOCATION=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"country":"[^"]*' | cut -d'"' -f4 || echo "未知")

echo -e "${C_YELLOW}[ 基础硬件与系统架构 ]${C_RESET}"
echo -e " CPU 型号       : ${C_CYAN}${CPU_MODEL}${C_RESET}"
echo -e " 核心总数       : ${C_CYAN}${CPU_CORES} 核心 (${ARCH})${C_RESET}"
echo -e " CPU 运行主频   : ${C_CYAN}${CPU_FREQ}${C_RESET}"
echo -e " 物理内存       : ${C_CYAN}${MEM_USED} MB / ${MEM_TOTAL} MB${C_RESET}"
echo -e " 内存工作频率   : ${C_CYAN}${MEM_SPEED}${MEM_TYPE}${C_RESET}"
echo -e " 虚拟内存 (Swap): ${C_CYAN}${SWAP_TOTAL} MB${C_RESET}"
echo -e " 系统内核       : ${C_CYAN}${KERNEL}${C_RESET}"
echo -e " 系统运行时间   : ${C_CYAN}${UPTIME}${C_RESET}"
echo ""
echo -e "${C_YELLOW}[ 网络与地理位置 ]${C_RESET}"
echo -e " IPv4 地址      : ${C_CYAN}${IPV4}${C_RESET}"
echo -e " IPv6 地址      : ${C_CYAN}${IPV6}${C_RESET}"
echo -e " 运营商 (ISP)   : ${C_CYAN}${ISP}${C_RESET}"
echo -e " 所在区域       : ${C_CYAN}${LOCATION}${C_RESET}"
echo ""

# 4. 全盘存储设备统计 (SMART 终生累计 + 系统当前运行读写量)
echo -e "${C_YELLOW}[ 硬盘存储设备、通电时间与读写统计 ]${C_RESET}"

if ! command -v smartctl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -o Acquire::Check-Valid-Until=false -qq >/dev/null 2>&1 || true
        apt-get install -y -qq smartmontools >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q smartmontools >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache smartmontools >/dev/null 2>&1 || true
    fi
fi

format_bytes() {
    local mb=$1
    if (( $(echo "$mb >= 1048576" | bc -l 2>/dev/null || awk -v n="$mb" 'BEGIN {print (n>=1048576)?1:0}') )); then
        awk -v m="$mb" 'BEGIN {printf "%.2f TB", m/1024/1024}'
    elif (( $(echo "$mb >= 1024" | bc -l 2>/dev/null || awk -v n="$mb" 'BEGIN {print (n>=1024)?1:0}') )); then
        awk -v m="$mb" 'BEGIN {printf "%.2f GB", m/1024}'
    else
        awk -v m="$mb" 'BEGIN {printf "%.2f MB", m}'
    fi
}

DISKS=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}' || echo "sda")

for d in $DISKS; do
    DEV="/dev/$d"
    SIZE=$(lsblk -dno SIZE "$DEV" 2>/dev/null || echo "未知")
    MODEL=$(lsblk -dno MODEL "$DEV" 2>/dev/null | sed 's/^[ \t]*//' || echo "")
    [ -z "$MODEL" ] && MODEL=$(cat /sys/block/$d/device/model 2>/dev/null | sed 's/^[ \t]*//' || echo "Disk")

    echo -e " ${C_GREEN}盘符: ${DEV} [${SIZE}] ${MODEL}${C_RESET}"

    # A. 系统本次开机以来的统计 (来自 /proc/diskstats)
    DISK_STAT=$(awk -v target="$d" '$3 == target {
        r_mb = ($6 * 512) / 1024 / 1024;
        w_mb = ($10 * 512) / 1024 / 1024;
        printf "%.2f|%.2f", r_mb, w_mb;
    }' /proc/diskstats)

    if [ -n "$DISK_STAT" ]; then
        RAW_R=$(echo "$DISK_STAT" | cut -d'|' -f1)
        RAW_W=$(echo "$DISK_STAT" | cut -d'|' -f2)
        echo -e " - 宿主开机读取 : ${C_CYAN}$(format_bytes $RAW_R)${C_RESET}"
        echo -e " - 宿主开机写入 : ${C_CYAN}$(format_bytes $RAW_W)${C_RESET}"
    fi

    # B. SMART 硬件终生累计数据
    if command -v smartctl >/dev/null 2>&1; then
        SMART_RAW=$(smartctl -a "$DEV" 2>/dev/null || true)
        
        # 通电时间
        POW_HOURS=$(echo "$SMART_RAW" | awk '/Power_On_Hours|Power_On_Time/ {print $10}' | head -n1)
        [ -z "$POW_HOURS" ] && POW_HOURS=$(echo "$SMART_RAW" | grep -i "Power On Hours:" | awk -F: '{print $2}' | tr -d ' ')
        if [ -n "$POW_HOURS" ] && [ "$POW_HOURS" != "0" ]; then
            POW_DAYS=$(awk -v h="$POW_HOURS" 'BEGIN {printf "%.1f", h/24}')
            echo -e " - 硬件通电时间 : ${C_CYAN}${POW_HOURS} 小时 (约 ${POW_DAYS} 天)${C_RESET}"
        fi

        # 通电次数
        POW_CYCLES=$(echo "$SMART_RAW" | awk '/Power_Cycle_Count/ {print $10}' | head -n1)
        [ -z "$POW_CYCLES" ] && POW_CYCLES=$(echo "$SMART_RAW" | grep -i "Power Cycles:" | awk -F: '{print $2}' | tr -d ' ')
        [ -n "$POW_CYCLES" ] && [ "$POW_CYCLES" != "0" ] && echo -e " - 硬件通电次数 : ${C_CYAN}${POW_CYCLES} 次${C_RESET}"

        # 终生总写入 / 读取 (Micron 5100/5300, Samsung, NVMe, SATA)
        TOTAL_W_FORMATTED=""
        TOTAL_R_FORMATTED=""

        # NVMe 固态硬盘
        NVME_W_UNITS=$(echo "$SMART_RAW" | grep -i "Data Units Written:" | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',')
        if [ -n "$NVME_W_UNITS" ]; then
            TOTAL_W_TB=$(awk -v u="$NVME_W_UNITS" 'BEGIN {printf "%.2f", (u * 512 * 1000) / (1024*1024*1024*1024)}')
            TOTAL_W_FORMATTED="${TOTAL_W_TB} TB"
        fi
        NVME_R_UNITS=$(echo "$SMART_RAW" | grep -i "Data Units Read:" | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',')
        if [ -n "$NVME_R_UNITS" ]; then
            TOTAL_R_TB=$(awk -v u="$NVME_R_UNITS" 'BEGIN {printf "%.2f", (u * 512 * 1000) / (1024*1024*1024*1024)}')
            TOTAL_R_FORMATTED="${TOTAL_R_TB} TB"
        fi

        # SATA 企业级固态 (Micron 5100/5300/5400 等)
        if [ -z "$TOTAL_W_FORMATTED" ]; then
            MICRON_LBAS=$(echo "$SMART_RAW" | awk '$1=="246" || $2=="Total_LBAs_Written" || $2=="Cumulative_Host_Sectors_Written" {print $10}' | head -n1)
            [ -z "$MICRON_LBAS" ] && MICRON_LBAS=$(echo "$SMART_RAW" | awk '$1=="241" || $2=="Host_Writes_32MiB" || $2=="Total_Writes_GiB" {print $10}' | head -n1)
            
            if [ -n "$MICRON_LBAS" ] && [ "$MICRON_LBAS" != "0" ]; then
                # 针对 Micron 5100/5300 判定 32MiB 块还是 512B 扇区
                if (( $(awk -v l="$MICRON_LBAS" 'BEGIN {print (l<500000000)?1:0}') )); then
                    TOTAL_W_TB=$(awk -v l="$MICRON_LBAS" 'BEGIN {printf "%.2f", (l * 32 * 1024 * 1024) / (1024*1024*1024*1024)}')
                    [ "$TOTAL_W_TB" = "0.00" ] && TOTAL_W_TB=$(awk -v l="$MICRON_LBAS" 'BEGIN {printf "%.2f", (l * 512) / (1024*1024*1024*1024)}')
                else
                    TOTAL_W_TB=$(awk -v l="$MICRON_LBAS" 'BEGIN {printf "%.2f", (l * 512) / (1024*1024*1024*1024)}')
                fi
                TOTAL_W_FORMATTED="${TOTAL_W_TB} TB"
            fi

            MICRON_R_LBAS=$(echo "$SMART_RAW" | awk '$1=="242" || $2=="Total_LBAs_Read" || $2=="Host_Reads_32MiB" || $2=="Total_Reads_GiB" {print $10}' | head -n1)
            if [ -n "$MICRON_R_LBAS" ] && [ "$MICRON_R_LBAS" != "0" ]; then
                if (( $(awk -v l="$MICRON_R_LBAS" 'BEGIN {print (l<500000000)?1:0}') )); then
                    TOTAL_R_TB=$(awk -v l="$MICRON_R_LBAS" 'BEGIN {printf "%.2f", (l * 32 * 1024 * 1024) / (1024*1024*1024*1024)}')
                    [ "$TOTAL_R_TB" = "0.00" ] && TOTAL_R_TB=$(awk -v l="$MICRON_R_LBAS" 'BEGIN {printf "%.2f", (l * 512) / (1024*1024*1024*1024)}')
                else
                    TOTAL_R_TB=$(awk -v l="$MICRON_R_LBAS" 'BEGIN {printf "%.2f", (l * 512) / (1024*1024*1024*1024)}')
                fi
                TOTAL_R_FORMATTED="${TOTAL_R_TB} TB"
            fi
        fi

        [ -n "$TOTAL_W_FORMATTED" ] && echo -e " - 硬件终生累计写入 : ${C_CYAN}${TOTAL_W_FORMATTED} (TBW 终生写入)${C_RESET}"
        [ -n "$TOTAL_R_FORMATTED" ] && echo -e " - 硬件终生累计读取 : ${C_CYAN}${TOTAL_R_FORMATTED}${C_RESET}"
    fi
    echo ""
done

# 5. 磁盘 I/O 顺序写入性能测试
echo -e "${C_YELLOW}[ 磁盘 I/O 顺序写入性能测试 ]${C_RESET}"
TEST_TARGET="/tmp/io_test_file"
IO_SPEED=$(dd if=/dev/zero of=${TEST_TARGET} bs=64k count=16k conv=fdatasync 2>&1 | awk -F, 'END {print $NF}' | sed 's/^[ \t]*//' | tr -d '\n' || echo "未知")
rm -f ${TEST_TARGET}
echo -e " 1GB 顺序写入速率: ${C_GREEN}${IO_SPEED}${C_RESET}"
echo ""

# 6. 网络双向上传与下载测速 (Speedtest-CLI 动态优质节点)
echo -e "${C_YELLOW}[ 全球节点上传与下载双向测速 ]${C_RESET}"

SP_BIN="/tmp/speedtest"
if [ ! -f "$SP_BIN" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" | tar -xz -C /tmp speedtest 2>/dev/null || true
    elif [ "$ARCH" = "aarch64" ]; then
        curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz" | tar -xz -C /tmp speedtest 2>/dev/null || true
    fi
fi

if [ -x "$SP_BIN" ]; then
    echo -e "----------------------------------------------------------------------------------"
    printf "%-22s %-16s %-16s %-16s %-10s\n" "测试节点" "所在区域" "上传速度" "下载速度" "网络延迟"
    echo -e "----------------------------------------------------------------------------------"

    test_sp() {
        local name="$1"
        local region="$2"
        local s_id="$3"

        # 增加 8 秒超时，防止卡死
        local out=$(timeout 10 $SP_BIN --accept-license --accept-gdpr -s "$s_id" -f json 2>/dev/null || true)
        local down_bytes=$(echo "$out" | grep -o '"download":{"bandwidth":[^,]*' | awk -F: '{print $3}' || echo 0)
        local up_bytes=$(echo "$out" | grep -o '"upload":{"bandwidth":[^,]*' | awk -F: '{print $3}' || echo 0)
        local lat=$(echo "$out" | grep -o '"latency":{"low":[^,]*,"high":[^,]*,"jitter":[^,]*,"iqm":[^,]*' | awk -F'"iqm":' '{print $2}' || awk -F'"latency":' '{print $2}' | cut -d',' -f1 || echo "")
        
        [ -z "$lat" ] && lat=$(echo "$out" | grep -o '"ping":{"jitter":[^,]*,"latency":[^}]*' | awk -F'"latency":' '{print $2}' | tr -d '}' || echo "")

        local down_mbps="不可达"
        local up_mbps="不可达"
        [ -n "$down_bytes" ] && [ "$down_bytes" != "0" ] && down_mbps=$(awk -v b="$down_bytes" 'BEGIN {printf "%.2f Mbps", (b*8)/1000/1000}')
        [ -n "$up_bytes" ] && [ "$up_bytes" != "0" ] && up_mbps=$(awk -v b="$up_bytes" 'BEGIN {printf "%.2f Mbps", (b*8)/1000/1000}')
        [ -n "$lat" ] && [ "$lat" != "null" ] && lat="$(awk -v l="$lat" 'BEGIN {printf "%.1f ms", l}')" || lat="N/A"

        printf "%-22s %-16s %-16s %-16s %-10s\n" "$name" "$region" "$up_mbps" "$down_mbps" "$lat"
    }

    # 1. 自动测试最近的本地最佳测速点 (Nearest Auto)
    test_sp "Local Auto Best"   "本地最佳节点"   ""
    # 2. 欧洲优质节点 (德国 Hetzner / 英国)
    test_sp "Hetzner Online"    "德国 纽伦堡"    "36295"
    test_sp "Clouvider Ltd"     "英国 伦敦"      "31010"
    # 3. 北美节点 (美国 洛杉矶 / 纽约)
    test_sp "ReliableSite"      "美国 洛杉矶"    "15395"
    test_sp "Secura Hosting"    "美国 纽约"      "44988"
    # 4. 亚太优质节点 (日本 / 新加坡)
    test_sp "IPAAS Co"          "日本 东京"      "48463"
    test_sp "Singtel"           "新加坡"        "13623"
    
    echo -e "----------------------------------------------------------------------------------"
else
    echo -e " 无法获取测速组件，跳过网络测速。"
fi

rm -f /tmp/speedtest /tmp/speedtest.5 /tmp/speedtest.md 2>/dev/null || true
echo -e "${C_GREEN}====================== 全部测试流程已顺利完成 ======================${C_RESET}"
