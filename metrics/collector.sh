#!/bin/bash

#######################################
# MiniRun Metrics Collector
# 
# Collects container metrics and exports to various formats
# Can be scheduled via cron for historical data collection
#
# Usage: ./metrics/collector.sh [--format json|prometheus|csv]
#######################################

set -e

# Configuration
METRICS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$METRICS_DIR")"
CONTAINERS_DIR="$PROJECT_ROOT/containers"
HISTORY_DIR="$METRICS_DIR/history"

# Create history directory
mkdir -p "$HISTORY_DIR"

# Default format
FORMAT="json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --format)
            FORMAT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Collect metrics and save
TIMESTAMP=$(date +%s)
DATE_STR=$(date '+%Y-%m-%d_%H-%M-%S')

case $FORMAT in
    json)
        "$PROJECT_ROOT/scripts/monitor.sh" --json > "$HISTORY_DIR/metrics_$DATE_STR.json"
        echo "Metrics saved to: $HISTORY_DIR/metrics_$DATE_STR.json"
        ;;
    prometheus)
        "$PROJECT_ROOT/scripts/monitor.sh" --prometheus > "$HISTORY_DIR/metrics_$DATE_STR.prom"
        echo "Metrics saved to: $HISTORY_DIR/metrics_$DATE_STR.prom"
        ;;
    csv)
        "$PROJECT_ROOT/scripts/monitor.sh" --csv > "$HISTORY_DIR/metrics_$DATE_STR.csv"
        echo "Metrics saved to: $HISTORY_DIR/metrics_$DATE_STR.csv"
        ;;
    *)
        echo "Unknown format: $FORMAT"
        exit 1
        ;;
esac