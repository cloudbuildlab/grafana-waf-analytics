#!/bin/bash

# WAF Log Sync Script
# Downloads and processes WAF logs from S3

set -e

LOG_DIR="/mnt/data/waf-logs"
S3_BUCKET="s3://${config_bucket}/AWSLogs/"
REGION="${region}"

echo "$(date): Starting WAF log sync..."

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Sync logs from S3 (incremental)
echo "$(date): Syncing logs from S3..."
aws s3 sync "$S3_BUCKET" "$LOG_DIR/" --region "$REGION" --quiet

# Decompress any .gz files
echo "$(date): Decompressing .gz files..."
find "$LOG_DIR" -name "*.log.gz" -exec gunzip -f {} \;

# Clean up old logs (older than 30 days)
echo "$(date): Cleaning up old logs..."
find "$LOG_DIR" -name "*.log" -mtime +30 -delete

# Count current log files
LOG_COUNT=$(find "$LOG_DIR" -name "*.log" | wc -l)
echo "$(date): Sync complete. Current log files: $LOG_COUNT"

# Show log file locations for debugging
echo "$(date): Log files located at:"
find "$LOG_DIR" -name "*.log" | head -5

# Convert NDJSON to JSON arrays for Grafana
echo "$(date): Converting logs to JSON arrays..."
if [ -x /usr/local/bin/convert-ndjson.sh ]; then
    /usr/local/bin/convert-ndjson.sh
    echo "$(date): Log conversion completed"
else
    echo "$(date): Converter script not found, skipping conversion"
fi
