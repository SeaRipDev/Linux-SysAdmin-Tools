#!/bin/bash
####################################################################################################
#
# Fedora System Doctor - Interactive System Health Check and Repair
#
# Purpose: Diagnose and repair common Fedora system issues
# Optimized for Fedora Workstation and Server
#
# Usage: sudo bash FedoraSysDr.sh
#
# Author: SeaRipDev
# Version: 1.0
# Date: 2025-11-25
#
####################################################################################################

# Script configuration
SCRIPT_VERSION="1.0"
LOG_DIR="/var/log/fedora-sysdr"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/check-$TIMESTAMP.log"
BACKUP_DIR="/root/fedora-sysdr-backup"

# Counters for issues
ISSUES_FOUND=0
ISSUES_FIXED=0
WARNINGS_FOUND=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

####################################################################################################
# Helper Functions
####################################################################################################

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE" 2>/dev/null
}

print_header() {
    echo ""
    print_color "$CYAN" "=========================================="
    print_color "$CYAN" "$1"
    print_color "$CYAN" "=========================================="
}

print_success() {
    print_color "$GREEN" "✓ $1"
}

print_error() {
    print_color "$RED" "✗ $1"
    ((ISSUES_FOUND++))
}

print_warning() {
    print_color "$YELLOW" "⚠ $1"
    ((WARNINGS_FOUND++))
}

print_info() {
    print_color "$BLUE" "ℹ $1"
}

ask_yes_no() {
    local question=$1
    local response
    while true; do
        read -p "$(echo -e ${YELLOW}$question ${NC}[y/n]: )" response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

####################################################################################################
# System Detection
####################################################################################################

detect_fedora_system() {
    print_info "Detecting Fedora system..."

    if [ -f /etc/fedora-release ]; then
        DISTRO_NAME=$(cat /etc/fedora-release)
        print_success "Distribution: $DISTRO_NAME"

        # Extract Fedora version number
        FEDORA_VERSION=$(rpm -E %fedora)
        print_info "Fedora Version: $FEDORA_VERSION"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "fedora" ]]; then
            DISTRO_NAME=$PRETTY_NAME
            FEDORA_VERSION=$VERSION_ID
            print_success "Distribution: $DISTRO_NAME"
        else
            print_error "Not a Fedora system!"
            exit 1
        fi
    else
        print_error "Not a Fedora system!"
        exit 1
    fi

    # DNF should be available on all modern Fedora
    if command -v dnf &> /dev/null; then
        print_success "Package Manager: dnf"
    else
        print_error "DNF package manager not found!"
        exit 1
    fi
}

####################################################################################################
# Pre-Flight Checks
####################################################################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root or with sudo"
        echo ""
        echo "Please run: sudo bash $0"
        exit 1
    fi
    print_success "Running with root privileges"
}

create_log_dir() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_success "Log directory created: $LOG_DIR"
        else
            print_warning "Could not create log directory. Logging to /tmp"
            LOG_DIR="/tmp"
            LOG_FILE="$LOG_DIR/fedora-sysdr-$TIMESTAMP.log"
        fi
    fi
}

####################################################################################################
# Fedora-Specific Health Checks
####################################################################################################

check_fedora_version() {
    print_header "Checking Fedora Version & EOL Status"

    print_info "Running Fedora $FEDORA_VERSION"

    # Fedora has a predictable release schedule
    # Each version is supported for approximately 13 months
    current_year=$(date +%Y)
    current_month=$(date +%m)

    # Fedora releases twice a year (roughly April and October)
    # Version numbers increment by 1 each release
    # This is a rough check - actual EOL dates should be verified

    if [ "$FEDORA_VERSION" -lt 39 ]; then
        print_error "Fedora $FEDORA_VERSION is likely End of Life - upgrade recommended!"
    elif [ "$FEDORA_VERSION" -lt 40 ]; then
        print_warning "Fedora $FEDORA_VERSION may be approaching EOL soon - consider upgrading"
    else
        print_success "Fedora version is current"
    fi

    # Check for version upgrade availability
    print_info "Checking for Fedora version upgrades..."
    available_upgrade=$(dnf system-upgrade download --refresh --releasever=$((FEDORA_VERSION + 1)) --assumeno 2>&1 | head -n 20)

    if echo "$available_upgrade" | grep -q "Fedora $((FEDORA_VERSION + 1))"; then
        print_info "Fedora $((FEDORA_VERSION + 1)) is available for upgrade"
    fi
}

