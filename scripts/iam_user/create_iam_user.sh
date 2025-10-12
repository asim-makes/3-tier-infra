#!/bin/bash

# Configuration
REGION="us-east-1"
USERNAME="3-tier-infra-user"
POLICY_NAME="3-tier-deployment-policy"
POLICY_FILE="scripts/iam_user_policy.json"
CLI_PROFILE="$USERNAME-profile"
CREDENTIALS_FILE="creds/$USERNAME-credentials.json"

# Logging Setup
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/iam-user-$(date +%Y%m%d_%H%M%S).log"
ACCOUNT_ID=""

mkdir -p "$LOG_DIR"

log()
{
    local log_level="$1"
    local log_message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$log_level] $log_message" | tee -a "$LOG_FILE" >&2
}

# Function to get the AWS Account ID
get_account_id()
{
    log "INFO" "Retrieving AWS Account ID..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>>"$LOG_FILE")
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to retrieve AWS Account ID. Check your AWS CLI configuration."
        exit 1
    fi
    log "INFO" "AWS Account ID: $ACCOUNT_ID"
}

create_or_get_policy()
{
    local policy_name="$1"
    local policy_arn=""

    log "INFO" "Checking if policy '$policy_name' already exists..."

    policy_arn=$(aws iam list-policies --scope Local \
        --query "Policies[?PolicyName=='$policy_name'].Arn" \
        --output text --region "$REGION" 2>/dev/null)

    if [ -n "$policy_arn" ]; then
        log "SUCCESS" "Policy '$policy_name' already exists. ARN: $policy_arn"
        echo "$policy_arn"
        return 0
    else
        log "WARN" "Policy '$policy_name' not found. Creating new policy..."

        if [ ! -f "$POLICY_FILE" ]; then
            log "ERROR" "Policy file '$POLICY_FILE' not found. Cannot create policy."
            return 1
        fi

        create_output=$(aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document file://"$POLICY_FILE" \
            --region "$REGION" 2>>"$LOG_FILE")

        if [ $? -eq 0 ]; then
            policy_arn=$(echo "$create_output" | jq -r '.Policy.Arn')
            log "SUCCESS" "Policy created successfully. ARN: $policy_arn"
            echo "$policy_arn"
            return 0
        else
            log "ERROR" "Failed to create policy '$policy_name'."
            return 1
        fi
    fi
}

create_user()
{
    local username="$1"
    log "INFO" "Checking if IAM user '$username' exists..."
    aws iam get-user --user-name "$username" --region "$REGION" &>/dev/null

    if [ $? -eq 0 ]; then
        log "WARN" "User '$username' already exists. Skipping user creation."
        return 0
    else
        log "INFO" "Creating user '$username'..."
        aws iam create-user --user-name "$username" --region "$REGION"
        if [ $? -eq 0 ]; then
            log "SUCCESS" "User '$username' created successfully."
            return 0
        else
            log "ERROR" "Failed to create user '$username'."
            return 1
        fi
    fi
}

create_access_key_and_profile() {
    local username="$1"
    local profile_name="$2"
    local region="$3"

    log "INFO" "Creating new access key for user '$username'..."
    
    key_output=$(aws iam create-access-key \
        --user-name "$username" \
        --region "$region" \
        --output json 2>> "$LOG_FILE")
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create access key for user '$username'. Check key limit."
        return 1
    fi

    ACCESS_KEY_ID=$(echo "$key_output" | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$key_output" | jq -r '.AccessKey.SecretAccessKey')

    log "INFO" "Storing credentials in local AWS CLI profile '$profile_name'..."
    aws configure set aws_access_key_id "$ACCESS_KEY_ID" --profile "$profile_name"
    aws configure set aws_secret_access_key "$SECRET_ACCESS_KEY" --profile "$profile_name"
    aws configure set region "$region" --profile "$profile_name"
    aws configure set output json --profile "$profile_name"

    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to configure AWS CLI profile '$profile_name'."
        return 1
    fi

    log "SUCCESS" "Credentials successfully stored in local CLI profile: '$profile_name'"

    log "INFO" "Saving raw credentials to file: $CREDENTIALS_FILE"
    
    jq -n \
        --arg user "$username" \
        --arg access_key "$ACCESS_KEY_ID" \
        --arg secret_key "$SECRET_ACCESS_KEY" \
        --arg region "$region" \
        --arg profile "$profile_name" \
        '{
            "User": $user,
            "AWS_ACCESS_KEY_ID": $access_key,
            "AWS_SECRET_ACCESS_KEY": $secret_key,
            "Region": $region,
            "ProfileName": $profile
        }' > "$CREDENTIALS_FILE"
    
    # Set restrictive permissions on the file
    chmod 600 "$CREDENTIALS_FILE"
    
    log "SUCCESS" "Raw credentials saved to $CREDENTIALS_FILE. File permissions set to 600."

    unset ACCESS_KEY_ID
    unset SECRET_ACCESS_KEY
    return 0
}

# Start the script

log "--------------------------------------------------------"
log "STARTING SCRIPT: AWS IAM User Setup for $USERNAME"
log "--------------------------------------------------------"

# Prerequisite: Check for AWS CLI and jq (for JSON parsing)
if ! command -v aws &>/dev/null || ! command -v jq &>/dev/null; then
    log "ERROR" "Prerequisites missing: AWS CLI and 'jq' are required."
    exit 1
fi

get_account_id

if ! create_user "$USERNAME"; then
    log "FATAL" "User creation failed. Exiting."
    exit 1
fi

POLICY_ARN=$(create_or_get_policy "$POLICY_NAME")

if [ -z "$POLICY_ARN" ]; then
    log "FATAL" "Could not resolve or create policy ARN. Exiting."
    exit 1
fi

log "INFO" "Attempting to attach policy to user '$USERNAME'..."

is_attached=$(aws iam list-attached-user-policies \
    --user-name "$USERNAME" \
    --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyName" \
    --output text --region "$REGION" 2>/dev/null)

if [ -n "$is_attached" ]; then
    log "SUCCESS" "Policy '$POLICY_NAME' is already attached to user '$USERNAME'."
else
    aws iam attach-user-policy \
        --user-name "$USERNAME" \
        --policy-arn "$POLICY_ARN" \
        --region "$REGION"

    if [ $? -eq 0 ]; then
        log "SUCCESS" "Policy '$POLICY_NAME' successfully attached to user '$USERNAME'."
    else
        log "ERROR" "Failed to attach policy '$POLICY_NAME' to user '$USERNAME'."
        exit 1
    fi
fi

if ! create_access_key_and_profile "$USERNAME" "$CLI_PROFILE" "$REGION"; then
    log "FATAL" "Access key or profile configuration failed. Exiting."
    exit 1
fi

log "--------------------------------------------------------"
log "SCRIPT COMPLETED."
log "--------------------------------------------------------"
