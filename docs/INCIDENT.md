# Postmortem: ops.baris.hu unavailable during weekly patching

> **This incident is simulated.** It is a realistic scenario written against an earlier version of
> this configuration (ELB health checks, no patch awareness in the runbook) to practise incident
> response and to explain why the auto-remediation works the way it does. Instance IDs, timestamps
> and counts are illustrative. You can reproduce the failure mode: set `health_check_type = "ELB"`
> in `modules/compute/main.tf` and run the maintenance window task on demand. The write-up follows a
> blameless format: it looks at systems and decisions, not at people.

| | |
|---|---|
| **Incident ID** | INC-2026-001 |
| **Date** | Sunday 18 October 2026 |
| **Severity** | SEV-2 (full outage of a non-critical public site) |
| **Duration of user impact** | 3 min 40 s (03:03:10 – 03:06:50 CEST) |
| **Detected by** | CloudWatch alarm `no-healthy-hosts` (automated, 2 min after impact began) |
| **Status** | Resolved. Fixes merged. Follow-ups tracked below. |
| **Author** | Site owner (CloudOps) |

## Summary

During the weekly Patch Manager maintenance window, the only web instance rebooted to finish a
kernel update. The Auto Scaling group used **ELB health checks**. It saw the rebooting instance
fail two ALB health checks and **terminated it mid-patch**. In the same minute, the new
auto-remediation runbook tried to restart nginx on the instance that was already being terminated.
The site served 502/503 until a replacement instance had booted and passed health checks,
3 minutes 40 seconds in total.

A patch reboot on a single instance was always going to cause about 60–90 seconds of downtime.
Three automations reacting to the same signal, with no coordination, made the outage **2.5× longer**,
caused the patch run to fail, and paged a human for a planned event.

## Impact

- **Users:** `https://ops.baris.hu` returned 502/503 for 3 min 40 s. ALB access logs show
  **41 failed requests**, mostly from an external uptime monitor (the site has little organic
  traffic at 03:00).
- **Patching:** the maintenance window execution ended **Failed** (`i-0a1c…` was terminated during
  `AWS-RunPatchBaseline`). Patch compliance briefly showed one instance missing. The replacement
  launched from the latest AL2023 AMI, so it was compliant.
- **Noise:** 4 alarm emails were sent between 03:04 and 03:08 for an event that was planned.
- **Data:** none. The site is stateless.

## Timeline (CEST, UTC+2)

| Time | Event |
|---|---|
| 03:00:00 | Maintenance window `ops-baris-prod-patching` starts. `AWS-RunPatchBaseline Install, RebootIfNeeded` is sent to `i-0a1c…` (the only InService instance, `min_size = 1`). |
| 03:02:41 | 14 packages installed, including `kernel`. The agent reboots the instance (`RebootIfNeeded`). |
| 03:02:55 | First ALB health check against `/health` fails (connection refused). |
| 03:03:10 | Second failure. Target is **unhealthy**. With no healthy targets left, the ALB fails open, and requests return 502. **User impact starts.** |
| 03:03:12 | Auto Scaling (health check type `ELB`) marks `i-0a1c…` **Unhealthy** and starts terminating it. A replacement `i-0b7e…` is launched. |
| 03:04:00 | `app-unhealthy` alarm → ALARM. Email #1. EventBridge starts `RestartUnhealthyService`. |
| 03:04:03 | Runbook: `findUnhealthyInstances` returns `i-0a1c…`. At that time the runbook did **not** check lifecycle state or in-progress patching. |
| 03:04:05 | Runbook: `restartService` sends `systemctl restart nginx` to `i-0a1c…`. The command is never delivered (instance is shutting down). |
| 03:05:00 | `no-healthy-hosts` alarm → ALARM (2 × 1 min datapoints). Email #2: "The site is down." **Detection.** |
| 03:05:07 | Runbook times out on delivery and the execution ends **Failed**. Nobody is told: that version of the runbook had no result notification. |
| 03:05:40 | Maintenance window task for `i-0a1c…` ends **Failed** (`InstanceTerminated`). |
| 03:06:20 | `i-0b7e…` finishes user data (`dnf install` through the S3 endpoint, nginx and CloudWatch agent started). |
| 03:06:50 | `i-0b7e…` passes 2 health checks. Target is **healthy**. **User impact ends.** |
| 03:08:00 | `app-unhealthy` and `no-healthy-hosts` → OK. Emails #3 and #4. |
| 09:15 | Engineer reads the emails and starts the investigation (no on-call at night: email-only notification is a known limitation of this project). |
| 11:30 | Root cause identified, fix designed (below), and the change opened as a PR. |
| 14:10 | Fix applied. Patch window re-run on demand and verified with no replacement and no runbook action (see *Verification*). |

## Detection

- **What worked:** `no-healthy-hosts` fired 1 min 50 s after impact began. `app-unhealthy` fired
  even earlier, 50 s in. The alarm descriptions linked to the right runbook sections.
- **What didn't:** notification is email-only, so nobody saw it until 09:15. For this project that
  is acceptable, but it would not be for a production service. The alarms also had no idea that a
  maintenance window was running, so a planned reboot looked exactly like an outage.

