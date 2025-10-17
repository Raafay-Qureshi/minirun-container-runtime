# Metrics and Monitoring System

Real-time and historical metrics collection for tracking container runtime performance.

## Overview

Two components for monitoring:
- **monitor.sh** - Real-time dashboard with live updates
- **collector.sh** - Scheduled collection for historical data

Both support multiple output formats (human-readable, JSON, Prometheus, CSV).

## Quick Start
```bash
# Real-time monitoring
./scripts/monitor.sh

# Continuous updates (refreshes every 2 seconds)
./scripts/monitor.sh --continuous

# Collect historical snapshot
./metrics/collector.sh --format json
```

## Metrics Collected

**System-Level:**
- Load average (1-minute)
- Memory usage (used/total/percentage)
- Disk usage percentage

**Per-Container:**
- Process count
- Memory usage vs limit
- CPU time (microseconds)
- Running status

All metrics read directly from cgroups v2 filesystem (`/sys/fs/cgroup/minirun-{name}/`).

## Output Formats

### Human-Readable Dashboard
```
╔════════════════════════════════════════════════╗
║   MiniRun Container Runtime - Monitor         ║
╚════════════════════════════════════════════════╝

📊 System Metrics (2024-01-15 10:30:00)
─────────────────────────────────────────────────
  Load Average:  0.45
  Memory:        4.2G / 16G (26.25%)
  Disk Usage:    45%

📦 Container Status
─────────────────────────────────────────────────

  🟢 webapp [running]
     Processes:    3
     Memory:       128M / 512M (25.0%)
     CPU (μs):     1234567
```

### JSON (for programmatic access)
```bash
./scripts/monitor.sh --json
```
```json
{
  "timestamp": 1705315800,
  "date": "2024-01-15 10:30:00",
  "system": {
    "load_average": 0.45,
    "memory": {
      "used_bytes": 4503599627370496,
      "total_bytes": 17179869184,
      "percent": 26.25
    },
    "disk_usage_percent": 45
  },
  "containers": [
    {
      "name": "webapp",
      "status": "running",
      "processes": 3,
      "memory": {
        "current_bytes": 134217728,
        "max_bytes": 536870912
      },
      "cpu_usage_usec": 1234567
    }
  ]
}
```

### Prometheus (for monitoring integration)
```bash
./scripts/monitor.sh --prometheus
```
```
# HELP minirun_system_load_average System load average
# TYPE minirun_system_load_average gauge
minirun_system_load_average 0.45 1705315800000

# HELP minirun_container_status Container status (1=running, 0=stopped)
# TYPE minirun_container_status gauge
minirun_container_status{name="webapp"} 1 1705315800000

# HELP minirun_container_memory_bytes Container memory usage
# TYPE minirun_container_memory_bytes gauge
minirun_container_memory_bytes{name="webapp",type="current"} 134217728 1705315800000
```

### CSV (for spreadsheet analysis)
```bash
./scripts/monitor.sh --csv
```
```csv
timestamp,container,status,processes,memory_current,memory_max,cpu_usage_usec
1705315800,webapp,running,3,134217728,536870912,1234567
```

## Automated Collection

Set up cron job for periodic collection:
```bash
# Edit crontab
crontab -e

# Collect every 5 minutes
*/5 * * * * /path/to/metrics/collector.sh --format json

# Collect hourly
0 * * * * /path/to/metrics/collector.sh --format json
```

Historical data stored in `metrics/history/`:
```
metrics/history/
├── metrics_2024-01-15_10-00-00.json
├── metrics_2024-01-15_10-05-00.json
└── metrics_2024-01-15_10-10-00.json
```

## Analysis Examples

### Using jq (JSON processor)
```bash
# Average load across all metrics
jq -s 'map(.system.load_average) | add / length' metrics/history/*.json

# Count running containers over time
jq -s 'map(.containers | map(select(.status=="running")) | length)' metrics/history/*.json

# Memory usage trend for specific container
jq '.containers[] | select(.name=="webapp") | .memory.current_bytes' metrics/history/*.json
```

### Using Python
```python
import json
import glob

# Load historical metrics
metrics_files = sorted(glob.glob('metrics/history/metrics_*.json'))

for file in metrics_files:
    with open(file) as f:
        data = json.load(f)
        print(f"Time: {data['date']}")
        print(f"Load: {data['system']['load_average']}")
        print(f"Containers: {len(data['containers'])}\n")
```

## Prometheus Integration

Export metrics for Prometheus scraping:
```bash
# Write to Prometheus text file
./scripts/monitor.sh --prometheus > /var/lib/prometheus/minirun.prom

# Add to crontab for periodic updates
* * * * * /path/to/scripts/monitor.sh --prometheus > /var/lib/prometheus/minirun.prom
```

Configure Prometheus scrape:
```yaml
scrape_configs:
  - job_name: 'minirun'
    file_sd_configs:
      - files:
        - '/var/lib/prometheus/minirun.prom'
```

## Grafana Dashboards

Query examples for visualization:
```promql
# Total containers
count(minirun_container_status)

# Running containers
sum(minirun_container_status)

# Container memory usage
minirun_container_memory_bytes{type="current"}

# System load
minirun_system_load_average
```

## Maintenance

### Cleanup Old Metrics
```bash
# Remove metrics older than 7 days
find metrics/history -name "metrics_*.json" -mtime +7 -delete

# Keep only last 100 snapshots
ls -t metrics/history/metrics_*.json | tail -n +101 | xargs rm -f
```

## Troubleshooting

**No metrics appear:**
- Check if containers exist: `ls containers/`
- Verify cgroups accessible: `ls /sys/fs/cgroup/minirun-*/`
- Ensure script is executable: `chmod +x scripts/monitor.sh`

**Permission denied on cgroup files:**
- Some cgroup files require root access
- Run with sudo: `sudo ./scripts/monitor.sh`

**Collector not running via cron:**
- Use absolute paths in crontab
- Check cron logs: `grep CRON /var/log/syslog`
- Verify collector script permissions

## Implementation Details

Metrics are read directly from Linux kernel interfaces:
- System load: `/proc/loadavg`
- Memory: `/proc/meminfo`
- Container processes: `/sys/fs/cgroup/minirun-{name}/cgroup.procs`
- Container memory: `/sys/fs/cgroup/minirun-{name}/memory.current`
- Container CPU: `/sys/fs/cgroup/minirun-{name}/cpu.stat`

No external dependencies required - uses standard Unix tools (`cat`, `awk`, `date`).

## Future Enhancements

Potential additions:
- Real-time streaming to time-series databases
- Threshold-based alerting
- Network I/O metrics (when network namespace implemented)
- Container lifecycle event tracking
- Anomaly detection
- Integration with external monitoring systems

---

**Related Documentation:**
- [`scripts/monitor.sh`](../scripts/monitor.sh) - Real-time monitoring implementation
- [`scripts/deploy.sh`](../scripts/deploy.sh) - Deployment metrics and reporting