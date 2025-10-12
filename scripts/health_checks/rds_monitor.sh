# This script is used inside EC2 to check if EC2 can connect with RDS or not.

#!/bin/bash
RDS_ENDPOINT="<your-rds-endpoint>"
RDS_PORT="5432"
LOG_FILE="rds_connectivity_log.txt"

echo "Starting continuous connectivity check to $RDS_ENDPOINT on port $RDS_PORT..." > $LOG_FILE

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    RESOLVED_IP=$(dig +short $RDS_ENDPOINT | head -n 1)

    nc -zw1 $RDS_ENDPOINT $RDS_PORT 

    if [ $? -eq 0 ]; then
        STATUS="Connected"
    else
        STATUS="Failed"
    fi

    echo "$TIMESTAMP | IP Resolved: $RESOLVED_IP | Status: $STATUS" | tee -a $LOG_FILE
    sleep 1
done