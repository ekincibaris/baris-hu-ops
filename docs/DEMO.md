# 5-minute live demo

The goal is to show the whole loop in five minutes: infrastructure as code, scaling, failure,
detection, automatic repair, audit trail and teardown. Everything is real AWS. Nothing is mocked.

**Be upfront about one thing.** A cold `terraform apply` takes 8–12 minutes, mostly ACM validation
and the interface endpoints. Deploy before the call, and in the demo show that the running
infrastructure matches the code (`terraform plan` → *No changes*). If the interviewer wants to see a
deploy, start `terraform apply` from scratch at the beginning of the call and give the architecture
walkthrough while it runs.

## Pre-flight (about 20 minutes before)

```bash
cd envs/prod
# terraform.tfvars for demos:
#   single_az_endpoints = true   # about €0.10 an hour instead of €0.16
#   cpu_target_value    = 40     # scale-out triggers sooner and adds more instances
terraform apply                                  # 8–12 min
```

Checklist:
- [ ] You have confirmed the SNS subscription email, and the inbox is open in a browser tab.
- [ ] `https://ops.baris.hu` loads and shows one instance ID and AZ.
- [ ] `scripts/demo.sh status`: 1 target `healthy`, all alarms `OK` (`INSUFFICIENT_DATA` is fine
      for the first minutes).
- [ ] Browser tabs: the status page, the CloudWatch dashboard (`terraform output dashboard_url`),
      Systems Manager → Automation → Executions, and EC2 → Auto Scaling groups → Activity.
- [ ] Two terminals in the repository root. **Terminal B** runs `scripts/demo.sh watch` the whole time.
- [ ] `session-manager-plugin --version` works.
- [ ] No load is left over from a rehearsal: `scripts/demo.sh unload`.

## The five minutes

| Time | Say | Do (terminal A unless noted) | What they see |
|---|---|---|---|
| **0:00** | "One `terraform apply` builds a private web tier: no SSH, no internet egress, self-healing." Show the README diagram. | `terraform -chdir=envs/prod plan` | *No changes*: AWS matches git. Mention the CI checks on the PR. |
| **0:40** | "The instance is in a private subnet. Load goes in through Run Command, not SSH." | `scripts/demo.sh load 8` | A command ID. In the console under Run Command, the command reaches the instance through the VPC endpoint. |
| **1:00** | "Now I break the app on purpose. Everyone has seen this ticket: website is down." | `scripts/demo.sh break soft` | nginx is stopped. Within about 30 s, terminal B shows the target as `unhealthy` (`Target.FailedHealthChecks`). The status page shows a 502/503. |
| **1:30** | "The ALB checks /health every 15 s. Two failures make the target unhealthy. A 1-minute alarm fires, and EventBridge starts an SSM Automation runbook." | Watch terminal B | `ops-baris-prod-app-unhealthy` → `ALARM` (about 60–90 s after the break). The ALARM email arrives. |
| **2:30** | "The alarm doesn't say which instance is broken. The runbook asks the target group, skips anything being patched, restarts nginx and verifies." | `scripts/demo.sh executions` | Steps `findUnhealthyInstances` → `restartService` → `verifyOrEscalate` all `Success`, with output `recovered`. |
| **3:00** | "Every step is logged." | `scripts/demo.sh logs` (Ctrl-C after a few lines) | JSON lines: target states, the decision, polls, the result. Also mention the run-command log with the journal output. |
| **3:20** | "Meanwhile, the load has pushed CPU over target, so Auto Scaling adds capacity." | Point at terminal B and the dashboard | Desired capacity 1 → 2 (or 3 with target 40). A new instance shows `initial` → `healthy`. Refresh the page and a second instance ID/AZ appears. |
| **3:50** | "Here's how I get onto a box: no keys, no port 22, and the session is recorded." | `scripts/demo.sh shell`, then `sudo journalctl -u nginx -n 5`, then `exit` | A shell over SSM. Show the `/ops-baris-prod/ec2/session-manager` log group with the transcript. |
| **4:20** | "Demo's done, so I tear it down. Running this costs about 10 cents an hour." | `scripts/demo.sh unload` then `terraform -chdir=envs/prod destroy` | Destroy starts. Finish questions while it runs (5–10 min). |

## Timings and why

| Event | Typical delay | Why |
|---|---|---|
| Target unhealthy after break | 15–30 s | Health check interval 15 s × unhealthy threshold 2 |
| `app-unhealthy` alarm → ALARM | 60–90 s after the break | ALB metrics are per minute; 1 of 1 datapoint |
| Runbook start | < 5 s after ALARM | EventBridge rule on the alarm state change |
| Back to healthy | 10–40 s after the restart | Healthy threshold 2 × 15 s |
| Scale-out decision | 3–4 min after load starts | Target tracking needs 3 one-minute datapoints above target |
| New instance in service | 1.5–3 min more | Boot, `dnf install nginx amazon-cloudwatch-agent`, health checks |
| `[auto-remediation] recovered` email | ~2.5–3.5 min after the break | All of the above |

## Plan B (if AWS is slow)

- **The alarm is slow to fire:** force the state. This produces the same EventBridge event, so the
  runbook runs for real:
  ```bash
  aws cloudwatch set-alarm-state --alarm-name ops-baris-prod-app-unhealthy \
    --state-value ALARM --state-reason "demo: forced"
  ```
  If nginx is already running again, the runbook ends in `nothingToDo` and logs *why* it did
  nothing. That's also a good thing to show.
- **Scale-out is slow:** talk through `aws autoscaling describe-scaling-activities` and the target
  tracking alarms (`TargetTracking-ops-baris-prod-web-AlarmHigh-...`) in the CloudWatch alarm list.
  The decision is visible there before the instance launches.
- **Everything is slow:** keep screenshots from the rehearsal in a folder and walk through them.

## Bonus: the escalation path (+3 minutes)

If they ask "what if a restart doesn't fix it?":

```bash
scripts/demo.sh break hard     # corrupts nginx.conf, then stops nginx
```

The runbook restarts nginx, the restart fails (`nginx -t` error in the run-command log), the target
stays unhealthy for 120 s, and then the runbook calls `SetInstanceHealth Unhealthy`. Auto Scaling
terminates the instance and launches a fresh one from the latest AMI. The email says `escalated`.
This is the "restart first, replace second" ladder from the README, and it is why the ASG uses
`EC2` health checks.

## Reset between rehearsals

```bash
scripts/demo.sh unload
aws cloudwatch set-alarm-state --alarm-name ops-baris-prod-app-unhealthy --state-value OK --state-reason reset
# If a hard break left a broken instance and escalation is disabled:
aws autoscaling set-instance-health --instance-id <id> --health-status Unhealthy
```
