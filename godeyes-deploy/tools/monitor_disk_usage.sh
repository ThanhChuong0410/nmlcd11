#!/bin/bash

##############################################################
############## Directory Disk Usage Monitor Script ###########
##############################################################

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEND_EMAIL_SCRIPT="$SCRIPT_DIR/send_email.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

RECIPIENT_EMAIL=chuongthanh0410@gmail.com

# Warning thresholds (GB) - configurable
WARNING_THRESHOLD_GB="${WARNING_THRESHOLD_GB:-10}"
CRITICAL_THRESHOLD_GB="${CRITICAL_THRESHOLD_GB:-20}"

# Info log function
info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC}  $1 "
}

# Debug log function
debug() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${CYAN} $1 ${NC}"
}

# Warning log function
warn() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW} $1 ${NC}"
}

# Error log function
error() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${RED} $1 ${NC}"
}

# Success log function
success() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${GREEN} $1 ${NC}"
}

# Check if send_email.sh exists
check_email_script() {
    if [ ! -f "$SEND_EMAIL_SCRIPT" ]; then
        error "send_email.sh not found at: $SEND_EMAIL_SCRIPT"
        return 1
    fi

    if [ ! -x "$SEND_EMAIL_SCRIPT" ]; then
        info "Making send_email.sh executable..."
        chmod +x "$SEND_EMAIL_SCRIPT"
    fi

    return 0
}

# Convert bytes to human readable format
bytes_to_human() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes} B"
        elif [ $bytes -lt $((1024 * 1024)) ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
        elif [ $bytes -lt $((1024 * 1024 * 1024)) ]; then
        echo "$(echo "scale=2; $bytes / 1024 / 1024" | bc) MB"
    else
        echo "$(echo "scale=2; $bytes / 1024 / 1024 / 1024" | bc) GB"
    fi
}

# Get directory size in bytes
get_dir_size() {
    local dir="$1"
    du -sb "$dir" 2>/dev/null | awk '{print $1}'
}

# Get disk usage of the partition
get_partition_info() {
    local dir="$1"
    df -h "$dir" | tail -1
}

