#!/bin/bash

REGION=""
JQ_PATH=$(which jq)

LOG_DIR="logs"
LOG_FILE="$LOG_DIR/ec2-health-check-$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() {
    local log_message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp $log_message" | tee -a "$LOG_FILE"
}

usage() {
    # Prints usage information and exits with status 1
    echo "Usage: $0 --region <AWS_REGION> [--az <AVAILABILITY_ZONE>]"
    echo ""
    echo "Checks EC2 instance health (System and Instance Status) and reports unhealthy instances."
    echo ""
    echo "  --region <REGION>           The AWS region to check (e.g., us-east-1). (Required)"
    echo "  --az <AVAILABILITY_ZONE>    Optional. Filter results by a specific Availability Zone (e.g., us-east-1a)."
    echo "  --help                      Display this help message."
    exit 1
}

log "--------------------------------------------------------------------------------"
log "STARTING SCRIPT: EC2 Instance Health Check"

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

log "Defining AWS filters for running, potentially impaired instances."
FILTERS="Name=instance-state-name,Values=running"
FILTERS="${FILTERS} Name=instance-status.status,Values=impaired,insufficient-data"
FILTERS="${FILTERS} Name=system-status.status,Values=impaired,insufficient-data"

if [ ! -z "$AZ_FILTER" ]; then
    log "INFO: Filtering by Availability Zone: $AZ_FILTER"
    echo "INFO: Filtering by Availability Zone: $AZ_FILTER"
    FILTERS="${FILTERS} Name=availability-zone,Values=$AZ_FILTER"
fi

log "--- Instance Health Check: $REGION $([ ! -z "$AZ_FILTER" ] && echo "($AZ_FILTER)") ---"
echo "--- Instance Health Check: $REGION $([ ! -z "$AZ_FILTER" ] && echo "($AZ_FILTER)") ---"

log "Fetching instance status reports..."
UNHEALTHY_INSTANCES=$(aws ec2 describe-instance-status \
    --region "$REGION" \
    --filters $(echo "$FILTERS" | tr ' ' '\n') \
    --query 'InstanceStatuses[].{ID:InstanceId, AZ:AvailabilityZone, State:InstanceState.Name, InstanceStatus:InstanceStatus.Status, SystemStatus:SystemStatus.Status, EventCode:Events[0].Code}' \
    --output json 2>/dev/null \
    | $JQ_PATH -c '.[]'
)

if [ $? -ne 0 ]; then
    log "FATAL ERROR: AWS CLI command failed. Check your credentials and region name."
    echo "🚨 ERROR: AWS CLI command failed. Check your credentials and region name."
    exit 1
fi

if [ -z "$UNHEALTHY_INSTANCES" ]; then
    log "SUCCESS: All monitored instances are reported as OK (or not applicable)."
    echo "✅ SUCCESS: All monitored instances are reported as OK (or not applicable)."
    echo "--------------------------------------------------------------------------"
else
    log "ALERT: Found $(echo "$UNHEALTHY_INSTANCES" | wc -l) UNHEALTHY instance(s)."
    echo "🚨 WARNING: Found UNHEALTHY instances:"
    echo "--------------------------------------------------------------------------"
    echo "Instance ID | AZ | State | Instance Status | System Status | Event"
    echo "--------------------------------------------------------------------------"

    echo "$UNHEALTHY_INSTANCES" | while IFS= read -r INSTANCE_INFO; do
        ID=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.ID')
        AZ=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.AZ')
        STATE=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.State')
        INST_STATUS=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.InstanceStatus')
        SYS_STATUS=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.SystemStatus')
        EVENT=$(echo "$INSTANCE_INFO" | $JQ_PATH -r '.EventCode')

        log "UNHEALTHY: ID: $ID | AZ: $AZ | Instance Status: $INST_STATUS | System Status: $SYS_STATUS | Event: $EVENT"
        printf "%-11s | %-11s | %-5s | %-15s | %-13s | %s\n" "$ID" "$AZ" "$STATE" "$INST_STATUS" "$SYS_STATUS" "$EVENT"
    done
    echo "--------------------------------------------------------------------------"
fi

log "SCRIPT FINISHED."
log "--------------------------------------------------------------------------------"
exit 0
