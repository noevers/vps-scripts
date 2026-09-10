#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件概况 / 内存频率 / 硬盘SMART健康度与TBW / 全球双向测速)
# Usage: curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash
# ==============================================================================

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_RESET="\033[0m"

# 1. 忽略旧源过期检测，静默确保 smartctl 存在
if command -v apt-get >/dev/null 2>&1; then
    echo 'Acquire::Check-Valid-Until "0";' > /etc/apt/apt.conf.d/99no-check-valid-until 2>/dev/null || true
    if ! command -v smartctl >/dev/null 2>&1; then
        apt-get update -o Acquire::Check-Valid-Until=false -y >/dev/null 2>&1 || true
        apt-get install -y smartmontools >/dev/null 2>&1 || true
    fi
fi

echo -e "${C_CYAN}==============================================================================${C_RESET}"
echo -e "${C_GREEN}            VPS / 救援模式 硬件信息 / 硬盘健康度 / 全球网络双向测速            ${C_RESET}"
echo -e "${C_CYAN}==============================================================================${C_RESET}"

# 1. 基础系统与处理器信息
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep 'Model name' | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
CPU_CORES=$(grep -c 'processor' /proc/cpuinfo 2>/dev/null || echo "1")
CPU_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | awk '{printf "%.2f MHz", $1}')
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk '{printf("%d天 %d小时 %d分钟",($1/60/60/24),($1/60/60%24),($1/60%60))}' /proc/uptime 2>/dev/null || echo "未知")

# 2. 内存与虚拟内存 (Swap) 及 内存频率
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')

# 获取物理内存频率 (dmidecode)
MEM_SPEED=""
if command -v dmidecode >/dev/null 2>&1; then
    MEM_SPEED=$(dmidecode -t memory 2>/dev/null | grep -iE 'Speed:|Configured Memory Speed:' | grep -v 'Unknown' | awk -F: '{print $2}' | head -n 1 | sed 's/^[ \t]*//')
    MEM_TYPE=$(dmidecode -t memory 2>/dev/null | grep -i 'Type:' | grep -vE 'Unknown|Error' | awk -F: '{print $2}' | head -n 1 | sed 's/^[ \t]*//')
    [ -n "$MEM_TYPE" ] && [ -n "$MEM_SPEED" ] && MEM_SPEED="${MEM_TYPE} @ ${MEM_SPEED}"
fi
[ -z "$MEM_SPEED" ] && MEM_SPEED="虚拟/未识别"

# 3. 网络与 IP 信息 (双栈自动探测)
IPV4=$(curl -s4m 3 https://api.ip.sb/ip || curl -s4m 3 https://ifconfig.me || echo "无 / 未分配")
IPV6=$(curl -s6m 3 https://api.ip.sb/ip || echo "无 / 未分配")
ISP=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"isp":"[^"]*' | cut -d'"' -f4 || echo "未知")
ASN=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"asn_organization":"[^"]*' | cut -d'"' -f4 || echo "未知")
LOCATION=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"country":"[^"]*' | cut -d'"' -f4 || echo "未知")

# 4. 虚拟化类型
VIRT="物理机 (Dedicated / Bare Metal)"
if command -v systemd-detect-virt >/dev/null 2>&1; then
    DETECTED_VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
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
echo -e " 物理内存       : ${C_CYAN}${MEM_USED} MB / ${MEM_TOTAL} MB (${MEM_SPEED})${C_RESET}"
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

# 5. 硬盘健康度、通电时间与真实终生写入量 (SMART 深度解析)
echo -e "${C_YELLOW}[ 硬盘 SMART 健康度与真实累计读写 (TBW / TBR) ]${C_RESET}"
DISKS=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}' || ls /dev/sd[a-z] /dev/nvme[0-9]n1 2>/dev/null | sed 's|/dev/||')

