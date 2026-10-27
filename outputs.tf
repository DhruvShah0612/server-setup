output "aws_region" {
  value = var.aws_region
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "ec2_public_ip" {
  value = aws_eip.app.public_ip
}

output "ec2_ssh_command" {
  value = "ssh -i ${local.name_prefix}.pem ubuntu@${aws_eip.app.public_ip}"
}

output "private_key_file" {
  value     = local_sensitive_file.private_key.filename
  sensitive = true
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app.bucket
}

output "iam_user_name" {
  value = aws_iam_user.app.name
}

output "iam_role_name" {
  value = aws_iam_role.secret.name
}

output "iam_instance_profile_name" {
  value = aws_iam_instance_profile.app.name
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.address
}

output "rds_master_secret_arn" {
  value     = aws_db_instance.mysql.master_user_secret[0].secret_arn
  sensitive = true
}

output "api_secret_name" {
  value = aws_secretsmanager_secret.api.name
}

output "vpc_id" {
  value = data.aws_vpc.default.id
}
