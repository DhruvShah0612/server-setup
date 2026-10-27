variable "project_name" {
  description = "Short project name; use lowercase letters, numbers, and hyphens."
  type        = string
  default     = "ovulation-tracker"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.project_name)) && length(var.project_name) >= 3
    error_message = "project_name must be lowercase and contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name, such as dev, staging, or prod."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.environment))
    error_message = "environment must use lowercase letters, numbers, or hyphens."
  }
}

variable "aws_region" {
  description = "AWS region in which regional resources will be created."
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type."
}

variable "ec2_root_volume_size" {
  type        = number
  default     = 30
  description = "EC2 root volume size in GiB."
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_storage_size" {
  type    = number
  default = 20
}

variable "db_engine_version" {
  type        = string
  default     = "8.4.11"
  description = "Must be supported by RDS in the selected region."
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR ranges allowed to SSH to EC2. Replace 0.0.0.0/0 with your public IP/32."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_allowed_cidrs" {
  description = "CIDR ranges allowed to reach TCP 5000. Restrict for production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "rds_allowed_cidrs" {
  description = "CIDR ranges allowed to connect to MySQL. Strongly recommend restricting this."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "s3_bucket_suffix" {
  description = "Optional globally-unique suffix for the S3 bucket, e.g. team42. Keep empty to use project-environment."
  type        = string
  default     = ""
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window. Use 7-30 days."
  type        = number
  default     = 7
}
