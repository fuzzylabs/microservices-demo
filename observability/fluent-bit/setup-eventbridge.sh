#!/usr/bin/env bash

# Configure EventBridge rules to run one-off ECS diagnosis tasks.
#
# Each service creates one rule:
#   Alarm "<service><ALARM_SUFFIX>" enters ALARM
#   -> EventBridge runs ECS task with container env overrides:
#      SERVICE_NAME, LOG_GROUP, TIME_RANGE_MINUTES

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
ROLE_NAME="${ROLE_NAME:-EventBridgeEcsRunTaskRole}"
RULE_PREFIX="${RULE_PREFIX:-sre-agent-diagnose}"
ALARM_SUFFIX="${ALARM_SUFFIX:--error}"

ECS_CLUSTER="${ECS_CLUSTER:-}"
TASK_DEFINITION="${TASK_DEFINITION:-}"
SUBNET_IDS="${SUBNET_IDS:-}"
SECURITY_GROUP_IDS="${SECURITY_GROUP_IDS:-}"
LOG_GROUP="${LOG_GROUP:-}"
SERVICES="${SERVICES:-}"

CONTAINER_NAME="${CONTAINER_NAME:-sre-agent}"
TIME_RANGE_MINUTES="${TIME_RANGE_MINUTES:-15}"
TASK_COUNT="${TASK_COUNT:-1}"
LAUNCH_TYPE="${LAUNCH_TYPE:-FARGATE}"
ASSIGN_PUBLIC_IP="${ASSIGN_PUBLIC_IP:-DISABLED}"

require_var() {
    local name="$1"
    local value="$2"
    if [[ -z "${value}" ]]; then
        echo -e "${RED}Error:${NC} ${name} is required."
        exit 1
    fi
}

csv_to_json_array() {
    local csv="$1"
    local result=""
    local item=""
    IFS=',' read -ra parts <<< "${csv}"
    for item in "${parts[@]}"; do
        item="$(echo "${item}" | xargs)"
        [[ -z "${item}" ]] && continue
        if [[ -n "${result}" ]]; then
            result+=","
        fi
        result+="\"${item}\""
    done
    echo "${result}"
}

