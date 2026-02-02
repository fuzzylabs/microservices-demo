#!/bin/bash

# ============================================================
# Create CloudWatch Alarms for ERROR Metrics
# ============================================================
# This script creates alarms that trigger when errors are detected
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# CONFIGURATION
# ============================================================
AWS_REGION="eu-west-2"
METRIC_NAMESPACE="Microservices/Errors"

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE} Creating CloudWatch Alarms for Error Metrics${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ============================================================
# Helper function to create alarm
# ============================================================
create_alarm() {
    local ALARM_NAME=$1
    local METRIC_NAME=$2
    local THRESHOLD=$3
    local DESCRIPTION=$4
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "$DESCRIPTION" \
        --metric-name "$METRIC_NAME" \
        --namespace "$METRIC_NAMESPACE" \
        --statistic Sum \
        --period 60 \
        --threshold "$THRESHOLD" \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}✓ Created alarm: ${ALARM_NAME}${NC}"
}

# ============================================================
# Create alarms for each error type
# ============================================================

echo -e "${YELLOW}Creating alarms for specific error types...${NC}"
echo ""

# Checkout memory error - triggers immediately (1 occurrence)
create_alarm \
    "Checkout-Memory-Error" \
    "CheckoutMemoryError" \
    0 \
    "CRITICAL: Checkout service is allocating 2GB memory (T-shirt bug triggered)"

# Payment validation error - triggers immediately
create_alarm \
    "Payment-Validation-Error" \
    "PaymentValidationError" \
    0 \
    "CRITICAL: Payment service is rejecting valid credit cards"

# Currency conversion error - triggers immediately
create_alarm \
    "Currency-Conversion-Error" \
    "CurrencyConversionError" \
    0 \
    "WARNING: Currency conversion resulted in zero, falling back to original currency"

# Shipping quote error - triggers on every request (will be noisy)
create_alarm \
    "Shipping-Quote-Error" \
    "ShippingQuoteError" \
    0 \
    "WARNING: Shipping quotes are calculated with zero items"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} ✅ All alarms created successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "View alarms in AWS Console:"
echo "  CloudWatch → Alarms → All alarms"
echo ""
echo "Created alarms:"
echo "  • Checkout-Memory-Error       (threshold: > 0)"
echo "  • Payment-Validation-Error    (threshold: > 0)"
echo "  • Currency-Conversion-Error   (threshold: > 0)"
echo "  • Shipping-Quote-Error        (threshold: > 0)"
