#!/bin/bash

REGION=""
JQ_PATH=$(which jq)

LOG_DIR="logs"
LOG_FILE="$LOG_DIR/ec2-health-check-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() {
    local log_message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    # Log to both stdout and the log file
    echo "$timestamp $log_message" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 --region <AWS_REGION> [--az <AVAILABILITY_ZONE>]"
    echo ""
    echo "Gathers key inventory details for EC2 instances."
    echo ""
    echo "  --region <REGION>           The AWS region to check (e.g., us-east-1). (Required)"
    echo "  --az <AVAILABILITY_ZONE>    Optional. Filter results by a specific Availability Zone (e.g., us-east-1a)."
    echo "  --help                      Display this help message."
    exit 1
}

log "--------------------------------------------------------------------------------"
log "STARTING SCRIPT: EC2 Instance Inventory Check"

AZ_FILTER=""
while [ "$1" != "" ]; do
    PARAM=$(echo "$1" | awk -F= '{print $1}')
    VALUE=$(echo "$1" | awk -F= '{print $2}')
    case $PARAM in
        -h | --help)
            usage
            ;;
        --region)
            REGION=$2
            shift
            ;;
        --az)
            AZ_FILTER=$2
            shift
            ;;
        *)
            log "ERROR: Unknown parameter \"$PARAM\""
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            ;;
    esac
    shift
done

if [ -z "$REGION" ]; then
    log "ERROR: --region is required."
    echo "ERROR: --region is required."
    usage
fi

log "Target Region: $REGION"

if [ -z "$JQ_PATH" ]; then
    log "FATAL ERROR: 'jq' is not installed."
    echo "ERROR: 'jq' is not installed. Please install it to run this script."
    exit 1
fi

log "INFO: 'jq' found at: $JQ_PATH"

log "Defining AWS filters for running and stopped instances."
FILTERS="Name=instance-state-name,Values=running,stopped"

if [ ! -z "$AZ_FILTER" ]; then
    log "INFO: Filtering by Availability Zone: $AZ_FILTER"
    echo "INFO: Filtering instances by Availability Zone: $AZ_FILTER"
    FILTERS="${FILTERS} Name=availability-zone,Values=$AZ_FILTER"
fi

log "--- EC2 Instance Inventory: $REGION $([ ! -z "$AZ_FILTER" ] && echo "($AZ_FILTER)") ---"
echo "--- EC2 Instance Inventory: $REGION $([ ! -z "$AZ_FILTER" ] && echo "($AZ_FILTER)") ---"

log "Fetching EC2 instance data using describe-instances..."
EC2_DATA=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters $(echo "$FILTERS" | tr ' ' '\n') \
    --query 'Reservations[].Instances[].{
        ID:InstanceId,
        Name:Tags[?Key==`Name`].Value | [0],
        AZ:Placement.AvailabilityZone,
        State:State.Name,
        Type:InstanceType,
        OS:PlatformDetails,
        PrivateIP:PrivateIpAddress,
        PublicIP:PublicIpAddress
    }' \
    --output json 2>/dev/null \
    | $JQ_PATH -c '.[]'
)

if [ $? -ne 0 ]; then
    log "FATAL ERROR: AWS CLI command failed. Check your credentials and region name."
    echo "🚨 ERROR: AWS CLI command failed. Check your credentials and region name."
    exit 1
fi

if [ -z "$EC2_DATA" ]; then
    log "SUCCESS: No instances found matching the criteria."
    echo "✅ No instances found matching the criteria."
    echo "------------------------------------------------------------------------------------------------------------------------"
else
    INSTANCE_COUNT=$(echo "$EC2_DATA" | wc -l | tr -d '[:space:]')
    log "INFO: Found $INSTANCE_COUNT EC2 Instance(s)."
    echo "Found EC2 Instances:"
    echo "------------------------------------------------------------------------------------------------------------------------"
    printf "%-20s | %-11s | %-11s | %-8s | %-10s | %-15s | %-15s | %s\n" "Name" "ID" "AZ" "State" "Type" "Private IP" "Public IP" "OS"
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "$EC2_DATA" | while IFS= read -r INSTANCE_INFO; do
        NAME=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.Name // "N/A"')
        ID=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.ID')
        AZ=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.AZ')
        STATE=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.State')
        TYPE=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.Type')
        PRIV_IP=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.PrivateIP // "N/A"')
        PUB_IP=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.PublicIP // "N/A"')
        OS=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.OS // "N/A"')

        log "INVENTORY: ID: $ID | Name: $NAME | State: $STATE | Type: $TYPE | Private IP: $PRIV_IP"
        printf "%-20s | %-11s | %-11s | %-8s | %-10s | %-15s | %-15s | %s\n" \
            "${NAME:0:20}" "$ID" "$AZ" "$STATE" "$TYPE" "$PRIV_IP" "$PUB_IP" "${OS:0:15}"
    done
    echo "------------------------------------------------------------------------------------------------------------------------"
fi

log "SCRIPT FINISHED."
log "--------------------------------------------------------------------------------"
exit 0
