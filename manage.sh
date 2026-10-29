#!/usr/bin/env bash
# Astro Blog on AWS Full Stack - Interactive Management Utility (Bash)
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$1"; }
err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$1"; }

RUNNER="npm"
if command -v bun >/dev/null 2>&1; then RUNNER="bun"; fi

run_dev() {
  step "Starting Local Dev Server ($RUNNER)"
  $RUNNER run dev
}

run_build() {
  step "Testing Production Build ($RUNNER)"
  $RUNNER run build
}

run_setup() {
  step "Running One-Click AWS Setup"
  ./setup.sh
}

run_deploy() {
  step "Deploying Infrastructure to AWS"
  ./deploy.sh
}

run_status() {
  step "Infrastructure Status"
  BLOG_URL=$(terraform -chdir=terraform output -raw blog_url 2>/dev/null || true)
  MEDIA_CDN=$(terraform -chdir=terraform output -raw media_cdn_url 2>/dev/null || true)
  NEWSLETTER=$(terraform -chdir=terraform output -raw newsletter_signup_endpoint 2>/dev/null || true)
  echo "Blog URL:    $BLOG_URL"
  echo "Media CDN:   $MEDIA_CDN"
  echo "Newsletter:  $NEWSLETTER"

  if [[ -n "$BLOG_URL" ]]; then
    echo
    warn "Probing ALB endpoint health ($BLOG_URL)..."
    if curl -s -f -m 5 -o /dev/null "$BLOG_URL"; then
      ok "ALB and EC2 blog app are HEALTHY and responding with HTTP 200!"
    else
      warn "Endpoint not responding with HTTP 200 yet. Instances may still be starting up."
    fi
  fi
}

run_logs() {
  step "Recent CloudWatch Logs (ECS Comments API)"
  aws logs tail "/ecs/astro-blog-comments-api" --since 30m || true
}

run_create_user() {
  step "Create Cognito Admin User"
  POOL_ID=$(terraform -chdir=terraform output -raw cognito_user_pool_id 2>/dev/null || true)
  if [[ -z "$POOL_ID" ]]; then
    err "Cognito User Pool not found. Deploy first."
    return
  fi
  read -rp "Admin username [admin]: " USERNAME
  USERNAME="${USERNAME:-admin}"
  read -rp "Admin email: " EMAIL
  read -rp "Admin password [DemoPassword123!]: " PASSWORD
  PASSWORD="${PASSWORD:-DemoPassword123!}"

  aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username "$USERNAME" --user-attributes Name=email,Value="$EMAIL" --message-action SUPPRESS
  aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" --username "$USERNAME" --password "$PASSWORD" --permanent
  ok "Admin user created! Log in at http://<ALB_URL>/admin"
}

run_seed() {
  step "Seeding DynamoDB with Sample Posts"
  TABLE=$(terraform -chdir=terraform output -raw dynamodb_table_name 2>/dev/null || true)
  REGION=$(terraform -chdir=terraform output -raw aws_region 2>/dev/null || true)
  if [[ -z "$TABLE" ]]; then
    err "DynamoDB table not found. Deploy first."
    return
  fi
  AWS_REGION="$REGION" DYNAMODB_TABLE="$TABLE" node scripts/seed.mjs
  ok "DynamoDB seeded."
}

run_destroy() {
  step "Tearing Down AWS Stack"
  read -rp "Type 'destroy' to confirm teardown: " CONFIRM
  if [[ "$CONFIRM" == "destroy" ]]; then
    ./destroy.sh
  else
    warn "Aborted."
  fi
}

show_menu() {
  while true; do
    echo "========================================================"
    echo "  Astro Blog on AWS Full Stack - Management Console"
    echo "========================================================"
    echo "  [1] Run Local Development Server"
    echo "  [2] Test Production Build"
    echo "  [3] One-Click Setup & Deploy"
    echo "  [4] View Live Infrastructure Status"
    echo "  [5] Create Admin User in Amazon Cognito"
    echo "  [6] Seed Sample Posts into Amazon DynamoDB"
    echo "  [7] Stream ECS Fargate CloudWatch Logs"
    echo "  [8] Teardown / Destroy Entire Stack"
    echo "  [q] Quit"
    echo "--------------------------------------------------------"
    read -rp "Choose an option (1-8 or q): " CHOICE
    case "$CHOICE" in
      1) run_dev ;;
      2) run_build ;;
      3) run_setup ;;
      4) run_status ;;
      5) run_create_user ;;
      6) run_seed ;;
      7) run_logs ;;
      8) run_destroy ;;
      q|Q) echo "Goodbye!"; exit 0 ;;
      *) warn "Invalid selection" ;;
    esac
    echo
    read -rp "Press Enter to continue..."
  done
}

ACTION="${1:-menu}"
case "$ACTION" in
  dev) run_dev ;;
  build) run_build ;;
  setup) run_setup ;;
  deploy) run_deploy ;;
  status) run_status ;;
  create-user) run_create_user ;;
  seed) run_seed ;;
  logs) run_logs ;;
  destroy) run_destroy ;;
  *) show_menu ;;
esac
