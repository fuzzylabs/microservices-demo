# 🚀 Deploying the Application to EKS

## Prerequisites
- AWS CLI installed and configured
- Docker installed and running
- kubectl configured with cluster access
- Helm 3.x installed

## ECR Configuration
| Setting | Value |
|---------|-------|
| **Registry** | `554043692091.dkr.ecr.eu-west-2.amazonaws.com` |
| **Namespace** | `sre-agent` |
| **Region** | `eu-west-2` |

---

## 1. Login to AWS
Make sure you're authenticated with your AWS account.

## 2. Set up your kubeconfig
Run the following command to configure access to your EKS cluster:
```bash
aws eks --region eu-west-2 update-kubeconfig --name <cluster-name>
```

## 3. Deploy the application
Apply the Kubernetes manifests to start the deployment:
```bash
helm upgrade --install appdeployment ./release/app-deployment \
  --set image.repository_uri=554043692091.dkr.ecr.eu-west-2.amazonaws.com/sre-agent
```

## 4. Get the load balancer address
Once the deployment is complete, retrieve the external IP:
```bash
kubectl get svc frontend-external
```

---

## 🔄 Updating Services (Quick Deploy)

If you've made code changes to any services, use the provided deploy script:

```bash
./deploy-updated-services.sh
```

This script will:
1. Login to AWS ECR
2. Build Docker images for modified services
3. Push images to ECR
4. Restart Kubernetes deployments
5. Wait for rollouts to complete

---

## 🔧 Manual Image Build & Push

If you need to manually rebuild a single service:

### Step 1: Login to ECR
```bash
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin 554043692091.dkr.ecr.eu-west-2.amazonaws.com
```

### Step 2: Build the image
```bash
cd src/<service-name>
docker build -t <service-name>:latest .
```

### Step 3: Tag and push
```bash
docker tag <service-name>:latest 554043692091.dkr.ecr.eu-west-2.amazonaws.com/sre-agent/<service-name>:latest
docker push 554043692091.dkr.ecr.eu-west-2.amazonaws.com/sre-agent/<service-name>:latest
```

### Step 4: Restart the deployment
```bash
kubectl rollout restart deployment <service-name>
kubectl rollout status deployment <service-name>
```

---

## 📦 Available ECR Repositories

| Service | ECR Repository |
|---------|---------------|
| cartservice | `sre-agent/cartservice` |
| checkoutservice | `sre-agent/checkoutservice` |
| currencyservice | `sre-agent/currencyservice` |
| frontend | `sre-agent/frontend` |
| paymentservice | `sre-agent/paymentservice` |
| productcatalogservice | `sre-agent/productcatalogservice` |
| shippingservice | `sre-agent/shippingservice` |

---

## 🐛 Troubleshooting

### Check pod status
```bash
kubectl get pods
```

### View logs for a specific service
```bash
kubectl logs -l app=<service-name> --tail=100
```

### View ERROR level logs only
```bash
kubectl logs -l app=<service-name> | grep -i error
```

### Describe a failing pod
```bash
kubectl describe pod <pod-name>
```

### Force delete and recreate a deployment
```bash
kubectl delete deployment <service-name>
helm upgrade --install appdeployment ./release/app-deployment \
  --set image.repository_uri=554043692091.dkr.ecr.eu-west-2.amazonaws.com/sre-agent
```