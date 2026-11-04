# Plan-level tests that run without AWS credentials (`terraform test`).
# The AWS provider is mocked, so these check the wiring and the guardrails of
# this configuration, not AWS behaviour.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b"]
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_elb_service_account" {
    defaults = {
      arn = "arn:aws:iam::054676820928:root"
    }
  }
}

variables {
  allowed_account_ids = ["123456789012"]
  alarm_email         = "alerts@example.com"
}

run "defaults_are_private_and_ssm_only" {
  command = plan

  assert {
    condition     = length(module.network.interface_endpoint_ids) == 5
    error_message = "Expected interface endpoints for ssm, ssmmessages, ec2messages, logs and monitoring."
  }

  assert {
    condition     = module.network.nat_gateway_enabled == false
    error_message = "NAT must be off by default."
  }

  assert {
    condition     = module.compute.remediation_tag_key == "AutoRemediationGroup"
    error_message = "Remediation tag key changed; the runbook IAM condition depends on it."
  }

  assert {
    condition     = module.compute.asg_name == "ops-baris-prod-web"
    error_message = "Unexpected Auto Scaling group name."
  }
}

run "single_az_endpoints_and_nat_toggle" {
  command = plan

  variables {
    single_az_endpoints = true
    enable_nat_gateway  = true
  }

  assert {
    condition     = module.network.nat_gateway_enabled == true
    error_message = "enable_nat_gateway should turn the NAT gateway on."
  }
}

run "rejects_bad_email" {
  command = plan

  variables {
    alarm_email = "not-an-email"
  }

  expect_failures = [var.alarm_email]
}

run "rejects_domain_outside_zone" {
  command = plan

  variables {
    domain_name = "ops.example.com"
  }

  expect_failures = [var.domain_name]
}

run "rejects_min_above_max" {
  command = plan

  variables {
    asg_min_size = 4
    asg_max_size = 3
  }

  expect_failures = [var.asg_max_size]
}

run "rejects_non_graviton_instance" {
  command = plan

  variables {
    instance_type = "t3.micro"
  }

  expect_failures = [var.instance_type]
}
