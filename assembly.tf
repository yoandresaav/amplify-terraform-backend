
data "archive_file" "lambda_assembly" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_assembly.py"
  output_path = "lambda_assembly.zip"
}

resource "aws_lambda_function" "lambda_assembly_function" {
  filename      = "lambda_assembly.zip"
  function_name = "lambda_function_assembly"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_assembly.handler"

  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime = "python3.10"

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }
}

resource "aws_cloudwatch_log_group" "logs_lambda_assembly" {
  name              = "/aws/lambda/lambda_function_assembly"
  retention_in_days = 14
}

resource "aws_api_gateway_method" "AssemblyItem" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.api_authorizer.id
}

resource "aws_api_gateway_integration" "assembly_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id

  http_method = aws_api_gateway_method.AssemblyItem.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.lambda_assembly_function.invoke_arn
}

resource "aws_lambda_permission" "assembly_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_assembly_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.upload_api.execution_arn}/*/*/*"
}


resource "aws_api_gateway_method_response" "AssemblyStatus200" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id

  http_method = aws_api_gateway_method.AssemblyItem.http_method
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

resource "aws_api_gateway_integration_response" "AssemblyIntegrationResponse200" {
  depends_on = [aws_api_gateway_integration.assembly_integration]

  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_rest_api.upload_api.root_resource_id

  http_method = aws_api_gateway_method.AssemblyItem.http_method
  status_code = aws_api_gateway_method_response.AssemblyStatus200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods"     = "'GET,OPTIONS,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin"      = "'*'",
    "method.response.header.Access-Control-Allow-Credentials" = "'true'"

  }
}

