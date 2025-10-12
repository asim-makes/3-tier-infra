#!/bin/bash

# AWS Settings
REGION="us-east-1"
TOPIC_NAME="CDK-Buffer"

EC2_INSTANCE_ID="i-01af26efe7ed5fa1b"
RDS_INSTANCE_ID="appstack-rdsinstance6c916663-yieyweuwdwk4"

# Alarm 1: EC2 High CPU Threshold
ALARM_CPU_NAME="EC2-High-CPU-$REGION"
ALARM_CPU_THRESHOLD=80.0

# Alarm 2: RDS Low Storage Threshold
ALARM_RDS_NAME="RDS-Low-Storage-$REGION"
ALARM_RDS_THRESHOLD=10737418240

# LOGGING SETUP
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/infra-alarms-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() {
    local log_message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp $log_message" | tee -a "$LOG_FILE"
}

log "--------------------------------------------------------"
log "STARTING SCRIPT: EC2 and RDS Alarm Setup"
log "Region: $REGION | Target Topic: $TOPIC_NAME"


log "1. Searching for SNS Topic: $TOPIC_NAME..."

TOPIC_ARN_RAW=$(aws sns list-topics \
    --region "$REGION" \
    --query "Topics[?ends_with(TopicArn, ':$TOPIC_NAME')].TopicArn" \
    --output text 2>&1)

TOPIC_ARN=$(echo "$TOPIC_ARN_RAW" | tr -d '[:space:]')

if [ -z "$TOPIC_ARN" ]; then
    log "ERROR: Could not find a topic named '$TOPIC_NAME' in region $REGION."
    log "       Action: Please create the SNS topic first and ensure the name is correct."
    log "--------------------------------------------------------"
    echo "Failed to set up alarms. Check the logs at logs/ for errors."
    exit 1
fi

log "SUCCESS: Found Topic ARN: $TOPIC_ARN"

# ALARM 1: EC2 High CPU Utilization (> 80%)
if [ "$EC2_INSTANCE_ID" == "i-xxxxxxxxxxxxxxxxx" ]; then
    log "SKIP: EC2_INSTANCE_ID placeholder not updated. Skipping EC2 alarm setup."
else
    log "2. EC2 Alarm: Checking for existing CPU alarm for $EC2_INSTANCE_ID..."

    EXISTING_CPU_ALARM=$(aws cloudwatch describe-alarms \
        --region "$REGION" \
        --alarm-names "$ALARM_CPU_NAME-$EC2_INSTANCE_ID" \
        --query "MetricAlarms" \
        --output text 2>/dev/null)

    if [ -n "$EXISTING_CPU_ALARM" ]; then
        log "   Alarm already exists. Skipping EC2 alarm creation."
    else
        log "   Alarm not found. Creating CloudWatch Metric Alarm: $ALARM_CPU_NAME-$EC2_INSTANCE_ID..."

        aws cloudwatch put-metric-alarm \
            --region "$REGION" \
            --alarm-name "$ALARM_CPU_NAME-$EC2_INSTANCE_ID" \
            --alarm-description "Triggers when EC2 CPU utilization exceeds $ALARM_CPU_THRESHOLD% for 10 minutes." \
            --metric-name CPUUtilization \
            --namespace AWS/EC2 \
            --statistic Average \
            --period 300 \
            --evaluation-periods 2 \
            --threshold $ALARM_CPU_THRESHOLD \
            --comparison-operator GreaterThanThreshold \
            --dimensions Name=InstanceId,Value=$EC2_INSTANCE_ID \
            --alarm-actions "$TOPIC_ARN" 2>&1

        if [ $? -eq 0 ]; then
            log "   SUCCESS: EC2 CPU Alarm created/updated successfully."
        else
            log "   ERROR: Failed to create EC2 CPU Alarm."
        fi
    fi
fi


# ALARM 2: RDS Low Free Storage (< 10 GB)
if [ "$RDS_INSTANCE_ID" == "my-production-rds" ]; then
    log "SKIP: RDS_INSTANCE_ID placeholder not updated. Skipping RDS alarm setup."
else
    log "3. RDS Alarm: Checking for existing Storage alarm for $RDS_INSTANCE_ID..."

    EXISTING_RDS_ALARM=$(aws cloudwatch describe-alarms \
        --region "$REGION" \
        --alarm-names "$ALARM_RDS_NAME-$RDS_INSTANCE_ID" \
        --query "MetricAlarms" \
        --output text 2>/dev/null)

    if [ -n "$EXISTING_RDS_ALARM" ]; then
        log "   Alarm already exists. Skipping RDS alarm creation."
    else
        log "   Alarm not found. Creating CloudWatch Metric Alarm: $ALARM_RDS_NAME-$RDS_INSTANCE_ID (Threshold: 10 GB)..."

        aws cloudwatch put-metric-alarm \
            --region "$REGION" \
            --alarm-name "$ALARM_RDS_NAME-$RDS_INSTANCE_ID" \
            --alarm-description "Triggers when RDS free storage space drops below 10 GB." \
            --metric-name FreeStorageSpace \
            --namespace AWS/RDS \
            --statistic Minimum \
            --period 300 \
            --evaluation-periods 1 \
            --threshold $ALARM_RDS_THRESHOLD \
            --comparison-operator LessThanThreshold \
            --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE_ID \
            --alarm-actions "$TOPIC_ARN" 2>&1

        if [ $? -eq 0 ]; then
            log "   SUCCESS: RDS Storage Alarm created/updated successfully."
        else
            log "   ERROR: Failed to create RDS Storage Alarm."
        fi
    fi
fi

log "SCRIPT FINISHED: Review logs for details."
log "--------------------------------------------------------"
echo "Infra alarm setup complete. Check the logs/infra-alarms-$(date +%Y%m%d).log file."
