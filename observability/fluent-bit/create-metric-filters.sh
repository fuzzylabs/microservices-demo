#!/bin/bash

# ============================================================
# Create CloudWatch Metric Filters for ERROR Logs
# ============================================================
# This script creates metric filters to detect ERROR level logs
# from your microservices and creates CloudWatch metrics
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
CLUSTER_NAME="no-loafers-for-you"
AWS_REGION="eu-west-2"
LOG_GROUP="/aws/containerinsights/${CLUSTER_NAME}/application"
METRIC_NAMESPACE="Microservices/Errors"

# Services to monitor (these match your intentional errors)
SERVICES=(
    "checkoutservice"
    "currencyservice"
    "paymentservice"
    "shippingservice"
)

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE} Creating CloudWatch Metric Filters for ERROR Logs${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Configuration:"
echo "  Log Group:        $LOG_GROUP"
echo "  Metric Namespace: $METRIC_NAMESPACE"
echo "  Region:           $AWS_REGION"
echo ""

# ============================================================
# Create metric filter for ALL errors (severity: error)
# ============================================================
echo -e "${YELLOW}Creating metric filter for ALL application errors...${NC}"

aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "AllApplicationErrors" \
    --filter-pattern '{ $.severity = "error" }' \
    --metric-transformations \
        metricName=ErrorCount,metricNamespace=$METRIC_NAMESPACE,metricValue=1,defaultValue=0 \
    --region "$AWS_REGION"

echo -e "${GREEN}✓ Created: AllApplicationErrors${NC}"

# ============================================================
# Create metric filters for each service
# ============================================================
echo ""
echo -e "${YELLOW}Creating metric filters for individual services...${NC}"

for SERVICE in "${SERVICES[@]}"; do
    FILTER_NAME="${SERVICE}-errors"
    METRIC_NAME="${SERVICE}ErrorCount"
    
    # Filter pattern matches severity=error AND pod name contains service name
    FILTER_PATTERN="{ ($.severity = \"error\") && ($.kubernetes.pod_name = \"*${SERVICE}*\") }"
    
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP" \
        --filter-name "$FILTER_NAME" \
        --filter-pattern "$FILTER_PATTERN" \
        --metric-transformations \
            metricName=$METRIC_NAME,metricNamespace=$METRIC_NAMESPACE,metricValue=1,defaultValue=0 \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}✓ Created: ${FILTER_NAME} → ${METRIC_NAME}${NC}"
done

# ============================================================
# Create metric filter for specific error messages
# ============================================================
echo ""
echo -e "${YELLOW}Creating metric filters for specific error patterns...${NC}"

# Memory allocation error (checkout service)
aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "checkout-memory-error" \
    --filter-pattern '"Allocating 2 GB of memory"' \
    --metric-transformations \
        metricName=CheckoutMemoryError,metricNamespace=$METRIC_NAMESPACE,metricValue=1,defaultValue=0 \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Created: checkout-memory-error${NC}"

# Credit card validation error (payment service)
aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "payment-validation-error" \
    --filter-pattern '"Credit card validation failed"' \
    --metric-transformations \
        metricName=PaymentValidationError,metricNamespace=$METRIC_NAMESPACE,metricValue=1,defaultValue=0 \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Created: payment-validation-error${NC}"

# Currency conversion error (currency service)
aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "currency-conversion-error" \
    --filter-pattern '"Currency conversion resulted in zero"' \
    --metric-transformations \
        metricName=CurrencyConversionError,metricNamespace=$METRIC_NAMESPACE,metricValue=1,defaultValue=0 \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Created: currency-conversion-error${NC}"

# Shipping quote error (shipping service)
aws logs put-metric-filter \
    --log-group-name "$LOG_GROUP" \
    --filter-name "shipping-quote-error" \
    --filter-pattern '"Shipping quote calculated with zero items"' \
    --metric-transformations \
        metricName=ShippingQuoteError,metricNamespace=$METRIC_NAMESPACE,metricValue=1,defaultValue=0 \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Created: shipping-quote-error${NC}"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} ✅ All metric filters created successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "Metrics are available in CloudWatch under namespace: ${METRIC_NAMESPACE}"
echo ""
echo "Created metrics:"
echo "  • ErrorCount              - All errors across all services"
echo "  • checkoutserviceErrorCount"
echo "  • currencyserviceErrorCount"
echo "  • paymentserviceErrorCount"
echo "  • shippingserviceErrorCount"
echo "  • CheckoutMemoryError     - T-shirt memory allocation"
echo "  • PaymentValidationError  - Credit card rejected"
echo "  • CurrencyConversionError - Zero conversion fallback"
echo "  • ShippingQuoteError      - Hardcoded zero quote"
echo ""
echo "To view metrics in AWS Console:"
echo "  CloudWatch → Metrics → All metrics → ${METRIC_NAMESPACE}"
echo ""
echo "To create an alarm (example):"
echo "  aws cloudwatch put-metric-alarm \\"
echo "    --alarm-name 'High-Error-Rate' \\"
echo "    --metric-name ErrorCount \\"
echo "    --namespace ${METRIC_NAMESPACE} \\"
echo "    --statistic Sum \\"
echo "    --period 300 \\"
echo "    --threshold 10 \\"
echo "    --comparison-operator GreaterThanThreshold \\"
echo "    --evaluation-periods 1 \\"
echo "    --region ${AWS_REGION}"
