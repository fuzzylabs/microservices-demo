# Fluent Bit Setup for CloudWatch Logs

This setup follows the [official AWS documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html).

## Prerequisites

### 1. IAM Permissions
Your EKS node IAM role needs the `CloudWatchAgentServerPolicy` attached.

**Option A: Attach AWS Managed Policy (Recommended)**
```bash
# Get your node role name
NODE_ROLE=$(aws eks describe-nodegroup \
  --cluster-name YOUR_CLUSTER_NAME \
  --nodegroup-name YOUR_NODEGROUP_NAME \
  --query 'nodegroup.nodeRole' --output text | cut -d'/' -f2)


# Attach the policy
aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

## Quick Deploy

1. **Set your cluster name** in the deploy script:
   ```bash
   vi deploy-fluent-bit.sh
   # Update: CLUSTER_NAME="your-cluster-name"
   ```

2. **Run the deploy script:**
   ```bash
   ./deploy-fluent-bit.sh
   ```

   Or pass cluster name as environment variable:
   ```bash
   CLUSTER_NAME=my-cluster ./deploy-fluent-bit.sh
   ```

## What Gets Created

| Resource | Description |
|----------|-------------|
| Namespace | `amazon-cloudwatch` |
| ConfigMap | `fluent-bit-cluster-info` - cluster config |
| ServiceAccount | `fluent-bit` |
| ClusterRole | `fluent-bit-role` - read pods/logs |
| DaemonSet | `fluent-bit` - runs on every node |

## CloudWatch Log Groups

After deployment, these log groups are created automatically:

| Log Group | Content |
|-----------|---------|
| `/aws/containerinsights/<cluster>/application` | Container logs from `/var/log/containers` |
| `/aws/containerinsights/<cluster>/host` | Host logs (dmesg, secure, messages) |
| `/aws/containerinsights/<cluster>/dataplane` | Kubernetes dataplane logs (kubelet, kube-proxy) |

## Verify Deployment

```bash
# Check pods are running
kubectl get pods -n amazon-cloudwatch

# View Fluent Bit logs
kubectl logs -n amazon-cloudwatch -l k8s-app=fluent-bit --tail=50
```

## Alarm Routing to ECS Task

After creating metric filters and alarms, configure EventBridge to start an ECS task for each service alarm:

```bash
cd /Users/oscar/Desktop/work/microservices-demo/observability/fluent-bit

AWS_PROFILE=default \
AWS_REGION=eu-west-2 \
ECS_CLUSTER=sre-agent \
TASK_DEFINITION=sre-agent \
SUBNET_IDS=private-subnet-id \
SECURITY_GROUP_IDS=sg-aaa \
LOG_GROUP=/aws/containerinsights/no-loafers-for-you/application \
SERVICES=cartservice,checkoutservice,currencyservice,paymentservice,shippingservice \
./setup-eventbridge.sh
```

What this does:
- Creates/updates EventBridge rules `Trigger-Agent-<service>` for `*-error` CloudWatch alarms.
- Sets each rule target to ECS `RunTask` (not API destination).
- Passes service context to the container as overrides:
  - `SERVICE_NAME`
  - `LOG_GROUP`
  - `TIME_RANGE_MINUTES`

## Finding ERROR Logs in CloudWatch

Use CloudWatch Logs Insights to query for errors:

```sql
fields @timestamp, @message, kubernetes.pod_name, kubernetes.namespace_name
| filter @message like /(?i)error/
| sort @timestamp desc
| limit 100
```

Or filter by severity (for JSON-structured logs):

```sql
fields @timestamp, @message, kubernetes.pod_name
| filter severity = "error"
| sort @timestamp desc
| limit 100
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n amazon-cloudwatch -l k8s-app=fluent-bit
```

### IAM permission errors
Check if CloudWatchAgentServerPolicy is attached to your node role.

### No logs appearing
1. Verify Fluent Bit pods are running
2. Check Fluent Bit logs for errors
3. Ensure correct region is configured

## Uninstall

```bash
kubectl delete -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml

kubectl delete configmap fluent-bit-cluster-info -n amazon-cloudwatch
kubectl delete namespace amazon-cloudwatch
```
