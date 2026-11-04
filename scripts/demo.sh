#!/usr/bin/env bash
# Helper for the live interview demo (docs/DEMO.md). Needs the AWS CLI v2, the
# Session Manager plugin and credentials for the account the stack runs in.
#
#   scripts/demo.sh status            target health, scaling, alarms
#   scripts/demo.sh watch             status every 15 seconds
#   scripts/demo.sh load [minutes]    burn CPU on every InService instance (default 8)
#   scripts/demo.sh unload            stop the CPU burn early
#   scripts/demo.sh break [soft|hard] soft: stop nginx (restart fixes it)
#                                     hard: corrupt nginx.conf too (restart fails -> ASG replaces)
#   scripts/demo.sh executions        recent auto-remediation runs and their result
#   scripts/demo.sh logs [group]      tail automation (default), run-command or triggers logs
#   scripts/demo.sh shell             Session Manager shell on the first instance
set -euo pipefail

REGION="${AWS_REGION:-eu-central-1}"
export AWS_REGION="$REGION" AWS_PAGER=""
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/envs/prod"

tf_output() { terraform -chdir="$TF_DIR" output -raw "$1"; }

ASG_NAME="${ASG_NAME:-$(tf_output asg_name)}"
TG_ARN="${TG_ARN:-$(tf_output target_group_arn)}"
RUNBOOK="${RUNBOOK:-$(tf_output remediation_runbook)}"
NAME_PREFIX="${ASG_NAME%-web}"

in_service_instances() {
  # shellcheck disable=SC2016 # backticks are JMESPath literals, not shell
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
    --output text
}

first_instance() {
  local ids
  ids="$(in_service_instances)"
  if [ -z "$ids" ] || [ "$ids" = "None" ]; then
    echo "no InService instances in $ASG_NAME" >&2
    exit 1
  fi
  echo "${ids%%[[:space:]]*}"
}

run_shell() {
  # run_shell <comment> <instance ids...> -- <command>...
  local comment="$1"; shift
  local ids=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do ids+=("$1"); shift; done
  shift
  local params
  params="$(python3 -c 'import json,sys; print(json.dumps({"commands": sys.argv[1:]}))' "$@")"
  aws ssm send-command \
    --document-name AWS-RunShellScript \
    --comment "$comment" \
    --instance-ids "${ids[@]}" \
    --parameters "$params" \
    --cloud-watch-output-config "CloudWatchOutputEnabled=true,CloudWatchLogGroupName=/$NAME_PREFIX/ec2/run-command" \
    --query 'Command.CommandId' --output text
}

cmd_status() {
  echo "== $(date -u +%H:%M:%S) UTC  ASG $ASG_NAME"
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' --output text \
    | awk '{printf "   capacity  min=%s desired=%s max=%s\n", $1, $2, $3}'
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' --output text \
    | sed 's/^/   instance  /'
  echo "== target health"
  aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output text \
    | sed 's/^/   /'
  echo "== alarms"
  aws cloudwatch describe-alarms --alarm-name-prefix "$NAME_PREFIX" \
    --query 'MetricAlarms[].[StateValue,AlarmName]' --output text | sed 's/^/   /'
  echo "== latest scaling activity"
  aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG_NAME" --max-items 2 \
    --query 'Activities[].[StartTime,StatusCode,Description]' --output text | sed 's/^/   /'
}

cmd_watch() {
  while true; do
    clear || true
    cmd_status
    sleep 15
  done
}

cmd_load() {
  local minutes="${1:-8}"
  local seconds=$((minutes * 60))
  # shellcheck disable=SC2046 # word splitting of instance IDs is intended
  set -- $(in_service_instances)
  echo "burning all vCPUs for $minutes min on: $*"
  # shellcheck disable=SC2016 # $(nproc) and $i must expand on the instance, not here
  run_shell "demo: cpu load ${minutes}m" "$@" -- \
    'for i in $(seq "$(nproc)"); do systemd-run --unit="demo-cpu-burn-$i" --collect timeout '"$seconds"' sh -c "while :; do :; done"; done' \
    'systemctl list-units --no-pager "demo-cpu-burn-*"'
}

cmd_unload() {
  # shellcheck disable=SC2046
  set -- $(in_service_instances)
  run_shell "demo: stop cpu load" "$@" -- \
    'systemctl stop "demo-cpu-burn-*" || true'
}

cmd_break() {
  local mode="${1:-soft}"
  local id
  id="$(first_instance)"
  case "$mode" in
    soft)
      echo "stopping nginx on $id (auto-remediation should restart it)"
      run_shell "demo: break nginx (soft)" "$id" -- 'systemctl stop nginx' 'systemctl is-active nginx || true'
      ;;
    hard)
      echo "corrupting nginx.conf and stopping nginx on $id (restart fails -> instance gets replaced)"
      run_shell "demo: break nginx (hard)" "$id" -- \
        'echo "this_is_not_a_directive;" >> /etc/nginx/nginx.conf' \
        'systemctl stop nginx' \
        'nginx -t || true'
      ;;
    *)
      echo "usage: $0 break [soft|hard]" >&2
      exit 2
      ;;
  esac
}

cmd_executions() {
  aws ssm describe-automation-executions \
    --filters "Key=DocumentNamePrefix,Values=$RUNBOOK" --max-results 5 \
    --query 'AutomationExecutionMetadataList[].[ExecutionStartTime,AutomationExecutionStatus,AutomationExecutionId]' \
    --output text
  local latest
  latest="$(aws ssm describe-automation-executions \
    --filters "Key=DocumentNamePrefix,Values=$RUNBOOK" --max-results 1 \
    --query 'AutomationExecutionMetadataList[0].AutomationExecutionId' --output text)"
  if [ -n "$latest" ] && [ "$latest" != "None" ]; then
    echo "== steps of $latest"
    aws ssm get-automation-execution --automation-execution-id "$latest" \
      --query 'AutomationExecution.StepExecutions[].[StepName,StepStatus]' --output text
    echo "== outputs"
    aws ssm get-automation-execution --automation-execution-id "$latest" \
      --query 'AutomationExecution.Outputs' --output json
  fi
}

cmd_logs() {
  local group
  case "${1:-automation}" in
    automation) group="/$NAME_PREFIX/ssm/automation" ;;
    run-command) group="/$NAME_PREFIX/ec2/run-command" ;;
    triggers) group="/aws/events/$NAME_PREFIX/remediation-triggers" ;;
    *) echo "usage: $0 logs [automation|run-command|triggers]" >&2; exit 2 ;;
  esac
  aws logs tail "$group" --since 30m --follow --format short
}

cmd_shell() {
  aws ssm start-session --target "$(first_instance)"
}

case "${1:-status}" in
  status) cmd_status ;;
  watch) cmd_watch ;;
  load) cmd_load "${2:-8}" ;;
  unload) cmd_unload ;;
  break) cmd_break "${2:-soft}" ;;
  executions) cmd_executions ;;
  logs) cmd_logs "${2:-automation}" ;;
  shell) cmd_shell ;;
  *)
    sed -n '2,14p' "$0"
    exit 2
    ;;
esac