check_dnf_repos() {
    print_header "Checking DNF Repositories"

    # Check for enabled repositories
    enabled=$(dnf repolist enabled 2>/dev/null | grep -c "^[^!]" || echo "0")
    if [ "$enabled" -gt 0 ]; then
        print_success "$enabled repository/repositories enabled"
    else
        print_error "No enabled repositories found"
    fi

    # List enabled repos
    print_info "Enabled repositories:"
    dnf repolist enabled --quiet 2>/dev/null | grep -E "^(fedora|updates|rpmfusion)" | while read -r line; do
        print_info "  - $(echo $line | awk '{print $1}')"
    done

    # Check for RPM Fusion
    if dnf repolist enabled 2>/dev/null | grep -q "rpmfusion"; then
        print_success "RPM Fusion repositories are enabled"
    else
        print_info "RPM Fusion repositories not detected (optional but useful)"
    fi

    # Check for repository errors
    print_info "Testing repository connectivity..."
    dnf repolist -q 2>&1 | grep -i "error\|fail" > /tmp/repo-errors.log
    if [ -s /tmp/repo-errors.log ]; then
        print_error "Repository errors detected:"
        cat /tmp/repo-errors.log | head -n 5
    else
        print_success "All repositories accessible"
    fi

    # Check metadata age
    print_info "Checking repository metadata freshness..."
    metadata_age=$(dnf check-update --refresh 2>&1 | grep -i "metadata" | head -n 1)
    if [ -n "$metadata_age" ]; then
        print_info "$metadata_age"
    fi
}

check_flatpak() {
    print_header "Checking Flatpak Status"

    if command -v flatpak &> /dev/null; then
        print_success "Flatpak is installed"

        # Check for Flathub
        if flatpak remotes 2>/dev/null | grep -q "flathub"; then
            print_success "Flathub repository is configured"
        else
            print_warning "Flathub repository not configured"
        fi

        # Count installed flatpaks
        flatpak_count=$(flatpak list --app 2>/dev/null | wc -l)
        if [ "$flatpak_count" -gt 0 ]; then
            print_info "$flatpak_count Flatpak application(s) installed"

            # Check for updates
            flatpak_updates=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
            if [ "$flatpak_updates" -gt 0 ]; then
                print_warning "$flatpak_updates Flatpak update(s) available"
            else
                print_success "All Flatpak applications are up to date"
            fi
        else
            print_info "No Flatpak applications installed"
        fi
    else
        print_warning "Flatpak is not installed"
    fi
}

check_firmware() {
    print_header "Checking Firmware Updates"

    if command -v fwupdmgr &> /dev/null; then
        print_success "fwupd is installed"

        # Refresh firmware metadata
        print_info "Checking for firmware updates..."
        fwupdmgr refresh --force &>/dev/null

        # Check for available updates
        fw_updates=$(fwupdmgr get-updates 2>&1)

        if echo "$fw_updates" | grep -q "No upgrades"; then
            print_success "Firmware is up to date"
        elif echo "$fw_updates" | grep -q "Devices with no available firmware updates"; then
            print_success "No firmware updates available"
        elif echo "$fw_updates" | grep -q "has firmware updates"; then
            print_warning "Firmware updates are available"
            echo "$fw_updates" | grep -A 2 "has firmware updates" | head -n 10
        else
            print_info "Could not determine firmware update status"
        fi
    else
        print_warning "fwupd not installed (firmware updates unavailable)"
    fi
}

check_selinux() {
    print_header "Checking SELinux Status"

    if command -v getenforce &> /dev/null; then
        selinux_status=$(getenforce)

        case $selinux_status in
            Enforcing)
                print_success "SELinux is Enforcing (secure)"

                # Check for SELinux denials
                if command -v ausearch &> /dev/null; then
                    denials=$(ausearch -m avc -ts recent 2>/dev/null | grep -c "denied" || echo "0")
                    if [ "$denials" -gt 10 ]; then
                        print_warning "Found $denials recent SELinux denials"
                        print_info "Run: ausearch -m avc -ts recent | audit2why"
                    elif [ "$denials" -gt 0 ]; then
                        print_info "Found $denials recent SELinux denials (normal)"
                    fi
                fi
                ;;
            Permissive)
                print_warning "SELinux is in Permissive mode (not enforcing)"
                ;;
            Disabled)
                print_warning "SELinux is Disabled (not recommended)"
                ;;
            *)
                print_error "Could not determine SELinux status"
                ;;
        esac
    else
        print_warning "SELinux tools not installed"
    fi
}

