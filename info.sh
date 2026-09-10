#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件概况 / 内存频率 / 硬盘SMART健康度与真实TBW / 全球多节点极速带宽测速)
# Usage: curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash
# ==============================================================================

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_RESET="\033[0m"

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

CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep 'Model name:' | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
CPU_CORES=$(grep -c 'processor' /proc/cpuinfo)
CPU_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F: '{print $2}' | awk '{printf "%.2f MHz", $1}')
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk '{printf("%d天 %d小时 %d分钟",($1/60/60/24),($1/60/60%24),($1/60%60))}' /proc/uptime)

MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
MEM_SPEED=""
if command -v dmidecode >/dev/null 2>&1; then
    MEM_SPEED=$(dmidecode -t memory 2>/dev/null | grep -iE 'Speed:' | grep -v -i 'Configured' | grep -v -i 'Unknown' | head -n1 | awk -F: '{print $2}' | sed 's/^[ \t]*//')
    MEM_TYPE=$(dmidecode -t memory 2>/dev/null | grep -iE 'Type:' | grep -v -i 'Error' | grep -v -i 'Unknown' | head -n1 | awk -F: '{print $2}' | sed 's/^[ \t]*//')
    [ -n "$MEM_TYPE" ] && [ -n "$MEM_SPEED" ] && MEM_SPEED="$MEM_TYPE @ $MEM_SPEED"
fi
[ -z "$MEM_SPEED" ] && MEM_SPEED="标准/虚拟化内存"

IPV4=$(curl -s4m 3 https://api.ip.sb/ip || curl -s4m 3 https://ifconfig.me || echo "无 / 未分配")
IPV6=$(curl -s6m 3 https://api.ip.sb/ip || echo "无 / 未分配")
ISP=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"isp":"[^"]*' | cut -d'"' -f4 || echo "未知")
ASN=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"asn_organization":"[^"]*' | cut -d'"' -f4 || echo "未知")
LOCATION=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o '"country":"[^"]*' | cut -d'"' -f4 || echo "未知")

VIRT="物理机 (Dedicated / Bare Metal)"
if command -v systemd-detect-virt >/dev/null 2>&1; then
    DETECTED_VIRT=$(systemd-detect-virt 2>/dev/null || true)
    [ -n "$DETECTED_VIRT" ] && [ "$DETECTED_VIRT" != "none" ] && VIRT="$DETECTED_VIRT"
elif [ -f /.dockerenv ]; then
    VIRT="Docker Container"
elif grep -qa 'KVM' /sys/class/dmi/id/product_name 2>/dev/null; then
    VIRT="KVM"
fi

echo -e "${C_YELLOW}[ 基础硬件与系统架构 ]${C_RESET}"
echo -e " CPU 型号       : ${C_CYAN}${CPU_MODEL}${C_RESET}"
echo -e " 核心总数       : ${C_CYAN}${CPU_CORES} 核心 (${ARCH})${C_RESET}"
echo -e " CPU 主频       : ${C_CYAN}${CPU_FREQ}${C_RESET}"
echo -e " 物理内存       : ${C_CYAN}${MEM_USED} MB / ${MEM_TOTAL} MB (规格: ${MEM_SPEED})${C_RESET}"
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

echo -e "${C_YELLOW}[ 硬盘 SMART 健康度与真实累计读写 (TBW) ]${C_RESET}"
disks=$(lsblk -d -n -o NAME,SIZE,MODEL 2>/dev/null | grep -E '^(sd|nvme|vd|hd)' || true)