resolve_cluster_arn() {
    local cluster_value="$1"
    local cluster_arn=""
    if [[ "${cluster_value}" == arn:aws:ecs:*:cluster/* ]]; then
        echo "${cluster_value}"
        return
    fi
    cluster_arn="$(aws ecs describe-clusters \
        --region "${AWS_REGION}" \
        --clusters "${cluster_value}" \
        --query 'clusters[0].clusterArn' \
        --output text)"
    if [[ -z "${cluster_arn}" || "${cluster_arn}" == "None" ]]; then
        echo -e "${RED}Error:${NC} Could not resolve cluster ARN for ECS_CLUSTER=${cluster_value}."
        exit 1
    fi
    echo "${cluster_arn}"
}

ensure_events_role() {
    local task_definition_arn="$1"
    local cluster_arn="$2"
    local exec_role_arn="$3"
    local task_role_arn="$4"

    local trust_policy
    trust_policy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

    if ! aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
        echo "Creating IAM role ${ROLE_NAME}..." >&2
        aws iam create-role \
            --role-name "${ROLE_NAME}" \
            --assume-role-policy-document "${trust_policy}" >/dev/null
    else
        echo "Using existing IAM role ${ROLE_NAME}..." >&2
    fi

    local policy_document
    local pass_roles=""
    if [[ -n "${exec_role_arn}" && "${exec_role_arn}" != "None" ]]; then
        pass_roles+="\"${exec_role_arn}\""
    fi
    if [[ -n "${task_role_arn}" && "${task_role_arn}" != "None" ]]; then
        if [[ -n "${pass_roles}" ]]; then
            pass_roles+=","
        fi
        pass_roles+="\"${task_role_arn}\""
    fi

    policy_document='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ecs:RunTask"],"Resource":["'"${task_definition_arn}"'"],"Condition":{"ArnEquals":{"ecs:cluster":"'"${cluster_arn}"'"}}}'
    if [[ -n "${pass_roles}" ]]; then
        policy_document+=',{"Effect":"Allow","Action":["iam:PassRole"],"Resource":['"${pass_roles}"'],"Condition":{"StringLike":{"iam:PassedToService":"ecs-tasks.amazonaws.com"}}}'
    fi
    policy_document+=']}'

    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name "AllowRunTaskFromEventBridge" \
        --policy-document "${policy_document}" >/dev/null

    aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text
}

main() {
    require_var "AWS_REGION (or AWS default region)" "${AWS_REGION}"
    require_var "ECS_CLUSTER" "${ECS_CLUSTER}"
    require_var "TASK_DEFINITION" "${TASK_DEFINITION}"
    require_var "SUBNET_IDS" "${SUBNET_IDS}"
    require_var "SECURITY_GROUP_IDS" "${SECURITY_GROUP_IDS}"
    require_var "LOG_GROUP" "${LOG_GROUP}"
    require_var "SERVICES" "${SERVICES}"

    if [[ "${ASSIGN_PUBLIC_IP}" != "ENABLED" && "${ASSIGN_PUBLIC_IP}" != "DISABLED" ]]; then
        echo -e "${RED}Error:${NC} ASSIGN_PUBLIC_IP must be ENABLED or DISABLED."
        exit 1
    fi
    if [[ "${LAUNCH_TYPE}" != "FARGATE" && "${LAUNCH_TYPE}" != "EC2" ]]; then
        echo -e "${RED}Error:${NC} LAUNCH_TYPE must be FARGATE or EC2."
        exit 1
    fi
    if ! [[ "${TIME_RANGE_MINUTES}" =~ ^[0-9]+$ ]] || [[ "${TIME_RANGE_MINUTES}" -le 0 ]]; then
        echo -e "${RED}Error:${NC} TIME_RANGE_MINUTES must be a positive integer."
        exit 1
    fi

    local subnets_json
    local security_groups_json
    local cluster_arn
    local task_definition_arn
    local task_execution_role_arn
    local task_role_arn
    local role_arn

    subnets_json="$(csv_to_json_array "${SUBNET_IDS}")"
    security_groups_json="$(csv_to_json_array "${SECURITY_GROUP_IDS}")"
    if [[ -z "${subnets_json}" || -z "${security_groups_json}" ]]; then
        echo -e "${RED}Error:${NC} SUBNET_IDS and SECURITY_GROUP_IDS must be valid CSV values."
        exit 1
    fi

    cluster_arn="$(resolve_cluster_arn "${ECS_CLUSTER}")"

    task_definition_arn="$(aws ecs describe-task-definition \
        --region "${AWS_REGION}" \
        --task-definition "${TASK_DEFINITION}" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)"

    task_execution_role_arn="$(aws ecs describe-task-definition \
        --region "${AWS_REGION}" \
        --task-definition "${TASK_DEFINITION}" \
        --query 'taskDefinition.executionRoleArn' \
        --output text)"

    task_role_arn="$(aws ecs describe-task-definition \
        --region "${AWS_REGION}" \
        --task-definition "${TASK_DEFINITION}" \
        --query 'taskDefinition.taskRoleArn' \
        --output text)"

    role_arn="$(ensure_events_role \
        "${task_definition_arn}" \
        "${cluster_arn}" \
        "${task_execution_role_arn}" \
        "${task_role_arn}")"

    echo -e "${BLUE}Configuring EventBridge rules...${NC}"
    echo "Region:           ${AWS_REGION}"
    echo "Cluster:          ${cluster_arn}"
    echo "Task definition:  ${task_definition_arn}"
    echo "Container:        ${CONTAINER_NAME}"
    echo "Services:         ${SERVICES}"
    echo "Log group:        ${LOG_GROUP}"
    echo

    local service
    IFS=',' read -ra service_items <<< "${SERVICES}"
    for service in "${service_items[@]}"; do
        service="$(echo "${service}" | xargs)"
        [[ -z "${service}" ]] && continue

        local alarm_name="${service}${ALARM_SUFFIX}"
        local rule_name="${RULE_PREFIX}-${service}"
        local event_pattern
        local overrides_payload
        local escaped_overrides_payload
        local targets_file

        event_pattern=$(
            cat <<EOF
{"source":["aws.cloudwatch"],"detail-type":["CloudWatch Alarm State Change"],"detail":{"state":{"value":["ALARM"]},"alarmName":["${alarm_name}"]}}
EOF
        )

        aws events put-rule \
            --region "${AWS_REGION}" \
            --name "${rule_name}" \
            --state ENABLED \
            --event-pattern "${event_pattern}" >/dev/null

        overrides_payload=$(
            cat <<EOF
{"containerOverrides":[{"name":"${CONTAINER_NAME}","environment":[{"name":"SERVICE_NAME","value":"${service}"},{"name":"LOG_GROUP","value":"${LOG_GROUP}"},{"name":"TIME_RANGE_MINUTES","value":"${TIME_RANGE_MINUTES}"}]}]}
EOF
        )
        escaped_overrides_payload="$(echo "${overrides_payload}" | sed 's/"/\\"/g')"

        targets_file="$(mktemp)"
        cat >"${targets_file}" <<EOF
[
  {
    "Id": "Target-${service}",
    "Arn": "${cluster_arn}",
    "RoleArn": "${role_arn}",
    "Input": "${escaped_overrides_payload}",
    "EcsParameters": {
      "TaskDefinitionArn": "${task_definition_arn}",
      "TaskCount": ${TASK_COUNT},
      "LaunchType": "${LAUNCH_TYPE}",
      "NetworkConfiguration": {
        "awsvpcConfiguration": {
          "Subnets": [${subnets_json}],
          "SecurityGroups": [${security_groups_json}],
          "AssignPublicIp": "${ASSIGN_PUBLIC_IP}"
        }
      }
    },
    "RetryPolicy": {
      "MaximumRetryAttempts": 0,
      "MaximumEventAgeInSeconds": 60
    }
  }
]
EOF

        aws events put-targets \
            --region "${AWS_REGION}" \
            --rule "${rule_name}" \
            --targets "file://${targets_file}" >/dev/null
        rm -f "${targets_file}"

        echo -e "${GREEN}✓${NC} ${rule_name} (${alarm_name} -> ${service})"
    done

    echo
    echo -e "${GREEN}Done.${NC} CloudWatch alarms now trigger one-off ECS diagnosis tasks."
}

main "$@"