check_firewalld() {
    print_header "Checking Firewall Status"

    if command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            print_success "firewalld is running"

            # Get active zone
            active_zone=$(firewall-cmd --get-active-zones 2>/dev/null | head -n1)
            if [ -n "$active_zone" ]; then
                print_info "Active zone: $active_zone"

                # List open services
                services=$(firewall-cmd --list-services 2>/dev/null)
                print_info "Allowed services: $services"

                # List open ports
                ports=$(firewall-cmd --list-ports 2>/dev/null)
                if [ -n "$ports" ]; then
                    print_info "Open ports: $ports"
                fi
            fi
        else
            print_warning "firewalld is not running"
        fi
    else
        print_warning "firewalld not installed"
    fi
}

check_kernel_updates() {
    print_header "Checking Kernel Status"

    # Current running kernel
    running_kernel=$(uname -r)
    print_info "Running kernel: $running_kernel"

    # Latest installed kernel
    latest_kernel=$(rpm -q kernel | tail -n1 | sed 's/kernel-//')
    print_info "Latest installed: $latest_kernel"

    if [ "$running_kernel" != "$latest_kernel" ]; then
        print_warning "System is not running the latest kernel (reboot recommended)"
    else
        print_success "Running the latest installed kernel"
    fi

    # Check for available kernel updates
    kernel_updates=$(dnf check-update kernel 2>/dev/null | grep "^kernel" | wc -l)
    if [ "$kernel_updates" -gt 0 ]; then
        print_warning "Kernel updates available"
    else
        print_success "Kernel is up to date"
    fi

    # List all installed kernels
    installed_kernels=$(rpm -q kernel | wc -l)
    print_info "Total installed kernels: $installed_kernels"
    if [ "$installed_kernels" -gt 3 ]; then
        print_info "Old kernels will be auto-removed (installonly_limit in dnf.conf)"
    fi
}

check_disk_space() {
    print_header "Checking Disk Space"

    # Check each mounted filesystem
    while IFS= read -r line; do
        filesystem=$(echo "$line" | awk '{print $1}')
        mountpoint=$(echo "$line" | awk '{print $6}')
        usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')

        if [ "$usage" -ge 90 ]; then
            print_error "$mountpoint is ${usage}% full (Critical!)"
        elif [ "$usage" -ge 75 ]; then
            print_warning "$mountpoint is ${usage}% full"
        else
            print_success "$mountpoint is ${usage}% full"
        fi
    done < <(df -h | grep "^/dev")

    # Check inode usage
    print_info "Checking inode usage..."
    while IFS= read -r line; do
        filesystem=$(echo "$line" | awk '{print $1}')
        mountpoint=$(echo "$line" | awk '{print $6}')
        usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')

        if [ "$usage" -ge 90 ]; then
            print_error "$mountpoint inodes are ${usage}% full"
        elif [ "$usage" -ge 75 ]; then
            print_warning "$mountpoint inodes are ${usage}% full"
        fi
    done < <(df -i | grep "^/dev")

    # Check for large files in /var
    print_info "Checking for large files in /var..."
    large_files=$(find /var -type f -size +1G 2>/dev/null | wc -l)
    if [ "$large_files" -gt 0 ]; then
        print_info "Found $large_files file(s) over 1GB in /var"
    fi
}

check_package_system() {
    print_header "Checking Package System Health"

    # Check for package manager lock
    if [ -f /var/cache/dnf/metadata_lock.pid ]; then
        if ps -p $(cat /var/cache/dnf/metadata_lock.pid) > /dev/null 2>&1; then
            print_warning "Package manager is currently locked (another process using it)"
        fi
    fi

    # Check for duplicate packages
    duplicates=$(dnf repoquery --duplicates 2>/dev/null | wc -l)
    if [ "$duplicates" -gt 0 ]; then
        print_warning "Found $duplicates duplicate package(s)"
    else
        print_success "No duplicate packages found"
    fi

    # Check for available updates
    print_info "Checking for available updates..."
    total_updates=$(dnf check-update -q 2>/dev/null | grep -v "^$\|^Last" | wc -l)

    if [ "$total_updates" -gt 0 ]; then
        print_warning "$total_updates package update(s) available"
    else
        print_success "All packages are up to date"
    fi

    # Check DNF cache size
    cache_size=$(du -sh /var/cache/dnf 2>/dev/null | awk '{print $1}')
    if [ -n "$cache_size" ]; then
        print_info "DNF cache size: $cache_size"
    fi
}

