resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-notifications"
}

# Optional - only subscribes if you set admin_notification_email.
# Subscribing triggers a "confirm subscription" email from AWS that you
# need to click before notifications actually arrive.
resource "aws_sns_topic_subscription" "owner_email" {
  count     = var.admin_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.admin_notification_email
}

# Decouples "someone signed up" from "send them a welcome email" - the
# newsletter-signup Lambda just drops a message here and returns
# immediately; send-welcome-email Lambda consumes it independently.
resource "aws_sqs_queue" "welcome_email" {
  name                       = "${var.project_name}-welcome-email-queue"
  message_retention_seconds = 3600
  visibility_timeout_seconds = 30
}
