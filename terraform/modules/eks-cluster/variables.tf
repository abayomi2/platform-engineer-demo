# terraform/modules/eks-cluster/variables.tf
variable "project_name" {
    type        = string
}

variable "aws_region" {
    description = "The AWS region where the EKS cluster will be created."
    type        = string
    default     = "us-east-1" # Update this to your desired region
}

variable "vpc_id" {
    description = "The ID of the VPC where the EKS cluster will be created."
    type        = string
}

variable "vpc_cidr" {
    description = "The CIDR block for the VPC"
    type        = string
} 

variable "private_subnet_ids" {
    description = "List of private subnet IDs for the EKS cluster."
    type        = list(string)
}

variable "public_subnets_ids" {
    description = "List of public subnet IDs for the EKS cluster."
    type        = list(string)
}

variable "rds_security_group_id" {
    description = "The security group ID of the RDS database."
    type        = string
}
variable "eks_version" {
  description = "The version of EKS to use for the cluster."
  type        = string
  default     = "1.31" # Update this to the desired EKS version 
  
}



  



# variable "private_subnet_ids" {
#   type = list(string)
# }
# variable "public_subnet_ids" { # For ALB/NLB
#   type = list(string)
# }
# variable "rds_security_group_id" {
#   description = "The security group ID of the RDS database."
#   type        = string
# }
# variable "vpc_cidr" {
#   description = "The CIDR block for the VPC"
#   type        = string
# }
