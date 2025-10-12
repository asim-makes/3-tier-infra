#!/bin/bash

usage() {
    echo "Usage: $0 <LOG_GROUP_NAME> [FILTER_PATTERN]"
    echo "Example 1 (All logs): $0 /ecs/myapp-log-group"
    echo "Example 2 (Filter for errors): $0 /ecs/myapp-log-group ERROR"
    exit 1
}

if [ -z "$1" ]; then
    echo "Error: Log Group Name is required."
    usage
fi

LOG_GROUP_NAME="$1"
FILTER_PATTERN="$2"
REGION="us-east-1"

START_TIME_MS=$(($(date +%s -d '1 hour ago') * 1000))

echo "Fetching log events from '$LOG_GROUP_NAME' since $(date -d @$((START_TIME_MS / 1000))) UTC..."

AWS_LOGS_COMMAND="aws logs filter-log-events \
    --log-group-name \"$LOG_GROUP_NAME\" \
    --start-time $START_TIME_MS \
    --region \"$REGION\" \
    --output text \
    --query 'events[*].[timestamp, message]'"

if [ -n "$FILTER_PATTERN" ]; then
    echo "Applying filter pattern: '$FILTER_PATTERN'"
    AWS_LOGS_COMMAND+=" --filter-pattern \"$FILTER_PATTERN\""
fi

eval "$AWS_LOGS_COMMAND" | while IFS=$'\t' read -r timestamp message; do
    HUMAN_TIME=$(date -d @$((timestamp / 1000)) +'%Y-%m-%d %H:%M:%S')

    echo "[$HUMAN_TIME] $message"
done

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "Error: Failed to fetch logs. Check Log Group Name and IAM permissions."
fi