check_services() {
    print_header "Checking System Services"

    # Check for failed services
    failed_services=$(systemctl --failed --no-legend | wc -l)

    if [ "$failed_services" -gt 0 ]; then
        print_error "Found $failed_services failed service(s):"
        systemctl --failed --no-legend | while read -r line; do
            service=$(echo "$line" | awk '{print $1}')
            print_error "  - $service"
        done
    else
        print_success "No failed services"
    fi

    # Check critical Fedora services
    critical_services=("sshd" "NetworkManager" "firewalld" "rsyslog" "chronyd" "systemd-resolved")
    print_info "Checking critical services..."

    for service in "${critical_services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            if systemctl is-active --quiet "$service"; then
                print_success "$service is running"
            else
                if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                    print_warning "$service is enabled but not running"
                else
                    print_info "$service is not enabled"
                fi
            fi
        fi
    done
}

check_system_logs() {
    print_header "Checking System Logs for Errors"

    # Check for errors in current boot
    error_count=$(journalctl -p err -b 2>/dev/null | grep -c "")

    if [ "$error_count" -gt 50 ]; then
        print_error "Found $error_count errors in system logs"
        print_info "Recent errors:"
        journalctl -p err -b --no-pager -n 5 2>/dev/null | tail -n 5
    elif [ "$error_count" -gt 10 ]; then
        print_warning "Found $error_count errors in system logs"
    else
        print_success "Minimal errors in system logs ($error_count)"
    fi

    # Check journal size
    journal_size=$(journalctl --disk-usage 2>/dev/null | awk '{print $7}' | sed 's/\.$//')
    if [ -n "$journal_size" ]; then
        print_info "Journal disk usage: $journal_size"
    fi
}

check_memory() {
    print_header "Checking Memory Status"

    # Get memory info
    total_mem=$(free -m | awk 'NR==2{print $2}')
    used_mem=$(free -m | awk 'NR==2{print $3}')
    available_mem=$(free -m | awk 'NR==2{print $7}')
    mem_percent=$(( used_mem * 100 / total_mem ))

    if [ "$mem_percent" -ge 90 ]; then
        print_error "Memory usage is ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
    elif [ "$mem_percent" -ge 75 ]; then
        print_warning "Memory usage is ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
    else
        print_success "Memory usage is ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
    fi

    # Check swap
    swap_total=$(free -m | awk 'NR==3{print $2}')
    if [ "$swap_total" -eq 0 ]; then
        print_warning "No swap space configured"
    else
        swap_used=$(free -m | awk 'NR==3{print $3}')
        if [ "$swap_total" -gt 0 ]; then
            swap_percent=$(( swap_used * 100 / swap_total ))
            if [ "$swap_percent" -ge 50 ]; then
                print_warning "Swap usage is ${swap_percent}% (system may be low on RAM)"
            else
                print_success "Swap usage is ${swap_percent}%"
            fi
        fi
    fi

    # Check for zram (common on Fedora)
    if swapon --show | grep -q "zram"; then
        print_success "zram swap is active (compressed RAM swap)"
    fi
}

check_disk_health() {
    print_header "Checking Disk Health (SMART)"

    if ! command -v smartctl &> /dev/null; then
        print_warning "smartctl not installed (install smartmontools package)"
        return
    fi

    # Find all physical disks
    for disk in /dev/sd? /dev/nvme?n?; do
        if [ -b "$disk" ]; then
            disk_name=$(basename "$disk")

            # Check SMART health
            smart_health=$(smartctl -H "$disk" 2>/dev/null | grep "SMART overall-health" | awk '{print $NF}')

            if [ "$smart_health" == "PASSED" ]; then
                print_success "$disk_name: SMART status PASSED"
            elif [ "$smart_health" == "FAILED" ]; then
                print_error "$disk_name: SMART status FAILED - Disk may be failing!"
            else
                print_info "$disk_name: SMART status unknown or not supported"
            fi
        fi
    done
}

