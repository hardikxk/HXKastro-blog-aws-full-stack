# Protects the blog's admin routes (create/edit posts). Provisions
# the Cognito user pool and app client.
resource "aws_cognito_user_pool" "admin" {
  name = "${var.project_name}-admin-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  tags = { Project = var.project_name }
}

resource "aws_cognito_user_pool_client" "admin" {
  name         = "${var.project_name}-admin-client"
  user_pool_id = aws_cognito_user_pool.admin.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}
