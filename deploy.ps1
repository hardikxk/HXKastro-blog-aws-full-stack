# Windows PowerShell deployment script:
# Installs dependencies, builds container images with Docker or Podman, pushes to ECR,
# applies Terraform, and seeds DynamoDB.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$containerTool = "docker"
if (-not (Get-Command docker -ErrorAction SilentlyContinue) -and (Get-Command podman -ErrorAction SilentlyContinue)) {
    $containerTool = "podman"
}
Write-Host "==> Using container engine: $containerTool" -ForegroundColor Cyan

$pkgTool = "npm"
if (Get-Command bun -ErrorAction SilentlyContinue) {
    $pkgTool = "bun"
} elseif (Test-Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe\bun-windows-x64\bun.exe") {
    $env:Path = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe\bun-windows-x64;" + $env:Path
    $pkgTool = "bun"
}

Write-Host "==> Step 1/6: Installing dependencies using $pkgTool" -ForegroundColor Cyan
if ($pkgTool -eq "bun") {
    bun install
    Push-Location comments-api
    bun install
    Pop-Location
} else {
    npm install
    Push-Location comments-api
    npm install
    Pop-Location
}

Write-Host "==> Step 2/6: Initializing Terraform" -ForegroundColor Cyan
# Automatically export active AWS CLI session credentials into environment variables for Terraform
try {
    $credsRaw = (aws configure export-credentials --format process 2>$null) | Out-String
    if ($credsRaw) {
        $credsJson = $credsRaw | ConvertFrom-Json
        if ($credsJson -and $credsJson.AccessKeyId) {
            $env:AWS_ACCESS_KEY_ID = $credsJson.AccessKeyId
            $env:AWS_SECRET_ACCESS_KEY = $credsJson.SecretAccessKey
            if ($credsJson.SessionToken) {
                $env:AWS_SESSION_TOKEN = $credsJson.SessionToken
            } else {
                Remove-Item env:AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
            }
            Write-Host "  [OK] Exported AWS credentials to environment for Terraform." -ForegroundColor Green
        }
    }
} catch {
    Write-Warning "Could not export AWS CLI session credentials automatically: $_"
}

terraform -chdir=terraform init -input=false

Write-Host "==> Step 3/6: Creating ECR repositories" -ForegroundColor Cyan
& terraform -chdir=terraform apply -auto-approve "-target=aws_ecr_repository.blog_app" "-target=aws_ecr_repository.comments_api"

# Region isn't in terraform output yet (only ECR was targeted), so read from tfvars
$region = (Select-String -Path terraform\terraform.tfvars -Pattern 'aws_region\s*=\s*"([^"]+)"').Matches.Groups[1].Value
if (-not $region) { $region = "ap-southeast-2" }  # fallback
$blogRepo = (terraform -chdir=terraform output -raw ecr_blog_app_repository_url 2>$null)
$apiRepo  = (terraform -chdir=terraform output -raw ecr_comments_api_repository_url 2>$null)
if (-not $blogRepo -or -not $apiRepo) {
    Write-Error "Failed to retrieve ECR repository URLs from Terraform output."
    exit 1
}
$blogRepo = $blogRepo.Trim()
$apiRepo  = $apiRepo.Trim()
$registry = $blogRepo.Split('/')[0]

Write-Host "==> Authenticating $containerTool with ECR ($registry)" -ForegroundColor Cyan
$ecrPassword = (aws ecr get-login-password --region $region)
& $containerTool login --username AWS --password $ecrPassword $registry

Write-Host "==> Step 4/6: Building and pushing blog app image" -ForegroundColor Cyan
& $containerTool build -t astro-blog-app:latest .
& $containerTool tag astro-blog-app:latest "${blogRepo}:latest"
& $containerTool push "${blogRepo}:latest"

Write-Host "==> Step 5/6: Building and pushing comments API image" -ForegroundColor Cyan
& $containerTool build -t comments-api:latest ./comments-api
& $containerTool tag comments-api:latest "${apiRepo}:latest"
& $containerTool push "${apiRepo}:latest"

Write-Host "==> Step 6/6: Deploying full infrastructure" -ForegroundColor Cyan
terraform -chdir=terraform apply -auto-approve

Write-Host "==> Seeding initial DynamoDB posts..." -ForegroundColor Cyan
try {
    $table = (terraform -chdir=terraform output -raw dynamodb_table_name).Trim()
    $env:AWS_REGION = $region
    $env:DYNAMODB_TABLE = $table
    node scripts/seed.mjs
} catch {
    Write-Warning "Could not seed DynamoDB automatically: $_"
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " Deployment Complete!" -ForegroundColor Green
Write-Host " Blog URL:   $(terraform -chdir=terraform output -raw blog_url)"
Write-Host " Media CDN:  $(terraform -chdir=terraform output -raw media_cdn_url)"
Write-Host " Newsletter: $(terraform -chdir=terraform output -raw newsletter_signup_endpoint)"
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Note: EC2 takes ~2-3 min (boot + pull image), Fargate ~1-2 min."
Write-Host "Run .\manage.ps1 status to check target health."
