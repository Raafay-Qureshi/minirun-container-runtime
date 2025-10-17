#!/bin/bash


# MiniRun Container Runtime - Monitoring Script
# 
# Collects and displays system metrics for running containers
# Tracks CPU, memory, process count, and container status
#
# Usage: ./scripts/monitor.sh [options]
# Options:
#   --continuous    Run in continuous monitoring mode (refresh every 2s)
#   --json          Output metrics in JSON format
#   --prometheus    Output in Prometheus-compatible format
#   --csv           Output in CSV format for analysis


set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project directories
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINERS_DIR="$PROJECT_ROOT/containers"
METRICS_DIR="$PROJECT_ROOT/metrics"

# Configuration
CONTINUOUS_MODE=false
OUTPUT_FORMAT="human"  # human, json, prometheus, csv
REFRESH_INTERVAL=2


# Print colored message

print_message() {
    echo -e "${1}${2}${NC}"
}


# Parse command line arguments

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --continuous|-c)
                CONTINUOUS_MODE=true
                shift
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --prometheus)
                OUTPUT_FORMAT="prometheus"
                shift
                ;;
            --csv)
                OUTPUT_FORMAT="csv"
                shift
                ;;
            --interval)
                REFRESH_INTERVAL="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  -c, --continuous    Run in continuous monitoring mode"
                echo "  --json              Output metrics in JSON format"
                echo "  --prometheus        Output in Prometheus-compatible format"
                echo "  --csv               Output in CSV format"
                echo "  --interval N        Set refresh interval to N seconds (default: 2)"
                echo "  -h, --help          Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}


# Get system-wide metrics

get_system_metrics() {
    local timestamp=$(date +%s)
    local date_str=$(date '+%Y-%m-%d %H:%M:%S')
    
    # CPU usage (1-minute load average)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    # Memory usage
    local mem_total=$(free -b | awk '/Mem:/ {print $2}')
    local mem_used=$(free -b | awk '/Mem:/ {print $3}')
    local mem_percent=$(awk "BEGIN {printf \"%.2f\", ($mem_used/$mem_total)*100}")
    
    # Disk usage
    local disk_usage=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | tr -d '%')
    
    echo "$timestamp|$date_str|$load_avg|$mem_used|$mem_total|$mem_percent|$disk_usage"
}


# Get container-specific metrics

get_container_metrics() {
    local container_name="$1"
    local cgroup_path="/sys/fs/cgroup/minirun-$container_name"
    
    # Check if container cgroup exists
    if [ ! -d "$cgroup_path" ]; then
        echo "0|0|0|0|stopped"
        return
    fi
    
    # Process count
    local proc_count=0
    if [ -f "$cgroup_path/cgroup.procs" ]; then
        proc_count=$(wc -l < "$cgroup_path/cgroup.procs" 2>/dev/null || echo "0")
    fi
    
    # Memory usage
    local mem_current=0
    local mem_max=0
    if [ -f "$cgroup_path/memory.current" ]; then
        mem_current=$(cat "$cgroup_path/memory.current" 2>/dev/null || echo "0")
    fi
    if [ -f "$cgroup_path/memory.max" ]; then
        mem_max=$(cat "$cgroup_path/memory.max" 2>/dev/null || echo "0")
    fi
    
    # CPU usage (approximate from cpu.stat)
    local cpu_usage=0
    if [ -f "$cgroup_path/cpu.stat" ]; then
        cpu_usage=$(grep "usage_usec" "$cgroup_path/cpu.stat" 2>/dev/null | awk '{print $2}' || echo "0")
    fi
    
    # Status
    local status="running"
    if [ "$proc_count" -eq 0 ]; then
        status="stopped"
    fi
    
    echo "$proc_count|$mem_current|$mem_max|$cpu_usage|$status"
}


# Display metrics in human-readable format

