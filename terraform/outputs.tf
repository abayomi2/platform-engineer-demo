# terraform/outputs.tf
output "ecr_repository_url" {
  description = "The URL of the ECR repository."
  value       = aws_ecr_repository.app_repo.repository_url
}

output "jenkins_public_ip" {
  description = "The public IP address of the Jenkins server."
  value       = module.jenkins_server.jenkins_public_ip
}

output "jenkins_security_group_id" {
  description = "The Security Group ID of the Jenkins server."
  value       = module.jenkins_server.jenkins_security_group_id
}

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint of the EKS cluster."
  value       = module.eks_cluster.cluster_endpoint
}

output "db_secret_arn" {
  description = "The ARN of the AWS Secrets Manager secret holding DB credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "kubeconfig_command" {
  description = "Command to update your kubeconfig for EKS."
  value       = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region ${var.aws_region}"
}
output "alb_controller_policy_arn" {
  description = "ARN of the IAM Policy for the AWS Load Balancer Controller."
  value       = module.eks_cluster.alb_controller_policy_arn
}