## Root cause

Three automations owned the same signal, *target unhealthy*, and reacted to it in different ways
with no coordination:

| Automation | Intended reaction | Speed |
|---|---|---|
| Patch Manager | "I rebooted it. Wait about 90 s." | n/a, it caused the signal |
| Auto Scaling (`health_check_type = "ELB"`) | "Terminate and replace." | **~2 s** after the target turned unhealthy |
| Remediation runbook | "Restart nginx." | ~55 s (alarm period plus EventBridge) |

The fastest reaction won, and it was the most destructive one. Auto Scaling replaced an instance
that would have recovered by itself about 60 s later. The runbook then acted on an instance that was
already being terminated.

**Why did it happen?**
1. *Why was the site down for 3 min 40 s instead of about 90 s?* Because the instance was
   replaced instead of being allowed to finish rebooting.
2. *Why was it replaced?* Because the ASG used ELB health checks, which treat any failed target as
   a dead instance. The health check grace period only protects newly launched instances, not a
   reboot.
3. *Why were ELB health checks enabled?* They are the common default advice. When I added the
   remediation runbook, I did not revisit which component owns which failure.
4. *Why didn't the runbook notice?* It only asked "which target is unhealthy?". It did not ask "is
   anyone else already working on it?" (lifecycle state, patching).
5. *Why was any downtime possible at all?* `min_size = 1`. A single instance has no redundancy for
   planned reboots, so even a perfectly coordinated patch run causes about 60–90 s of downtime.

**Contributing factors**
- Patch reboots and real outages produced identical signals, and nothing marked the maintenance
  window.
- The first version of the runbook had no verification step, so a failed restart ended the run with
  no escalation.

## Resolution: what changed (all in this repository)

1. **One owner per failure type.** The ASG now uses `health_check_type = "EC2"`. Auto Scaling
   owns *instance* failures. The runbook owns *application* failures, and escalates to Auto Scaling
   with `SetInstanceHealth Unhealthy` (respecting the grace period) only if a restart does not
   bring the target back within 120 s. See README → *Auto-remediation*.
2. **The runbook checks before it acts.** `findUnhealthyInstances` now skips targets that are
   not InService members of the group, and **skips instances with an in-progress
   `AWS-RunPatchBaseline` invocation**. Every skip is logged with its reason.
3. **Verify, then escalate.** The new `verifyOrEscalate` step polls target health and reports
   `recovered`, `escalated` or `still_unhealthy` to SNS.
4. **Human escalation by duration.** A new `unhealthy-hosts-sustained` alarm (6 min) pages a person
   only when automation has had its chance. `app-unhealthy` is now informational.
5. **Patch one instance at a time.** The maintenance window has `max_concurrency = 1` and
   `max_errors = 1`.

### Verification

On 18 Oct 14:10 I re-ran the maintenance window task with the fix applied:

- The instance rebooted and the target was unhealthy for 78 s.
- `app-unhealthy` fired. The runbook ran and logged
  `{"event": "decision", "restart": [], "skipped": {"i-0b7e…": "patching in progress (command 5c1f…)"}}`,
  then ended at `nothingToDo`.
- **No replacement happened.** The patch task ended **Success**. Total impact was 78 s, which is the
  expected cost of `min_size = 1`.

I also tested the escalation path with `scripts/demo.sh break hard`: the restart failed, the runbook
escalated after 120 s, Auto Scaling replaced the instance, and the email said `escalated`.

## Follow-ups

| # | Action | Priority | Status |
|---|---|---|---|
| 1 | Zero-downtime patching: a scheduled action raises desired capacity to 2 at 02:45 on Sundays and back to 1 at 05:15. Alternatively, switch patching to instance refresh only (launch before terminate). | P1 | Open |
| 2 | Send `no-healthy-hosts` to a channel that can wake someone (SNS → chat or pager), keeping email for the rest. | P2 | Open |
| 3 | Suppress or annotate `app-unhealthy` notifications during the maintenance window (or use alarm mute rules) to cut noise. | P3 | Open |
| 4 | Add a CloudWatch Synthetics canary to measure availability from outside the VPC, so impact numbers don't depend on ALB metrics. | P3 | Open |
| 5 | Monthly game day: run `docs/DEMO.md`, including the hard-break escalation, and record the timings. | P3 | Open |
| 6 | Document the ownership table (who reacts to which signal) in the README. | P2 | **Done** |

## Lessons learned

- **What went well:** the alarms fired fast and pointed to the right runbook. The replacement
  instance booted cleanly with no internet access, which validated the endpoint design under
  pressure. Logs in CloudWatch were enough to rebuild the timeline to the second.
- **What went poorly:** every automation was correct on its own, and together they made things
  worse. I added automation without asking "what else reacts to this signal?"
- **Where I got lucky:** it happened at 03:00 on a Sunday on a status page. The same design on a
  revenue-generating service would have meant a real outage every week.
- **Takeaway:** before adding self-healing, write down **who owns each failure signal**, and make
  sure every automation checks whether someone else is already handling it.
