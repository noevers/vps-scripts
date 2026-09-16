#!/bin/bash
# ==============================================================================
# Script: tune.sh (Debian 12 代理节点与网络吞吐专项优化)
# Description: BBR+FQ 拥塞控制 / 100万文件句柄与高并发优化 / TCP 缓冲区扩容 / 
#              UDP (QUIC/Hysteria/TUIC) 缓冲区与防丢包 / 虚拟内存降 Swappiness
# Usage:
#   curl -sL https://raw.githubusercontent.com/noevers/vps-scripts/main/tune.sh | bash
# ==============================================================================

set -e

# --- 颜色与输出格式 ---
C_RESET="\033[0m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_CYAN="\033[1;36m"

info()  { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
ok()    { echo -e "${C_GREEN}[OK]${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $*"; exit 1; }

# 必须 root 权限
[ "$(id -u)" -ne 0 ] && error "请使用 root 用户运行此脚本！"

echo -e "${C_BLUE}==============================================================================${C_RESET}"
echo -e "${C_GREEN}       Debian 12 代理节点与高并发网络优化脚本 (vps-scripts/tune.sh)           ${C_RESET}"
echo -e "${C_BLUE}==============================================================================${C_RESET}"

# 1. 检查并加载必要内核模块
info "检查并加载 BBR 与 FQ 内核模块..."
modprobe tcp_bbr 2>/dev/null || true
if ! grep -q "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
    mkdir -p /etc/modules-load.d
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

# 2. 系统级文件句柄与进程限制 (limits.conf)
info "调优系统最大文件描述符与进程限制 (1,000,000 limits)..."
cat << 'LIMITS_EOF' > /etc/security/limits.d/99-proxy-limits.conf
* soft nofile 1000000
* hard nofile 1000000
* soft nproc 1000000
* hard nproc 1000000
root soft nofile 1000000
root hard nofile 1000000
root soft nproc 1000000
root hard nproc 1000000
LIMITS_EOF

# 调优 systemd 全局句柄限制
mkdir -p /etc/systemd/system.conf.d
cat << 'SYSCONF_EOF' > /etc/systemd/system.conf.d/99-limits.conf
[Manager]
DefaultLimitNOFILE=1000000
DefaultLimitNPROC=1000000
SYSCONF_EOF

# 3. 核心网络与内核参数优化 (sysctl)
info "应用针对 TCP/UDP (Xray/Sing-box/Hysteria/TUIC) 的内核调优参数..."

cat << 'SYSCTL_EOF' > /etc/sysctl.d/99-proxy-tune.conf
# ==============================================================================
# TCP 拥塞控制与排队规则 (BBR + FQ)
# ==============================================================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ==============================================================================
# 连接队列与高并发防丢包
# ==============================================================================
fs.file-max = 1000000
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 65535

# ==============================================================================
# TIME_WAIT 连接重用与快速释放
# ==============================================================================
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# ==============================================================================
# TCP Keepalive 优化 (防止长连接/代理隧道被运营商静默中断)
# ==============================================================================
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# ==============================================================================
# TCP 缓冲区扩容 (提升远距离跨境大延迟链路吞吐量)
# ==============================================================================
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 67108864
net.ipv4.tcp_wmem = 4096 1048576 67108864

# ==============================================================================
# UDP 缓冲区专项优化 (针对 QUIC / Hysteria 2 / TUIC / WireGuard 防止丢包限速)
# ==============================================================================
net.core.optmem_max = 65536
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# ==============================================================================
# TCP 窗口与路径优化 (提升抗抖动与握手速度)
# ==============================================================================
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_notsent_lowat = 16384

# ==============================================================================
# 虚拟内存与 Swap 调优 (降低 Swappiness，保留物理内存响应速度)
# ==============================================================================
vm.swappiness = 10
vm.dirty_ratio = 30
vm.dirty_background_ratio = 5
SYSCTL_EOF

# 生效 sysctl 参数
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-proxy-tune.conf >/dev/null 2>&1

# 4. 验证并输出当前配置状态
echo ""
echo -e "${C_BLUE}==============================================================================${C_RESET}"
echo -e "${C_GREEN}                      网络与内核优化配置验证结果                             ${C_RESET}"
echo -e "${C_BLUE}==============================================================================${C_RESET}"

CUR_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
CUR_QD=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
CUR_NOFILE=$(ulimit -n)
CUR_RMEM=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "未知")
CUR_WMEM=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "未知")

echo -e "TCP 拥塞控制算法 : ${C_GREEN}${CUR_CC}${C_RESET} (目标: bbr)"
echo -e "队列排队调度算法 : ${C_GREEN}${CUR_QD}${C_RESET} (目标: fq)"
echo -e "当前会话文件句柄 : ${C_GREEN}${CUR_NOFILE}${C_RESET} (系统配置: 1000000)"
echo -e "核心接收缓冲上限 : ${C_GREEN}${CUR_RMEM}${C_RESET} (64MB)"
echo -e "核心发送缓冲上限 : ${C_GREEN}${CUR_WMEM}${C_RESET} (64MB)"
echo -e "${C_BLUE}==============================================================================${C_RESET}"

if [ "$CUR_CC" = "bbr" ]; then
    ok "BBR 拥塞控制算法已成功启用并生效！"
else
    warn "当前算法为 $CUR_CC，部分内核需要重启后生效，建议运行 reboot 重启生效。"
fi

ok "代理网络与系统高并发调优配置已全部完成，长期有效！"
