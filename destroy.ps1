# Tears down all AWS resources created by the stack.
Set-Location $PSScriptRoot

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
            }
            Write-Host "  [OK] Exported AWS session credentials to environment for Terraform." -ForegroundColor Green
        }
    }
} catch {
    Write-Warning "Could not export AWS CLI session credentials automatically: $_"
}

Write-Host "==> Destroying AWS infrastructure..." -ForegroundColor Yellow
terraform -chdir=terraform destroy -auto-approve
Write-Host "Teardown complete. All billable resources removed." -ForegroundColor Green
