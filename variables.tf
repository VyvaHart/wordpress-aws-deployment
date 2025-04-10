variable "aws_region" {
  description = "Required AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (2 for ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.4.0/24"]
  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Minimum 2 public subnets in different AZs are required for the ALB"
  }
}

variable "public_subnet_azs" {
  description = "List of Availability Zones for the public subnets (must match length of public_subnet_cidrs)"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "ec2_key_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
}

variable "db_username" {
  description = "Username for the RDS MySQL database"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Password for the RDS MySQL database"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Name of the RDS MySQL database"
  type        = string
  default     = "wordpressdb"
}

# --- not used in .tf resource creation (used by deploy_wordpress.sh script) ---
variable "wp_admin_user" {
  description = "Admin username for the WordPress installation"
  type        = string
  sensitive   = true
}

variable "wp_admin_password" {
  description = "Admin password for the WordPress installation"
  type        = string
  sensitive   = true
}

variable "wp_admin_email" {
  description = "Admin email for the WordPress installation"
  type        = string
  sensitive   = false
}