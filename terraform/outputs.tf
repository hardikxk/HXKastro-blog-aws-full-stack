output "aws_region" {
  value = var.aws_region
}

output "blog_url" {
  description = "Main entrypoint - the blog, comments API (/api/*), everything"
  value       = "http://${aws_lb.main.dns_name}"
}

output "media_cdn_url" {
  description = "CloudFront URL for blog media (images/thumbnails)"
  value       = "https://${aws_cloudfront_distribution.media.domain_name}"
}

output "newsletter_signup_endpoint" {
  value = "${aws_apigatewayv2_api.main.api_endpoint}/subscribe"
}

output "ecr_blog_app_repository_url" {
  value = aws_ecr_repository.blog_app.repository_url
}

output "ecr_comments_api_repository_url" {
  value = aws_ecr_repository.comments_api.repository_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "s3_media_bucket" {
  value = aws_s3_bucket.media.bucket
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_comments_api_service_name" {
  value = aws_ecs_service.comments_api.name
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.blog.name
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.admin.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.admin.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.notifications.arn
}
