#!/bin/bash

# Configuration
REGION="us-east-1"
TOPIC_NAME="CDK-Buffer"
ALARM_NAME_LOW="Billing-Immediate-Alert-$REGION"
ALARM_THRESHOLD_LOW=1.00 

# Logging Setup
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/billing-alarm-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() {
    local log_message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp $log_message" | tee -a "$LOG_FILE"
}

# Start logging
log "--------------------------------------------------------"
log "STARTING SCRIPT: AWS Billing Alarm Setup"
log "Region: $REGION | Target Alarm: $ALARM_NAME_LOW"

log "1. Checking for existing alarm: $ALARM_NAME_LOW..."

EXISTING_ALARM=$(aws cloudwatch describe-alarms \
    --region "$REGION" \
    --alarm-names "$ALARM_NAME_LOW" \
    --query "MetricAlarms" \
    --output text 2>/dev/null)

if [ -n "$EXISTING_ALARM" ]; then
    log "Alarm already exists. Skipping creation and exiting."
    log "--------------------------------------------------------"
	echo "Alarm already exists."
    exit 0
fi

log "Alarm not found. Proceeding with creation."

log "2. Checking for enabled EstimatedCharges billing metric..."

BILLING_METRIC=$(aws cloudwatch list-metrics \
    --namespace "AWS/Billing" \
    --metric-name "EstimatedCharges" \
    --region "$REGION" \
    --query "Metrics[?length(Dimensions)==\`1\` && Dimensions[0].Name=='Currency' && Dimensions[0].Value=='USD']" \
    --output text 2>&1)

if [ -z "$BILLING_METRIC" ]; then
    log "Billing metric not enabled. Failed to find metric."
    log "   Action: Enable it in the Billing Console -> Preferences -> Receive CloudWatch Alerts."
    log "--------------------------------------------------------"
	echo "Failed to create cloud watch alarm. Check the logs at logs/ for errors."
    exit 1
fi

log "Billing metric is enabled."

log "3. Searching for SNS Topic: $TOPIC_NAME..."

TOPIC_ARN_RAW=$(aws sns list-topics \
    --region "$REGION" \
    --query "Topics[?contains(TopicArn, '$TOPIC_NAME')].TopicArn" \
    --output text 2>&1)

# Clean the output by removing any surrounding spaces/newlines
TOPIC_ARN=$(echo "$TOPIC_ARN_RAW" | tr -d '[:space:]')

if [ -z "$TOPIC_ARN" ]; then
    log "Could not find a topic named '$TOPIC_NAME' in region $REGION."
    log "   Action: Please create the SNS topic first and ensure the name is correct."
    log "--------------------------------------------------------"
	echo "Failed to create cloud watch alarm. Check the logs at logs/ for errors."
    exit 1
fi

log "Found Topic ARN: $TOPIC_ARN"

log "4. Creating CloudWatch Metric Alarm: $ALARM_NAME_LOW (Threshold: \$$ALARM_THRESHOLD_LOW)..."

aws cloudwatch put-metric-alarm \
    --region "$REGION" \
    --alarm-name "$ALARM_NAME_LOW" \
    --alarm-description "Early warning for any charges exceeding $ALARM_THRESHOLD_LOW USD." \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 21600 \
    --evaluation-periods 1 \
    --threshold $ALARM_THRESHOLD_LOW \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions Name=Currency,Value=USD \
    --alarm-actions "$TOPIC_ARN" 2>&1

if [ $? -eq 0 ]; then
    log "SUCCESS: Alarm $ALARM_NAME_LOW created/updated successfully."
    log "   Notification will be sent to $TOPIC_NAME when charges exceed \$$ALARM_THRESHOLD_LOW USD."
	echo "CloudWatch Alarm created successfully."
else
    log "ERROR: Failed to create the CloudWatch alarm."
    log "--------------------------------------------------------"
	echo "Failed to create cloud watch alarm. Check the logs at logs/ for errors."
    exit 1
fi

log "--------------------------------------------------------"