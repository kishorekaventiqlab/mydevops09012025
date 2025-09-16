#!/bin/bash

# Set up comprehensive logging to /var/log/user_data.log
LOG_FILE="/var/log/user_data.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get EC2 metadata using IMDSv2
get_metadata() {
    local metadata_path=$1
    local token
    
    # Get IMDSv2 token
    token=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        --connect-timeout 5 \
        --silent \
        --fail 2>/dev/null)
    
    if [ -n "$token" ]; then
        # Use token to get metadata
        curl -H "X-aws-ec2-metadata-token: $token" \
            --connect-timeout 5 \
            --silent \
            --fail \
            "http://169.254.169.254/latest/meta-data/$metadata_path" 2>/dev/null
    else
        echo "Unable to retrieve metadata"
    fi
}

log_message "=== Starting User Data Script Execution ==="
log_message "Script started at: $(date)"

# Get instance metadata using IMDSv2
log_message "Retrieving instance metadata..."
INSTANCE_ID=$(get_metadata "instance-id")
INSTANCE_TYPE=$(get_metadata "instance-type")
AVAILABILITY_ZONE=$(get_metadata "placement/availability-zone")

log_message "Instance ID: $INSTANCE_ID"
log_message "Instance Type: $INSTANCE_TYPE"
log_message "Availability Zone: $AVAILABILITY_ZONE"

# Update system and install httpd
log_message "Step 1: Updating system packages"
if yum update -y; then
    log_message "✅ System update completed successfully"
else
    log_message "❌ System update failed"
    exit 1
fi

log_message "Step 2: Installing httpd web server"
if yum install -y httpd; then
    log_message "✅ httpd installed successfully"
else
    log_message "❌ httpd installation failed"
    exit 1
fi

log_message "Step 3: Starting and enabling httpd service"
if systemctl start httpd; then
    log_message "✅ httpd service started successfully"
else
    log_message "❌ Failed to start httpd service"
    exit 1
fi

if systemctl enable httpd; then
    log_message "✅ httpd service enabled for auto-start"
else
    log_message "❌ Failed to enable httpd service"
fi

# Get instance DNS using IMDSv2
log_message "Step 4: Retrieving instance DNS"
INSTANCE_DNS=$(get_metadata "public-hostname")
if [ -z "$INSTANCE_DNS" ] || [ "$INSTANCE_DNS" = "Unable to retrieve metadata" ]; then
    INSTANCE_DNS=$(get_metadata "local-hostname")
    log_message "Using local hostname: $INSTANCE_DNS"
else
    log_message "Instance DNS: $INSTANCE_DNS"
fi

# Create simple HTML page
log_message "Step 5: Creating HTML webpage"
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Hello AWS from $INSTANCE_DNS</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            margin: 0;
            padding: 50px;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 20px;
        }
        .dns-info {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px auto;
            max-width: 600px;
        }
        .metadata-info {
            background: rgba(255,255,255,0.05);
            padding: 15px;
            border-radius: 5px;
            margin: 10px 0;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <h1>Hello AWS from $INSTANCE_DNS</h1>
    <div class="dns-info">
        <p><strong>Instance DNS:</strong> $INSTANCE_DNS</p>
        <p><strong>Status:</strong> ✅ Online</p>
        <p><strong>Last Updated:</strong> $(date)</p>
        <div class="metadata-info">
            <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
            <p><strong>Instance Type:</strong> $INSTANCE_TYPE</p>
            <p><strong>Availability Zone:</strong> $AVAILABILITY_ZONE</p>
        </div>
    </div>
</body>
</html>
EOF

if [ -f /var/www/html/index.html ]; then
    log_message "✅ HTML file created successfully"
    HTML_SIZE=$(wc -c < /var/www/html/index.html)
    log_message "HTML file size: $HTML_SIZE bytes"
else
    log_message "❌ Failed to create HTML file"
    exit 1
fi

# Set proper permissions
log_message "Step 6: Setting file permissions"
if chown -R apache:apache /var/www/html; then
    log_message "✅ Ownership set to apache:apache"
else
    log_message "❌ Failed to set ownership"
fi

if chmod -R 755 /var/www/html; then
    log_message "✅ Permissions set to 755"
else
    log_message "❌ Failed to set permissions"
fi

# RESTART httpd service after HTML creation and permission changes
log_message "Step 7: Restarting httpd service after content setup"
if systemctl restart httpd; then
    log_message "✅ httpd service restarted successfully"
else
    log_message "❌ Failed to restart httpd service"
    exit 1
fi

# Verify httpd is running and accessible
log_message "Step 8: Verifying web server accessibility"
sleep 5  # Give httpd a moment to fully start

if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "200"; then
    log_message "✅ Web server is responding correctly (HTTP 200)"
else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
    log_message "❌ Web server not responding correctly (HTTP $HTTP_CODE)"
fi

# Check httpd service status
HTTPD_STATUS=$(systemctl is-active httpd)
log_message "httpd service status: $HTTPD_STATUS"

# Test actual content
log_message "Step 9: Testing HTML content delivery"
CONTENT_TEST=$(curl -s http://localhost | grep -c "Hello AWS")
if [ "$CONTENT_TEST" -gt 0 ]; then
    log_message "✅ HTML content is being served correctly"
else
    log_message "❌ HTML content not found in response"
fi

# Final logging
log_message "=== User Data Script Execution Completed ==="
log_message "Total execution time: $SECONDS seconds"
log_message "Final status: SUCCESS"
log_message "Website URL: http://$INSTANCE_DNS"
log_message "Log file location: $LOG_FILE"

# Also create a simple completion indicator
echo "Simple HTML site setup completed at $(date)" > /var/log/setup.log
echo "User data execution log: $LOG_FILE" >> /var/log/setup.log
echo "Instance ID: $INSTANCE_ID" >> /var/log/setup.log
echo "Instance DNS: $INSTANCE_DNS" >> /var/log/setup.log

# Make log file readable
chmod 644 $LOG_FILE

log_message "User data script finished successfully!"
log_message "Script ended at: $(date)"
