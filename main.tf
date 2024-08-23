# https://github.com/robty123/s3-proxy/blob/master/s3-proxy-gateway/iam-s3-proxy-role.tf
# Set region
variable "region" {
  description = "The AWS region to deploy resources in"
  default     = "us-east-2"  # or whatever region you're working in
}

variable "bucket_name" {
  type = string
  default = "our-file-upload-bucket-1"
}


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
  region = var.region
}

# Create an S3 bucket for file uploads and save assembled files
resource "aws_s3_bucket" "file_upload_bucket" {
  bucket = "our-file-upload-bucket-1" # Change this to a unique name due to aws time to release this resource
  force_destroy = true
}

output "s3_bucket_name" {
  value = aws_s3_bucket.file_upload_bucket.bucket
}


# Create S3 Full Access Policy
resource "aws_iam_policy" "s3_policy" {
  name        = "s3-policy"
  description = "Policy for allowing all S3 Actions"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        }
    ]
}
EOF
}

# Create API Gateway Role
resource "aws_iam_role" "s3_api_gateway_role" {
  name = "s3-api-gateway-role"

  # Create Trust Policy for API Gateway
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach S3 Access Policy to the API Gateway Role
resource "aws_iam_role_policy_attachment" "s3_policy_attach" {
  role       = aws_iam_role.s3_api_gateway_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}


# Create an API Gateway that integrates with your Lambda function.
resource "aws_api_gateway_rest_api" "upload_api" {
  name        = "File Upload API"
  description = "API for file upload using a s3 function"
  binary_media_types = "${var.supported_binary_media_types}"
}

module "cors" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"

  api_id            = aws_api_gateway_rest_api.upload_api.id
  api_resource_id   = aws_api_gateway_resource.Item.id
  # api_resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  allow_credentials = true
}


module "cors-Folder" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"

  api_id            = aws_api_gateway_rest_api.upload_api.id
  api_resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  allow_credentials = true
}


resource "aws_api_gateway_resource" "Folder" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  parent_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  path_part   = "{folder}"
}

resource "aws_api_gateway_resource" "Item" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  parent_id   = aws_api_gateway_resource.Folder.id
  path_part   = "{item}"
}

### GET a item from s3
data "archive_file" "lambda_download_file" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_download.py"
  output_path = "lambda_download.zip"
}

resource "aws_lambda_function" "lambda_download_function" {
  filename      = "lambda_download.zip"
  function_name = "lambda_function_download"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_download.handler"

  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime = "python3.10"

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }
}

resource "aws_cloudwatch_log_group" "logs_lambda_download" {
  name              = "/aws/lambda/lambda_function_download"
  retention_in_days = 14
}

resource "aws_api_gateway_method" "GetItem" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.Item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.api_authorizer.id


  request_parameters = {
    "method.request.path.folder" = true,
    "method.request.path.item"   = true,
  }
}

# La idea es integrar con S3
resource "aws_api_gateway_integration" "s3_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.GetItem.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.lambda_download_function.invoke_arn

  request_parameters = {
    "integration.request.path.folder" = "method.request.path.folder",
    "integration.request.path.item"   = "method.request.path.item"
  }
}

resource "aws_lambda_permission" "download_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_download_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.upload_api.execution_arn}/*/*/*"
}


resource "aws_api_gateway_method_response" "Status200" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.GetItem.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  depends_on = [aws_api_gateway_method.GetItem]
}

