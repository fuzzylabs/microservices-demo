#!/bin/bash

# ============================================================
# Create CloudWatch Metric Filters for ERROR Logs
# ============================================================
# One filter per service: severity=error + pod_name contains service
# ============================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# CONFIGURATION
# ============================================================
CLUSTER_NAME="no-loafers-for-you"
AWS_REGION="eu-west-2"
LOG_GROUP="/aws/containerinsights/${CLUSTER_NAME}/application"
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
echo -e "${BLUE} Creating CloudWatch Metric Filters${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# ============================================================
# Create metric filter for each service
# Pattern: severity=error AND pod_name contains service name
# ============================================================

for SERVICE in "${SERVICES[@]}"; do
    FILTER_NAME="${SERVICE}-errors"
    METRIC_NAME="${SERVICE}ErrorCount"
    FILTER_PATTERN="{ ($.log_processed.severity = "error")  && ($.kubernetes.pod_name = \"*${SERVICE}*\") }"
    
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP" \
        --filter-name "$FILTER_NAME" \
        --filter-pattern "$FILTER_PATTERN" \
        --metric-transformations \
            metricName=$METRIC_NAME,metricNamespace=$METRIC_NAMESPACE,metricValue=1 \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}✓ ${FILTER_NAME} → ${METRIC_NAME}${NC}"
done

echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
echo "Metrics created:"
for SERVICE in "${SERVICES[@]}"; do
    echo "  • ${SERVICE}ErrorCount"
done
