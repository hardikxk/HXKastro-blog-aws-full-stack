<#
.SYNOPSIS
    Astro Blog on AWS Full Stack - Interactive Management Utility
.DESCRIPTION
    Provides a unified CLI for managing local testing, AWS deployment,
    health checks, Cognito user creation, DynamoDB seeding, and teardown.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("menu", "dev", "build", "deploy", "setup", "status", "create-user", "seed", "logs", "destroy")]
    [string]$Action = "menu"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Write-Header ($text) {
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor White
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Write-Success ($text) { Write-Host "  [OK] $text" -ForegroundColor Green }
function Write-Warn ($text)    { Write-Host "  [!]  $text" -ForegroundColor Yellow }
function Write-ErrorMsg ($text){ Write-Host "  [X]  $text" -ForegroundColor Red }

function Get-PackageRunner {
    if (Get-Command bun -ErrorAction SilentlyContinue) { return "bun" }
    
    # Auto-detect if bun was just installed in User AppData or WinGet
    $bunWinget = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe\bun-windows-x64\bun.exe"
    if (Test-Path $bunWinget) {
        $env:Path = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe\bun-windows-x64;" + $env:Path
        return "bun"
    }
    return "npm"
}

function Run-Dev {
    Write-Header "Starting Local Development Server"
    $runner = Get-PackageRunner
    Write-Host "Using $runner to run dev server on http://localhost:4321..." -ForegroundColor Yellow
    if ($runner -eq "bun") {
        bun dev
    } else {
        npm run dev
    }
}

function Run-Build {
    Write-Header "Testing Production Build"
    $runner = Get-PackageRunner
    Write-Host "Running build via $runner..." -ForegroundColor Yellow
    if ($runner -eq "bun") {
        bun run build
    } else {
        npm run build
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Build completed successfully! Server bundle in dist/server/entry.mjs"
    } else {
        Write-ErrorMsg "Build failed. Check error output above."
    }
}

function Run-Setup {
    Write-Header "Running One-Click AWS Setup"
    & "$PSScriptRoot\setup.ps1"
}

function Run-Deploy {
    Write-Header "Deploying Infrastructure to AWS"
    & "$PSScriptRoot\deploy.ps1"
}

function Run-Status {
    Write-Header "Deployed Infrastructure Status"
    try {
        $blogUrl = (terraform -chdir=terraform output -raw blog_url 2>$null).Trim()
        $mediaCdn = (terraform -chdir=terraform output -raw media_cdn_url 2>$null).Trim()
        $newsletter = (terraform -chdir=terraform output -raw newsletter_signup_endpoint 2>$null).Trim()

        Write-Host "Blog URL:    $blogUrl"
        Write-Host "Media CDN:   $mediaCdn"
        Write-Host "Newsletter:  $newsletter"

        if ($blogUrl) {
            Write-Host "`nProbing ALB endpoint health ($blogUrl)..." -ForegroundColor Yellow
            $resp = Invoke-WebRequest -Uri $blogUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($resp.StatusCode -eq 200) {
                Write-Success "ALB and EC2 blog app are HEALTHY and responding with HTTP 200!"
            } else {
                Write-Warn "ALB returned HTTP $($resp.StatusCode). Instances may still be starting up."
            }
        }
    } catch {
        Write-Warn "Endpoint not reachable yet. Instances may still be bootstrapping."
    }
}

function Run-CreateAdminUser {
    Write-Header "Create Cognito Admin User"
    try {
        $poolId = (terraform -chdir=terraform output -raw cognito_user_pool_id 2>$null).Trim()
        if (-not $poolId) {
            Write-ErrorMsg "Cognito User Pool not found in Terraform outputs. Has the stack been deployed?"
            return
        }

        Write-Host "Target User Pool: $poolId" -ForegroundColor Yellow
        $username = Read-Host "Enter admin username [admin]"
        if (-not $username) { $username = "admin" }

        $email = Read-Host "Enter admin email address"
        if (-not $email) {
            Write-ErrorMsg "Email is required for Cognito user creation."
            return
        }

        $password = Read-Host "Enter temporary password (min 8 chars, 1 uppercase, 1 lowercase, 1 number) [DemoPassword123!]"
        if (-not $password) { $password = "DemoPassword123!" }

        Write-Host "Creating user '$username'..." -ForegroundColor Cyan
        aws cognito-idp admin-create-user `
            --user-pool-id $poolId `
            --username $username `
            --user-attributes Name=email,Value=$email `
            --message-action SUPPRESS

        Write-Host "Setting permanent password..." -ForegroundColor Cyan
        aws cognito-idp admin-set-user-password `
            --user-pool-id $poolId `
            --username $username `
            --password $password `
            --permanent

        Write-Success "Admin user created successfully!"
        Write-Host "You can now log in at: http://<ALB_URL>/admin with username: $username" -ForegroundColor Green
    } catch {
        Write-ErrorMsg "Failed to create Cognito user: $_"
    }
}

function Run-Seed {
    Write-Header "Seeding DynamoDB with Sample Posts"
    try {
        $table = (terraform -chdir=terraform output -raw dynamodb_table_name 2>$null).Trim()
        $region = (terraform -chdir=terraform output -raw aws_region 2>$null).Trim()
        if (-not $table) {
            Write-ErrorMsg "DynamoDB Table not found. Please deploy first."
            return
        }
        $env:AWS_REGION = $region
        $env:DYNAMODB_TABLE = $table
        node scripts/seed.mjs
        Write-Success "DynamoDB seeded."
    } catch {
        Write-ErrorMsg "Failed to seed DynamoDB: $_"
    }
}

function Run-Logs {
    Write-Header "Recent CloudWatch Logs (ECS Comments API)"
    try {
        $logGroup = "/ecs/astro-blog-comments-api"
        Write-Host "Fetching last 20 log events from $logGroup..." -ForegroundColor Yellow
        aws logs tail $logGroup --since 30m
    } catch {
        Write-ErrorMsg "Could not retrieve logs: $_"
    }
}

function Run-Destroy {
    Write-Header "Tear Down AWS Infrastructure"
    Write-Warn "This will DESTROY ALL resources (ALB, EC2, Fargate, S3, DynamoDB) to avoid charges."
    $confirm = Read-Host "Type 'destroy' to confirm teardown"
    if ($confirm -eq "destroy") {
        & "$PSScriptRoot\destroy.ps1"
    } else {
        Write-Host "Teardown aborted." -ForegroundColor Yellow
    }
}

function Show-Menu {
    while ($true) {
        Write-Header "Astro Blog on AWS Full Stack - Management Console"
        Write-Host "  [1] Run Local Development Server (http://localhost:4321)"
        Write-Host "  [2] Test Production Build (npm / bun run build)"
        Write-Host "  [3] One-Click Setup & Deploy (setup.ps1 -> deploy.ps1)"
        Write-Host "  [4] View Live Infrastructure Status & Endpoints"
        Write-Host "  [5] Create Admin User in Amazon Cognito"
        Write-Host "  [6] Seed Sample Posts into Amazon DynamoDB"
        Write-Host "  [7] Stream ECS Fargate CloudWatch Logs"
        Write-Host "  [8] Teardown / Destroy Entire Stack (Avoid AWS Costs)"
        Write-Host "  [Q] Quit"
        Write-Host "--------------------------------------------------------"

        $choice = (Read-Host "Choose an option (1-8 or Q)").Trim().ToUpper()

        switch ($choice) {
            "1" { Run-Dev }
            "2" { Run-Build }
            "3" { Run-Setup }
            "4" { Run-Status }
            "5" { Run-CreateAdminUser }
            "6" { Run-Seed }
            "7" { Run-Logs }
            "8" { Run-Destroy }
            "Q" { Write-Host "Goodbye!`n"; return }
            default { Write-Warn "Invalid choice. Please pick 1-8 or Q." }
        }

        Write-Host "`nPress Enter to return to menu..."
        [void][System.Console]::ReadLine()
    }
}

# Dispatcher
switch ($Action) {
    "dev"         { Run-Dev }
    "build"       { Run-Build }
    "setup"       { Run-Setup }
    "deploy"      { Run-Deploy }
    "status"      { Run-Status }
    "create-user" { Run-CreateAdminUser }
    "seed"        { Run-Seed }
    "logs"        { Run-Logs }
    "destroy"     { Run-Destroy }
    default       { Show-Menu }
}
