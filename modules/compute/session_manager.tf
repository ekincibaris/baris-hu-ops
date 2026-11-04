################################################################################
# Session Manager preferences: every session is encrypted with the project KMS
# key and streamed to an encrypted CloudWatch log group for audit.
#
# SSM-SessionManagerRunShell is a single, account-and-region-wide document.
# If it already exists (e.g. someone saved preferences in the console), import
# it or set manage_session_manager_preferences = false. See README.
################################################################################

resource "aws_ssm_document" "session_preferences" {
  count = var.manage_session_manager_preferences ? 1 : 0

  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences managed by Terraform (${var.name})"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.this["session_audit"].name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = var.kms_key_arn
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = tostring(var.session_idle_timeout_minutes)
      maxSessionDuration          = "60"
      shellProfile = {
        windows = ""
        linux   = "cd ~ && exec bash -l"
      }
    }
  })
}