if [ -n "$disks" ]; then
    while read -r name size model; do
        dev="/dev/$name"
        [ ! -b "$dev" ] && continue

        echo -e " ${C_CYAN}硬盘设备       : ${dev} (${model:-未知型号} - ${size})${C_RESET}"

        if command -v smartctl >/dev/null 2>&1; then
            smart_out=$(smartctl -a "$dev" 2>/dev/null || smartctl -x "$dev" 2>/dev/null || true)
            
            health_pct=$(echo "$smart_out" | grep -i 'Percentage Used:' | awk '{print 100 - $3"%"}')
            if [ -z "$health_pct" ]; then
                wearout=$(echo "$smart_out" | grep -E '(Media_Wearout_Indicator|Wear_Range_Delta)' | awk '{print $4}')
                if [ -n "$wearout" ] && [ "$wearout" -gt 0 ] 2>/dev/null; then
                    health_pct="${wearout}%"
                elif echo "$smart_out" | grep -q 'SMART overall-health self-assessment test result: PASSED'; then
                    health_pct="100% (SMART 正常)"
                else
                    health_pct="正常 / 不支持直读"
                fi
            fi

            poh=$(echo "$smart_out" | grep -E '(Power_On_Hours|Power On Hours:)' | awk '{print $(NF)}' | tr -d ',' || true)
            [ -z "$poh" ] && poh=$(echo "$smart_out" | grep -i 'Power On Hours:' | awk -F: '{print $2}' | awk '{print $1}' | tr -d ',' || true)

            poc=$(echo "$smart_out" | grep -E '(Power_Cycle_Count|Power Cycles:)' | awk '{print $(NF)}' | tr -d ',' || true)

            tbw=""
            lba_written=$(echo "$smart_out" | grep -E 'Total_LBAs_Written|Logical Sectors Written:' | awk '{print $(NF)}' | tr -d ',' || true)
            if [ -n "$lba_written" ] && [ "$lba_written" -gt 0 ] 2>/dev/null; then
                tbw=$(awk -v lba="$lba_written" 'BEGIN {printf "%.2f TB", (lba * 512) / (1024*1024*1024*1024)}')
            fi
            if [ -z "$tbw" ]; then
                data_written=$(echo "$smart_out" | grep -i 'Data Units Written:' | awk '{print $4}' | tr -d ',' || true)
                if [ -n "$data_written" ] && [ "$data_written" -gt 0 ] 2>/dev/null; then
                    tbw=$(awk -v du="$data_written" 'BEGIN {printf "%.2f TB", (du * 512000) / (1024*1024*1024*1024)}')
                fi
            fi
            [ -z "$tbw" ] && tbw="不支持此项统计 / 虚拟化磁盘"

            tbr=""
            lba_read=$(echo "$smart_out" | grep -E 'Total_LBAs_Read|Logical Sectors Read:' | awk '{print $(NF)}' | tr -d ',' || true)
            if [ -n "$lba_read" ] && [ "$lba_read" -gt 0 ] 2>/dev/null; then
                tbr=$(awk -v lba="$lba_read" 'BEGIN {printf "%.2f TB", (lba * 512) / (1024*1024*1024*1024)}')
            fi
            if [ -z "$tbr" ]; then
                data_read=$(echo "$smart_out" | grep -i 'Data Units Read:' | awk '{print $4}' | tr -d ',' || true)
                if [ -n "$data_read" ] && [ "$data_read" -gt 0 ] 2>/dev/null; then
                    tbr=$(awk -v du="$data_read" 'BEGIN {printf "%.2f TB", (du * 512000) / (1024*1024*1024*1024)}')
                fi
            fi
            [ -z "$tbr" ] && tbr="不支持此项统计"

            echo -e "   - 硬盘健康度  : ${C_GREEN}${health_pct}${C_RESET}"
            if [ -n "$poh" ] && [ "$poh" -gt 0 ] 2>/dev/null; then
                days=$(awk -v h="$poh" 'BEGIN {printf "%.1f", h/24}')
                echo -e "   - 通电时间    : ${poh} 小时 (约 ${days} 天)"
            else
                echo -e "   - 通电时间    : 未知 / 虚拟化设备"
            fi
            [ -n "$poc" ] && echo -e "   - 通电次数    : ${poc} 次"
            echo -e "   - 终生总写入  : ${C_YELLOW}${tbw}${C_RESET}"
            echo -e "   - 终生总读取  : ${tbr}"
        else
            echo -e "   - SMART 提示  : 未安装 smartctl 工具"
        fi
        echo ""
    done <<< "$disks"
