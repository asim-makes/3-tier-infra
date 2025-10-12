#!/bin/bash

REGION=""
JQ_PATH=$(which jq)

LOG_DIR="logs"
LOG_FILE="$LOG_DIR/alb-health-check-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() {
    local log_message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp $log_message" | tee -a "$LOG_FILE"
}

usage() {
    # Prints usage information and exits with status 1
    echo "Usage: $0 --region <AWS_REGION>"
    echo ""
    echo "Checks the health of all targets registered with ALB/NLB Target Groups."
    echo ""
    echo "  --region <REGION>           The AWS region to check (e.g., us-east-1). (Required)"
    echo "  --help                      Display this help message."
    exit 1
}

log "--------------------------------------------------------------------------------"
log "STARTING SCRIPT: ALB Target Health Check"

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
            log "ERROR: Unknown parameter \"$PARAM\""
            usage
            ;;
    esac
    shift
done

if [ -z "$REGION" ]; then
    log "ERROR: --region is required."
    usage
fi

log "Target Region: $REGION"

if [ -z "$JQ_PATH" ]; then
    log "FATAL ERROR: 'jq' is not installed."
    echo "ERROR: 'jq' is not installed. Please install it to run this script."
    exit 1
fi

log "INFO: 'jq' found at: $JQ_PATH"

log "--- ALB Target Health Check: $REGION ---"
echo "--- ALB Target Health Check: $REGION ---"
echo "Fetching all Target Groups..."

TARGET_GROUPS=$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --query 'TargetGroups[].{ARN:TargetGroupArn, Name:TargetGroupName}' \
    --output json 2>/dev/null \
    | $JQ_PATH -c '.[]'
)

if [ $? -ne 0 ]; then
    log "FATAL ERROR: AWS CLI command failed when fetching Target Groups. Check your credentials and region name."
    echo "🚨 ERROR: AWS CLI command failed when fetching Target Groups. Check your credentials and region name."
    exit 1
fi

if [ -z "$TARGET_GROUPS" ]; then
    log "INFO: No Target Groups found in this region."
    echo "✅ No Target Groups found in this region."
    exit 0
fi

UNHEALTHY_COUNT=0
log "INFO: Found $(echo "$TARGET_GROUPS" | wc -l) Target Group(s). Starting health check iteration."

echo "------------------------------------------------------------------------------------------------------------------------"
printf "%-30s | %-12s | %-11s | %-15s | %s\n" "Target Group Name" "Target ID" "Port" "Health Status" "Description/Reason"
echo "------------------------------------------------------------------------------------------------------------------------"

echo "$TARGET_GROUPS" | while IFS= read -r TG_INFO; do
    TG_ARN=$(echo "$TG_INFO" | $JQ_PATH -r '.ARN')
    TG_NAME=$(echo "$TG_INFO" | $JQ_PATH -r '.Name')

    log "PROCESSING: Target Group: $TG_NAME ($TG_ARN)"

    TARGET_HEALTH=$(aws elbv2 describe-target-health \
        --region "$REGION" \
        --target-group-arn "$TG_ARN" \
        --query 'TargetHealthDescriptions[].{
            ID:Target.Id,
            Port:Target.Port,
            State:TargetHealth.State,
            Reason:TargetHealth.Reason,
            Description:TargetHealth.Description
        }' \
        --output json 2>/dev/null \
        | $JQ_PATH -c '.[]'
    )

    if [ -z "$TARGET_HEALTH" ]; then
        printf "%-30s | %-12s | %-11s | %-15s | %s\n" "$TG_NAME" "N/A" "N/A" "N/A" "No targets found in group."
        log "WARNING: $TG_NAME has no registered targets."
    else
        echo "$TARGET_HEALTH" | while IFS= read -r HEALTH_INFO; do
            TARGET_ID=$(echo "$HEALTH_INFO" | $JQ_PATH -r '.ID // "N/A"')
            PORT=$(echo "$HEALTH_INFO" | $JQ_PATH -r '.Port // "N/A"')
            STATE=$(echo "$HEALTH_INFO" | $JQ_PATH -r '.State // "N/A"')
            REASON=$(echo "$HEALTH_INFO" | $JQ_PATH -r '.Reason // "N/A"')
            DESC=$(echo "$HEALTH_INFO" | $JQ_PATH -r '.Description // "N/A"')

            LOG_LINE="TARGET $TARGET_ID:$PORT | State: $STATE | TG: $TG_NAME"

            if [[ "$STATE" != "healthy" ]]; then
                REASON_OUTPUT="$REASON - $DESC"
                log "ALERT: UNHEALTHY TARGET $LOG_LINE. Reason: $REASON_OUTPUT"
            else
                REASON_OUTPUT="OK"
                log "STATUS: HEALTHY TARGET $LOG_LINE."
            fi

            printf "%-30s | %-12s | %-11s | %-15s | %s\n" \
                "${TG_NAME:0:30}" "${TARGET_ID:0:12}" "$PORT" "$STATE" "${REASON_OUTPUT}"
        done
    fi
done

echo "------------------------------------------------------------------------------------------------------------------------"

log "SUMMARY: Target health check complete. Review logs for specific unhealthy targets."
echo "✅ SUMMARY: All targets reported in the inventory have been checked."

log "SCRIPT FINISHED."
log "--------------------------------------------------------------------------------"
exit 0
