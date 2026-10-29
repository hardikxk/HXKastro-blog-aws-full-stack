#!/bin/bash
set -e

dnf install -y docker
systemctl enable docker
systemctl start docker

aws ecr get-login-password --region ${aws_region} \
  | docker login --username AWS --password-stdin "$(echo ${ecr_repo_url} | cut -d/ -f1)"

docker pull ${ecr_repo_url}:${image_tag}

docker run -d --restart unless-stopped \
  -p ${container_port}:${container_port} \
  -e PORT=${container_port} \
  -e HOST=0.0.0.0 \
  -e AWS_REGION=${aws_region} \
  -e DYNAMODB_TABLE=${dynamodb_table} \
  -e S3_MEDIA_BUCKET=${s3_bucket} \
  -e NEWSLETTER_API_URL=${newsletter_api_url} \
  -e COGNITO_USER_POOL_ID=${cognito_user_pool_id} \
  -e COGNITO_CLIENT_ID=${cognito_client_id} \
  -e MEDIA_CDN_URL=${media_cdn_url} \
  ${ecr_repo_url}:${image_tag}
