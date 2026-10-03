data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Zips the handler source. output_base64sha256 is what makes Terraform notice
# that the CODE changed - see source_code_hash below.
data "archive_file" "order_api" {
  type             = "zip"
  source_dir       = "${path.module}/../src/order-api"
  output_path      = "${path.module}/order-api.zip"
  output_file_mode = "0666" # the same file modes on the IDE and in CodeBuild, so the same hash
}

data "archive_file" "fulfilment" {
  type             = "zip"
  source_dir       = "${path.module}/../src/fulfilment"
  output_path      = "${path.module}/fulfilment.zip"
  output_file_mode = "0666"
}