fi

echo -e "${C_YELLOW}[ 磁盘 I/O 顺序写入性能测试 ]${C_RESET}"
TEST_FILE="/tmp/io_bench_test"
[ -d "/root" ] && TEST_FILE="/root/io_bench_test"
IO_SPEED=$(dd if=/dev/zero of=${TEST_FILE} bs=64k count=16k conv=fdatasync 2>&1 | awk -F, 'END {print $NF}' | sed 's/^[ \t]*//')
rm -f ${TEST_FILE}
echo -e " 1GB 顺序写入速率: ${C_GREEN}${IO_SPEED}${C_RESET}"
echo ""

echo -e "${C_YELLOW}[ 全球主流节点上传与下载双向测速 ]${C_RESET}"
echo -e "----------------------------------------------------------------------------------"
printf "%-14s | %-18s | %-13s | %-13s | %-9s\n" "提供商" "所在区域" "发送/上传速率" "接收/下载速率" "网络延迟"
echo -e "----------------------------------------------------------------------------------"

test_node() {
    local provider="$1"
    local region="$2"
    local dl_url="$3"
    local ul_url="$4"
    local ping_host=$(echo "$dl_url" | awk -F/ '{print $3}' | awk -F: '{print $1}')

    local latency=$(ping -4 -c 2 -W 1 "$ping_host" 2>/dev/null | awk -F'/' 'END {if (NF>4) printf "%.1f ms", $5; else echo "超时"}')
    [ -z "$latency" ] && latency="N/A"

    local dl_raw=$(curl -4 -k -sLo /dev/null -w "%{speed_download}" -m 4 "$dl_url" 2>/dev/null || echo 0)
    local dl_mbps=$(awk -v s="$dl_raw" 'BEGIN {if (s>0) printf "%.2f Mbps", s*8/1024/1024; else echo "不可达"}')

    local ul_raw=0
    if [ -n "$ul_url" ]; then
        ul_raw=$(dd if=/dev/zero bs=1M count=10 2>/dev/null | curl -4 -k -sLo /dev/null -w "%{speed_upload}" -m 4 -X POST --data-binary @- "$ul_url" 2>/dev/null || echo 0)
    fi
    local ul_mbps=$(awk -v s="$ul_raw" 'BEGIN {if (s>0) printf "%.2f Mbps", s*8/1024/1024; else echo "不可达"}')

    printf "%-14s | %-18s | %-13s | %-13s | %-9s\n" "$provider" "$region" "$ul_mbps" "$dl_mbps" "$latency"
}

test_node "Hetzner"    "德国 (纽伦堡)"      "https://fsn1-speed.hetzner.com/100MB.bin"                           "https://fsn1-speed.hetzner.com/"
test_node "Clouvider"  "英国 (伦敦 10G)"    "https://lon.speedtest.clouvider.net/backend/garbage.php?ckSize=100" "https://lon.speedtest.clouvider.net/backend/empty.php"
test_node "Leaseweb"   "荷兰 (阿姆斯特丹)"  "http://mirror.nl.leaseweb.net/speedtest/100mb.bin"                  ""
test_node "Linode"     "亚太 (新加坡 10G)"  "http://speedtest.singapore.linode.com/100MB-singapore.bin"          ""
test_node "Linode"     "亚太 (日本 东京)"   "http://speedtest.tokyo2.linode.com/100MB-tokyo2.bin"               ""
test_node "Linode"     "北美 (美国 弗里蒙特)" "http://speedtest.fremont.linode.com/100MB-fremont.bin"            ""

echo -e "----------------------------------------------------------------------------------"
echo -e "${C_GREEN}所有测试执行完毕！${C_RESET}"
