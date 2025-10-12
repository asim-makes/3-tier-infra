#!/bin/bash

usage() {
    echo "Usage: $0 <INSTANCE_ID>"
    echo "Example: $0 i-0abcdef1234567890"
    exit 1
}

if [ -z "$1" ]; then
    echo "Error: Instance ID is required."
    usage
fi

INSTANCE_ID="$1"
REGION="us-east-1"

echo "Starting Session Manager session for instance: $INSTANCE_ID in $REGION..."

aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$REGION"

if [ $? -eq 0 ]; then
    echo "Session ended."
else
    echo "Error: Failed to start Session Manager session."
    echo "Ensure the instance is running, the SSM Agent is installed and running, and the IAM role has 'AmazonSSMManagedInstanceCore' permissions."
fi