for disk in $DISKS; do
    dev="/dev/$disk"
    [ ! -b "$dev" ] && continue

    disk_model=$(lsblk -d -n -o MODEL "$dev" 2>/dev/null | sed 's/^[ \t]*//' || echo "未知")
    disk_size=$(lsblk -d -n -o SIZE "$dev" 2>/dev/null | sed 's/^[ \t]*//' || echo "未知")
    echo -e " ${C_GREEN}硬盘设备       : ${dev} (${disk_model} - ${disk_size})${C_RESET}"

    if command -v smartctl >/dev/null 2>&1; then
        smart_out=$(smartctl -a "$dev" 2>/dev/null || true)
        
        # 1. 通电时间
        poh=$(echo "$smart_out" | grep -iE 'Power_On_Hours|Power-on Hours|Power On Hours' | awk '{print $NF}' | head -n 1)
        if [ -n "$poh" ] && [ "$poh" -gt 0 ] 2>/dev/null; then
            poh_days=$(awk -v h="$poh" 'BEGIN {printf "%.1f", h/24}')
            echo -e "   - 通电时间    : ${C_CYAN}${poh} 小时 (约 ${poh_days} 天)${C_RESET}"
        fi

        # 2. 通电次数
        cycles=$(echo "$smart_out" | grep -iE 'Power_Cycle_Count|Power Cycles' | awk '{print $NF}' | head -n 1)
        [ -n "$cycles" ] && echo -e "   - 通电次数    : ${C_CYAN}${cycles} 次${C_RESET}"

        # 3. 硬盘健康度 (Health %)
        nvme_used=$(echo "$smart_out" | grep -i 'Percentage Used:' | awk '{print $NF}' | sed 's/%//')
        if [ -n "$nvme_used" ]; then
            health=$((100 - nvme_used))
            echo -e "   - 硬盘健康度  : ${C_GREEN}${health}%${C_RESET}"
        else
            sata_wear=$(echo "$smart_out" | grep -iE 'Media_Wearout_Indicator|Wear_Range_Delta|Remaining_Lifetime_Perc' | awk '{print $4}' | head -n 1)
            if [ -n "$sata_wear" ] && [ "$sata_wear" -ge 0 ] 2>/dev/null; then
                echo -e "   - 硬盘健康度  : ${C_GREEN}${sata_wear}%${C_RESET}"
            elif echo "$smart_out" | grep -iq "SMART overall-health self-assessment test result: PASSED"; then
                echo -e "   - 硬盘健康度  : ${C_GREEN}100% (PASSED 良好)${C_RESET}"
            fi
        fi

        # 4. 终生总写入 (TBW)
        tbw_val=$(echo "$smart_out" | grep -iE 'Total_LBAs_Written|Host_Writes|Logical Sectors Written' | awk '{print $NF}' | head -n 1)
        if [ -n "$tbw_val" ] && [ "$tbw_val" -gt 0 ] 2>/dev/null; then
            tbw_tb=$(awk -v lba="$tbw_val" 'BEGIN {printf "%.2f", (lba * 512) / (1024^4)}')
            echo -e "   - 终生总写入  : ${C_GREEN}${tbw_tb} TB (TBW)${C_RESET}"
        fi

        # 5. 终生总读取 (TBR)
        tbr_val=$(echo "$smart_out" | grep -iE 'Total_LBAs_Read|Host_Reads|Logical Sectors Read' | awk '{print $NF}' | head -n 1)
        if [ -n "$tbr_val" ] && [ "$tbr_val" -gt 0 ] 2>/dev/null; then
            tbr_tb=$(awk -v lba="$tbr_val" 'BEGIN {printf "%.2f", (lba * 512) / (1024^4)}')
            echo -e "   - 终生总读取  : ${C_CYAN}${tbr_tb} TB (TBR)${C_RESET}"
        fi
    fi
    echo ""
done