####################################################################################################
# Fedora-Specific Repair Functions
####################################################################################################

repair_package_system() {
    print_header "Repairing Package System"

    if ask_yes_no "Attempt to repair package database?"; then
        # Clean package cache
        print_info "Cleaning package cache..."
        dnf clean all

        # Rebuild RPM database
        print_info "Rebuilding RPM database..."
        rpm --rebuilddb

        # Check for package issues
        print_info "Running package verification..."
        dnf check

        print_success "Package repair completed"
        ((ISSUES_FIXED++))
    fi
}

repair_failed_services() {
    print_header "Repairing Failed Services"

    failed_services=$(systemctl --failed --no-legend | awk '{print $1}')

    if [ -z "$failed_services" ]; then
        print_info "No failed services to repair"
        return
    fi

    if ask_yes_no "Attempt to restart failed services?"; then
        for service in $failed_services; do
            print_info "Attempting to restart $service..."
            systemctl restart "$service"
            if systemctl is-active --quiet "$service"; then
                print_success "$service restarted successfully"
                ((ISSUES_FIXED++))
            else
                print_error "$service could not be restarted"
                print_info "Check logs with: journalctl -u $service -n 50"
            fi
        done
    fi
}

cleanup_disk_space() {
    print_header "Cleaning Up Disk Space"

    if ask_yes_no "Clean up system logs and temporary files?"; then
        # Clean journal logs (keep last 7 days)
        print_info "Cleaning journal logs (keeping last 7 days)..."
        journalctl --vacuum-time=7d

        # Clean package cache
        print_info "Cleaning DNF cache..."
        dnf clean all -y

        # Clean /tmp (files older than 10 days)
        print_info "Cleaning old temporary files..."
        find /tmp -type f -atime +10 -delete 2>/dev/null

        # Clean /var/tmp
        find /var/tmp -type f -atime +10 -delete 2>/dev/null

        # Compress old log files
        print_info "Compressing old log files..."
        find /var/log -type f -name "*.log" -mtime +30 -exec gzip {} \; 2>/dev/null

        print_success "Cleanup completed"
        ((ISSUES_FIXED++))
    fi
}

update_system() {
    print_header "Updating System Packages"

    total_updates=$(dnf check-update -q 2>/dev/null | grep -v "^$\|^Last" | wc -l)

    if [ "$total_updates" -eq 0 ]; then
        print_success "No updates available"
        return
    fi

    print_warning "Found $total_updates package update(s)"

    if ask_yes_no "Update all packages now?"; then
        print_info "Updating packages..."
        dnf update -y

        if [ $? -eq 0 ]; then
            print_success "System updated successfully"
            ((ISSUES_FIXED++))

            # Check if reboot is required
            if [ -f /var/run/reboot-required ]; then
                print_warning "System reboot is recommended"
            fi
        else
            print_error "Failed to update system"
        fi
    fi
}

update_flatpak() {
    print_header "Updating Flatpak Applications"

    if ! command -v flatpak &> /dev/null; then
        print_info "Flatpak not installed"
        return
    fi

    flatpak_updates=$(flatpak remote-ls --updates 2>/dev/null | wc -l)

    if [ "$flatpak_updates" -eq 0 ]; then
        print_success "No Flatpak updates available"
        return
    fi

    print_warning "Found $flatpak_updates Flatpak update(s)"

    if ask_yes_no "Update Flatpak applications now?"; then
        print_info "Updating Flatpaks..."
        flatpak update -y

        if [ $? -eq 0 ]; then
            print_success "Flatpak applications updated successfully"
            ((ISSUES_FIXED++))
        else
            print_error "Failed to update Flatpak applications"
        fi
    fi
}

update_firmware() {
    print_header "Updating Firmware"

    if ! command -v fwupdmgr &> /dev/null; then
        print_info "fwupd not installed"
        return
    fi

    # Refresh firmware metadata
    fwupdmgr refresh --force &>/dev/null

    # Check for updates
    fw_updates=$(fwupdmgr get-updates 2>&1)

    if echo "$fw_updates" | grep -q "No upgrades\|no available firmware"; then
        print_success "No firmware updates available"
        return
    fi

    if echo "$fw_updates" | grep -q "has firmware updates"; then
        print_warning "Firmware updates are available"

        if ask_yes_no "Update firmware now?"; then
            print_info "Updating firmware..."
            fwupdmgr update -y

            if [ $? -eq 0 ]; then
                print_success "Firmware updated successfully"
                print_warning "A reboot may be required for firmware changes"
                ((ISSUES_FIXED++))
            else
                print_error "Failed to update firmware"
            fi
        fi
    fi
}

