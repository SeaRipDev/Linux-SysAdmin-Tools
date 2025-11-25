#!/bin/bash
####################################################################################################
#
# Linux System Doctor - Interactive System Health Check and Repair
#
# Purpose: Diagnose and repair common Linux system issues
# Similar to Windows DISM/SFC for Linux systems
#
# Usage: sudo bash LinuxSystemDoctor.sh
#
# Author: CWRip / SeaDubRip
# Version: 1.0
# Date: 2025-11-25
#
####################################################################################################

# Script configuration
SCRIPT_VERSION="1.0"
LOG_DIR="/var/log/system-doctor"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/check-$TIMESTAMP.log"
BACKUP_DIR="/root/system-doctor-backup"

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
NC='\033[0m' # No Color

####################################################################################################
# Helper Functions
####################################################################################################

# Print colored output and log
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

# Ask yes/no question
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

detect_distro() {
    print_info "Detecting Linux distribution..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
        DISTRO_NAME=$PRETTY_NAME
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
        DISTRO_NAME=$(cat /etc/redhat-release)
    else
        DISTRO="unknown"
        DISTRO_NAME="Unknown Linux"
    fi

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    else
        PKG_MANAGER="unknown"
    fi

    print_success "Distribution: $DISTRO_NAME"
    print_success "Package Manager: $PKG_MANAGER"
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
            LOG_FILE="$LOG_DIR/system-doctor-$TIMESTAMP.log"
        fi
    fi
}

####################################################################################################
# Health Check Functions
####################################################################################################

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
}

check_package_system() {
    print_header "Checking Package System Health"

    case $PKG_MANAGER in
        apt)
            print_info "Checking apt package database..."

            # Check for dpkg lock
            if [ -f /var/lib/dpkg/lock ] || [ -f /var/lib/apt/lists/lock ]; then
                if fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
                    print_warning "Package manager is currently locked (another process using it)"
                fi
            fi

            # Run apt-get check
            apt-get check &> /tmp/apt-check.log
            if [ $? -eq 0 ]; then
                print_success "Package database is healthy"
            else
                print_error "Package database has issues"
                cat /tmp/apt-check.log >> "$LOG_FILE"
            fi

            # Check for broken packages
            broken=$(dpkg -l | grep "^iU\|^iF" | wc -l)
            if [ "$broken" -gt 0 ]; then
                print_error "Found $broken broken package(s)"
            else
                print_success "No broken packages found"
            fi

            # Check for available updates
            print_info "Checking for available updates..."
            apt-get update -qq 2>&1 | tee -a "$LOG_FILE" > /dev/null
            upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
            if [ "$upgradable" -gt 0 ]; then
                print_info "$upgradable package(s) can be upgraded"
            else
                print_success "All packages are up to date"
            fi
            ;;

        yum|dnf)
            print_info "Checking $PKG_MANAGER package database..."

            # Run package check
            $PKG_MANAGER check &> /tmp/pkg-check.log
            if [ $? -eq 0 ]; then
                print_success "Package database is healthy"
            else
                print_warning "Package database may have issues"
                cat /tmp/pkg-check.log >> "$LOG_FILE"
            fi

            # Check for available updates
            print_info "Checking for available updates..."
            updates=$($PKG_MANAGER check-update -q | grep -v "^$" | wc -l)
            if [ "$updates" -gt 0 ]; then
                print_info "$updates package(s) can be upgraded"
            else
                print_success "All packages are up to date"
            fi
            ;;

        *)
            print_warning "Unsupported package manager: $PKG_MANAGER"
            ;;
    esac
}

check_services() {
    print_header "Checking System Services"

    # Check if systemd is available
    if command -v systemctl &> /dev/null; then
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

        # Check critical services
        critical_services=("sshd" "ssh" "network" "NetworkManager" "systemd-journald")
        print_info "Checking critical services..."

        for service in "${critical_services[@]}"; do
            if systemctl list-unit-files | grep -q "^${service}.service"; then
                if systemctl is-active --quiet "$service"; then
                    print_success "$service is running"
                else
                    print_warning "$service is not running"
                fi
            fi
        done
    else
        print_warning "systemd not available, skipping service checks"
    fi
}

check_system_logs() {
    print_header "Checking System Logs for Errors"

    if command -v journalctl &> /dev/null; then
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
    else
        # Fallback to checking /var/log/messages or syslog
        if [ -f /var/log/messages ]; then
            error_count=$(grep -i "error\|fail" /var/log/messages | tail -n 100 | wc -l)
            print_info "Found $error_count error-related entries in /var/log/messages (last 100 lines)"
        elif [ -f /var/log/syslog ]; then
            error_count=$(grep -i "error\|fail" /var/log/syslog | tail -n 100 | wc -l)
            print_info "Found $error_count error-related entries in /var/log/syslog (last 100 lines)"
        fi
    fi
}

