#!/bin/bash

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

LOG_DIR="/var/log/ec2_monitor"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/monitor_$(date +'%Y%m%d_%H%M%S').log"

log() {
    local COLOR="$1"
    local TEXT="$2"
    echo -e "${COLOR}${TEXT}${RESET}"
    echo -e "${TEXT}" >> "$LOG_FILE"
}

section() {
    log "$CYAN" "\n========== $1 =========="
}

section "SYSTEM INFO"
log "$BLUE" "Hostname: $(hostname)"
log "$BLUE" "Date: $(date)"
uname -a | tee -a "$LOG_FILE"
[ -f /etc/os-release ] && grep PRETTY_NAME /etc/os-release | tee -a "$LOG_FILE"

section "AWS EC2 METADATA"
if curl --silent http://169.254.169.254/latest/meta-data/ > /dev/null; then
    curl -s http://169.254.169.254/latest/meta-data/ | while read item; do
        VALUE=$(curl -s http://169.254.169.254/latest/meta-data/$item)
        log "$BLUE" "$item: $VALUE"
    done
else
    log "$RED" "Not an EC2 instance or metadata unavailable."
fi

section "UPTIME"
uptime | tee -a "$LOG_FILE"

section "CPU USAGE"
top -bn1 | grep "Cpu(s)" | tee -a "$LOG_FILE"

section "MEMORY USAGE"
free -h | tee -a "$LOG_FILE"

section "DISK USAGE"
df -h | tee -a "$LOG_FILE"

section "INODE USAGE"
df -i | tee -a "$LOG_FILE"

section "TOP 10 PROCESSES BY CPU"
ps aux --sort=-%cpu | head -n 11 | tee -a "$LOG_FILE"

section "TOP 10 PROCESSES BY MEMORY"
ps aux --sort=-%mem | head -n 11 | tee -a "$LOG_FILE"

section "NETWORK INTERFACES"
ip -brief address | tee -a "$LOG_FILE"

section "OPEN PORTS"
ss -tuln | tee -a "$LOG_FILE"

section "LOGGED-IN USERS"
who | tee -a "$LOG_FILE"

section "DIRECTORY SIZES (/home, /var, /etc)"
du -sh /home/* /var/* /etc/* 2>/dev/null | sort -hr | head -n 15 | tee -a "$LOG_FILE"

section "RECENT ERROR LOGS"

log "$YELLOW" "Scanning /var/log/syslog for errors..."
grep -Ei 'error|fail|panic|critical' /var/log/syslog 2>/dev/null | tail -n 20 | tee -a "$LOG_FILE"

log "$YELLOW" "Scanning /var/log/messages for errors..."
grep -Ei 'error|fail|panic|critical' /var/log/messages 2>/dev/null | tail -n 20 | tee -a "$LOG_FILE"

log "$YELLOW" "Scanning /var/log/auth.log for errors..."
grep -Ei 'fail|error|denied' /var/log/auth.log 2>/dev/null | tail -n 20 | tee -a "$LOG_FILE"

log "$YELLOW" "Scanning /var/log/dmesg for recent kernel warnings..."
dmesg --level=err,warn | tail -n 20 | tee -a "$LOG_FILE"

section "THRESHOLD ALERTS"

CPU_IDLE=$(top -bn1 | grep "%id" | awk -F'id,' '{ print $1 }' | awk '{ print $(NF) }' | cut -d. -f1)
DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
MEM_FREE=$(free -m | awk '/Mem:/ {print $4}')

[ "$CPU_IDLE" -lt 20 ] && log "$RED" "⚠️  High CPU usage detected (Idle: $CPU_IDLE%)"
[ "$DISK_USED" -gt 85 ] && log "$RED" "⚠️  Disk usage > 85% ($DISK_USED%)"
[ "$MEM_FREE" -lt 500 ] && log "$RED" "⚠️  Free memory < 500MB ($MEM_FREE MB)"

log "$GREEN" "\n✅ Monitoring complete. Log saved to $LOG_FILE"
