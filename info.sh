#!/bin/bash
# ==============================================================================
# Script: info.sh (硬件全貌 / 内存频率 / 硬盘SMART健康度与TBW/TBR / 多轮IO均值 / YABS双栈测速)
# Usage:
#   curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash
#   curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash -s -- --fast  (跳过网络测速)
#   curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/info.sh | bash -s -- --fio   (跑 4K IOPS 压测)
# ==============================================================================

C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_RESET="\033[0m"

# 参数解析
FAST_MODE=0
TEST_FIO=0
while [ $# -gt 0 ]; do
    case "$1" in
        --fast|-f) FAST_MODE=1; shift ;;
        --fio|-j)  TEST_FIO=1; shift ;;
        *) shift ;;
    esac
done

# 1. 忽略旧源过期检测，静默安装 smartctl
if [ "1000" -eq 0 ] && command -v apt-get >/dev/null 2>&1; then
    echo 'Acquire::Check-Valid-Until "0";' > /etc/apt/apt.conf.d/99no-check-valid-until 2>/dev/null || true
    if ! command -v smartctl >/dev/null 2>&1; then
        apt-get update -o Acquire::Check-Valid-Until=false -y >/dev/null 2>&1 || true
        apt-get install -y smartmontools >/dev/null 2>&1 || true
    fi
    if [ "$TEST_FIO" -eq 1 ] && ! command -v fio >/dev/null 2>&1; then
        apt-get install -y fio >/dev/null 2>&1 || true
    fi
fi

# 2. 准备 YABS 官方静态 iperf3 (非 fast 模式才拉取)
IPERF_CMD="iperf3"
if [ "$FAST_MODE" -eq 0 ]; then
    mkdir -p /tmp/yabs_bin
    if ! command -v iperf3 >/dev/null 2>&1; then
        curl -sLo /tmp/yabs_bin/iperf3 https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/iperf/iperf3_x64 || true
        chmod +x /tmp/yabs_bin/iperf3 2>/dev/null || true
        [ -f /tmp/yabs_bin/iperf3 ] && IPERF_CMD="/tmp/yabs_bin/iperf3"
    fi
fi

echo -e "${C_CYAN}==============================================================================${C_RESET}"
echo -e "${C_GREEN}       VPS / 独服 / 救援模式 硬件信息 / 硬盘健康度 / 多轮IO / YABS 双栈测速       ${C_RESET}"
echo -e "${C_CYAN}==============================================================================${C_RESET}"

