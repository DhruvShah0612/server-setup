data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_base = lower(var.s3_bucket_suffix == "" ? local.name_prefix : "${local.name_prefix}-${var.s3_bucket_suffix}")
  bucket_name = substr(local.bucket_base, 0, 63)

  s3_policy_name     = "${local.name_prefix}-s3-policy"
  secret_policy_name = "${local.name_prefix}-secret-policy"
  api_secret_name    = "${var.project_name}/${var.environment}/api"
}

# Use the default VPC and its subnets instead of creating new networking resources.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# EC2 security group
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-sg"
  description = "Security group for ${local.name_prefix} EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.ssh_allowed_cidrs
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.app_allowed_cidrs
    content {
      description = "Application TCP 5000"
      from_port   = 5000
      to_port     = 5000
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg" }
}

# Generate an SSH private key locally and register its public key in AWS.
# The private key and Terraform state are sensitive; do not commit either to Git.
resource "tls_private_key" "ec2" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2" {
  key_name   = local.name_prefix
  public_key = tls_private_key.ec2.public_key_openssh
  tags       = { Name = local.name_prefix }
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ec2.private_key_pem
  filename        = "${path.module}/${local.name_prefix}.pem"
  file_permission = "0600"
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  key_name                    = aws_key_pair.ec2.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.ec2_root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  iam_instance_profile = aws_iam_instance_profile.app.name

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = local.name_prefix }
}

# Elastic IP attached to the EC2 instance for a stable public IP that survives stop/start.
resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = local.name_prefix }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}

# S3 bucket. S3 bucket names are globally unique across AWS, so set s3_bucket_suffix if needed.
resource "aws_s3_bucket" "app" {
  bucket = local.bucket_name
  tags   = { Name = local.bucket_name }
}

resource "aws_s3_bucket_ownership_controls" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = false
  block_public_policy     = true
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# IAM user
resource "aws_iam_user" "app" {
  name = "${local.name_prefix}-s3"
  tags = { Name = "${local.name_prefix}-s3" }
}

# IAM role trust policy: EC2 can assume this role. The role is created and policies are attached,
# but it is not automatically attached to the EC2 instance; use an instance profile if required.
resource "aws_iam_role" "secret" {
  name = "${local.name_prefix}-secret"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-secret" }
}

resource "aws_iam_policy" "s3" {
  name        = local.s3_policy_name
  description = "Allow access to the project's S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.app.arn]
      },
      {
        Sid      = "ObjectAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.app.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_policy" "secret" {
  name        = local.secret_policy_name
  description = "Allow reading the project's API secret"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.api.arn]
    }]
  })
}

resource "aws_iam_user_policy_attachment" "s3" {
  user       = aws_iam_user.app.name
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_iam_user_policy_attachment" "secret" {
  user       = aws_iam_user.app.name
  policy_arn = aws_iam_policy.secret.arn
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.secret.name
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_iam_role_policy_attachment" "secret" {
  role       = aws_iam_role.secret.name
  policy_arn = aws_iam_policy.secret.arn
}

# Instance profile so the EC2 instance can assume the IAM role at runtime.
resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-profile"
  role = aws_iam_role.secret.name
  tags = { Name = "${local.name_prefix}-profile" }
}

# RDS security group - default CIDR matches the requested spec but is unsafe for production.
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "MySQL access for ${local.name_prefix}"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.rds_allowed_cidrs
    content {
      description = "MySQL"
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = data.aws_subnets.default.ids
  tags       = { Name = "${local.name_prefix}-db-subnets" }
}

resource "aws_db_instance" "mysql" {
  identifier                  = local.name_prefix
  engine                      = "mysql"
  engine_version              = var.db_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_storage_size
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  port                        = 3306

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true
  multi_az               = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  deletion_protection        = var.environment == "prod"
  skip_final_snapshot        = var.environment != "prod"

  tags = { Name = local.name_prefix }
}

# Custom API secret. RDS creates/manages its master password in a separate Secrets Manager secret.
# This secret stores the endpoint and ARN of that managed credential; it does not duplicate the password.
resource "aws_secretsmanager_secret" "api" {
  name                    = local.api_secret_name
  description             = "Application configuration for ${local.name_prefix}"
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = { Name = local.api_secret_name }
}

resource "aws_secretsmanager_secret_version" "api" {
  secret_id = aws_secretsmanager_secret.api.id

  secret_string = jsonencode({
    project_name          = var.project_name
    environment           = var.environment
    database_engine       = "mysql"
    database_name         = var.db_name
    database_username     = var.db_username
    database_host         = aws_db_instance.mysql.address
    database_port         = aws_db_instance.mysql.port
    rds_master_secret_arn = aws_db_instance.mysql.master_user_secret[0].secret_arn
  })
}
