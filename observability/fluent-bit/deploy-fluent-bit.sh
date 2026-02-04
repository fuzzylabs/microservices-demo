#!/bin/bash

# ============================================================
# Deploy Fluent Bit to EKS for CloudWatch Logs
# ============================================================
# Based on Official AWS Documentation:
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================================
CLUSTER_NAME="no-loafers-for-you"           # Your EKS cluster name (REQUIRED)
AWS_REGION="eu-west-2"    # Your AWS region

# Optional settings
FLUENT_BIT_HTTP_PORT='2020'
FLUENT_BIT_READ_FROM_HEAD='Off'  # Set to 'On' to read all historical logs

# ============================================================
# Validate configuration
# ============================================================
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}Error: CLUSTER_NAME is not set${NC}"
    echo ""
    echo "Usage: Edit this script and set CLUSTER_NAME, or run:"
    echo "  CLUSTER_NAME=your-cluster-name ./deploy-fluent-bit.sh"
    exit 1
fi

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE} Deploying Fluent Bit for CloudWatch Logs (Official AWS)${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Configuration:"
echo "  Cluster:    $CLUSTER_NAME"
echo "  Region:     $AWS_REGION"
echo ""

# ============================================================
# Step 1: Create namespace
# ============================================================
echo -e "${YELLOW}Step 1: Creating amazon-cloudwatch namespace...${NC}"

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

echo -e "${GREEN}✓ Namespace created${NC}"

# ============================================================
# Step 2: Create ConfigMap with cluster info
# ============================================================
echo ""
echo -e "${YELLOW}Step 2: Creating cluster-info ConfigMap...${NC}"

# Calculate read settings
[[ ${FLUENT_BIT_READ_FROM_HEAD} = 'On' ]] && FluentBitReadFromTail='Off' || FluentBitReadFromTail='On'
[[ -z ${FLUENT_BIT_HTTP_PORT} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'

# Delete existing configmap if exists (to allow updates)
kubectl delete configmap fluent-bit-cluster-info -n amazon-cloudwatch 2>/dev/null || true

kubectl create configmap fluent-bit-cluster-info \
    --from-literal=cluster.name=${CLUSTER_NAME} \
    --from-literal=http.server=${FluentBitHttpServer} \
    --from-literal=http.port=${FLUENT_BIT_HTTP_PORT} \
    --from-literal=read.head=${FLUENT_BIT_READ_FROM_HEAD} \
    --from-literal=read.tail=${FluentBitReadFromTail} \
    --from-literal=logs.region=${AWS_REGION} \
    -n amazon-cloudwatch

echo -e "${GREEN}✓ ConfigMap created${NC}"

# ============================================================
# Step 3: Deploy Fluent Bit DaemonSet (Official AWS manifest)
# ============================================================
echo ""
echo -e "${YELLOW}Step 3: Deploying Fluent Bit DaemonSet...${NC}"

kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml


echo -e "${GREEN}✓ Fluent Bit DaemonSet deployed${NC}"

# ============================================================
# Step 4: Wait for rollout
# ============================================================
echo ""
echo -e "${YELLOW}Step 4: Waiting for Fluent Bit pods to be ready...${NC}"

kubectl rollout status daemonset/fluent-bit -n amazon-cloudwatch --timeout=120s

# ============================================================
# Step 5: Verify deployment
# ============================================================
echo ""
echo -e "${YELLOW}Step 5: Verifying deployment...${NC}"

echo ""
kubectl get pods -n amazon-cloudwatch

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} ✅ Fluent Bit deployed successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "CloudWatch Log Groups created:"
echo "  • /aws/containerinsights/${CLUSTER_NAME}/application"
echo "  • /aws/containerinsights/${CLUSTER_NAME}/host"
echo "  • /aws/containerinsights/${CLUSTER_NAME}/dataplane"
echo ""
echo "To verify logs in CloudWatch Console:"
echo "  1. Open CloudWatch → Log groups"
echo "  2. Look for /aws/containerinsights/${CLUSTER_NAME}/application"
echo "  3. Check log streams for recent events"
echo ""
echo "To check Fluent Bit pod logs:"
echo "  kubectl logs -n amazon-cloudwatch -l k8s-app=fluent-bit --tail=50"
echo ""
echo "If you see IAM permission errors, attach the CloudWatchAgentServerPolicy"
echo "to your EKS node IAM role. See: iam-policy.json"
