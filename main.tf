# Set aws provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-2"
}


# Create an S3 bucket for file uploads and save assembled files
resource "aws_s3_bucket" "file_upload_bucket" {
  bucket = "our-file-upload-bucket-1" # Change this to a unique name due to aws time to release this resource
}

# Create a DynamoDB table to store file chunks
resource "aws_dynamodb_table" "chunks_table" {
  name         = "chunksTable"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key     = "FileId"

  attribute {
    name = "FileId"
    type = "S"
  }
}

resource "aws_lambda_function" "file_upload_lambda" {
  filename      = "file_upload_lambda.zip"
  function_name = "file_upload_lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "file_upload_lambda.handler"
  runtime       = "python3.10"

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.file_upload_bucket.bucket
      TABLE_NAME  = aws_dynamodb_table.chunks_table.name
      USER_POOL_ID = aws_cognito_user_pool.user_pool.id
    }
  }
}

resource "aws_lambda_function" "file_assembly_lambda" {
  filename      = "file_assembly_lambda.zip"
  function_name = "file_assembly_lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.10"

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.file_upload_bucket.bucket
      TABLE_NAME  = aws_dynamodb_table.chunks_table.name
    }
  }
}

# Create an API Gateway that integrates with your Lambda function.
resource "aws_api_gateway_rest_api" "upload_api" {
  name        = "File Upload API"
  description = "API for file upload using a s3 function"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_s3_bucket_policy" "upload_policy" {
  bucket = aws_s3_bucket.file_upload_bucket.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "${aws_s3_bucket.file_upload_bucket.arn}/*"
    }
  ]
}
EOF
}

resource "aws_api_gateway_resource" "upload_resource" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  parent_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "upload_method" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.upload_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# La idea es integrar con S3
resource "aws_api_gateway_integration" "s3_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_method.http_method
  type        = "AWS"
  integration_http_method = "PUT"
  uri         = "arn:aws:apigateway:${var.region}:s3:path/${aws_s3_bucket.file_upload_bucket.bucket}/*"

  credentials = aws_iam_role.api_gateway_role.arn
}

# Aqui integra con la funcion lambda
resource "aws_api_gateway_integration" "upload_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_method.http_method
  type        = "AWS_PROXY"
  uri         = aws_lambda_function.file_upload_lambda.invoke_arn

  integration_http_method = "POST"
}

# This will require users to be authenticated via Cognito to access your API.
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name        = "CognitoAuthorizer"
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  type        = "COGNITO_USER_POOLS"

  identity_source = "method.request.header.Authorization"

  provider_arns = [
    aws_cognito_user_pool.user_pool.arn
  ]
}

# Deployment of the API Gateway
resource "aws_api_gateway_deployment" "upload_api_deployment" {
  depends_on = [aws_api_gateway_integration.s3_integration]
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  stage_name  = "prod"

}

# Output the API Gateway URL
output "api_gateway_url" {
  value = "${aws_api_gateway_deployment.upload_api_deployment.invoke_url}"
}

# Lambda Permission
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_assembly_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.file_upload_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.file_upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_assembly_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".part" # assuming chunk files end with .part
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# Create an IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "APIGatewayS3UploadRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  inline_policy {
    name   = "S3UploadPolicy"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "${aws_s3_bucket.file_upload_bucket.arn}/*"
    }
  ]
}
EOF
  }
}

# IAM Role for Lambda TODO: Check this, probably we dont need more
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name = "LambdaPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject"
          ]
          Resource = [
            "${aws_s3_bucket.file_upload_bucket.arn}/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "cognito-idp:DescribeUserPool",
            "cognito-idp:AdminGetUser"
          ]
          Resource = "${aws_cognito_user_pool.user_pool.arn}"
        }
      ]
    })
  }
}

resource "aws_iam_role_policy_attachment" "lambda_s3_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.file_upload_bucket.bucket
}


# Cognito user pool
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
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain   = "file-upload-user-pool-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# Output the Cognito user pool domain
output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}
