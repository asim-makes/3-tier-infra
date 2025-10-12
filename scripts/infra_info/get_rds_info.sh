#!/bin/bash

REGION=""
JQ_PATH=$(which jq)

LOG_DIR="logs"
LOG_FILE="$LOG_DIR/rds-inventory-check-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() {
    local log_message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp $log_message" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 --region <AWS_REGION>"
    echo ""
    echo "Gathers configuration details for all RDS DB instances."
    echo ""
    echo "  --region <REGION>          The AWS region to check (e.g., us-east-1). (Required)"
    echo "  --help                     Display this help message."
    exit 1
}

log "--------------------------------------------------------------------------------"
log "STARTING SCRIPT: RDS DB Instance Inventory Check"

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
        *)
            log "ERROR: unknown parameter \"$PARAM\""
            echo "ERROR: unknown parameter \"$PARAM\"" # Keep terminal output
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

log "--- RDS DB Instance Inventory: $REGION ---"
echo "--- RDS DB Instance Inventory: $REGION ---"

log "Fetching RDS instance data using describe-db-instances..."
RDS_DATA=$(aws rds describe-db-instances \
    --region "$REGION" \
    --query 'DBInstances[].{
        ID:DBInstanceIdentifier,
        Engine:Engine,
        Size:DBInstanceClass,
        Status:DBInstanceStatus,
        MultiAZ:MultiAz,
        Endpoint:Endpoint.Address
    }' \
    --output json 2>/dev/null \
    | $JQ_PATH -c '.[]')

if [ $? -ne 0 ]; then
    log "FATAL ERROR: AWS CLI command failed. Check your credentials and region name."
    echo "🚨 ERROR: AWS CLI command failed. Check your credentials and region name."
    exit 1
fi

if [ -z "$RDS_DATA" ]; then
    log "SUCCESS: No RDS DB instances found in this region."
    echo "✅ No RDS DB instances found in this region."
    echo "------------------------------------------------------------------------------------------------"
else
    INSTANCE_COUNT=$(echo "$RDS_DATA" | wc -l | tr -d '[:space:]')
    log "INFO: Found $INSTANCE_COUNT RDS Instance(s)."
    echo "Found RDS Instances:"
    echo "------------------------------------------------------------------------------------------------"
    printf "%-25s | %-15s | %-12s | %-10s | %-7s | %s\n" "Identifier" "Engine" "Size" "Status" "Multi-AZ" "Endpoint Address"
    echo "------------------------------------------------------------------------------------------------"

    echo "$RDS_DATA" | while IFS= read -r DB_INFO; do
        ID=$(echo "$DB_INFO" | $JQ_PATH -r '.ID // "N/A"')
        ENGINE=$(echo "$DB_INFO" | $JQ_PATH -r '.Engine // "N/A"')
        SIZE=$(echo "$DB_INFO" | $JQ_PATH -r '.Size // "N/A"')
        STATUS=$(echo "$DB_INFO" | $JQ_PATH -r '.Status // "N/A"')
        MULTIAZ=$(echo "$DB_INFO" | $JQ_PATH -r '.MultiAZ')
        ENDPOINT=$(echo "$DB_INFO" | $JQ_PATH -r '.Endpoint // "N/A"')

        if [ "$MULTIAZ" = "true" ]; then
            MULTIAZ_FMT="Yes"
        else
            MULTIAZ_FMT="No"
        fi

        log "INVENTORY: ID: $ID | Engine: $ENGINE | Size: $SIZE | Status: $STATUS | Multi-AZ: $MULTIAZ_FMT"

        printf "%-25s | %-15s | %-12s | %-10s | %-7s | %s\n" \
            "${ID:0:25}" "${ENGINE:0:15}" "${SIZE:0:12}" "${STATUS:0:10}" "$MULTIAZ_FMT" "${ENDPOINT:0:40}..."
    done
    echo "------------------------------------------------------------------------------------------------"
fi

log "SCRIPT FINISHED."
log "--------------------------------------------------------------------------------"
exit 0
