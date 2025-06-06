#!/bin/bash

# ========================================================================
# Kernel Management System Installer (v2 with Alias)
#
# 这个脚本将自动安装和配置内核管理系统，包括：
# 1. 主升级脚本 (manage-kernel.sh)
# 2. 快捷命令 'xupdate'
# 3. 后台清理脚本 (kernel-cleaner)
# 4. systemd 服务 (kernel-cleanup.service)
#
# 只需运行一次 'sudo ./setup-kernel-management.sh' 即可完成所有设置。
# ========================================================================

# --- 定义文件路径和颜色 ---
MANAGE_SCRIPT_PATH="/usr/local/bin/manage-kernel.sh"
SYMLINK_PATH="/usr/local/bin/xupdate" # 快捷命令的路径
CLEANER_SCRIPT_PATH="/usr/local/bin/kernel-cleaner"
SERVICE_FILE_PATH="/etc/systemd/system/kernel-cleanup.service"

C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RED='\033[0;31m'

log_info() { echo -e "${C_CYAN}INFO: $1${C_RESET}"; }
log_ok() { echo -e "${C_GREEN}OK: $1${C_RESET}"; }
log_warn() { echo -e "${C_YELLOW}WARN: $1${C_RESET}"; }
log_error() { echo -e "${C_RED}ERROR: $1${C_RESET}"; }


# --- 确保以 root 权限运行 ---
if [ "$(id -u)" -ne 0 ]; then
  log_error "此安装脚本需要以 root 权限运行。请使用 'sudo ./setup-kernel-management.sh'。"
  exit 1
fi

set -e # 如果任何命令失败，则立即退出

# --- 1. 创建主管理脚本 (manage-kernel.sh) ---
log_info "正在创建主管理脚本: $MANAGE_SCRIPT_PATH..."
tee "$MANAGE_SCRIPT_PATH" > /dev/null << 'EOF'
#!/bin/bash
# This is the main script you run to upgrade the kernel.
C_RESET='\033[0m';C_RED='\033[0;31m';C_GREEN='\033[0;32m';C_YELLOW='\033[0;33m';C_BLUE='\033[0;34m';log_info(){echo -e "${C_BLUE}INFO: $1${C_RESET}";};log_ok(){echo -e "${C_GREEN}OK: $1${C_RESET}";};log_error(){echo -e "${C_RED}ERROR: $1${C_RESET}";};log_warn(){echo -e "${C_YELLOW}WARN: $1${C_RESET}";};main(){if [ "$(id -u)" -ne 0 ];then log_error "此脚本需要以 root 权限运行。请使用 'sudo'。";exit 1;fi;log_info "正在更新系统并安装新内核...";apt-get update&&apt-get full-upgrade -y;if [ $? -eq 0 ];then log_ok "系统升级完成。";log_info "正在启用下一次启动后的自动清理服务...";systemctl enable kernel-cleanup.service;log_ok "自动清理服务已启用。";log_warn "请立即重启系统 'sudo reboot' 来应用新内核。旧内核将在重启后被自动清理。";else log_error "系统升级失败。未启用自动清理服务。";exit 1;fi;};main
EOF
chmod +x "$MANAGE_SCRIPT_PATH"
log_ok "主管理脚本创建成功。"

# --- 2. 创建快捷命令 xupdate ---
log_info "正在创建快捷命令: $SYMLINK_PATH..."
# 使用 -sf 参数：s 表示符号链接，f 表示如果目标已存在则强制覆盖
ln -sf "$MANAGE_SCRIPT_PATH" "$SYMLINK_PATH"
log_ok "快捷命令 'xupdate' 创建成功。"

# --- 3. 创建后台清理脚本 (kernel-cleaner) ---
log_info "正在创建后台清理脚本: $CLEANER_SCRIPT_PATH..."
tee "$CLEANER_SCRIPT_PATH" > /dev/null << 'EOF'
#!/bin/bash
# This script runs in the background to clean old kernels.
EXTRA_KERNELS_TO_KEEP=1;KERNEL_PATTERN='linux-image-*-xanmod*';log_to_syslog(){logger -t KERNEL_CLEANER "$1";};log_to_syslog "Starting automatic kernel cleanup...";if [ "$(id -u)" -ne 0 ];then log_to_syslog "Error: Not root. Exiting.";exit 1;fi;RUNNING_KERNEL_IMAGE="linux-image-$(uname -r)";ALL_KERNELS=$(dpkg-query -W -f='${Package}\n' "$KERNEL_PATTERN" 2>/dev/null|sort -V);OTHER_KERNELS=$(echo "$ALL_KERNELS"|grep -v "$RUNNING_KERNEL_IMAGE");LATEST_BACKUP_KERNELS=$(echo "$OTHER_KERNELS"|tail -n "$EXTRA_KERNELS_TO_KEEP");KERNELS_TO_KEEP_LIST="$RUNNING_KERNEL_IMAGE";if [ ! -z "$LATEST_BACKUP_KERNELS" ];then KERNELS_TO_KEEP_LIST=$(echo -e "$KERNELS_TO_KEEP_LIST\n$LATEST_BACKUP_KERNELS"|sort -u);fi;KERNELS_TO_PURGE_LIST=$(comm -23 <(echo "$ALL_KERNELS"|sort) <(echo "$KERNELS_TO_KEEP_LIST"|sort));if [ -z "$KERNELS_TO_PURGE_LIST" ];then log_to_syslog "No old kernels to clean. Exiting.";exit 0;fi;PACKAGES_TO_PURGE="";for KERNEL_IMAGE in $KERNELS_TO_PURGE_LIST;do PACKAGES_TO_PURGE="$PACKAGES_TO_PURGE $KERNEL_IMAGE";VERSION_STRING=$(echo "$KERNEL_IMAGE"|sed -e "s/linux-image-//");HEADER_PKG="linux-headers-${VERSION_STRING}";if dpkg-query -W -f='${Status}' "$HEADER_PKG" 2>/dev/null|grep -q "ok installed";then PACKAGES_TO_PURGE="$PACKAGES_TO_PURGE $HEADER_PKG";fi;done;log_to_syslog "Purging packages: $PACKAGES_TO_PURGE";echo "$PACKAGES_TO_PURGE"|tr ' ' '\n'|xargs -r apt-get purge -y --allow-remove-essential;apt-get autoremove -y;update-grub;log_to_syslog "Kernel cleanup finished successfully."
EOF
chmod +x "$CLEANER_SCRIPT_PATH"
log_ok "后台清理脚本创建成功。"


# --- 4. 创建 systemd 服务文件 ---
log_info "正在创建 systemd 服务文件: $SERVICE_FILE_PATH..."
tee "$SERVICE_FILE_PATH" > /dev/null << 'EOF'
[Unit]
Description=One-time Kernel Cleanup Service
After=network-online.target multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "/usr/local/bin/kernel-cleaner && systemctl disable kernel-cleanup.service"
TimeoutStartSec=15min

[Install]
WantedBy=multi-user.target
EOF
log_ok "systemd 服务文件创建成功。"


# --- 5. 完成系统设置 ---
log_info "正在重载 systemd 配置以识别新服务..."
systemctl daemon-reload
log_ok "systemd 配置重载完成。"

echo
log_ok "========================================"
log_ok "  内核管理系统安装成功！"
log_ok "========================================"
echo
log_info "用法说明:"
echo "当您想升级内核时，只需在终端运行以下任一命令："
log_warn "  sudo xupdate"
echo "或"
log_warn "  sudo manage-kernel.sh"
echo
echo "升级后重启，旧内核将会被自动清理。"
echo

exit 0