check_memory() {
    print_header "Checking Memory Status"

    # Get memory info
    total_mem=$(free -m | awk 'NR==2{print $2}')
    used_mem=$(free -m | awk 'NR==2{print $3}')
    free_mem=$(free -m | awk 'NR==2{print $4}')
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
        swap_percent=$(( swap_used * 100 / swap_total ))
        if [ "$swap_percent" -ge 50 ]; then
            print_warning "Swap usage is ${swap_percent}% (system may be low on RAM)"
        else
            print_success "Swap usage is ${swap_percent}%"
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
# Repair Functions
####################################################################################################

repair_package_system() {
    print_header "Repairing Package System"

    case $PKG_MANAGER in
        apt)
            if ask_yes_no "Attempt to repair package database?"; then
                print_info "Configuring any unconfigured packages..."
                dpkg --configure -a

                print_info "Fixing broken dependencies..."
                apt-get install -f -y

                print_info "Cleaning package cache..."
                apt-get clean
                apt-get autoclean

                print_success "Package repair completed"
                ((ISSUES_FIXED++))
            fi
            ;;

        yum|dnf)
            if ask_yes_no "Attempt to repair package database?"; then
                print_info "Cleaning package cache..."
                $PKG_MANAGER clean all

                print_info "Rebuilding package database..."
                rpm --rebuilddb

                print_success "Package repair completed"
                ((ISSUES_FIXED++))
            fi
            ;;
    esac
}

repair_failed_services() {
    print_header "Repairing Failed Services"

    if ! command -v systemctl &> /dev/null; then
        print_warning "systemd not available"
        return
    fi

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
            fi
        done
    fi
}

cleanup_disk_space() {
    print_header "Cleaning Up Disk Space"

    if ask_yes_no "Clean up system logs and temporary files?"; then
        # Clean journal logs (keep last 7 days)
        if command -v journalctl &> /dev/null; then
            print_info "Cleaning journal logs (keeping last 7 days)..."
            journalctl --vacuum-time=7d
        fi

        # Clean package cache
        case $PKG_MANAGER in
            apt)
                print_info "Cleaning apt cache..."
                apt-get autoclean -y
                apt-get clean -y
                ;;
            yum|dnf)
                print_info "Cleaning $PKG_MANAGER cache..."
                $PKG_MANAGER clean all -y
                ;;
        esac

        # Clean /tmp (files older than 10 days)
        print_info "Cleaning old temporary files..."
        find /tmp -type f -atime +10 -delete 2>/dev/null

        # Clean old log files
        print_info "Compressing old log files..."
        find /var/log -type f -name "*.log" -mtime +30 -exec gzip {} \; 2>/dev/null

        print_success "Cleanup completed"
        ((ISSUES_FIXED++))
    fi
}

####################################################################################################
# Main Menu
####################################################################################################

show_menu() {
    print_header "Linux System Doctor v$SCRIPT_VERSION"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  1) Run full system health check"
    echo "  2) Check package system only"
    echo "  3) Check disk space and health"
    echo "  4) Check services"
    echo "  5) Check system logs"
    echo "  6) Repair package system issues"
    echo "  7) Restart failed services"
    echo "  8) Clean up disk space"
    echo "  9) Run all checks and repairs (recommended)"
    echo "  0) Exit"
    echo ""
}

run_full_check() {
    print_header "Running Full System Health Check"
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
        fi
    else
        print_success "No issues found! System is healthy."
    fi
}

show_summary() {
    print_header "System Doctor Summary"
    echo ""
    print_info "Hostname: $(hostname)"
    print_info "Uptime: $(uptime -p 2>/dev/null || uptime)"
    print_info "Distribution: $DISTRO_NAME"
    print_info "Kernel: $(uname -r)"
    echo ""
    print_info "Issues Found: $ISSUES_FOUND"
    print_info "Warnings: $WARNINGS_FOUND"
    print_info "Issues Fixed: $ISSUES_FIXED"
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
detect_distro

# Main loop
while true; do
    show_menu
    read -p "$(echo -e ${CYAN}Enter your choice ${NC}[0-9]: )" choice

    case $choice in
        1) run_full_check ;;
        2) check_package_system ;;
        3) check_disk_space; check_disk_health ;;
        4) check_services ;;
        5) check_system_logs ;;
        6) repair_package_system ;;
        7) repair_failed_services ;;
        8) cleanup_disk_space ;;
        9) run_full_repair ;;
        0)
            show_summary
            print_color "$GREEN" "Thank you for using Linux System Doctor!"
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please enter a number from 0-9."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
