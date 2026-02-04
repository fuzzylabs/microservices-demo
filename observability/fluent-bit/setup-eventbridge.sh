#!/bin/bash

# ============================================================
# Setup EventBridge Rules (One per Service)
# ============================================================
# This handles the mapping of "servicename-error" alarm to
# "servicename" payload without changing alarm names.
# ============================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# CONFIGURATION
# ============================================================
AWS_REGION="eu-west-2"
WEBHOOK_URL="https://unscolding-inexpertly-arya.ngrok-free.dev/diagnose"
LOG_GROUP="/aws/containerinsights/no-loafers-for-you/application"
CONNECTION_NAME="AgentWebhookConnection"
DESTINATION_NAME="AgentDiagnoseDestination"

SERVICES=(
    "cartservice"
    "checkoutservice"
    "currencyservice"
    "paymentservice"
    "shippingservice"
)

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE} Setting up EventBridge Mappings per Service${NC}"
echo -e "${BLUE}============================================================${NC}"

# 1. Ensure Connection and Destination exist
echo "Ensuring Connection and API Destination exist..."
aws events create-connection \
    --name "$CONNECTION_NAME" \
    --auth-parameters '{"ApiKeyAuthParameters": {"ApiKeyName": "x-unused", "ApiKeyValue": "unused"}}' \
    --authorization-type "API_KEY" \
    --region "$AWS_REGION" 2>/dev/null || true

CONNECTION_ARN=$(aws events describe-connection --name "$CONNECTION_NAME" --region "$AWS_REGION" --query 'ConnectionArn' --output text)

DEST_ARN=$(aws events create-api-destination \
    --name "$DESTINATION_NAME" \
    --connection-arn "$CONNECTION_ARN" \
    --invocation-endpoint "$WEBHOOK_URL" \
    --http-method "POST" \
    --region "$AWS_REGION" \
    --query 'ApiDestinationArn' \
    --output text 2>/dev/null || \
aws events describe-api-destination --name "$DESTINATION_NAME" --region "$AWS_REGION" --query 'ApiDestinationArn' --output text)

# 2. Ensure IAM Role exists
ROLE_NAME="EventBridgeApiDestRole"
TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY"
fi
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "AllowInvokeApiDest" --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{\"Effect\": \"Allow\", \"Action\": \"events:InvokeApiDestination\", \"Resource\": \"$DEST_ARN\"}]
}"
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

# 3. Create a Rule and Target for EACH service
for SERVICE in "${SERVICES[@]}"; do
    RULE_NAME="Trigger-Agent-$SERVICE"
    ALARM_NAME="${SERVICE}-error"
    
    echo "Processing $SERVICE (Mapping $ALARM_NAME -> $SERVICE)..."

    # Create Rule for specific alarm
    aws events put-rule \
        --name "$RULE_NAME" \
        --event-pattern "{
            \"source\": [\"aws.cloudwatch\"],
            \"detail-type\": [\"CloudWatch Alarm State Change\"],
            \"detail\": {
                \"state\": { \"value\": [\"ALARM\"] },
                \"alarmName\": [\"$ALARM_NAME\"]
            }
        }" \
        --state ENABLED \
        --region "$AWS_REGION"

    # Create Target with STATIC payload for this service
    PAYLOAD="{\"log_group\":\"$LOG_GROUP\",\"service_name\":\"$SERVICE\",\"time_range_minutes\":15}"
    
    aws events put-targets \
        --rule "$RULE_NAME" \
        --targets "[
            {
                \"Id\": \"Target-$SERVICE\",
                \"Arn\": \"$DEST_ARN\",
                \"RoleArn\": \"$ROLE_ARN\",
                \"Input\": \"$(echo $PAYLOAD | sed 's/"/\\"/g')\"
            }
        ]" \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}  ✓ Rule created: $RULE_NAME${NC}"
done

echo ""
echo -e "${GREEN}✅ All mappings created!${NC}"
echo "Alarm 'currencyservice-error' will now send 'currencyservice' to agent."
echo ""
