data "archive_file" "thumbnail_generator" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-src/thumbnail-generator"
  output_path = "${path.module}/build/thumbnail-generator.zip"
}

data "archive_file" "newsletter_signup" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-src/newsletter-signup"
  output_path = "${path.module}/build/newsletter-signup.zip"
}

data "archive_file" "send_welcome_email" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-src/send-welcome-email"
  output_path = "${path.module}/build/send-welcome-email.zip"
}

# --- Thumbnail generator: triggered by S3 uploads under originals/ ---

resource "aws_lambda_function" "thumbnail_generator" {
  function_name    = "${var.project_name}-thumbnail-generator"
  role              = aws_iam_role.lambda_thumbnail.arn
  handler           = "index.handler"
  runtime           = "python3.12"
  filename          = data.archive_file.thumbnail_generator.output_path
  source_code_hash  = data.archive_file.thumbnail_generator.output_base64sha256
  timeout           = 10
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.thumbnail_generator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.media.arn
}

resource "aws_s3_bucket_notification" "media" {
  bucket = aws_s3_bucket.media.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.thumbnail_generator.arn
    events               = ["s3:ObjectCreated:*"]
    filter_prefix        = "originals/"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# --- Newsletter signup: triggered by API Gateway ---

resource "aws_lambda_function" "newsletter_signup" {
  function_name    = "${var.project_name}-newsletter-signup"
  role              = aws_iam_role.lambda_newsletter.arn
  handler           = "index.handler"
  runtime           = "python3.12"
  filename          = data.archive_file.newsletter_signup.output_path
  source_code_hash  = data.archive_file.newsletter_signup.output_base64sha256
  timeout           = 10

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.main.name
      SQS_QUEUE_URL  = aws_sqs_queue.welcome_email.url
    }
  }
}

# --- Send welcome email: triggered by SQS ---

resource "aws_lambda_function" "send_welcome_email" {
  function_name    = "${var.project_name}-send-welcome-email"
  role              = aws_iam_role.lambda_welcome.arn
  handler           = "index.handler"
  runtime           = "python3.12"
  filename          = data.archive_file.send_welcome_email.output_path
  source_code_hash  = data.archive_file.send_welcome_email.output_base64sha256
  timeout           = 10

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "welcome_email" {
  event_source_arn = aws_sqs_queue.welcome_email.arn
  function_name     = aws_lambda_function.send_welcome_email.arn
  batch_size        = 1
}
