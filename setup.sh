#!/usr/bin/env bash
# One-click setup: installs Terraform/Docker/AWS CLI if missing, gets you
# authenticated to AWS, collects a few config values, then hands off to
# ./deploy.sh. Safe to re-run - it skips anything already done.
set -euo pipefail
cd "$(dirname "$0")"

AUTO_YES=false
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && AUTO_YES=true

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$1"; }
err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$1"; }
has()  { command -v "$1" >/dev/null 2>&1; }

if [[ ! -f Dockerfile || ! -d terraform ]]; then
  err "Run this from the project root (the folder containing Dockerfile and terraform/)."
  exit 1
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

pkg_mgr=""
if has apt-get; then pkg_mgr="apt"
elif has dnf; then pkg_mgr="dnf"
elif has brew; then pkg_mgr="brew"
fi

step "System check"
echo "  OS: $OS   Arch: $ARCH   Package manager: ${pkg_mgr:-none detected}"

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
step "Terraform"
if has terraform; then
  ok "already installed ($(terraform version | head -1))"
else
  echo "  Installing..."
  case "$pkg_mgr" in
    apt)
      sudo apt-get update -y
      sudo apt-get install -y gnupg software-properties-common curl unzip lsb-release
      curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
      sudo apt-get update -y
      sudo apt-get install -y terraform
      ;;
    dnf)
      sudo dnf install -y dnf-plugins-core
      sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
      sudo dnf install -y terraform
      ;;
    brew)
      brew tap hashicorp/tap
      brew install hashicorp/tap/terraform
      ;;
    *)
      TF_VERSION="1.9.8"
      case "$ARCH" in
        x86_64) TF_ARCH="amd64" ;;
        arm64|aarch64) TF_ARCH="arm64" ;;
        *) err "Unsupported architecture for auto-install. Install manually: https://developer.hashicorp.com/terraform/install"; exit 1 ;;
      esac
      TF_OS="linux"; [[ "$OS" == "Darwin" ]] && TF_OS="darwin"
      curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${TF_OS}_${TF_ARCH}.zip"
      unzip -oq /tmp/terraform.zip -d /tmp
      sudo mv /tmp/terraform /usr/local/bin/terraform
      ;;
  esac
  has terraform && ok "installed ($(terraform version | head -1))" \
    || { err "install failed - see https://developer.hashicorp.com/terraform/install"; exit 1; }
fi

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------
step "Docker"
if ! has docker; then
  echo "  Installing..."
  case "$pkg_mgr" in
    apt)
      sudo apt-get update -y
      sudo apt-get install -y docker.io
      sudo systemctl enable docker
      sudo systemctl start docker
      sudo usermod -aG docker "$USER" || true
      warn "Added $USER to the docker group - if docker commands below fail with a permission error, run 'newgrp docker' or log out/in, then re-run this script."
      ;;
    dnf)
      sudo dnf install -y docker
      sudo systemctl enable docker
      sudo systemctl start docker
      sudo usermod -aG docker "$USER" || true
      ;;
    brew)
      brew install --cask docker
      warn "Docker Desktop was installed - launching it now. Wait until its icon shows 'running', then re-run this script."
      open -a Docker 2>/dev/null || true
      exit 0
      ;;
    *)
      err "Could not auto-install Docker. Install it manually: https://docs.docker.com/get-docker/"
      exit 1
      ;;
  esac
else
  ok "already installed"
fi

if ! docker info >/dev/null 2>&1; then
  warn "Docker is installed but the daemon isn't responding yet."
  [[ "$OS" == "Linux" ]] && { sudo systemctl start docker || true; sleep 3; }
  if ! docker info >/dev/null 2>&1; then
    err "Docker daemon still unreachable. On macOS, open Docker Desktop and wait for it to finish starting, then re-run this script."
    exit 1
  fi
fi
ok "Docker daemon is running"

# ---------------------------------------------------------------------------
# AWS CLI v2
# ---------------------------------------------------------------------------
step "AWS CLI"
need_install=true
if has aws && [[ "$(aws --version 2>&1)" == aws-cli/2* ]]; then
  ok "AWS CLI v2 already installed ($(aws --version 2>&1))"
  need_install=false
elif has aws; then
  warn "Found $(aws --version 2>&1) - this project needs v2. Upgrading."
fi

if $need_install; then
  case "$OS" in
    Linux)
      case "$ARCH" in
        x86_64) AWS_PKG="awscli-exe-linux-x86_64.zip" ;;
        aarch64|arm64) AWS_PKG="awscli-exe-linux-aarch64.zip" ;;
        *) err "Unsupported architecture. Install manually: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"; exit 1 ;;
      esac
      curl -fsSLo /tmp/awscliv2.zip "https://awscli.amazonaws.com/$AWS_PKG"
      unzip -oq /tmp/awscliv2.zip -d /tmp
      sudo /tmp/aws/install --update
      ;;
    Darwin)
      if has brew; then
        brew install awscli
      else
        curl -fsSLo /tmp/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
        sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
      fi
      ;;
    *)
      err "Unsupported OS for auto-install. Install manually: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
      exit 1
      ;;
  esac
  has aws && ok "installed ($(aws --version 2>&1))" || { err "AWS CLI install failed"; exit 1; }
