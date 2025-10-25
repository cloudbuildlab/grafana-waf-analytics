# grafana-waf-analytics

AWS WAF log analytics and monitoring dashboard built with Grafana, Loki, and Promtail

## Architecture

```plaintext
S3 WAF Logs → EC2 Sync Service → Local JSON Files → Grafana → Dashboards
```

## Features

- **Real-time Analytics**: WAF logs synced every 5 minutes from S3
- **Geographic Analysis**: Country-based threat analysis and filtering
- **Rule Monitoring**: Track WAF rule matches and actions
- **HTTP Status Tracking**: Monitor connection patterns and response codes
- **Secure Access**: SSM Session Manager port forwarding only

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Access to `${var.waf_logs_bucket_name}` S3 bucket

### Deployment

1. **Configure variables**:

   Copy the example variables file and update with your values:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your S3 bucket name
   ```

2. **Initialize Terraform**:

   ```bash
   terraform init
   ```

3. **Plan deployment**:

   ```bash
   terraform plan
   ```

4. **Deploy infrastructure**:

   ```bash
   terraform apply
   ```

5. **Wait for instance initialization** (5-10 minutes)

### Access Grafana

1. **Get instance ID**:

   ```bash
   terraform output instance_id
   ```

2. **Establish SSM port forwarding**:

   ```bash
   terraform output ssm_connection_command
   ```

3. **Access Grafana**:
   - Open browser to `http://localhost:3000`
   - Login: `admin` / `admin`

## Dashboards

### WAF Analytics Overview

- Request volume over time
- Top blocked IPs
- Action distribution (ALLOW/BLOCK/COUNT)
- Top rule matches

### Geographic Analysis

- Geographic distribution of requests
- Top blocked countries
- Country-based filtering

### Connection Monitoring

- HTTP status code distribution
- Status codes over time
- Connection pattern analysis

## Configuration

### WAF Log Sync

- **Frequency**: Every 5 minutes
- **Retention**: 30 days
- **Source**: `s3://${var.waf_logs_bucket_name}/AWSLogs/`
- **Destination**: `/var/waf-logs/`

### Grafana Settings

- **Port**: 3000
- **Data Directory**: `/var/lib/grafana`
- **Logs Directory**: `/var/log/grafana`
- **Plugin**: Infinity Datasource for JSON files

## Management

### Manual Log Sync

```bash
sudo /usr/local/bin/sync-waf-logs.sh
```

### Service Management

```bash
# Check Grafana status
sudo systemctl status grafana

# Check WAF sync timer
sudo systemctl status waf-sync.timer

# View sync logs
sudo journalctl -u waf-sync.service -f
```

### Update Dashboards

1. Modify JSON files in `grafana-configs/grafana/provisioning/dashboards/`
2. Run `terraform apply` to upload changes
3. Restart Grafana: `sudo systemctl restart grafana`

## Troubleshooting

### Instance Not Accessible via SSM

- Ensure VPC endpoints are created
- Check security group allows outbound HTTPS
- Verify IAM role has SSM permissions

### No WAF Logs Appearing

- Check sync service status: `sudo systemctl status waf-sync.timer`
- Verify S3 bucket permissions
- Check sync logs: `sudo journalctl -u waf-sync.service`

### Grafana Not Loading

- Check service status: `sudo systemctl status grafana`
- Review logs: `sudo journalctl -u grafana -f`
- Verify port 3000 is listening: `sudo netstat -tlnp | grep 3000`

## Security

- **No inbound firewall rules**: SSM only access
- **Encrypted S3 bucket**: AES256 encryption
- **IAM least privilege**: Read-only S3 access
- **VPC endpoints**: Private communication with AWS services

## Cost Optimization

- **t3.medium instance**: ~$30/month
- **S3 storage**: Minimal for configs (~$0.023/month)
- **Data transfer**: Minimal (sync only)

## Cleanup

```bash
terraform destroy
```

This will remove all resources including:

- EC2 instance
- VPC and networking
- S3 configuration bucket
- IAM roles and policies
