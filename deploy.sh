#!/usr/bin/env bash
# Deploys the entire stack with no manual console steps:
# VPC, ALB, EC2 Auto Scaling Group, ECS/Fargate, Lambda x3, API Gateway,
# S3, CloudFront, DynamoDB, SNS, SQS, Cognito, IAM, CloudWatch.
set -euo pipefail
cd "$(dirname "$0")"

CONTAINER_TOOL="docker"
if ! command -v docker >/dev/null 2>&1 && command -v podman >/dev/null 2>&1; then
  CONTAINER_TOOL="podman"
fi
echo "==> Using container engine: $CONTAINER_TOOL"

echo "==> Step 1/6: installing npm dependencies"
npm ci || npm install
(cd comments-api && npm ci || npm install)

echo "==> Step 2/6: terraform init"
terraform -chdir=terraform init -input=false

echo "==> Step 3/6: creating ECR repositories first"
terraform -chdir=terraform apply -auto-approve \
  -target=aws_ecr_repository.blog_app \
  -target=aws_ecr_repository.comments_api

REGION=$(terraform -chdir=terraform output -raw aws_region)
BLOG_REPO=$(terraform -chdir=terraform output -raw ecr_blog_app_repository_url)
API_REPO=$(terraform -chdir=terraform output -raw ecr_comments_api_repository_url)
REGISTRY="${BLOG_REPO%%/*}"

echo "==> Logging in to ECR ($REGISTRY)"
aws ecr get-login-password --region "$REGION" | $CONTAINER_TOOL login --username AWS --password-stdin "$REGISTRY"

echo "==> Step 4/6: building and pushing blog app image"
$CONTAINER_TOOL build -t astro-blog-app:latest .
$CONTAINER_TOOL tag astro-blog-app:latest "${BLOG_REPO}:latest"
$CONTAINER_TOOL push "${BLOG_REPO}:latest"

echo "==> Step 5/6: building and pushing comments API image"
$CONTAINER_TOOL build -t comments-api:latest ./comments-api
$CONTAINER_TOOL tag comments-api:latest "${API_REPO}:latest"
$CONTAINER_TOOL push "${API_REPO}:latest"

echo "==> Step 6/6: applying complete AWS architecture"
terraform -chdir=terraform apply -auto-approve

echo "==> Seeding initial posts to DynamoDB..."
TABLE_NAME=$(terraform -chdir=terraform output -raw dynamodb_table_name 2>/dev/null || echo "astro-blog-table")
AWS_REGION="$REGION" DYNAMODB_TABLE="$TABLE_NAME" node scripts/seed.mjs || true

echo
echo "=========================================================="
echo " Deployed Successfully!"
echo " Blog URL:   $(terraform -chdir=terraform output -raw blog_url)"
echo " Media CDN:  $(terraform -chdir=terraform output -raw media_cdn_url)"
echo " Newsletter: $(terraform -chdir=terraform output -raw newsletter_signup_endpoint)"
echo "=========================================================="
echo "Note: EC2 takes ~2-3 min (boot + pull image), Fargate ~1-2 min."
echo "Run ./manage.sh status to check health."
