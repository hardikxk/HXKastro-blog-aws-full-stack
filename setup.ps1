# One-click Windows setup: checks/installs prerequisites (Terraform, AWS CLI, Docker/Podman),
# handles AWS authentication, gathers project parameters, and invokes deploy.ps1.

[CmdletBinding()]
param(
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Write-Step ($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok ($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err ($msg)  { Write-Host "  [X] $msg" -ForegroundColor Red }

Write-Step "System check"
Write-Host "  OS: Windows PowerShell $($PSVersionTable.PSVersion)"

# 1. Container Tool (Docker or Podman)
Write-Step "Container Engine"
$containerTool = ""
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $containerTool = "docker"
    Write-Ok "Found Docker: $(docker --version)"
} elseif (Get-Command podman -ErrorAction SilentlyContinue) {
    $containerTool = "podman"
    Write-Ok "Found Podman: $(podman --version)"
} else {
    Write-Warn "Neither Docker nor Podman found in PATH."
    Write-Host "  Attempting to install Podman via winget..."
    winget install -e --id RedHat.Podman --silent --accept-package-agreements --accept-source-agreements
    if (Get-Command podman -ErrorAction SilentlyContinue) {
        $containerTool = "podman"
        Write-Ok "Podman installed successfully."
    } else {
        Write-Err "Could not find or install container runtime. Please install Docker or Podman."
        exit 1
    }
}

# 2. Terraform
Write-Step "Terraform"
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    # Check default install locations or winget
    $tfPaths = @("C:\Program Files\Terraform\terraform.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*\terraform.exe")
    $foundTf = Resolve-Path $tfPaths -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($foundTf) {
        $env:Path = (Split-Path $foundTf.Path) + ";" + $env:Path
    }
}

if (Get-Command terraform -ErrorAction SilentlyContinue) {
    Write-Ok "Terraform already installed: $(terraform version | Select-Object -First 1)"
} else {
    Write-Host "  Installing Terraform via winget..."
    winget install -e --id Hashicorp.Terraform --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + $env:Path
    if (Get-Command terraform -ErrorAction SilentlyContinue) {
        Write-Ok "Terraform installed."
    } else {
        # Check common winget package location
        $foundTf = Resolve-Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*\*\terraform.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundTf) {
            $env:Path = (Split-Path $foundTf.Path) + ";" + $env:Path
            Write-Ok "Terraform installed and loaded."
        } else {
            Write-Err "Could not auto-install Terraform. Install via: winget install -e --id Hashicorp.Terraform"
            exit 1
        }
    }
}

# 3. AWS CLI
Write-Step "AWS CLI"
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    $awsPaths = @("C:\Program Files\Amazon\AWSCLIV2\aws.exe", "C:\Program Files (x86)\Amazon\AWSCLIV2\aws.exe")
    $foundAws = Resolve-Path $awsPaths -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($foundAws) {
        $env:Path = (Split-Path $foundAws.Path) + ";" + $env:Path
    }
}

if (Get-Command aws -ErrorAction SilentlyContinue) {
    Write-Ok "AWS CLI already installed: $(aws --version)"
} else {
    Write-Host "  Installing AWS CLI v2 via winget..."
    winget install -e --id Amazon.AWSCLI --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + $env:Path
    if (Get-Command aws -ErrorAction SilentlyContinue) {
        Write-Ok "AWS CLI installed."
    } else {
        $foundAws = Resolve-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundAws) {
            $env:Path = (Split-Path $foundAws.Path) + ";" + $env:Path
            Write-Ok "AWS CLI installed and loaded."
        } else {
            Write-Err "Could not auto-install AWS CLI. Install via: winget install -e --id Amazon.AWSCLI"
            exit 1
        }
    }
}

# 4. AWS Authentication
Write-Step "AWS Authentication"
$identity = $null
try {
    $identity = aws sts get-caller-identity --output json 2>$null | ConvertFrom-Json
} catch {}

if ($identity -and $identity.Account) {
    Write-Ok "Already authenticated (Account: $($identity.Account), ARN: $($identity.Arn))"
} else {
    Write-Host "  No working AWS credentials found."
    Write-Host ""
    Write-Host "  What kind of AWS credentials are you using?"
    Write-Host "    1) Standard AWS credentials (Access Key + Secret Key)"
    Write-Host "    2) Temporary session credentials (Access Key + Secret + Session Token)"
    $accountKind = Read-Host "  Enter 1 or 2"

    if ($accountKind -eq "2") {
        Write-Host ""
        Write-Host "  Paste your session credentials below:"
        $ak = Read-Host "  Access Key ID"
        $sk = Read-Host "  Secret Access Key" -AsSecureString
        $skBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sk)
        $skPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($skBSTR)

        $st = Read-Host "  Session Token" -AsSecureString
        $stBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($st)
        $stPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($stBSTR)

        $reg = Read-Host "  Region [us-east-1]"
        if (-not $reg) { $reg = "us-east-1" }

        aws configure set aws_access_key_id $ak
        aws configure set aws_secret_access_key $skPlain
        aws configure set aws_session_token $stPlain
        aws configure set region $reg
        aws configure set output json
    } else {
        Write-Host ""
        Write-Host "  Running 'aws configure' for personal account setup..."
        aws configure
    }

    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-Ok "Authenticated successfully (Account: $($identity.Account))"
    } catch {
        Write-Err "Authentication failed. Please verify credentials."
        exit 1
    }
}

# 5. Project Configuration (terraform.tfvars)
Write-Step "Project Configuration"
if (Test-Path "terraform\terraform.tfvars") {
    Write-Ok "terraform\terraform.tfvars already exists. (Delete it to reconfigure)"
} else {
    $reg = Read-Host "  AWS Region [us-east-1]"
    if (-not $reg) { $reg = "us-east-1" }

    $proj = Read-Host "  Project name prefix [astro-blog]"
    if (-not $proj) { $proj = "astro-blog" }

    $email = Read-Host "  Email for SNS notifications on comments/subscribers (optional, enter to skip)"

    $tfvars = @"
aws_region                = "$reg"
project_name              = "$proj"
admin_notification_email  = "$email"
"@
    Set-Content -Path "terraform\terraform.tfvars" -Value $tfvars
    Write-Ok "Created terraform\terraform.tfvars"
}

# 6. Deploy Prompt
Write-Step "Ready to deploy"
Write-Host "  This will provision real AWS resources (EC2, Fargate, ALB, DynamoDB, S3, Lambda, etc.)"
if (-not $Yes) {
    $confirm = Read-Host "  Type 'deploy' to proceed with deployment"
    if ($confirm -ne "deploy") {
        Write-Host "  Deployment cancelled."
        exit 0
    }
}

& "$PSScriptRoot\deploy.ps1"
