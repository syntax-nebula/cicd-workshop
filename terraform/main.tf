# ---------- Storage and messaging ----------

resource "aws_dynamodb_table" "orders" {
  name         = "${local.prefix}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }

  point_in_time_recovery { enabled = true }

  lifecycle {
    prevent_destroy = false # workshop only; use true for a real table
  }
}

resource "aws_cloudwatch_event_bus" "main" {
  name = "${local.prefix}-bus"
}

resource "aws_sqs_queue" "shipping" {
  name                       = "${local.prefix}-shipping"
  visibility_timeout_seconds = 60
}

resource "aws_sqs_queue" "fulfilment_dlq" {
  name                      = "${local.prefix}-fulfilment-dlq"
  message_retention_seconds = 1209600
}

# ---------- IAM ----------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "order_api" {
  name               = "${local.prefix}-order-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role" "fulfilment" {
  name               = "${local.prefix}-fulfilment"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "order_api" {
  role = aws_iam_role.order_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:*:secret:cicd-workshop/payment-api-*" # the secret from Lab 3
      },
    ]
  })
}

resource "aws_iam_role_policy" "fulfilment" {
  role = aws_iam_role.fulfilment.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.shipping.arn, aws_sqs_queue.fulfilment_dlq.arn]
      },
    ]
  })
}

# ---------- Functions ----------

resource "aws_cloudwatch_log_group" "order_api" {
  name              = "/aws/lambda/${local.prefix}-order-api"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "fulfilment" {
  name              = "/aws/lambda/${local.prefix}-fulfilment"
  retention_in_days = 7
}

resource "aws_lambda_function" "order_api" {
  function_name = "${local.prefix}-order-api"
  role          = aws_iam_role.order_api.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  timeout       = 30
  memory_size   = 512
  publish       = true

  filename         = data.archive_file.order_api.output_path
  source_code_hash = data.archive_file.order_api.output_base64sha256

  environment {
    variables = {
      ORDERS_TABLE      = aws_dynamodb_table.orders.name
      EVENT_BUS_NAME    = aws_cloudwatch_event_bus.main.name
      ENVIRONMENT       = var.environment
      PAYMENT_SECRET_ID = "cicd-workshop/payment-api" # the handler reads it since Lab 3
    }
  }

  depends_on = [aws_cloudwatch_log_group.order_api]
}

resource "aws_lambda_function" "fulfilment" {
  function_name = "${local.prefix}-fulfilment"
  role          = aws_iam_role.fulfilment.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  timeout       = 30
  memory_size   = 256
  publish       = true

  filename         = data.archive_file.fulfilment.output_path
  source_code_hash = data.archive_file.fulfilment.output_base64sha256

  environment {
    variables = {
      SHIPPING_QUEUE_URL = aws_sqs_queue.shipping.url
      ENVIRONMENT        = var.environment
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.fulfilment_dlq.arn
  }

  depends_on = [aws_cloudwatch_log_group.fulfilment]
}

resource "aws_lambda_alias" "order_api_live" {
  name             = "live"
  function_name    = aws_lambda_function.order_api.function_name
  function_version = aws_lambda_function.order_api.version
}

# ---------- Event wiring ----------

resource "aws_cloudwatch_event_rule" "order_placed" {
  name           = "${local.prefix}-order-placed"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source        = ["cicd-workshop.orders"]
    "detail-type" = ["OrderPlaced"]
  })
}

resource "aws_cloudwatch_event_target" "fulfilment" {
  rule           = aws_cloudwatch_event_rule.order_placed.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = aws_lambda_function.fulfilment.arn
}

# Without this the rule matches and the invocation silently fails.
resource "aws_lambda_permission" "events_invoke_fulfilment" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fulfilment.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_placed.arn
}

# ---------- HTTP API ----------

resource "aws_apigatewayv2_api" "orders" {
  name          = "${local.prefix}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "order_api" {
  api_id                 = aws_apigatewayv2_api.orders.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.order_api_live.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_orders" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "POST /orders"
  target    = "integrations/${aws_apigatewayv2_integration.order_api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.orders.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_invoke_order_api" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_api.function_name
  qualifier     = aws_lambda_alias.order_api_live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.orders.execution_arn}/*/*"
}
