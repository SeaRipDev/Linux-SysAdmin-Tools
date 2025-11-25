#!/bin/bash
####################################################################################################
#
# RHEL System Doctor - Interactive System Health Check and Repair
#
# Purpose: Diagnose and repair common RHEL/CentOS/Rocky/AlmaLinux system issues
# Optimized for Red Hat Enterprise Linux and derivatives
#
# Usage: sudo bash RHELSysDr.sh
#
# Author: CWRip / SeaDubRip
# Version: 1.0
# Date: 2025-11-25
#
####################################################################################################

# Script configuration
SCRIPT_VERSION="1.0"
LOG_DIR="/var/log/rhel-sysdr"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/check-$TIMESTAMP.log"
BACKUP_DIR="/root/rhel-sysdr-backup"

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

detect_rhel_system() {
    print_info "Detecting RHEL-based system..."

    if [ -f /etc/redhat-release ]; then
        DISTRO_NAME=$(cat /etc/redhat-release)
        print_success "Distribution: $DISTRO_NAME"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME=$PRETTY_NAME
        print_success "Distribution: $DISTRO_NAME"
    else
        print_error "Not a RHEL-based system!"
        exit 1
    fi

    # Detect package manager
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        print_success "Package Manager: dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        print_success "Package Manager: yum"
    else
        print_error "No supported package manager found!"
        exit 1
    fi

    # Detect RHEL version
    if [ -f /etc/redhat-release ]; then
        RHEL_VERSION=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) 2>/dev/null)
        if [ -n "$RHEL_VERSION" ]; then
            print_info "RHEL Version: $RHEL_VERSION"
        fi
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
            LOG_FILE="$LOG_DIR/rhel-sysdr-$TIMESTAMP.log"
        fi
    fi
}

####################################################################################################
# RHEL-Specific Health Checks
####################################################################################################

check_subscription_status() {
    print_header "Checking Subscription Status"

    if command -v subscription-manager &> /dev/null; then
        # Check subscription status
        sub_status=$(subscription-manager status 2>&1)

        if echo "$sub_status" | grep -q "Overall Status: Current"; then
            print_success "System is properly subscribed"
        elif echo "$sub_status" | grep -q "Overall Status: Invalid"; then
            print_error "System subscription is invalid or expired"
        elif echo "$sub_status" | grep -q "not registered"; then
            print_warning "System is not registered to Red Hat Subscription Management"
        else
            print_warning "Could not determine subscription status"
        fi

        # Check for available updates from subscription
        print_info "Checking subscribed repositories..."
        enabled_repos=$(subscription-manager repos --list-enabled 2>/dev/null | grep "Repo ID" | wc -l)
        if [ "$enabled_repos" -gt 0 ]; then
            print_success "$enabled_repos repository/repositories enabled"
        else
            print_warning "No repositories enabled"
        fi
    else
        print_info "subscription-manager not available (might be CentOS/Rocky/AlmaLinux)"
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
                print_warning "SELinux is Disabled (not recommended for production)"
                ;;
            *)
                print_error "Could not determine SELinux status"
                ;;
        esac

        # Check SELinux booleans that are commonly problematic
        print_info "Checking critical SELinux booleans..."
        if command -v getsebool &> /dev/null; then
            httpd_network=$(getsebool httpd_can_network_connect 2>/dev/null | awk '{print $3}')
            if [ "$httpd_network" == "on" ]; then
                print_info "httpd_can_network_connect is ON"
            fi
        fi
    else
        print_warning "SELinux tools not installed"
    fi
}

check_firewalld() {
    print_header "Checking Firewall Status"

    if command -v firewall-cmd &> /dev/null; then
        # Check if firewalld is running
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
        print_info "firewalld not installed, checking iptables..."

        if command -v iptables &> /dev/null; then
            rule_count=$(iptables -L -n | grep -c "ACCEPT\|DROP\|REJECT")
            if [ "$rule_count" -gt 0 ]; then
                print_info "iptables rules are configured ($rule_count rules)"
            else
                print_warning "No firewall rules detected"
            fi
        fi
    fi
}