display_human() {
    clear
    
    # Banner
    print_message "$BLUE" "╔════════════════════════════════════════════════╗"
    print_message "$BLUE" "║   MiniRun Container Runtime - Monitor         ║"
    print_message "$BLUE" "╚════════════════════════════════════════════════╝"
    echo ""
    
    # System metrics
    local sys_metrics=$(get_system_metrics)
    IFS='|' read -r timestamp date_str load_avg mem_used mem_total mem_percent disk_usage <<< "$sys_metrics"
    
    print_message "$CYAN" "📊 System Metrics ($date_str)"
    echo "─────────────────────────────────────────────────"
    echo "  Load Average:  $load_avg"
    echo "  Memory:        $(numfmt --to=iec $mem_used) / $(numfmt --to=iec $mem_total) ($mem_percent%)"
    echo "  Disk Usage:    $disk_usage%"
    echo ""
    
    # Container metrics
    print_message "$CYAN" "📦 Container Status"
    echo "─────────────────────────────────────────────────"
    
    local container_count=0
    local running_count=0
    
    if [ -d "$CONTAINERS_DIR" ]; then
        for config_file in "$CONTAINERS_DIR"/*.json; do
            if [ -f "$config_file" ]; then
                container_count=$((container_count + 1))
                local container_name=$(basename "$config_file" .json)
                
                # Get container metrics
                local metrics=$(get_container_metrics "$container_name")
                IFS='|' read -r proc_count mem_current mem_max cpu_usage status <<< "$metrics"
                
                # Count running containers
                if [ "$status" = "running" ]; then
                    running_count=$((running_count + 1))
                fi
                
                # Display container info
                local status_icon="⚪"
                local status_color="$NC"
                if [ "$status" = "running" ]; then
                    status_icon="🟢"
                    status_color="$GREEN"
                fi
                
                echo ""
                print_message "$status_color" "  $status_icon $container_name [$status]"
                
                if [ "$status" = "running" ]; then
                    echo "     Processes:    $proc_count"
                    if [ "$mem_max" != "0" ] && [ "$mem_max" != "max" ]; then
                        local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_current/$mem_max)*100}")
                        echo "     Memory:       $(numfmt --to=iec $mem_current) / $(numfmt --to=iec $mem_max) ($mem_percent%)"
                    else
                        echo "     Memory:       $(numfmt --to=iec $mem_current) (no limit)"
                    fi
                    echo "     CPU (μs):     $cpu_usage"
                fi
            fi
        done
    fi
    
    echo ""
    echo "─────────────────────────────────────────────────"
    print_message "$YELLOW" "  Total: $container_count containers | Running: $running_count"
    
    if [ "$CONTINUOUS_MODE" = true ]; then
        echo ""
        print_message "$YELLOW" "  Refreshing every ${REFRESH_INTERVAL}s... (Ctrl+C to exit)"
    fi
}


# Display metrics in JSON format

display_json() {
    local sys_metrics=$(get_system_metrics)
    IFS='|' read -r timestamp date_str load_avg mem_used mem_total mem_percent disk_usage <<< "$sys_metrics"
    
    echo "{"
    echo "  \"timestamp\": $timestamp,"
    echo "  \"date\": \"$date_str\","
    echo "  \"system\": {"
    echo "    \"load_average\": $load_avg,"
    echo "    \"memory\": {"
    echo "      \"used_bytes\": $mem_used,"
    echo "      \"total_bytes\": $mem_total,"
    echo "      \"percent\": $mem_percent"
    echo "    },"
    echo "    \"disk_usage_percent\": $disk_usage"
    echo "  },"
    echo "  \"containers\": ["
    
    local first=true
    if [ -d "$CONTAINERS_DIR" ]; then
        for config_file in "$CONTAINERS_DIR"/*.json; do
            if [ -f "$config_file" ]; then
                local container_name=$(basename "$config_file" .json)
                local metrics=$(get_container_metrics "$container_name")
                IFS='|' read -r proc_count mem_current mem_max cpu_usage status <<< "$metrics"
                
                if [ "$first" = false ]; then
                    echo "    ,"
                fi
                first=false
                
                echo "    {"
                echo "      \"name\": \"$container_name\","
                echo "      \"status\": \"$status\","
                echo "      \"processes\": $proc_count,"
                echo "      \"memory\": {"
                echo "        \"current_bytes\": $mem_current,"
                echo "        \"max_bytes\": $mem_max"
                echo "      },"
                echo "      \"cpu_usage_usec\": $cpu_usage"
                echo -n "    }"
            fi
        done
    fi
    
    echo ""
    echo "  ]"
    echo "}"
}


# Display metrics in Prometheus format

display_prometheus() {
    local timestamp=$(date +%s)000  # Prometheus uses milliseconds
    
    # System metrics
    local sys_metrics=$(get_system_metrics)
    IFS='|' read -r _ _ load_avg mem_used mem_total mem_percent disk_usage <<< "$sys_metrics"
    
    echo "# HELP minirun_system_load_average System load average"
    echo "# TYPE minirun_system_load_average gauge"
    echo "minirun_system_load_average $load_avg $timestamp"
    echo ""
    
    echo "# HELP minirun_system_memory_bytes System memory usage in bytes"
    echo "# TYPE minirun_system_memory_bytes gauge"
    echo "minirun_system_memory_bytes{type=\"used\"} $mem_used $timestamp"
    echo "minirun_system_memory_bytes{type=\"total\"} $mem_total $timestamp"
    echo ""
    
    # Container metrics
    if [ -d "$CONTAINERS_DIR" ]; then
        echo "# HELP minirun_container_status Container status (1=running, 0=stopped)"
        echo "# TYPE minirun_container_status gauge"
        
        echo "# HELP minirun_container_processes Number of processes in container"
        echo "# TYPE minirun_container_processes gauge"
        
        echo "# HELP minirun_container_memory_bytes Container memory usage"
        echo "# TYPE minirun_container_memory_bytes gauge"
        
        for config_file in "$CONTAINERS_DIR"/*.json; do
            if [ -f "$config_file" ]; then
                local container_name=$(basename "$config_file" .json)
                local metrics=$(get_container_metrics "$container_name")
                IFS='|' read -r proc_count mem_current mem_max cpu_usage status <<< "$metrics"
                
                local status_value=0
                if [ "$status" = "running" ]; then
                    status_value=1
                fi
                
                echo "minirun_container_status{name=\"$container_name\"} $status_value $timestamp"
                echo "minirun_container_processes{name=\"$container_name\"} $proc_count $timestamp"
                echo "minirun_container_memory_bytes{name=\"$container_name\",type=\"current\"} $mem_current $timestamp"
                echo "minirun_container_memory_bytes{name=\"$container_name\",type=\"max\"} $mem_max $timestamp"
            fi
        done
    fi
}


# Display metrics in CSV format

display_csv() {
    # Header
    echo "timestamp,container,status,processes,memory_current,memory_max,cpu_usage_usec"
    
    local sys_metrics=$(get_system_metrics)
    IFS='|' read -r timestamp _ _ _ _ _ _ <<< "$sys_metrics"
    
    if [ -d "$CONTAINERS_DIR" ]; then
        for config_file in "$CONTAINERS_DIR"/*.json; do
            if [ -f "$config_file" ]; then
                local container_name=$(basename "$config_file" .json)
                local metrics=$(get_container_metrics "$container_name")
                IFS='|' read -r proc_count mem_current mem_max cpu_usage status <<< "$metrics"
                
                echo "$timestamp,$container_name,$status,$proc_count,$mem_current,$mem_max,$cpu_usage"
            fi
        done
    fi
}


# Save metrics to file

save_metrics() {
    # Create metrics directory if it doesn't exist
    mkdir -p "$METRICS_DIR"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local metrics_file="$METRICS_DIR/metrics_$timestamp.$OUTPUT_FORMAT"
    
    case $OUTPUT_FORMAT in
        json)
            display_json > "$metrics_file"
            ;;
        prometheus)
            display_prometheus > "$metrics_file"
            ;;
        csv)
            display_csv > "$metrics_file"
            ;;
    esac
    
    echo "Metrics saved to: $metrics_file"
}


# Main monitoring loop

main() {
    parse_args "$@"
    
    if [ "$CONTINUOUS_MODE" = true ]; then
        # Continuous monitoring mode
        while true; do
            case $OUTPUT_FORMAT in
                human)
                    display_human
                    ;;
                json)
                    display_json
                    echo ""
                    ;;
                prometheus)
                    display_prometheus
                    echo ""
                    ;;
                csv)
                    display_csv
                    ;;
            esac
            
            sleep "$REFRESH_INTERVAL"
        done
    else
        # Single snapshot mode
        case $OUTPUT_FORMAT in
            human)
                display_human
                ;;
            json)
                display_json
                ;;
            prometheus)
                display_prometheus
                ;;
            csv)
                display_csv
                ;;
        esac
    fi
}

# Run main function
main "$@"