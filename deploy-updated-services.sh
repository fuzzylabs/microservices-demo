#!/bin/bash

# ============================================================
# Deploy Updated Services Script
# ============================================================
# This script rebuilds, pushes, and deploys the following services
# that were modified with error logging changes:
#   - checkoutservice
#   - currencyservice  
#   - paymentservice
#   - shippingservice
# ============================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================================
ECR_REGISTRY="554043692091.dkr.ecr.eu-west-2.amazonaws.com"
ECR_NAMESPACE="sre-agent"
AWS_REGION="eu-west-2"
IMAGE_TAG="latest"

# ============================================================
# Validate configuration
# ============================================================
validate_config() {
    if [ -z "$ECR_REGISTRY" ]; then
        echo -e "${RED}Error: ECR_REGISTRY is not set${NC}"
        echo "Please set ECR_REGISTRY in the script or as an environment variable"
        echo "Example: export ECR_REGISTRY=123456789.dkr.ecr.eu-west-2.amazonaws.com"
        exit 1
    fi
    
    if [ -z "$ECR_NAMESPACE" ]; then
        echo -e "${RED}Error: ECR_NAMESPACE is not set${NC}"
        echo "Please set ECR_NAMESPACE in the script or as an environment variable"
        echo "Example: export ECR_NAMESPACE=my-ecr-namespace"
        exit 1
    fi
}

# ============================================================
# Services to update
# ============================================================
SERVICES=(
    "checkoutservice"
    "currencyservice"
    "paymentservice"
    "shippingservice"
)

# Script directory (for relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Helper functions
# ============================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================
# Step 1: Login to AWS ECR
# ============================================================
login_to_ecr() {
    log_info "Logging in to AWS ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    log_success "Successfully logged in to ECR"
}

# ============================================================
# Step 2: Build, tag, and push Docker images
# ============================================================
build_and_push_service() {
    local service=$1
    local service_dir="${SCRIPT_DIR}/src/${service}"
    local full_image_uri="${ECR_REGISTRY}/${ECR_NAMESPACE}/${service}:${IMAGE_TAG}"
    
    log_info "Building ${service}..."
    
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory not found: $service_dir"
        return 1
    fi
    
    # Build the Docker image for AMD64 (EKS runs on x86_64)
    docker build --platform linux/amd64 -t "${service}:${IMAGE_TAG}" "$service_dir"
    log_success "Built ${service}:${IMAGE_TAG} (linux/amd64)"
    
    # Tag for ECR
    docker tag "${service}:${IMAGE_TAG}" "$full_image_uri"
    log_success "Tagged as ${full_image_uri}"
    
    # Push to ECR
    log_info "Pushing ${service} to ECR..."
    docker push "$full_image_uri"
    log_success "Pushed ${full_image_uri}"
}

# ============================================================
# Step 3: Restart deployments to pick up new images
# ============================================================
restart_deployment() {
    local service=$1
    log_info "Restarting deployment for ${service}..."
    kubectl rollout restart deployment "$service"
    log_success "Triggered rollout restart for ${service}"
}

# ============================================================
# Step 4: Wait for rollouts to complete
# ============================================================
wait_for_rollout() {
    local service=$1
    log_info "Waiting for ${service} rollout to complete..."
    kubectl rollout status deployment "$service" --timeout=300s
    log_success "${service} rollout completed"
}

# ============================================================
# Main execution
# ============================================================
main() {
    echo ""
    echo "============================================================"
    echo " Deploy Updated Services"
    echo "============================================================"
    echo ""
    echo "Services to update:"
    for svc in "${SERVICES[@]}"; do
        echo "  - $svc"
    done
    echo ""
    
    # Allow environment variable overrides
    ECR_REGISTRY="${ECR_REGISTRY:-$ECR_REGISTRY}"
    ECR_NAMESPACE="${ECR_NAMESPACE:-$ECR_NAMESPACE}"
    AWS_REGION="${AWS_REGION:-$AWS_REGION}"
    IMAGE_TAG="${IMAGE_TAG:-$IMAGE_TAG}"
    
    validate_config
    
    echo "Configuration:"
    echo "  ECR Registry:  $ECR_REGISTRY"
    echo "  ECR Namespace: $ECR_NAMESPACE"
    echo "  AWS Region:    $AWS_REGION"
    echo "  Image Tag:     $IMAGE_TAG"
    echo ""
    
    read -p "Continue with deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled"
        exit 0
    fi
    
    echo ""
    echo "============================================================"
    echo " Step 1: Login to AWS ECR"
    echo "============================================================"
    login_to_ecr
    
    echo ""
    echo "============================================================"
    echo " Step 2: Build and Push Docker Images"
    echo "============================================================"
    for service in "${SERVICES[@]}"; do
        echo ""
        echo "------------------------------------------------------------"
        echo " Processing: $service"
        echo "------------------------------------------------------------"
        build_and_push_service "$service"
    done
    
    echo ""
    echo "============================================================"
    echo " Step 3: Restart Kubernetes Deployments"
    echo "============================================================"
    for service in "${SERVICES[@]}"; do
        restart_deployment "$service"
    done
    
    echo ""
    echo "============================================================"
    echo " Step 4: Wait for Rollouts to Complete"
    echo "============================================================"
    for service in "${SERVICES[@]}"; do
        wait_for_rollout "$service"
    done
    
    echo ""
    echo "============================================================"
    echo -e " ${GREEN}✅ All services deployed successfully!${NC}"
    echo "============================================================"
    echo ""
    echo "To verify the deployments, run:"
    echo "  kubectl get pods"
    echo ""
    echo "To check logs for errors, run:"
    echo "  kubectl logs -l app=<service-name> --tail=100"
    echo ""
}

# Run main function
main "$@"
