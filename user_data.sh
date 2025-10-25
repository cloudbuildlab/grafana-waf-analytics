#!/bin/bash

# Log all output to standard AWS user-data log location
exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "WAF Analytics Dashboard Setup Starting..."
echo "Timestamp: $$(date)"
echo "=========================================="

# Update system
echo "Updating system packages..."
dnf update -y

# Install required packages
echo "Installing required packages..."
dnf install -y curl-minimal unzip tree htop jq

# Install & Start AWS SSM Agent (required for Session Manager)
# Amazon Linux 2023 does NOT come with the SSM Agent pre-installed
echo "Installing SSM agent..."
dnf install -y amazon-ssm-agent

# Enable and start SSM agent
echo "Starting SSM agent..."
systemctl enable --now amazon-ssm-agent

# Check if instance can reach AWS metadata service
echo "Testing AWS metadata service..."
INSTANCE_ID=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/instance-id)
if [ $? -eq 0 ]; then
  echo " - Metadata service reachable, Instance ID: $INSTANCE_ID"
else
  echo " - Metadata service NOT reachable"
fi

# Test IMDS v2 token (required for security)
echo "Testing IMDS v2 token..."
TOKEN=$(curl -s --max-time 5 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
if [ $? -eq 0 ] && [ -n "$TOKEN" ]; then
  echo " - IMDS v2 token obtained successfully"
  # Test getting credentials with v2 token
  curl -s --max-time 5 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ >/dev/null && echo " - IAM credentials accessible" || echo " - IAM credentials NOT accessible"

  # Test getting the actual IAM role name
  ROLE_NAME=$(curl -s --max-time 5 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
  if [ -n "$ROLE_NAME" ]; then
    echo " - IAM Role: $ROLE_NAME"
  fi
else
  echo " - IMDS v2 token NOT obtained - this may cause SSM issues"
fi

# Extend root filesystem if needed
echo "Extending root filesystem..."
growpart /dev/nvme0n1 1
resize2fs /dev/nvme0n1p1

# Install Loki
cd /tmp
curl -L -o install_loki.sh https://raw.githubusercontent.com/jdevto/cli-tools/refs/heads/main/scripts/install_loki.sh
chmod +x install_loki.sh
./install_loki.sh install --start

# Install Promtail
cd /tmp
curl -L -o install_promtail.sh https://raw.githubusercontent.com/jdevto/cli-tools/refs/heads/main/scripts/install_promtail.sh
chmod +x install_promtail.sh
./install_promtail.sh install --start

# Install Grafana
cd /tmp
curl -L -o install_grafana.sh https://raw.githubusercontent.com/jdevto/cli-tools/refs/heads/main/scripts/install_grafana.sh
chmod +x install_grafana.sh
./install_grafana.sh install --start

# Create directories
echo "Creating directories..."
mkdir -p /var/lib/loki/chunks
mkdir -p /var/lib/loki/rules
mkdir -p /var/lib/promtail
mkdir -p /etc/loki
mkdir -p /etc/promtail
mkdir -p /var/www/data
mkdir -p /var/lib/grafana

# Set permissions
chown -R loki:loki /var/lib/loki
chown -R promtail:promtail /var/lib/promtail
chown -R grafana:grafana /var/www/data
chown -R grafana:grafana /opt/grafana
chown -R grafana:grafana /var/lib/grafana

# Download and install Grafana Infinity plugin
echo "Installing Grafana Infinity plugin..."
cd /opt/grafana/bin
./grafana cli plugins install yesoreyeram-infinity-datasource
chown -R grafana:grafana /opt/grafana
echo "Grafana Infinity plugin installed successfully"

# Download grafana configuration
echo "Downloading grafana configuration..."
aws s3 sync s3://${config_bucket}/grafana/ /etc/grafana/ --region ${region}

# Download country coordinates data
echo "Downloading country coordinates data..."
aws s3 cp s3://${config_bucket}/data/country-coords.json /var/www/data/country-coords.json --region ${region}

# Download WAF sync configuration
echo "Downloading WAF sync configuration..."
aws s3 cp s3://${config_bucket}/waf-sync/waf-sync.service /etc/systemd/system/waf-sync.service --region ${region}
aws s3 cp s3://${config_bucket}/waf-sync/waf-sync.timer /etc/systemd/system/waf-sync.timer --region ${region}
aws s3 cp s3://${config_bucket}/waf-sync/sync-waf-logs.sh /usr/local/bin/sync-waf-logs.sh --region ${region}
chmod +x /usr/local/bin/sync-waf-logs.sh

# Download config sync configuration
echo "Downloading config sync configuration..."
aws s3 cp s3://${config_bucket}/config-sync/config-sync.service /etc/systemd/system/config-sync.service --region ${region}
aws s3 cp s3://${config_bucket}/config-sync/config-sync.timer /etc/systemd/system/config-sync.timer --region ${region}
aws s3 cp s3://${config_bucket}/config-sync/config-sync.sh /usr/local/bin/config-sync.sh --region ${region}
chmod +x /usr/local/bin/config-sync.sh

# Download dashboard files
echo "Downloading dashboard files..."
aws s3 sync s3://${config_bucket}/grafana/provisioning/dashboards/ /etc/grafana/provisioning/dashboards/ --region ${region}

# Download datasource files
echo "Downloading datasource files..."
aws s3 sync s3://${config_bucket}/grafana/provisioning/datasources/ /etc/grafana/provisioning/datasources/ --region ${region}

# Wait for data volume to be available
echo "Waiting for data volume to be available..."
while [ ! -e /dev/sdf ]; do
    echo "Waiting for /dev/sdf to be available..."
    sleep 5
done

# Check if volume is already formatted
if ! blkid /dev/sdf >/dev/null 2>&1; then
    echo "Formatting data volume..."
    mkfs.ext4 /dev/sdf
else
    echo "Data volume already formatted"
fi

# Mount data volume
echo "Mounting data volume..."
mkdir -p /mnt/data
mount /dev/sdf /mnt/data
echo "/dev/sdf /mnt/data ext4 defaults 0 2" >> /etc/fstab

# Create directories on data volume
echo "Creating directories on data volume..."
mkdir -p /mnt/data/grafana
mkdir -p /mnt/data/waf-logs
mkdir -p /mnt/data/loki
mkdir -p /var/log/grafana
mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards

# Create symlinks
echo "Creating symlinks..."
rm -rf /var/lib/grafana
rm -rf /var/waf-logs
ln -sf /mnt/data/grafana /var/lib/grafana
ln -sf /mnt/data/waf-logs /var/waf-logs

# Set permissions
chown -R grafana:grafana /var/lib/grafana
chown -R grafana:grafana /var/log/grafana
chown -R grafana:grafana /etc/grafana
chown -R grafana:grafana /mnt/data/grafana
chown -R grafana:grafana /var/waf-logs
chown -R loki:loki /mnt/data/loki

# Create simple HTTP server for static data
echo "Creating HTTP server for static data..."
cat > /usr/local/bin/serve-data.sh << 'EOF'
#!/bin/bash
cd /var/www/data
python3 -m http.server 8080 --bind 127.0.0.1
EOF
chmod +x /usr/local/bin/serve-data.sh

# Create systemd service for data server
cat > /etc/systemd/system/data-server.service << 'EOF'
[Unit]
Description=HTTP Server for Static Data
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/serve-data.sh
Restart=always
User=grafana
Group=grafana

[Install]
WantedBy=multi-user.target
EOF

# Start services
echo "Starting services..."
systemctl daemon-reload

# Start data server
echo "Starting data server..."
systemctl enable data-server.service
systemctl start data-server.service
if [ $? -eq 0 ]; then
  echo "Data server started successfully"
else
  echo "Error: Failed to start data server service"
  systemctl status data-server.service --no-pager
  exit 1
fi

# Start WAF sync timer
echo "Starting WAF sync timer..."
systemctl enable waf-sync.timer
systemctl start waf-sync.timer
if [ $? -eq 0 ]; then
  echo "WAF sync timer started successfully"
else
  echo "Error: Failed to start WAF sync timer"
  systemctl status waf-sync.timer --no-pager
  exit 1
fi

# Start config sync timer
echo "Starting config sync timer..."
systemctl enable config-sync.timer
systemctl start config-sync.timer
if [ $? -eq 0 ]; then
  echo "Config sync timer started successfully"
else
  echo "Error: Failed to start config sync timer"
  systemctl status config-sync.timer --no-pager
  exit 1
fi

# Run initial sync
echo "Running initial WAF log sync..."
/usr/local/bin/sync-waf-logs.sh
echo "Initial WAF log sync completed"

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 30

# Check service status with detailed verification
echo "Checking service status..."
FAILED_SERVICES=""

if systemctl is-active loki.service >/dev/null 2>&1; then
  echo "✓ Loki service is active"
else
  echo "✗ Loki service failed to start"
  FAILED_SERVICES="$FAILED_SERVICES loki"
fi

if systemctl is-active promtail.service >/dev/null 2>&1; then
  echo "✓ Promtail service is active"
else
  echo "✗ Promtail service failed to start"
  FAILED_SERVICES="$FAILED_SERVICES promtail"
fi

if systemctl is-active grafana.service >/dev/null 2>&1; then
  echo "✓ Grafana service is active"
else
  echo "✗ Grafana service failed to start"
  FAILED_SERVICES="$FAILED_SERVICES grafana"
fi

if systemctl is-active waf-sync.timer >/dev/null 2>&1; then
  echo "✓ WAF sync timer is active"
else
  echo "✗ WAF sync timer failed to start"
  FAILED_SERVICES="$FAILED_SERVICES waf-sync"
fi

if systemctl is-active config-sync.timer >/dev/null 2>&1; then
  echo "✓ Config sync timer is active"
else
  echo "✗ Config sync timer failed to start"
  FAILED_SERVICES="$FAILED_SERVICES config-sync"
fi

# Test Loki API
echo "Testing Loki API..."
if curl -s http://localhost:3100/ready >/dev/null 2>&1; then
  echo "✓ Loki API is responding"
else
  echo "✗ Loki API is not responding"
  FAILED_SERVICES="$FAILED_SERVICES loki-api"
fi

# Test Grafana API
echo "Testing Grafana API..."
if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
  echo "✓ Grafana API is responding"
else
  echo "✗ Grafana API is not responding"
  FAILED_SERVICES="$FAILED_SERVICES grafana-api"
fi

# Report any failures
if [ -n "$FAILED_SERVICES" ]; then
  echo ""
  echo "⚠️  WARNING: Some services failed to start properly: $FAILED_SERVICES"
  echo "Check the logs with: journalctl -u <service-name> --no-pager"
  echo ""
else
  echo ""
  echo "✅ All services are running successfully!"
  echo ""
fi

echo "=========================================="
echo "WAF Analytics Dashboard setup complete!"
echo "Completion timestamp: $$(date)"
echo ""
echo "Services running:"
echo "- Loki: http://localhost:3100"
echo "- Grafana: http://localhost:3000"
echo "- Data server: http://localhost:8080"
echo ""
echo "Grafana should be accessible via SSM port forwarding on port 3000"
echo "Use: aws ssm start-session --target <instance-id> --region ${region} --document-name AWS-StartPortForwardingSession --parameters 'portNumber=3000,localPortNumber=3000'"
echo "=========================================="
