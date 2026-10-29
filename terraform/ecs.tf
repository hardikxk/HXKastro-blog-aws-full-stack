resource "aws_cloudwatch_log_group" "comments_api" {
  name              = "/ecs/${var.project_name}-comments-api"
  retention_in_days = 3
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_ecs_task_definition" "comments_api" {
  family                   = "${var.project_name}-comments-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "comments-api"
      image     = "${aws_ecr_repository.comments_api.repository_url}:${var.comments_api_image_tag}"
      essential = true
      portMappings = [
        {
          containerPort = var.comments_api_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = tostring(var.comments_api_port) },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "DYNAMODB_TABLE", value = aws_dynamodb_table.main.name },
        { name = "SNS_TOPIC_ARN", value = aws_sns_topic.notifications.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.comments_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "comments-api"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "comments_api" {
  name            = "${var.project_name}-comments-api-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.comments_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true # no NAT Gateway in this VPC, so the task needs its own public IP to reach ECR/CloudWatch/DynamoDB
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.comments_api.arn
    container_name    = "comments-api"
    container_port    = var.comments_api_port
  }

  depends_on = [aws_lb_listener.http]
}
