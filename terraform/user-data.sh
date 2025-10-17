#!/bin/bash
# EC2 User Data Script - Runs on instance first boot
set -e  # Exit on any error

exec > >(tee /var/log/user-data.log)  # Log all output
exec 2>&1

echo "======================================"
echo "MiniRun Container Runtime Setup"
echo "Starting at: $(date)"
echo "======================================"

echo "Updating system packages..."
apt-get update
apt-get upgrade -y

echo "Installing dependencies..."
apt-get install -y gcc make git python3 python3-pip golang-go \
    postgresql-client curl wget jq htop  # All required build tools

export GOPATH=/root/go  # Set Go workspace
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

echo "Creating application directory..."
mkdir -p /opt/minirun
cd /opt/minirun

echo "Cloning repository..."
if [ -d ".git" ]; then
    git pull  # Update if already exists
else
    git clone https://github.com/yourusername/container-project.git .  # Replace with your repo
fi

echo "Building container runtime..."
mkdir -p bin
gcc -o bin/container_runtime src/container_runtime.c -Wall -Wextra  # Compile C runtime

chmod +x scripts/*.sh minirun tests/run_tests.sh  # Make scripts executable

if [ ! -d "myroot/bin" ]; then
    echo "Setting up root filesystem..."
    ./setup_container.sh  # Setup minimal container rootfs
fi

echo "Building Go orchestrator..."
cd orchestrator
go mod download  # Download dependencies
go build -o minirun-api main.go  # Build API binary

mkdir -p /etc/minirun  # Create config directory

echo "Configuring environment..."
cat > /etc/minirun/env.conf << EOF
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
EOF

echo "Creating systemd service..."
cat > /etc/systemd/system/minirun-api.service << 'EOF'
[Unit]
Description=MiniRun Container Orchestrator API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/minirun/orchestrator
EnvironmentFile=/etc/minirun/env.conf  # Load DB credentials
ExecStart=/opt/minirun/orchestrator/minirun-api
Restart=on-failure  # Auto-restart on crash
RestartSec=10       # Wait 10s before restart
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "Starting MiniRun API service..."
systemctl daemon-reload
systemctl enable minirun-api  # Start on boot
systemctl start minirun-api

sleep 5  # Wait for service startup

echo "Checking service status..."
systemctl status minirun-api --no-pager || true

echo "Testing API endpoint..."
curl -f http://localhost:8080/health || echo "API not ready yet"

echo "Configuring log rotation..."
cat > /etc/logrotate.d/minirun << 'EOF'
/var/log/minirun/*.log {
    daily       # Rotate daily
    rotate 7    # Keep 7 days
    compress    # Compress old logs
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
}
EOF

mkdir -p /var/log/minirun

echo "Setting up monitoring..."
cat > /usr/local/bin/minirun-monitor << 'EOF'
#!/bin/bash
cd /opt/minirun
./scripts/monitor.sh --format json > /var/log/minirun/metrics.json
EOF
chmod +x /usr/local/bin/minirun-monitor

echo "*/5 * * * * /usr/local/bin/minirun-monitor" | crontab -  # Run every 5 minutes

apt-get install -y fail2ban  # Install SSH brute-force protection
systemctl enable fail2ban
systemctl start fail2ban

echo "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 8080/tcp  # HTTP API
ufw allow 8443/tcp  # HTTPS API
ufw reload

cat > /etc/motd << 'EOF'
╔════════════════════════════════════════════════╗
║   MiniRun Container Runtime                    ║
║   Orchestrator API Server                      ║
╚════════════════════════════════════════════════╝

API Endpoints:
  - Health Check:    http://localhost:8080/health
  - Documentation:   http://localhost:8080/

Management Commands:
  - Check Status:    systemctl status minirun-api
  - View Logs:       journalctl -u minirun-api -f
  - Restart Service: systemctl restart minirun-api
  - Monitor:         /opt/minirun/scripts/monitor.sh

Project Directory: /opt/minirun

EOF

echo "======================================"
echo "MiniRun setup completed successfully!"
echo "Finished at: $(date)"
echo "======================================"

sleep 10
curl -s http://localhost:8080/health | jq . || echo "API is starting up..."  # Final health check