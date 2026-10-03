output "api_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "shipping_queue_url" {
  value = aws_sqs_queue.shipping.url
}

output "event_bus_name" {
  value = aws_cloudwatch_event_bus.main.name
}

output "order_api_version" {
  value = aws_lambda_function.order_api.version
}
