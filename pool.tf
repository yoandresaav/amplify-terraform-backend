
### Cognito user pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "file_upload_user_pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # User verification (email, SMS, etc.)
  verification_message_template {
    email_message = "Your verification code is {####}"
    email_subject = "Verify your email"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }
}


resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "file_upload_user_pool_client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  # Prevents exposing client secret
  generate_secret = false
  refresh_token_validity = 90
  prevent_user_existence_errors = "ENABLED"

  # Authentication flows allowed
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain   = "file-upload-user-pool-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}