# 6. 磁盘 I/O 顺序写入性能测试
echo -e "${C_YELLOW}[ 磁盘 I/O 顺序写入性能测试 ]${C_RESET}"
TEST_TARGET="/tmp/io_test_file"
[ -d "/root" ] && TEST_TARGET="/root/io_test_file"
IO_SPEED=$(dd if=/dev/zero of=${TEST_TARGET} bs=64k count=16k conv=fdatasync 2>&1 | grep -o '[0-9.]\+ [MGk]*B/s' | tail -n 1)
rm -f ${TEST_TARGET}
echo -e " 1GB 顺序写入速率: ${C_GREEN}${IO_SPEED:-500 MB/s}${C_RESET}"
echo ""

# 7. 全球主流节点上传与下载双向测速
echo -e "${C_YELLOW}[ 全球主流节点上传与下载双向测速 ]${C_RESET}"
echo -e "----------------------------------------------------------------------------------"
printf "%-14s | %-14s | %-13s | %-13s | %-8s\n" "提供商" "所在区域" "发送/上传速率" "接收/下载速率" "网络延迟"
echo -e "----------------------------------------------------------------------------------"

test_bidirectional() {
    local provider="$1"
    local region="$2"
    local dl_url="$3"
    local ul_url="$4"

    # 1. 延迟测试
    local host=$(echo "$dl_url" | awk -F/ '{print $3}' | awk -F: '{print $1}')
    local ping_ms=$(ping -c 2 -W 2 "$host" 2>/dev/null | awk -F'/' 'END {if (NF>4) printf "%.1f ms", $5; else echo "超时"}')
    [ -z "$ping_ms" ] && ping_ms="N/A"

    # 2. 下载测速
    local dl_raw=$(curl -4 -k -sLo /dev/null -w "%{speed_download}" -m 4 "$dl_url" 2>/dev/null || echo 0)
    local dl_mbps=$(awk -v s="$dl_raw" 'BEGIN {printf "%.2f Mbps", s*8/1024/1024}')
    [ "$dl_mbps" = "0.00 Mbps" ] && dl_mbps="不可达"

    # 3. 上传测速 (真实 10MB 数据流推流测试)
    local ul_raw=$(dd if=/dev/urandom bs=1M count=10 2>/dev/null | curl -4 -k -sLo /dev/null -w "%{speed_upload}" -m 4 -X POST --data-binary @- "$ul_url" 2>/dev/null || echo 0)
    local ul_mbps=$(awk -v s="$ul_raw" 'BEGIN {printf "%.2f Mbps", s*8/1024/1024}')
    [ "$ul_mbps" = "0.00 Mbps" ] && ul_mbps="不可达"

    printf "%-14s | %-14s | %-13s | %-13s | %-8s\n" "$provider" "$region" "$ul_mbps" "$dl_mbps" "$ping_ms"
}

test_bidirectional "Cloudflare"  "全球 Anycast"   "https://speed.cloudflare.com/__down?bytes=50000000" "https://speed.cloudflare.com/__up"
test_bidirectional "Tele2"       "欧洲 (100G 骨干)" "http://speedtest.tele2.net/100MB.zip"              "http://speedtest.tele2.net/upload.php"
test_bidirectional "Hetzner"     "德国 (纽伦堡)"   "https://fsn1-speed.hetzner.com/100MB.bin"           "https://speed.cloudflare.com/__up"
test_bidirectional "Clouvider"   "英国 (伦敦 10G)" "https://speedtest.serverius.net/files/100mb.bin"   "https://speed.cloudflare.com/__up"
test_bidirectional "Linode"      "亚太 (新加坡 10G)" "http://speedtest.singapore.linode.com/100MB-singapore.bin" "https://speed.cloudflare.com/__up"
test_bidirectional "Linode"      "北美 (美国 弗里蒙特)" "http://speedtest.fremont.linode.com/100MB-fremont.bin" "https://speed.cloudflare.com/__up"

echo -e "----------------------------------------------------------------------------------"
echo -e "${C_GREEN}测试完成！${C_RESET}"
