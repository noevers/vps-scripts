#!/bin/bash
set -e
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RESET="\033[0m"

echo -e "${C_CYAN}==============================================================================${C_RESET}"
echo -e "${C_GREEN}            VPS / 救援模式 (Rescue Mode) 硬件信息与带宽综合测试            ${C_RESET}"
echo -e "${C_CYAN}==============================================================================${C_RESET}"

CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | awk -F: "{print \$2}" | sed -e "s/^[ \t]*//" || echo "未知")
CPU_CORES=$(grep -c "processor" /proc/cpuinfo 2>/dev/null || echo "1")
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk "{printf(\"%d天 %d小时 %d分钟\",(\$1/60/60/24),(\$1/60/60%24),(\$1/60%60))}" /proc/uptime 2>/dev/null || echo "未知")
MEM_TOTAL=$(free -m 2>/dev/null | awk "/Mem:/ {print \$2}" || echo "0")
MEM_USED=$(free -m 2>/dev/null | awk "/Mem:/ {print \$3}" || echo "0")
SWAP_TOTAL=$(free -m 2>/dev/null | awk "/Swap:/ {print \$2}" || echo "0")

IPV4=$(curl -s4m 3 https://api.ip.sb/ip || curl -s4m 3 https://ifconfig.me || echo "无 / 未分配")
IPV6=$(curl -s6m 3 https://api.ip.sb/ip || echo "无 / 未分配")
ISP=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o "\"isp\":\"[^\"]*" | cut -d\" -f4 || echo "未知")
LOCATION=$(curl -s4m 3 https://api.ip.sb/geoip | grep -o "\"country\":\"[^\"]*" | cut -d\" -f4 || echo "未知")

echo -e "${C_YELLOW}[ 基础硬件与系统架构 ]${C_RESET}"
echo -e " CPU 型号       : ${C_CYAN}${CPU_MODEL}${C_RESET}"
echo -e " 核心总数       : ${C_CYAN}${CPU_CORES} 核心 (${ARCH})${C_RESET}"
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
echo -e "${C_YELLOW}[ 硬盘与存储设备 (lsblk) ]${C_RESET}"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT 2>/dev/null || fdisk -l 2>/dev/null | grep "Disk /dev" || true
echo ""

echo -e "${C_YELLOW}[ 磁盘 I/O 简易读写测试 ]${C_RESET}"
TEST_TARGET="/tmp/io_test_file"
IO_SPEED=$(dd if=/dev/zero of=${TEST_TARGET} bs=64k count=16k conv=fdatasync 2>&1 | awk -F, "{print \$NF}" | sed "s/^[ \t]*//")
rm -f ${TEST_TARGET}
echo -e " 顺序写入速率   : ${C_GREEN}${IO_SPEED}${C_RESET}"
echo ""

echo -e "${C_YELLOW}[ 全球主流节点网络下载测速 ]${C_RESET}"
echo -e "------------------------------------------------------------------------------"
printf "%-18s %-22s %-16s %-12s\n" "测试节点" "所在区域" "下载速度" "网络延迟"
echo -e "------------------------------------------------------------------------------"

test_speed() {
    local node_name="\$1"
    local region="\$2"
    local url="\$3"
    local host=$(echo "\$url" | awk -F/ "{print \$3}" | awk -F: "{print \$1}")
    local ping_ms=$(ping -c 2 -W 2 "\$host" 2>/dev/null | awk -F"/" "END {if (NF>4) printf \"%.1f ms\", \$5; else echo \"超时\"}")
    [ -z "\$ping_ms" ] && ping_ms="N/A"
    local speed=$(curl -k -m 6 -sLo /dev/null -w "%{speed_download}" "\$url" 2>/dev/null || echo 0)
    local speed_mbps=$(awk -v s="\$speed" "BEGIN {printf \"%.2f Mbps\", s*8/1024/1024}")
    printf "%-18s %-22s %-16s %-12s\n" "\$node_name" "\$region" "\$speed_mbps" "\$ping_ms"
}

test_speed "Cloudflare"     "全球 CDN Anycast"    "https://speed.cloudflare.com/__down?bytes=50000000"
test_speed "Fast.com"       "全球流媒体 CDN"    "https://api.fast.com/netflix/speedtest"
test_speed "Hetzner"        "欧洲 (德国 纽伦堡)"  "https://fsn1-speed.hetzner.com/100MB.bin"
test_speed "Linode"         "亚太 (日本 东京)"    "http://speedtest.tokyo2.linode.com/100MB-tokyo2.bin"
test_speed "Linode"         "亚太 (新加坡)"       "http://speedtest.singapore.linode.com/100MB-singapore.bin"
test_speed "Linode"         "北美 (美国 弗里蒙特)" "http://speedtest.fremont.linode.com/100MB-fremont.bin"

echo -e "------------------------------------------------------------------------------"
echo -e "${C_GREEN}测试完成！${C_RESET}"
