# terraform/modules/jenkins-server/variables.tf
variable "project_name" {
    description = "The name of the project for which Jenkins is being set up."
    type        = string
}

variable "aws_region" {
    description = "The AWS region in which the Jenkins server will be created."
}

variable "vpc_id" {
    description = "The ID of the VPC where the Jenkins server will be deployed."
    type        = string
}

variable "public_subnet_id" {
    description = "The ID of the public subnet where the Jenkins server will be deployed."
    type        = string
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster for Jenkins to configure kubectl against."
  type        = string
}