# Monitor directory and send report
monitor_directory() {
    local target_dir="$1"

    # Check if directory exists
    if [ ! -d "$target_dir" ]; then
        error "Directory does not exist: $target_dir"
        return 1
    fi

    info "Checking directory disk usage: $target_dir"

    # Get directory size
    local size_bytes=$(get_dir_size "$target_dir")
    local size_gb=$(echo "scale=2; $size_bytes / 1024 / 1024 / 1024" | bc)
    local size_human=$(bytes_to_human $size_bytes)

    info "Size: $size_human ($size_gb GB)"

    # Get root partition information
    local root_info=$(df -h / | tail -1)
    local root_total=$(echo "$root_info" | awk '{print $2}')
    local root_used=$(echo "$root_info" | awk '{print $3}')
    local root_avail=$(echo "$root_info" | awk '{print $4}')
    local root_percent=$(echo "$root_info" | awk '{print $5}' | sed 's/%//')

    # Get current partition information
    local partition_info=$(get_partition_info "$target_dir")
    local partition_used=$(echo "$partition_info" | awk '{print $5}' | sed 's/%//')

    # Calculate directory percentage compared to root partition
    local root_total_bytes=$(df -B1 / | tail -1 | awk '{print $2}')
    local dir_percent=$(echo "scale=4; ($size_bytes / $root_total_bytes) * 100" | bc)

    # Determine status and color
    local status="NORMAL"
    local status_color="#5cb85c"
    local subject_prefix="[INFO]"

    if (( $(echo "$size_gb >= $CRITICAL_THRESHOLD_GB" | bc -l) )); then
        status="CRITICAL"
        status_color="#d9534f"
        subject_prefix="[CRITICAL]"
        warn "WARNING: Size exceeds CRITICAL threshold ($CRITICAL_THRESHOLD_GB GB)"
        elif (( $(echo "$size_gb >= $WARNING_THRESHOLD_GB" | bc -l) )); then
        status="WARNING"
        status_color="#f0ad4e"
        subject_prefix="[WARNING]"
        warn "WARNING: Size exceeds WARNING threshold ($WARNING_THRESHOLD_GB GB)"
    fi

    # Prepare email
    local subject="$subject_prefix GodEyes Edge - Directory Disk Usage Report"

    local body="<html>
    <head>
    <style>
    body { font-family: Arial, sans-serif; }
    .status-badge {
        padding: 5px 10px;
        border-radius: 3px;
        color: white;
        font-weight: bold;
        display: inline-block;
    }
    .info-section {
        background-color: #f9f9f9;
        padding: 15px;
        border-radius: 5px;
        margin: 10px 0;
    }
    .threshold-info {
        background-color: #e7f3ff;
        padding: 10px;
        border-left: 4px solid #2196F3;
        margin: 10px 0;
    }
    table {
        width: 100%;
        margin: 10px 0;
    }
    </style>
    </head>
    <body>
    <h2>📊 Directory Disk Usage Report</h2>

    <div class='info-section'>
    <p><strong>⏰ Time:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p><strong>📁 Monitored Directory:</strong> $target_dir</p>
    <p><strong>🎯 Status:</strong> <span class='status-badge' style='background-color: $status_color;'>$status</span></p>
    </div>

    <div class='threshold-info'>
    <p><strong>⚙️ Warning Thresholds:</strong></p>
    <ul>
    <li>Warning: $WARNING_THRESHOLD_GB GB</li>
    <li>Critical: $CRITICAL_THRESHOLD_GB GB</li>
    </ul>
    </div>

    <h3>💾 Root Partition (/) Information:</h3>
    <div class='info-section'>
    <table border='1' cellpadding='8' cellspacing='0' style='border-collapse: collapse; width: 100%;'>
    <tr style='background-color: #f0f0f0;'>
    <th>Total Size</th>
    <th>Used</th>
    <th>Available</th>
    <th>% Used</th>
    </tr>
    <tr>
    <td style='text-align: center;'>$root_total</td>
    <td style='text-align: center;'>$root_used</td>
    <td style='text-align: center;'>$root_avail</td>
    <td style='text-align: center;'><strong>$root_percent%</strong></td>
    </tr>
    </table>
    </div>

    <h3>📂 Monitored Directory Information:</h3>
    <div class='info-section'>
    <table border='1' cellpadding='8' cellspacing='0' style='border-collapse: collapse; width: 100%;'>
    <tr style='background-color: #f0f0f0;'>
    <th>Directory Size</th>
    <th>% of Root Partition</th>
    </tr>
    <tr>
    <td style='text-align: center;'><strong>$size_human</strong> ($size_gb GB)</td>
    <td style='text-align: center;'><strong>$dir_percent%</strong></td>
    </tr>
    </table>
    </div>

    <hr>
    <p><em>📧 This email was sent automatically from GodEyes Edge Monitor system</em></p>
    <p><em>💡 Tip: You can change warning thresholds using WARNING_THRESHOLD_GB and CRITICAL_THRESHOLD_GB environment variables</em></p>
    </body>
    </html>"

    # Send email
    info "Sending email report..."
    "$SEND_EMAIL_SCRIPT" custom "$RECIPIENT_EMAIL" "$subject" "$body"

    if [ $? -eq 0 ]; then
        success "Report sent successfully"
        return 0
    else
        error "Failed to send report"
        return 1
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 <directory_path>"
    echo ""
    echo "Options:"
    echo "  <directory_path>    Directory path to monitor"
    echo ""
    echo "Environment Variables:"
    echo "  WARNING_THRESHOLD_GB    Warning threshold (GB, default: 10)"
    echo "  CRITICAL_THRESHOLD_GB   Critical threshold (GB, default: 20)"
    echo ""
    echo "Example:"
    echo "  $0 /var/log"
    echo "  WARNING_THRESHOLD_GB=5 CRITICAL_THRESHOLD_GB=15 $0 /var/log"
    echo ""
    echo "Crontab Example (runs daily at 9:00 AM):"
    echo "  0 9 * * * /path/to/monitor_disk_usage.sh /var/log >> /var/log/disk_monitor.log 2>&1"
}

# Main function
main() {
    info "=== GodEyes Edge - Disk Usage Monitor ==="

    # Check if directory parameter is provided
    if [ $# -eq 0 ]; then
        error "Please provide directory path to monitor"
        echo ""
        show_usage
        exit 1
    fi

    # Check email script
    check_email_script || exit 1

    # Get absolute path
    local target_dir=$(realpath "$1")

    # Monitor and send report
    monitor_directory "$target_dir"

    exit $?
}

main "$@"
