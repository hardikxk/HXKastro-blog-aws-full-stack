#!/usr/bin/env bash
# Run this when done. Every billed resource in this stack (EC2, Fargate, ALB,
# CloudFront, etc.) keeps running - and billing - until it's torn down.
set -euo pipefail
cd "$(dirname "$0")"

terraform -chdir=terraform destroy -auto-approve
echo "Everything torn down. Nothing left running or billing."
