# Linux System Administration Tools

Collection of shell scripts and utilities for Linux system administration, security, and maintenance.

## Scripts Included

### RHELSysDr.sh ⭐ (Red Hat Optimized)
Interactive system health checker and repair tool **optimized for RHEL/CentOS/Rocky/AlmaLinux**. Similar to Windows DISM/SFC but for Red Hat-based systems.

**RHEL-Specific Features:**
- Subscription Manager status checking
- SELinux status and denial monitoring
- Firewalld configuration checking
- YUM/DNF repository health
- Kernel update detection
- Security update detection and application
- Duplicate package detection and removal
- Old kernel cleanup

**Features:**
- Interactive menu-driven interface
- Color-coded output (errors, warnings, success)
- Comprehensive logging to /var/log/rhel-sysdr/
- Package system health checks and repairs
- Disk space and SMART health monitoring
- Service status checking and auto-restart
- System log analysis
- Memory usage monitoring

**Checks Performed:**
- ✅ Red Hat subscription status
- ✅ Repository connectivity and health
- ✅ SELinux status and denials
- ✅ Firewalld/iptables configuration
- ✅ Kernel version and available updates
- ✅ Package database integrity
- ✅ Duplicate and orphaned packages
- ✅ Security updates available
- ✅ Failed systemd services
- ✅ Disk space and inode usage
- ✅ SMART disk health
- ✅ Memory and swap usage
- ✅ System log errors

**Repairs Available:**
- 🔧 Rebuild RPM database
- 🔧 Remove duplicate packages
- 🔧 Fix broken dependencies
- 🔧 Restart failed services
- 🔧 Clean package cache
- 🔧 Remove old kernels
- 🔧 Apply security updates
- 🔧 Clean up logs and temp files

**Usage:**
```bash
sudo bash RHELSysDr.sh
```

**Interactive Menu:**
```
Health Checks:
  1) Run full system health check
  2) Check subscription & repositories
  3) Check SELinux status
  4) Check firewall configuration
  5) Check package system
  6) Check disk space & health
  7) Check services
  8) Check kernel status

Repairs:
  9) Repair package system issues
 10) Restart failed services
 11) Clean up disk space
 12) Apply security updates

Quick Actions:
 13) Run all checks and repairs (recommended)
```

---

### FedoraSysDr.sh ⭐ (Fedora Optimized)
Interactive system health checker and maintenance tool **optimized for Fedora Workstation and Server**.

**Fedora-Specific Features:**
- DNF package manager health and updates
- Flatpak application management and updates
- Firmware updates via fwupd
- Fedora version and EOL status checking
- RPM Fusion repository detection
- zram swap detection
- systemd-resolved checking
- SELinux status and denial monitoring
- Firewalld configuration checking

**Features:**
- Interactive menu-driven interface
- Color-coded output (errors, warnings, success)
- Comprehensive logging to /var/log/fedora-sysdr/
- Package system health checks and repairs
- Disk space and SMART health monitoring
- Service status checking and auto-restart
- System log analysis
- Memory usage monitoring

**Checks Performed:**
- ✅ Fedora version and EOL status
- ✅ DNF repository connectivity and health
- ✅ SELinux status and denials
- ✅ Firewalld configuration
- ✅ Kernel version and available updates
- ✅ Package database integrity
- ✅ Duplicate packages
- ✅ Failed systemd services
- ✅ Disk space and inode usage
- ✅ SMART disk health
- ✅ Memory and swap usage (including zram)
- ✅ System log errors
- ✅ Flatpak applications and updates
- ✅ Firmware update availability

**Updates & Repairs Available:**
- 🔧 Update system packages (DNF)
- 🔧 Update Flatpak applications
- 🔧 Update firmware (fwupd)
- 🔧 Rebuild RPM database
- 🔧 Remove duplicate packages
- 🔧 Restart failed services
- 🔧 Clean DNF cache
- 🔧 Clean up logs and temp files

**Usage:**
```bash
sudo bash FedoraSysDr.sh
```

**Interactive Menu:**
```
Health Checks:
  1) Run full system health check
  2) Check Fedora version & EOL status
  3) Check DNF repositories
  4) Check SELinux status
  5) Check firewall configuration
  6) Check package system
  7) Check disk space & health
  8) Check services
  9) Check kernel status
 10) Check Flatpak status
 11) Check firmware status

Updates & Repairs:
 12) Update system packages (DNF)
 13) Update Flatpak applications
 14) Update firmware (fwupd)
 15) Repair package system issues
 16) Restart failed services
 17) Clean up disk space

Quick Actions:
 18) Run all checks and updates (recommended)
```

---

### LinuxSystemDoctor.sh (Generic Linux)
Interactive system health checker and repair tool for general Linux systems (Ubuntu, Debian, Fedora, etc.).

**Features:**
- Interactive menu-driven interface
- Multi-distribution support (Ubuntu/Debian, RHEL/CentOS/Fedora)
- Package system health checks and repairs
- Disk space and health monitoring (SMART)
- Service status checking and auto-restart
- System log analysis
- Memory usage monitoring
- Automatic cleanup of logs and caches
- Color-coded output for easy reading
- Comprehensive logging

**Checks Performed:**
- ✅ Disk space and inode usage
- ✅ Package database integrity
- ✅ Broken package dependencies
- ✅ Failed systemd services
- ✅ System log errors
- ✅ Memory and swap usage
- ✅ Disk SMART health status

**Repairs Available:**
- 🔧 Fix broken package dependencies
- 🔧 Repair package database corruption
- 🔧 Restart failed services
- 🔧 Clean up disk space (logs, cache, temp files)

**Usage:**
```bash
sudo bash LinuxSystemDoctor.sh
```

**Interactive Menu Options:**
1. Run full system health check
2. Check package system only
3. Check disk space and health
4. Check services
5. Check system logs
6. Repair package system issues
7. Restart failed services
8. Clean up disk space
9. Run all checks and repairs (recommended)

## Planned Tools

- Security hardening automation
- Log analysis utilities
- Backup and recovery tools
- Performance monitoring scripts
- User management utilities
- STIG compliance checker (similar to macOS version)

## Contributing

Have a useful Linux admin script? Contributions are welcome!

## Requirements

- Linux (Ubuntu, CentOS, RHEL, Debian, etc.)
- Bash shell
- Root/sudo privileges for system-level operations

## Installation

```bash
git clone https://github.com/SeaRipDev/Linux-SysAdmin-Tools.git
cd Linux-SysAdmin-Tools
chmod +x *.sh
```

## Author

SeaRipDev

## License

Free to use and modify for personal and commercial purposes.

---

**Note:** Check back soon for Linux administration scripts!