####################################################################################################
# Main Menu
####################################################################################################

show_menu() {
    print_header "Fedora System Doctor v$SCRIPT_VERSION"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo -e "  ${CYAN}Health Checks:${NC}"
    echo "    1) Run full system health check"
    echo "    2) Check Fedora version & EOL status"
    echo "    3) Check DNF repositories"
    echo "    4) Check SELinux status"
    echo "    5) Check firewall configuration"
    echo "    6) Check package system"
    echo "    7) Check disk space & health"
    echo "    8) Check services"
    echo "    9) Check kernel status"
    echo "   10) Check Flatpak status"
    echo "   11) Check firmware status"
    echo ""
    echo -e "  ${MAGENTA}Updates & Repairs:${NC}"
    echo "   12) Update system packages (DNF)"
    echo "   13) Update Flatpak applications"
    echo "   14) Update firmware (fwupd)"
    echo "   15) Repair package system issues"
    echo "   16) Restart failed services"
    echo "   17) Clean up disk space"
    echo ""
    echo -e "  ${GREEN}Quick Actions:${NC}"
    echo "   18) Run all checks and updates (recommended)"
    echo "    0) Exit"
    echo ""
}

run_full_check() {
    print_header "Running Full System Health Check"
    check_fedora_version
    check_dnf_repos
    check_selinux
    check_firewalld
    check_kernel_updates
    check_disk_space
    check_package_system
    check_services
    check_system_logs
    check_memory
    check_disk_health
    check_flatpak
    check_firmware
}

run_full_update() {
    run_full_check
    echo ""
    if [ "$ISSUES_FOUND" -gt 0 ] || [ "$WARNINGS_FOUND" -gt 0 ]; then
        print_warning "Found $ISSUES_FOUND issue(s) and $WARNINGS_FOUND warning(s)"
        if ask_yes_no "Would you like to attempt automatic repairs and updates?"; then
            repair_package_system
            repair_failed_services
            cleanup_disk_space
            update_system
            update_flatpak
            update_firmware
        fi
    else
        print_success "No issues found! System is healthy."
        if ask_yes_no "Would you like to check for updates anyway?"; then
            update_system
            update_flatpak
            update_firmware
        fi
    fi
}

show_summary() {
    print_header "Fedora System Doctor Summary"
    echo ""
    print_info "Hostname: $(hostname)"
    print_info "Uptime: $(uptime -p 2>/dev/null || uptime)"
    print_info "Distribution: $DISTRO_NAME"
    print_info "Kernel: $(uname -r)"
    echo ""
    print_color "$GREEN" "✓ Issues Found: $ISSUES_FOUND"
    print_color "$YELLOW" "⚠ Warnings: $WARNINGS_FOUND"
    print_color "$BLUE" "🔧 Issues Fixed: $ISSUES_FIXED"
    echo ""
    print_info "Log file: $LOG_FILE"
    echo ""

    if [ "$ISSUES_FOUND" -gt 0 ] || [ "$WARNINGS_FOUND" -gt 0 ]; then
        print_warning "Some issues may require manual attention. Check the log file for details."
    fi
}

####################################################################################################
# Main Script
####################################################################################################

# Initialize
check_root
create_log_dir
detect_fedora_system

# Main loop
while true; do
    show_menu
    read -p "$(echo -e ${CYAN}Enter your choice ${NC}[0-18]: )" choice

    case $choice in
        1) run_full_check ;;
        2) check_fedora_version ;;
        3) check_dnf_repos ;;
        4) check_selinux ;;
        5) check_firewalld ;;
        6) check_package_system ;;
        7) check_disk_space; check_disk_health ;;
        8) check_services ;;
        9) check_kernel_updates ;;
        10) check_flatpak ;;
        11) check_firmware ;;
        12) update_system ;;
        13) update_flatpak ;;
        14) update_firmware ;;
        15) repair_package_system ;;
        16) repair_failed_services ;;
        17) cleanup_disk_space ;;
        18) run_full_update ;;
        0)
            show_summary
            print_color "$GREEN" "Thank you for using Fedora System Doctor!"
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please enter a number from 0-18."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
