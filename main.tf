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
  region = "us-east-1"
}
// Create lambda function
data aws_caller_identity current {}
 
locals {
 prefix = "trigger-on-upload"
 account_id          = data.aws_caller_identity.current.account_id
 ecr_repository_name = "${local.prefix}-lambda-container"
 ecr_image_tag       = "latest"
 region              = "us-east-1"
}
 
resource aws_ecr_repository repo {
 name = local.ecr_repository_name
 //force_delete = true
}
 
resource null_resource ecr_image {
 triggers = {
   nodejs_file = md5(file("${path.module}/trigger-on-upload.js"))
   docker_file = md5(file("${path.module}/Dockerfile"))
 }
 
 provisioner "local-exec" {
   command = <<EOF
           aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${local.region}.amazonaws.com
           docker build -t ${aws_ecr_repository.repo.repository_url}:${local.ecr_image_tag} .
           docker push ${aws_ecr_repository.repo.repository_url}:${local.ecr_image_tag}
       EOF
 }
}
 
data aws_ecr_image lambda_image {
 depends_on = [
   null_resource.ecr_image
 ]
 repository_name = local.ecr_repository_name
 image_tag       = local.ecr_image_tag
}
 
resource aws_iam_role lambda {
 name = "${local.prefix}-lambda-role"
 assume_role_policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Action": "sts:AssumeRole",
           "Principal": {
               "Service": "lambda.amazonaws.com"
           },
           "Effect": "Allow"
       }
   ]
}
 EOF
}

resource "aws_iam_role_policy" "revoke_keys_role_policy" {
  name = "${local.prefix}-lambda-policy"
  role = aws_iam_role.lambda.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*",
        "codecommit:*",
        "logs:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
 
resource "aws_lambda_function" "aws_lambda_func" {
 depends_on = [
   null_resource.ecr_image
 ]
 function_name = "${local.prefix}-lambda"
 role = aws_iam_role.lambda.arn
 timeout = 300
 image_uri = "${aws_ecr_repository.repo.repository_url}@${data.aws_ecr_image.lambda_image.id}"
 package_type = "Image"
}

resource "aws_s3_bucket" "lambda-upload-bucket" {
  bucket = "uploaded-lambda-bucket"
  force_destroy = true
}

resource "aws_s3_bucket" "lambda-triggered-bucket" {
  bucket = "triggered-lambda-bucket"
  force_destroy = true
}

resource "aws_lambda_permission" "allow_upload_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aws_lambda_func.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.lambda-upload-bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.lambda-upload-bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.aws_lambda_func.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_upload_bucket]
}