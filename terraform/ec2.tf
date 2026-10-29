data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "blog" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.ec2_instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    aws_region           = var.aws_region
    ecr_repo_url         = aws_ecr_repository.blog_app.repository_url
    image_tag            = var.blog_image_tag
    container_port       = var.container_port
    dynamodb_table       = aws_dynamodb_table.main.name
    s3_bucket            = aws_s3_bucket.media.bucket
    newsletter_api_url   = "${aws_apigatewayv2_api.main.api_endpoint}/subscribe"
    cognito_user_pool_id = aws_cognito_user_pool.admin.id
    cognito_client_id    = aws_cognito_user_pool_client.admin.id
    media_cdn_url        = "https://${aws_cloudfront_distribution.media.domain_name}"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-ec2"
      Project = var.project_name
    }
  }
}

resource "aws_autoscaling_group" "blog" {
  name                      = "${var.project_name}-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = aws_subnet.public[*].id
  target_group_arns         = [aws_lb_target_group.blog.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 90

  launch_template {
    id      = aws_launch_template.blog.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ec2"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project_name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.blog.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}
