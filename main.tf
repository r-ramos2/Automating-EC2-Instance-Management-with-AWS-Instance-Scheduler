provider "aws" {
  region = "us-east-1"
}

resource "aws_cloudformation_stack" "instance_scheduler" {
  name         = "InstanceSchedulerStack"
  template_url = "https://example.com/path/to/instance-scheduler-template.json"

  parameters = {
    TimeZone = "America/Los_Angeles"
    DynamoDBTable = aws_dynamodb_table.config_table.name
  }
}

resource "aws_dynamodb_table" "config_table" {
  name         = "InstanceSchedulerConfig"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "ScheduleId"
    type = "S"
  }

  hash_key = "ScheduleId"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_kms_key.arn
  }
}

resource "aws_kms_key" "dynamodb_kms_key" {
  description = "KMS key for encrypting DynamoDB instance scheduler table"
  deletion_window_in_days = 10
}

resource "aws_lambda_function" "instance_scheduler_lambda" {
  function_name = "InstanceSchedulerLambda"
  s3_bucket     = "my-bucket"
  s3_key        = "my-function.zip"
  handler       = "index.handler"
  runtime       = "nodejs14.x"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.config_table.name
    }
  }

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_execution_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.instance_scheduler_lambda.function_name}"
  retention_in_days = 30

  kms_key_id = aws_kms_key.logs_kms_key.arn
}

resource "aws_kms_key" "logs_kms_key" {
  description = "KMS key for encrypting CloudWatch logs"
  deletion_window_in_days = 10
}

resource "aws_cloudwatch_event_rule" "schedule_event" {
  name        = "InstanceSchedulerEventRule"
  schedule_expression = "cron(0 9 ? * MON-FRI *)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule_event.name
  target_id = "InstanceSchedulerLambda"
  arn       = aws_lambda_function.instance_scheduler_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.instance_scheduler_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule_event.arn
}