fi

# ---------------------------------------------------------------------------
# AWS authentication
# ---------------------------------------------------------------------------
step "AWS authentication"

if aws sts get-caller-identity >/dev/null 2>&1; then
  acct=$(aws sts get-caller-identity --query Account --output text)
  ok "Already authenticated (account $acct)"
else
  echo "  No working AWS credentials found."
  echo
  echo "  What kind of AWS credentials are you using?"
  echo "    1) Standard AWS credentials (Access Key + Secret Key)"
  echo "    2) Temporary session credentials (Access Key + Secret Key + Session Token)"
  read -rp "  Enter 1 or 2: " account_kind

  if [[ "$account_kind" == "2" ]]; then
    echo
    echo "  Paste your session credentials below:"
    read -rp "  Access Key ID: " ak
    read -rsp "  Secret Access Key: " sk; echo
    read -rsp "  Session Token: " st; echo
    read -rp "  Region [us-east-1]: " region
    region="${region:-us-east-1}"

    aws configure set aws_access_key_id "$ak"
    aws configure set aws_secret_access_key "$sk"
    aws configure set aws_session_token "$st"
    aws configure set region "$region"
    aws configure set output json

    warn "Temporary session credentials expire periodically. If a step fails with an expired token, re-run this script with fresh credentials."
  else
    echo
    echo "  Running 'aws configure' for standard credentials setup..."
    read -rp "  Press Enter when ready..." _
    aws configure
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    err "Still can't authenticate. Double-check what you entered and re-run this script."
    exit 1
  fi
  acct=$(aws sts get-caller-identity --query Account --output text)
  ok "Authenticated (account $acct)"
fi

# ---------------------------------------------------------------------------
# Soft permission check (informational only - never blocks on its own)
# ---------------------------------------------------------------------------
step "Permission check"
if aws iam list-roles --max-items 1 >/dev/null 2>&1; then
  ok "IAM role listing verified - custom role management ready"
else
  warn "Could not verify IAM role listing permissions. Ensure your AWS credentials have permission to create and attach IAM roles."
  if ! $AUTO_YES; then
    read -rp "  Continue anyway? [y/N] " cont
    [[ "$cont" =~ ^[Yy]$ ]] || exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Project configuration
# ---------------------------------------------------------------------------
step "Project configuration"
if [[ -f terraform/terraform.tfvars ]]; then
  ok "terraform/terraform.tfvars already exists - using it. Delete it and re-run to reconfigure."
else
  read -rp "  AWS region [us-east-1]: " region_in
  region_in="${region_in:-us-east-1}"
  read -rp "  Project name prefix [astro-blog]: " project_in
  project_in="${project_in:-astro-blog}"
  read -rp "  Email for SNS notifications on new comments/signups (blank to skip): " email_in

  cat > terraform/terraform.tfvars <<TFVARS
aws_region                = "${region_in}"
project_name              = "${project_in}"
admin_notification_email  = "${email_in}"
TFVARS
  ok "Wrote terraform/terraform.tfvars"
fi

# ---------------------------------------------------------------------------
# Optional budget alert
# ---------------------------------------------------------------------------
step "Cost safety net (optional)"
budget_in="n"
if ! $AUTO_YES; then
  read -rp "  Create a \$5 AWS Budget alert emailed to you? [y/N] " budget_in
fi
if [[ "$budget_in" =~ ^[Yy]$ ]]; then
  read -rp "  Email for the budget alert: " budget_email
  account_id=$(aws sts get-caller-identity --query Account --output text)
  cat > /tmp/budget.json <<JSON
{"BudgetName": "astro-blog-demo", "BudgetLimit": {"Amount": "5", "Unit": "USD"}, "TimeUnit": "MONTHLY", "BudgetType": "COST"}
JSON
  cat > /tmp/budget-notifications.json <<JSON
[{"Notification": {"NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 80, "ThresholdType": "PERCENTAGE"}, "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "${budget_email}"}]}]
JSON
  if aws budgets create-budget --account-id "$account_id" \
      --budget file:///tmp/budget.json \
      --notifications-with-subscribers file:///tmp/budget-notifications.json >/dev/null 2>&1; then
    ok "Budget alert created - you'll get an email at 80% of \$5"
  else
    warn "Couldn't create the budget (often blocked on restricted/lab accounts) - skipping, not fatal"
  fi
fi

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
step "Ready to deploy"
echo "  This creates real, billable AWS resources: VPC, ALB, EC2, ECS/Fargate, Lambda,"
echo "  API Gateway, S3, CloudFront, DynamoDB, SNS, SQS, Cognito, CloudWatch."
echo "  See README.md -> 'Cost notes' for what that runs - typically well under \$1 for a demo."
if ! $AUTO_YES; then
  echo
  read -rp "  Type 'deploy' to continue: " confirm
  [[ "$confirm" == "deploy" ]] || { echo "  Aborted - nothing was created."; exit 0; }
fi

./deploy.sh