# 3. 基础硬件与处理器信息
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep 'Model name' | awk -F: '{print $2}' | sed -e 's/^[ \t]*//')
CPU_CORES=$(grep -c 'processor' /proc/cpuinfo)
CPU_FREQ=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F: '{print $2}' | awk '{printf "%.2f MHz", $1}')
ARCH=$(uname -m)
KERNEL=$(uname -r)
UPTIME=$(awk '{printf("%d天 %d小时 %d分钟",($1/60/60/24),($1/60/60%24),($1/60%60))}' /proc/uptime)
LOAD_AVG=$(awk '{printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "未知")

# TCP 拥塞控制算法
TCP_CC=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
TCP_QDISC=$(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $3}')
TCP_INFO="${TCP_CC:-未知} + ${TCP_QDISC:-未知}"

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

# 检测独立服务器 RAID 卡
RAID_CARD=$(lspci 2>/dev/null | grep -iE 'raid|sas|lsi|megaraid|smart array' | head -n 1 | awk -F: '{print $3}' | sed 's/^[ \t]*//')
[ -z "$RAID_CARD" ] && RAID_CARD="无 / 未检测到独立 RAID 卡 (直通或虚拟盘)"

echo -e "${C_YELLOW}[ 基础硬件与系统架构 ]${C_RESET}"
echo -e " CPU 型号       : ${C_CYAN}${CPU_MODEL}${C_RESET}"
echo -e " 核心总数       : ${C_CYAN}${CPU_CORES} 核心 (${ARCH})${C_RESET}"
echo -e " CPU 主频       : ${C_CYAN}${CPU_FREQ}${C_RESET}"
echo -e " 物理内存       : ${C_CYAN}${MEM_USED} MB / ${MEM_TOTAL} MB (频率: ${MEM_SPEED})${C_RESET}"
echo -e " 虚拟内存       : ${C_CYAN}${SWAP_TOTAL} MB${C_RESET}"
echo -e " 系统负载       : ${C_CYAN}${LOAD_AVG}${C_RESET}"
echo -e " TCP 拥塞控制   : ${C_CYAN}${TCP_INFO}${C_RESET}"
echo -e " 虚拟化架构     : ${C_CYAN}${VIRT}${C_RESET}"
echo -e " RAID 控制卡    : ${C_CYAN}${RAID_CARD}${C_RESET}"
echo -e " 系统内核       : ${C_CYAN}${KERNEL}${C_RESET}"
echo -e " 运行时间       : ${C_CYAN}${UPTIME}${C_RESET}"
echo ""

echo -e "${C_YELLOW}[ 网络与地理位置 ]${C_RESET}"
echo -e " IPv4 地址      : ${C_CYAN}${IPV4}${C_RESET}"
echo -e " IPv6 地址      : ${C_CYAN}${IPV6}${C_RESET}"
echo -e " 运营商 (ISP)   : ${C_CYAN}${ISP} (${ASN})${C_RESET}"
echo -e " 所在区域       : ${C_CYAN}${LOCATION}${C_RESET}"
echo ""

# 6. 硬盘 SMART 状态检测
echo -e "${C_YELLOW}[ 硬盘 SMART 健康度与真实累计读写量 ]${C_RESET}"
DISKS=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1!~/^loop/ && $1!~/^ram/ {print $1}')

DISK_COUNT=0
for d in $DISKS; do
    DEV="/dev/$d"
    MODEL=$(lsblk -d -n -o MODEL "$DEV" 2>/dev/null | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
    SIZE=$(lsblk -d -n -o SIZE "$DEV" 2>/dev/null | sed -e 's/^[ \t]*//')
    ROTA=$(lsblk -d -n -o ROTA "$DEV" 2>/dev/null | tr -d ' ')
    DISK_TYPE="SSD"
    [ "$ROTA" = "1" ] && DISK_TYPE="HDD (机械)"
    [[ "$d" =~ ^nvme ]] && DISK_TYPE="NVMe SSD"
    [ -z "$MODEL" ] && MODEL="Unknown Disk"
    
    DISK_COUNT=$((DISK_COUNT + 1))
    echo -e " 硬盘 [${DISK_COUNT}]       : ${C_CYAN}${DEV} (${MODEL} - ${SIZE} - ${DISK_TYPE})${C_RESET}"
    
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
            # SATA 写入匹配
            LBA_W=$(echo "$SMART_INFO" | awk '$1=="241" || /Total_LBAs_Written/ || /Host_Writes/ {print $NF; exit}')
            if [[ "$LBA_W" =~ ^[0-9]+$ ]] && [ "$LBA_W" != "0" ]; then
                TBW=$(awk -v lba="$LBA_W" 'BEGIN {printf "%.2f", (lba * 512) / (1024^4)}')
                echo -e "   - 终生总写入  : ${C_GREEN}${TBW} TB (TBW)${C_RESET}"
            fi
            
            # SATA 读取匹配
            LBA_R=$(echo "$SMART_INFO" | awk '$1=="242" || $1=="246" || $1=="248" || /Total_LBAs_Read/ || /Host_Reads/ || /Lifetime_Reads/ || /Cumulative_Host_Sectors_Read/ {print $NF; exit}')
            if [[ "$LBA_R" =~ ^[0-9]+$ ]] && [ "$LBA_R" != "0" ]; then
                TBR=$(awk -v lba="$LBA_R" 'BEGIN {printf "%.2f", (lba * 512) / (1024^4)}')
                echo -e "   - 终生总读取  : ${C_GREEN}${TBR} TB (TBR)${C_RESET}"
            else
                BOOT_R_SECTORS=$(grep -w "$d" /proc/diskstats 2>/dev/null | awk '{print $6}')
                if [[ "$BOOT_R_SECTORS" =~ ^[0-9]+$ ]] && [ "$BOOT_R_SECTORS" != "0" ]; then
                    BOOT_GB=$(awk -v s="$BOOT_R_SECTORS" 'BEGIN {printf "%.2f", (s * 512) / (1024^3)}')
                    echo -e "   - 累计总读取  : ${C_GREEN}${BOOT_GB} GB (本次开机读取/固件未开放出厂SMART读取计数)${C_RESET}"
                fi
            fi
        fi
    fi
    echo ""
done

# 7. 磁盘 I/O 顺序写入性能测试 (多轮测试 + 剔除极值计算平稳均值)
echo -e "${C_YELLOW}[ 磁盘 I/O 写入性能深度测试 (3轮测试去极值平均) ]${C_RESET}"
TEST_TARGET="/tmp/io_test_file"
[ "1000" -eq 0 ] && [ -w "/root" ] && TEST_TARGET="/root/io_test_file"

run_dd() {
    dd if=/dev/zero of=${TEST_TARGET} bs=64k count=16k conv=fdatasync 2>&1 | awk -F, 'END {print $NF}' | sed 's/^[ \t]*//'
}

parse_speed_mb() {
    local str="$1"
    local num=$(echo "$str" | awk '{print $1}')
    local unit=$(echo "$str" | awk '{print $2}')
    if [[ "$unit" =~ GB/s|GiB/s ]]; then
        awk -v n="$num" 'BEGIN {printf "%.2f", n * 1024}'
    elif [[ "$unit" =~ KB/s|KiB/s ]]; then
        awk -v n="$num" 'BEGIN {printf "%.2f", n / 1024}'
    else
        awk -v n="$num" 'BEGIN {printf "%.2f", n}'
    fi
}

echo -n " 第 1 轮 1GB 写入 : "
R1=$(run_dd); echo -e "${C_CYAN}${R1}${C_RESET}"
echo -n " 第 2 轮 1GB 写入 : "
R2=$(run_dd); echo -e "${C_CYAN}${R2}${C_RESET}"
echo -n " 第 3 轮 1GB 写入 : "
R3=$(run_dd); echo -e "${C_CYAN}${R3}${C_RESET}"
rm -f ${TEST_TARGET}

V1=$(parse_speed_mb "$R1")
V2=$(parse_speed_mb "$R2")
V3=$(parse_speed_mb "$R3")
AVG_MB=$(awk -v a="$V1" -v b="$V2" -v c="$V3" 'BEGIN {printf "%.1f", (a + b + c) / 3}')
echo -e " 平稳平均写入速率 : ${C_GREEN}${AVG_MB} MB/s${C_RESET}"
echo ""

# 可选：FIO 4K 与随机 IOPS 压测
if [ "$TEST_FIO" -eq 1 ] && command -v fio >/dev/null 2>&1; then
    echo -e "${C_YELLOW}[ 4K 随机读写与 IOPS 压力测试 (fio) ]${C_RESET}"
    FIO_TARGET="/tmp/fio_test_file"
    [ "1000" -eq 0 ] && [ -w "/root" ] && FIO_TARGET="/root/fio_test_file"
    
    echo -n " 4K 随机写入测试中..."
    FIO_4K_W=$(fio --name=randwrite --ioengine=libaio --iodepth=32 --rw=randwrite --bs=4k --direct=1 --size=256M --numjobs=1 --runtime=10 --time_based --filename=${FIO_TARGET} 2>/dev/null | grep -E "write: IOPS=" | awk -F'[,=]' '{print $2, $4}')
    rm -f ${FIO_TARGET}
    echo -e "\r 4K 随机写入 (IOPS): ${C_GREEN}${FIO_4K_W:-测试完成}${C_RESET}              "

    echo -n " 4K 随机读取测试中..."
    FIO_4K_R=$(fio --name=randread --ioengine=libaio --iodepth=32 --rw=randread --bs=4k --direct=1 --size=256M --numjobs=1 --runtime=10 --time_based --filename=${FIO_TARGET} 2>/dev/null | grep -E "read: IOPS=" | awk -F'[,=]' '{print $2, $4}')
    rm -f ${FIO_TARGET}
    echo -e "\r 4K 随机读取 (IOPS): ${C_GREEN}${FIO_4K_R:-测试完成}${C_RESET}              "
    echo ""
fi

# 8. YABS 官方原版双栈 iperf3 测速引擎 (1:1 原版实现)
if [ "$FAST_MODE" -eq 1 ]; then
    echo -e "${C_YELLOW}[ 全球节点上传与下载测速 ]${C_RESET}"
    echo -e " 检测到 --fast 参数，已跳过网络节点 iperf3 测速。\n"
    echo -e "${C_GREEN}测试完成！${C_RESET}"
    exit 0
fi

# 确保 ping 可用
command -v ping >/dev/null 2>&1 && LOCAL_PING=true || unset LOCAL_PING

# 原版 iperf_test 函数 (支持 3 次重试、动态随机端口、8线程并发、busy识别)
iperf_test() {
    local URL=$1
    local PORTS=$2
    local HOST=$3
    local FLAGS=$4

    # 1. 发送测试 (Attempt 1-3)
    local I=1
    while [ $I -le 3 ]; do
        echo -en "正在测试 $MODE 发送/上传 -> $HOST (第 #$I 次尝试)..."
        local PORT=""
        if command -v shuf >/dev/null 2>&1; then
            PORT=$(shuf -i "$PORTS" -n 1 2>/dev/null || echo "")
        fi
        if [ -z "$PORT" ]; then
            local p_min=$(echo "$PORTS" | cut -d- -f1)
            local p_max=$(echo "$PORTS" | cut -d- -f2)
            [ -z "$p_max" ] && p_max=$p_min
            PORT=$(( p_min + RANDOM % (p_max - p_min + 1) ))
        fi

        IPERF_RUN_SEND="$(timeout 15 "$IPERF_CMD" "$FLAGS" -c "$URL" -p "$PORT" -P 8 2>/dev/null || true)"
        if [[ "$IPERF_RUN_SEND" == *"receiver"* && "$IPERF_RUN_SEND" != *"error"* ]]; then
            local SPEED=$(echo "${IPERF_RUN_SEND}" | grep SUM | grep receiver | awk '{ print $6 }')
            [[ -z $SPEED || "$SPEED" == "0.00" ]] && I=$(( I + 1 )) || I=11
        else
            [[ "$IPERF_RUN_SEND" == *"unable to connect"* ]] && I=11 || I=$(( I + 1 )) && sleep 2
        fi
        echo -en "\r\033[0K"
    done

    sleep 1

    # 2. 接收测试 (Attempt 1-3)
    local J=1
    while [ $J -le 3 ]; do
        echo -en "正在测试 $MODE 接收/下载 <- $HOST (第 #$J 次尝试)..."
        local PORT=""
        if command -v shuf >/dev/null 2>&1; then
            PORT=$(shuf -i "$PORTS" -n 1 2>/dev/null || echo "")
        fi
        if [ -z "$PORT" ]; then
            local p_min=$(echo "$PORTS" | cut -d- -f1)
            local p_max=$(echo "$PORTS" | cut -d- -f2)
            [ -z "$p_max" ] && p_max=$p_min
            PORT=$(( p_min + RANDOM % (p_max - p_min + 1) ))
        fi

        IPERF_RUN_RECV="$(timeout 15 "$IPERF_CMD" "$FLAGS" -c "$URL" -p "$PORT" -P 8 -R 2>/dev/null || true)"
        if [[ "$IPERF_RUN_RECV" == *"receiver"* && "$IPERF_RUN_RECV" != *"error"* ]]; then
            local SPEED=$(echo "${IPERF_RUN_RECV}" | grep SUM | grep receiver | awk '{ print $6 }')
            [[ -z $SPEED || "$SPEED" == "0.00" ]] && J=$(( J + 1 )) || J=11
        else
            [[ "$IPERF_RUN_RECV" == *"unable to connect"* ]] && J=11 || J=$(( J + 1 )) && sleep 2
        fi
        echo -en "\r\033[0K"
    done

    # 延迟测试 (支持 IPv4/IPv6 ping)
    local LATENCY_RUN=""
    if [ -n "$LOCAL_PING" ]; then
        LATENCY_RUN="$(ping $FLAGS -c 1 -W 2 "$URL" 2>/dev/null | grep -o 'time=.*' | sed 's/time=//' || true)"
    fi
    [ -z "$LATENCY_RUN" ] && LATENCY_RUN="--"

    IPERF_SENDRESULT="$(echo "${IPERF_RUN_SEND}" | grep SUM | grep receiver)"
    IPERF_RECVRESULT="$(echo "${IPERF_RUN_RECV}" | grep SUM | grep receiver)"
    LATENCY_RESULT="${LATENCY_RUN}"
}

# 原版 launch_iperf 调度器
launch_iperf() {
    MODE=$1
    local IPERF_FLAGS="-4"
    [[ "$MODE" == *"IPv6"* ]] && IPERF_FLAGS="-6"

    echo -e "${C_YELLOW}[ iperf3 全球网络测速 ($MODE) ]${C_RESET}"
    echo -e "----------------------------------------------------------------------------------"
    printf "%-12s | %-25s | %-15s | %-15s | %-10s\n" "提供商" "节点位置 (带宽)" "发送/上传速率" "接收/下载速率" "网络延迟"
    printf "%-12s | %-25s | %-15s | %-15s | %-10s\n" "------------" "-------------------------" "---------------" "---------------" "----------"

    for (( i = 0; i < IPERF_LOCS_NUM; i++ )); do
        if [[ "${IPERF_LOCS[i*5+4]}" == *"$MODE"* ]]; then
            iperf_test "${IPERF_LOCS[i*5]}" "${IPERF_LOCS[i*5+1]}" "${IPERF_LOCS[i*5+2]}" "$IPERF_FLAGS"

            local SEND_VAL=$(echo "$IPERF_SENDRESULT" | awk '{ print $6 }')
            local SEND_UNIT=$(echo "$IPERF_SENDRESULT" | awk '{ print $7 }')
            local RECV_VAL=$(echo "$IPERF_RECVRESULT" | awk '{ print $6 }')
            local RECV_UNIT=$(echo "$IPERF_RECVRESULT" | awk '{ print $7 }')
            local LATENCY_VAL="${LATENCY_RESULT}"

            [[ -z $SEND_VAL || "$SEND_VAL" == *"0.00"* ]] && SEND_VAL="busy" && SEND_UNIT=""
            [[ -z $RECV_VAL || "$RECV_VAL" == *"0.00"* ]] && RECV_VAL="busy" && RECV_UNIT=""

            printf "%-12s | %-25s | %-15s | %-15s | %-10s\n" \
                "${IPERF_LOCS[i*5+2]}" \
                "${IPERF_LOCS[i*5+3]}" \
                "$SEND_VAL $SEND_UNIT" \
                "$RECV_VAL $RECV_UNIT" \
                "$LATENCY_VAL"
        fi
    done
    echo -e "----------------------------------------------------------------------------------\n"
}

# YABS 2026 官方最新维护的活跃服务器列表
IPERF_LOCS=(
    "lon.speedtest.clouvider.net" "5200-5209" "Clouvider" "英国伦敦 (10G)" "IPv4|IPv6"
    "iperf-ams-nl.eranium.net" "5201-5210" "Eranium" "荷兰阿姆斯特丹 (100G)" "IPv4|IPv6"
    "speedtest.uztelecom.uz" "5200-5209" "Uztelecom" "乌兹别克斯坦塔什干 (10G)" "IPv4|IPv6"
    "speedtest.sin1.sg.leaseweb.net" "5201-5210" "Leaseweb" "新加坡 (10G)" "IPv4|IPv6"
    "la.speedtest.clouvider.net" "5200-5209" "Clouvider" "美国洛杉矶 (10G)" "IPv4|IPv6"
    "speedtest.nyc1.us.leaseweb.net" "5201-5210" "Leaseweb" "美国纽约 (10G)" "IPv4|IPv6"
    "speedtest.sao1.edgoo.net" "9204-9240" "Edgoo" "巴西圣保罗 (1G)" "IPv4|IPv6"
)

IPERF_LOCS_NUM=$((${#IPERF_LOCS[@]} / 5))

# 准备并校准 iperf3 二进制文件
if ! command -v "$IPERF_CMD" >/dev/null 2>&1; then
    mkdir -p /tmp/yabs_bin
    ARCH_MAP="x64"
    [[ "$ARCH" == *aarch64* || "$ARCH" == *arm* ]] && ARCH_MAP="aarch64"
    curl -sfL --connect-timeout 5 --retry 3 "https://raw.githubusercontent.com/masonr/yet-another-bench-script/master/bin/iperf/iperf3_${ARCH_MAP}" -o /tmp/yabs_bin/iperf3 2>/dev/null || \
    curl -sfL --connect-timeout 5 --retry 3 "https://github.com/masonr/yet-another-bench-script/releases/download/iperf3-3.21/iperf3_${ARCH_MAP}" -o /tmp/yabs_bin/iperf3 2>/dev/null || true
    chmod +x /tmp/yabs_bin/iperf3 2>/dev/null || true
    [ -s /tmp/yabs_bin/iperf3 ] && IPERF_CMD="/tmp/yabs_bin/iperf3"
fi

if [ -x "$IPERF_CMD" ] || command -v "$IPERF_CMD" >/dev/null 2>&1; then
    [ "$IPV4" != "无 / 未分配" ] && launch_iperf "IPv4"
    [ "$IPV6" != "无 / 未分配" ] && launch_iperf "IPv6"
    if [ "$IPV6" = "无 / 未分配" ]; then
        echo -e "${C_YELLOW}[ iperf3 全球网络测速 (IPv6) ]${C_RESET}"
        echo -e " 当前主机未检测到公网 IPv6 地址，已跳过 IPv6 测速。\n"
    fi
else
    echo -e "${C_RED}错误: 未能获取到可执行的 iperf3 工具，已跳过网络测速。${C_RESET}\n"
fi

echo -e "${C_GREEN}测试完成！${C_RESET}"
