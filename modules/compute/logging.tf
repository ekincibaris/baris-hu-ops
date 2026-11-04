################################################################################
# Log groups written by the instances, and the CloudWatch agent configuration.
################################################################################

locals {
  log_groups = {
    nginx_access  = "/${var.name}/ec2/nginx/access"
    nginx_error   = "/${var.name}/ec2/nginx/error"
    user_data     = "/${var.name}/ec2/user-data"
    run_command   = "/${var.name}/ec2/run-command"
    session_audit = "/${var.name}/ec2/session-manager"
  }

  cw_agent_config = {
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "root"
    }

    metrics = {
      namespace = "CWAgent"

      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }

      # Also publish group-level series so alarms and the dashboard can use one
      # metric for the whole Auto Scaling group.
      aggregation_dimensions = [["AutoScalingGroupName"]]

      metrics_collected = {
        mem = {
          measurement = ["mem_used_percent"]
          # Static dimension: avoids ec2:DescribeTags (there is no EC2 API endpoint).
          append_dimensions = { AutoScalingGroupName = local.asg_name }
        }

        disk = {
          measurement              = ["used_percent"]
          resources                = ["/"]
          drop_device              = true
          ignore_file_system_types = ["sysfs", "devtmpfs", "tmpfs", "overlay"]
          append_dimensions        = { AutoScalingGroupName = local.asg_name }
        }
      }
    }

    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/nginx/access.log"
              log_group_name  = local.log_groups.nginx_access
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/nginx/error.log"
              log_group_name  = local.log_groups.nginx_error
              log_stream_name = "{instance_id}"
            },
            {
              file_path       = "/var/log/user-data.log"
              log_group_name  = local.log_groups.user_data
              log_stream_name = "{instance_id}"
            },
          ]
        }
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ssm_parameter" "cw_agent_config" {
  #checkov:skip=CKV2_AWS_34:The agent config is not secret (metric names and log paths); a String parameter keeps it readable in the console.
  name        = "/${var.name}/cloudwatch-agent/config"
  description = "CloudWatch agent configuration for the status page instances"
  type        = "String"
  tier        = "Standard"
  value       = jsonencode(local.cw_agent_config)
}
