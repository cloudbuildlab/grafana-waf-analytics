#!/bin/bash

# Log all output to journal
exec > >(tee -a /var/log/config-sync.log) 2>&1

echo "=========================================="
echo "Grafana Configuration Sync Starting..."
echo "Timestamp: $(date)"
echo "=========================================="

# Get configuration from environment variables (set by user_data.sh)
CONFIG_BUCKET=${CONFIG_BUCKET:-"unknown"}
REGION=${AWS_REGION:-"ap-southeast-2"}

echo "Config bucket: $CONFIG_BUCKET"
echo "Region: $REGION"

# Download grafana configuration
echo "Downloading grafana configuration..."
aws s3 sync s3://${CONFIG_BUCKET}/grafana/ /etc/grafana/ --region ${REGION}

# Download promtail configuration
echo "Downloading promtail configuration..."
aws s3 cp s3://${CONFIG_BUCKET}/promtail/config.yml /etc/promtail/config.yml --region ${REGION}

# Download loki configuration
echo "Downloading loki configuration..."
aws s3 cp s3://${CONFIG_BUCKET}/loki/loki.yml /etc/loki/loki.yml --region ${REGION}

# Download country coordinates data
echo "Downloading country coordinates data..."
aws s3 cp s3://${CONFIG_BUCKET}/data/country-coords.json /var/www/data/country-coords.json --region ${REGION}

# Download WAF sync configuration
echo "Downloading WAF sync configuration..."
aws s3 cp s3://${CONFIG_BUCKET}/waf-sync/waf-sync.service /etc/systemd/system/waf-sync.service --region ${REGION}
aws s3 cp s3://${CONFIG_BUCKET}/waf-sync/waf-sync.timer /etc/systemd/system/waf-sync.timer --region ${REGION}
chmod +x /usr/local/bin/sync-waf-logs.sh

# Download config sync configuration
echo "Downloading config sync configuration..."
aws s3 cp s3://${CONFIG_BUCKET}/config-sync/config-sync.service /etc/systemd/system/config-sync.service --region ${REGION}
aws s3 cp s3://${CONFIG_BUCKET}/config-sync/config-sync.timer /etc/systemd/system/config-sync.timer --region ${REGION}
aws s3 cp s3://${CONFIG_BUCKET}/config-sync/config-sync.sh /usr/local/bin/config-sync.sh --region ${REGION}
chmod +x /usr/local/bin/config-sync.sh

# Download dashboard files
echo "Downloading dashboard files..."
aws s3 sync s3://${CONFIG_BUCKET}/grafana/provisioning/dashboards/ /etc/grafana/provisioning/dashboards/ --region ${REGION}

# Download datasource files
echo "Downloading datasource files..."
aws s3 sync s3://${CONFIG_BUCKET}/grafana/provisioning/datasources/ /etc/grafana/provisioning/datasources/ --region ${REGION}

# Reload systemd daemon to pick up any new service files
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Restart services to apply new configurations
echo "Restarting services to apply new configurations..."

# Restart Promtail if running
if systemctl is-active --quiet promtail.service; then
    echo "Restarting Promtail..."
    systemctl restart promtail.service
fi

# Restart Loki if running
if systemctl is-active --quiet loki.service; then
    echo "Restarting Loki..."
    systemctl restart loki.service
fi

# Restart WAF sync timer if running
if systemctl is-active --quiet waf-sync.timer; then
    echo "Restarting WAF sync timer..."
    systemctl restart waf-sync.timer
fi

# Restart config sync timer if running
if systemctl is-active --quiet config-sync.timer; then
    echo "Restarting config sync timer..."
    systemctl restart config-sync.timer
fi

# Restart Grafana to pick up new dashboards and datasources
if systemctl is-active --quiet grafana.service; then
    echo "Restarting Grafana to apply new dashboards and datasources..."
    systemctl restart grafana.service
fi
