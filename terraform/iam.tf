# ---------- Trust policies (one per principal type) ----------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------- EC2 (blog app) ----------
# Least-privilege: only what the instance needs to pull its own image and
# talk to this project's table/bucket/topic. No SSH key pair is used -
# SSM Session Manager (via the managed policy below) gives shell access
# instead, so there's no open port 22 to manage.

resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_app_permissions" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this specific action does not support resource-level scoping
  }
  statement {
    sid = "EcrPullBlogImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.blog_app.arn]
  }
  statement {
    sid = "AppData"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [aws_dynamodb_table.main.arn]
  }
  statement {
    sid       = "MediaBucket"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.media.arn, "${aws_s3_bucket.media.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ec2_app" {
  name   = "${var.project_name}-ec2-app-policy"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_app_permissions.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ---------- ECS Fargate (comments API) ----------

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_permissions" {
  statement {
    sid = "CommentsData"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
    ]
    resources = [aws_dynamodb_table.main.arn]
  }
  statement {
    sid       = "NotifyOnNewComment"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name   = "${var.project_name}-ecs-task-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_permissions.json
}

# ---------- Lambda: thumbnail generator (S3 -> S3) ----------

resource "aws_iam_role" "lambda_thumbnail" {
  name               = "${var.project_name}-lambda-thumbnail-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_thumbnail_logs" {
  role       = aws_iam_role.lambda_thumbnail.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_thumbnail_permissions" {
  statement {
    sid       = "ReadOriginals"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.media.arn}/originals/*"]
  }
  statement {
    sid       = "WriteThumbnails"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.media.arn}/thumbnails/*"]
  }
}

resource "aws_iam_role_policy" "lambda_thumbnail" {
  name   = "${var.project_name}-lambda-thumbnail-policy"
  role   = aws_iam_role.lambda_thumbnail.id
  policy = data.aws_iam_policy_document.lambda_thumbnail_permissions.json
}

# ---------- Lambda: newsletter signup (API Gateway -> DynamoDB + SQS) ----------

resource "aws_iam_role" "lambda_newsletter" {
  name               = "${var.project_name}-lambda-newsletter-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_newsletter_logs" {
  role       = aws_iam_role.lambda_newsletter.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_newsletter_permissions" {
  statement {
    sid       = "StoreSubscriber"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.main.arn]
  }
  statement {
    sid       = "QueueWelcomeEmail"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.welcome_email.arn]
  }
}

resource "aws_iam_role_policy" "lambda_newsletter" {
  name   = "${var.project_name}-lambda-newsletter-policy"
  role   = aws_iam_role.lambda_newsletter.id
  policy = data.aws_iam_policy_document.lambda_newsletter_permissions.json
}

# ---------- Lambda: send welcome email (SQS -> SNS) ----------

resource "aws_iam_role" "lambda_welcome" {
  name               = "${var.project_name}-lambda-welcome-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_welcome_logs" {
  role       = aws_iam_role.lambda_welcome.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_welcome_permissions" {
  statement {
    sid       = "ConsumeQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.welcome_email.arn]
  }
  statement {
    sid       = "PublishWelcome"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }
}

resource "aws_iam_role_policy" "lambda_welcome" {
  name   = "${var.project_name}-lambda-welcome-policy"
  role   = aws_iam_role.lambda_welcome.id
  policy = data.aws_iam_policy_document.lambda_welcome_permissions.json
}
