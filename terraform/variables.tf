# terraform/variables.tf
variable "aws_region" { 
  description = "The AWS region to deploy resources into."
  type        = string
  default     = "us-east-1" # <--- IMPORTANT: SET YOUR REGION HERE (e.g., "ap-southeast-2")
}

variable "project_name" {
  description = "A unique name for the project, used for resource naming."
  type        = string
  default     = "platform-engineer-eks-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnets_cidr" {
  description = "CIDR blocks for the private subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets_cidr" {
  description = "CIDR blocks for the public subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "db_username" {
  description = "Username for the RDS PostgreSQL database."
  type        = string
  default     = "pgadmin"
}

variable "db_password" {
  description = "Password for the RDS PostgreSQL database."
  type        = string
  sensitive   = true # Mark as sensitive to prevent logging
}

variable "db_instance_type" {
  description = "DB instance type for RDS PostgreSQL."
  type        = string
  default     = "db.t3.micro" # Free tier eligible, but may be too small for real load
}