resource "aws_api_gateway_method_response" "Status400" {
  depends_on = [aws_api_gateway_integration.s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.GetItem.http_method
  status_code = "400"
}

resource "aws_api_gateway_method_response" "Status500" {
  depends_on = [aws_api_gateway_integration.s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.GetItem.http_method
  status_code = "500"
}

resource "aws_api_gateway_integration_response" "IntegrationResponse200" {
  depends_on = [aws_api_gateway_integration.s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.GetItem.http_method
  status_code = aws_api_gateway_method_response.Status200.status_code
}

resource "aws_api_gateway_integration_response" "IntegrationResponse400" {
  depends_on = [aws_api_gateway_integration.s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.GetItem.http_method
  status_code = aws_api_gateway_method_response.Status400.status_code

  selection_pattern = "4\\d{2}"
}

resource "aws_api_gateway_integration_response" "IntegrationResponse500" {
  depends_on = [aws_api_gateway_integration.s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.GetItem.http_method
  status_code = aws_api_gateway_method_response.Status500.status_code

  selection_pattern = "5\\d{2}"
}


#### List Items
resource "aws_api_gateway_authorizer" "api_authorizer" {
  name          = "CognitoUserPoolAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_method" "ListItem" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  http_method   = "GET"

  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.api_authorizer.id
}

resource "aws_api_gateway_integration" "list_s3_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id

  http_method = aws_api_gateway_method.ListItem.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.lambda_list_function.invoke_arn
}

resource "aws_lambda_permission" "list_s3_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_list_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.upload_api.execution_arn}/*/*/*"
}


resource "aws_api_gateway_method_response" "ListStatus200" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id

  http_method = aws_api_gateway_method.ListItem.http_method
  status_code = "200"

  response_parameters = {
      "method.response.header.Access-Control-Allow-Origin" = true
      "method.response.header.Access-Control-Allow-Methods" = true
      "method.response.header.Access-Control-Allow-Headers" = true
      "method.response.header.Access-Control-Allow-Credentials" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "ListIntegrationResponse200" {
  depends_on = [aws_api_gateway_integration.list_s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id

  http_method = aws_api_gateway_method.ListItem.http_method
  status_code = aws_api_gateway_method_response.ListStatus200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"

  }
}
### /End list Items



### PUT Elements Adding a post to upload files to S3
resource "aws_api_gateway_method" "PostUpload" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.Item.id

  http_method   = "PUT"
  # authorization = "AWS_IAM"
  # authorization = "NONE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.api_authorizer.id

  request_parameters = {
    "method.request.header.Accept"              = false
    "method.request.header.Content-Type"        = false
    "method.request.header.x-amz-meta-fileinfo" = false
    "method.request.path.folder" = true,
    "method.request.path.item"   = true,
  }
}

resource "aws_api_gateway_integration" "post_s3_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.PostUpload.http_method
  type        = "AWS"
  integration_http_method = "PUT"
  uri         = "arn:aws:apigateway:${var.region}:s3:path/${var.bucket_name}/{folder}/{item}"

  credentials = aws_iam_role.s3_api_gateway_role.arn

  request_parameters = {
    "integration.request.path.folder"  = "method.request.path.folder"
    "integration.request.path.item"    = "method.request.path.item"
    "integration.request.header.x-amz-meta-fileinfo" = "method.request.header.x-amz-meta-fileinfo"
    "integration.request.header.Accept"              = "method.request.header.Accept"
    "integration.request.header.Content-Type"        = "method.request.header.Content-Type"
  }
}

resource "aws_api_gateway_method_response" "PostMethodStatus200" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.PostUpload.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Content-Length" = true
    "method.response.header.Content-Type"   = true
    "method.response.header.Access-Control-Allow-Headers"     = true,
    "method.response.header.Access-Control-Allow-Methods"     = true,
    "method.response.header.Access-Control-Allow-Origin"      = true,
    "method.response.header.Access-Control-Allow-Credentials" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
  depends_on = [aws_api_gateway_method.PostUpload]
}

resource "aws_api_gateway_method_response" "PostStatus400" {
  depends_on = [aws_api_gateway_integration.post_s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.PostUpload.http_method
  status_code = "400"
}

resource "aws_api_gateway_method_response" "PostStatus500" {
  depends_on = [aws_api_gateway_integration.post_s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.PostUpload.http_method
  status_code = "500"
}

resource "aws_api_gateway_integration_response" "PostIntegrationResponse200" {
  depends_on = [aws_api_gateway_integration.post_s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.PostUpload.http_method
  status_code = aws_api_gateway_method_response.PostMethodStatus200.status_code

  response_parameters = {
    "method.response.header.Content-Length" = "integration.response.header.Content-Length"
    "method.response.header.Content-Type"   = "integration.response.header.Content-Type"
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"
  }
}

resource "aws_api_gateway_integration_response" "PostIntegrationResponse400" {
  depends_on = [aws_api_gateway_integration.post_s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.PostUpload.http_method
  status_code = aws_api_gateway_method_response.PostStatus400.status_code

  selection_pattern = "4\\d{2}"
}

resource "aws_api_gateway_integration_response" "PostIntegrationResponse500" {
  depends_on = [aws_api_gateway_integration.post_s3_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.Item.id
  http_method = aws_api_gateway_method.PostUpload.http_method
  status_code = aws_api_gateway_method_response.PostStatus500.status_code

  selection_pattern = "5\\d{2}"
}


resource "aws_api_gateway_deployment" "S3APIDeployment" {
  depends_on  = [
    aws_api_gateway_integration.s3_integration,
    aws_api_gateway_integration.list_s3_integration,
    aws_api_gateway_integration.post_s3_integration,
  ]
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  stage_name  = "prod"
  lifecycle {
    create_before_destroy = true
  }
}

output "api_gateway_url_s3" {
  value = "${aws_api_gateway_deployment.S3APIDeployment.invoke_url}"
}


### Lambda function
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_s3" {
  statement {
    actions = [
      "s3:ListObjects",
    ]

    resources = [
      "arn:aws:s3:::*",
    ]
  }
}

# Create an IAM policy for the Lambda function
resource "aws_iam_policy" "lambda_s3" {
  name        = "lambda-s3-permissions"
  description = "Contains S3 put permission for lambda"
  policy      = data.aws_iam_policy_document.lambda_s3.json
}


resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.iam_for_lambda.name
  # policy_arn = aws_iam_policy.lambda_s3.arn
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}



data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_list.py"
  output_path = "lambda_list.zip"
}

resource "aws_lambda_function" "lambda_list_function" {
  filename      = "lambda_list.zip"
  function_name = "lambda_function_list"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_list.handler"

  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime = "python3.10"

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }
}

# Cloudwatch logs
resource "aws_cloudwatch_log_group" "logs_lambda_list" {
  name              = "/aws/lambda/lambda_function_list"
  retention_in_days = 14
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

### /End lambda to list files

