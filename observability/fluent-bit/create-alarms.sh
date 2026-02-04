#!/bin/bash

# ============================================================
# Create CloudWatch Alarms for ERROR Metrics
# ============================================================
# One alarm per service, triggers on any error
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
METRIC_NAMESPACE="Microservices/Errors"

# All services to monitor
SERVICES=(
    "cartservice"
    "checkoutservice"
    "currencyservice"
    "paymentservice"
    "shippingservice"
)

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE} Creating CloudWatch Alarms${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ============================================================
# Create alarm for each service
# ============================================================

for SERVICE in "${SERVICES[@]}"; do
    ALARM_NAME="${SERVICE}-error"
    METRIC_NAME="${SERVICE}ErrorCount"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Error detected in ${SERVICE}" \
        --metric-name "$METRIC_NAME" \
        --namespace "$METRIC_NAMESPACE" \
        --statistic Sum \
        --period 10 \
        --threshold 0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --datapoints-to-alarm 1 \
        --treat-missing-data notBreaching \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}✓ ${ALARM_NAME}${NC}"
done

echo ""
echo -e "${GREEN}Done! Alarms trigger on any error (10s) and stay ALARM for 30s of no errors.${NC}"