check_yum_repos() {
    print_header "Checking YUM/DNF Repositories"

    # Check for enabled repositories
    enabled=$(yum repolist enabled 2>/dev/null | grep -c "^[^!]" || echo "0")
    if [ "$enabled" -gt 0 ]; then
        print_success "$enabled repository/repositories enabled"
    else
        print_error "No enabled repositories found"
    fi

    # Check for repository errors
    print_info "Testing repository connectivity..."
    $PKG_MANAGER repolist -q 2>&1 | grep -i "error\|fail" > /tmp/repo-errors.log
    if [ -s /tmp/repo-errors.log ]; then
        print_error "Repository errors detected:"
        cat /tmp/repo-errors.log | head -n 5
    else
        print_success "All repositories accessible"
    fi

    # Check for fastest mirror (if yum-plugin-fastestmirror is installed)
    if rpm -q yum-plugin-fastestmirror &>/dev/null; then
        print_info "fastestmirror plugin is installed"
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
    kernel_updates=$($PKG_MANAGER check-update kernel 2>/dev/null | grep "^kernel" | wc -l)
    if [ "$kernel_updates" -gt 0 ]; then
        print_warning "Kernel updates available"
    else
        print_success "Kernel is up to date"
    fi

    # List all installed kernels
    installed_kernels=$(rpm -q kernel | wc -l)
    print_info "Total installed kernels: $installed_kernels"
    if [ "$installed_kernels" -gt 3 ]; then
        print_warning "Consider removing old kernels (keeping last 2-3)"
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
    if [ -f /var/run/yum.pid ]; then
        if ps -p $(cat /var/run/yum.pid) > /dev/null 2>&1; then
            print_warning "Package manager is currently locked (another process using it)"
        fi
    fi

    # Run package database check
    print_info "Checking package database integrity..."
    $PKG_MANAGER check &> /tmp/pkg-check.log
    if [ $? -eq 0 ]; then
        print_success "Package database is healthy"
    else
        print_warning "Package database may have issues"
        if [ -s /tmp/pkg-check.log ]; then
            print_info "Check details:"
            head -n 5 /tmp/pkg-check.log
        fi
    fi

    # Check for duplicate packages
    duplicates=$(package-cleanup --dupes 2>/dev/null | grep -v "^Loaded" | wc -l)
    if [ "$duplicates" -gt 0 ]; then
        print_warning "Found $duplicates duplicate package(s)"
    else
        print_success "No duplicate packages found"
    fi

    # Check for orphaned packages
    if command -v package-cleanup &> /dev/null; then
        orphans=$(package-cleanup --orphans 2>/dev/null | grep -v "^Loaded" | wc -l)
        if [ "$orphans" -gt 0 ]; then
            print_info "$orphans orphaned package(s) found"
        fi
    fi

    # Check for available updates
    print_info "Checking for available updates..."
    security_updates=$($PKG_MANAGER updateinfo list security 2>/dev/null | grep -v "^$\|^Loaded\|^Last\|^Update" | wc -l)
    total_updates=$($PKG_MANAGER check-update -q 2>/dev/null | grep -v "^$\|^Last" | wc -l)

    if [ "$security_updates" -gt 0 ]; then
        print_warning "$security_updates security update(s) available (apply soon!)"
    fi

    if [ "$total_updates" -gt 0 ]; then
        print_info "$total_updates total package(s) can be upgraded"
    else
        print_success "All packages are up to date"
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

    # Check critical RHEL services
    critical_services=("sshd" "NetworkManager" "firewalld" "rsyslog" "chronyd" "auditd")
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

    # Check audit logs for issues
    if [ -f /var/log/audit/audit.log ]; then
        audit_errors=$(ausearch -m avc -ts recent 2>/dev/null | grep -c "denied" || echo "0")
        if [ "$audit_errors" -gt 0 ]; then
            print_info "Found $audit_errors audit denials (check with ausearch)"
        fi
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
# RHEL-Specific Repair Functions
####################################################################################################

repair_package_system() {
    print_header "Repairing Package System"

    if ask_yes_no "Attempt to repair package database?"; then
        # Clean package cache
        print_info "Cleaning package cache..."
        $PKG_MANAGER clean all

        # Rebuild RPM database
        print_info "Rebuilding RPM database..."
        rpm --rebuilddb

        # Remove duplicate packages
        if command -v package-cleanup &> /dev/null; then
            print_info "Checking for duplicate packages..."
            if ask_yes_no "Remove duplicate packages?"; then
                package-cleanup --cleandupes -y
            fi
        fi

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
        print_info "Cleaning package cache..."
        $PKG_MANAGER clean all -y

        # Remove old kernels (keep last 2)
        if command -v package-cleanup &> /dev/null; then
            print_info "Removing old kernels (keeping last 2)..."
            if ask_yes_no "Remove old kernels?"; then
                package-cleanup --oldkernels --count=2 -y
            fi
        fi

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

apply_security_updates() {
    print_header "Applying Security Updates"

    security_updates=$($PKG_MANAGER updateinfo list security 2>/dev/null | grep -v "^$\|^Loaded\|^Last\|^Update" | wc -l)

    if [ "$security_updates" -eq 0 ]; then
        print_success "No security updates available"
        return
    fi

    print_warning "Found $security_updates security update(s)"

    if ask_yes_no "Apply security updates now?"; then
        print_info "Applying security updates..."
        $PKG_MANAGER update --security -y

        if [ $? -eq 0 ]; then
            print_success "Security updates applied successfully"
            ((ISSUES_FIXED++))

            # Check if reboot is required
            if needs-restarting -r &>/dev/null; then
                :
            else
                print_warning "System reboot is recommended"
            fi
        else
            print_error "Failed to apply security updates"
        fi
    fi
}

####################################################################################################
# Main Menu
####################################################################################################

show_menu() {
    print_header "RHEL System Doctor v$SCRIPT_VERSION"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  ${CYAN}Health Checks:${NC}"
    echo "    1) Run full system health check"
    echo "    2) Check subscription & repositories"
    echo "    3) Check SELinux status"
    echo "    4) Check firewall configuration"
    echo "    5) Check package system"
    echo "    6) Check disk space & health"
    echo "    7) Check services"
    echo "    8) Check kernel status"
    echo ""
    echo "  ${MAGENTA}Repairs:${NC}"
    echo "    9) Repair package system issues"
    echo "   10) Restart failed services"
    echo "   11) Clean up disk space"
    echo "   12) Apply security updates"
    echo ""
    echo "  ${GREEN}Quick Actions:${NC}"
    echo "   13) Run all checks and repairs (recommended)"
    echo "    0) Exit"
    echo ""
}

run_full_check() {
    print_header "Running Full System Health Check"
    check_subscription_status
    check_yum_repos
    check_selinux
    check_firewalld
    check_kernel_updates
    check_disk_space
    check_package_system
    check_services
    check_system_logs
    check_memory
    check_disk_health
}

run_full_repair() {
    run_full_check
    echo ""
    if [ "$ISSUES_FOUND" -gt 0 ] || [ "$WARNINGS_FOUND" -gt 0 ]; then
        print_warning "Found $ISSUES_FOUND issue(s) and $WARNINGS_FOUND warning(s)"
        if ask_yes_no "Would you like to attempt automatic repairs?"; then
            repair_package_system
            repair_failed_services
            cleanup_disk_space
            apply_security_updates
        fi
    else
        print_success "No issues found! System is healthy."
    fi
}

show_summary() {
    print_header "RHEL System Doctor Summary"
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
detect_rhel_system

# Main loop
while true; do
    show_menu
    read -p "$(echo -e ${CYAN}Enter your choice ${NC}[0-13]: )" choice

    case $choice in
        1) run_full_check ;;
        2) check_subscription_status; check_yum_repos ;;
        3) check_selinux ;;
        4) check_firewalld ;;
        5) check_package_system ;;
        6) check_disk_space; check_disk_health ;;
        7) check_services ;;
        8) check_kernel_updates ;;
        9) repair_package_system ;;
        10) repair_failed_services ;;
        11) cleanup_disk_space ;;
        12) apply_security_updates ;;
        13) run_full_repair ;;
        0)
            show_summary
            print_color "$GREEN" "Thank you for using RHEL System Doctor!"
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please enter a number from 0-13."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
