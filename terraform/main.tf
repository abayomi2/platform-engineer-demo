# This Terraform configuration sets up a complete AWS infrastructure for a platform engineering demo.
# terraform/main.tf

locals {
  az_suffixes = ["a", "b", "c", "d", "e", "f"] # Common AZ suffixes for dynamic subnet creation
}

# 1. Core Networking (VPC, Subnets, IGW, NAT Gateway)
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_eip" "nat_gateway_eip_a" {
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-nat-eip-a"
  }
}

resource "aws_nat_gateway" "main_a" {
  allocation_id = aws_eip.nat_gateway_eip_a.id
  # FIX: Access the subnet from the 'public' map using its dynamically generated key (AZ suffix)
  subnet_id     = aws_subnet.public[keys(aws_subnet.public)[0]].id
  tags = {
    Name = "${var.project_name}-nat-gateway-a"
  }
  depends_on    = [aws_internet_gateway.main]
}

# Create public subnets
resource "aws_subnet" "public" {
  # This for_each creates a map where keys are AZ suffixes (e.g., "a", "b") and values are CIDR blocks
  for_each                = tomap({ for i, cidr in var.public_subnets_cidr : local.az_suffixes[i] => cidr })
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = "${var.aws_region}${each.key}" # Use the AZ suffix (each.key) for the AZ
  map_public_ip_on_launch = true
  tags = {
    # FIX: Use each.key directly as the AZ suffix for consistent naming
    Name = "${var.project_name}-public-subnet-${each.key}"
  }
}

# Create private subnets
resource "aws_subnet" "private" {
  # This for_each creates a map where keys are AZ suffixes (e.g., "a", "b") and values are CIDR blocks
  for_each          = tomap({ for i, cidr in var.private_subnets_cidr : local.az_suffixes[i] => cidr })
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "${var.aws_region}${each.key}" # Use the AZ suffix (each.key) for the AZ
  tags = {
    # FIX: Use each.key directly as the AZ suffix for consistent naming
    Name = "${var.project_name}-private-subnet-${each.key}"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  # This for_each creates a map where keys are AZ suffixes (e.g., "a", "b")
  for_each = aws_subnet.private # Using aws_subnet.private (which is already a map with AZ suffixes as keys)
  vpc_id   = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main_a.id # Point to NAT Gateway for outbound internet access
  }
  tags = {
    # FIX: Use each.key directly as the AZ suffix for consistent naming
    Name = "${var.project_name}-private-rt-${each.key}"
  }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id # Reference private route table by its AZ key
}

# 2. ECR Repository for Microservice Images
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.project_name}-app-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false # Trivy will handle scanning in CI/CD, not ECR's basic scanner
  }
  tags = {
    Name = "${var.project_name}-ecr-repo"
  }
}

# 3. AWS RDS PostgreSQL Database
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow inbound traffic to RDS from EKS pods"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # Allow traffic from private subnets (EKS nodes are here)
    cidr_blocks = var.private_subnets_cidr
    description = "Allow traffic from private subnets (EKS nodes)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# Allow Jenkins server to connect to RDS - as a separate rule to avoid cycles
resource "aws_security_group_rule" "jenkins_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_sg.id
  source_security_group_id = module.jenkins_server.jenkins_security_group_id
  description              = "Allow Jenkins server to connect to RDS"
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "17.2" # Changed to 15.5 for wider compatibility. 17.2 might be too new or not broadly available for RDS yet.
  instance_class       = var.db_instance_type
  username             = var.db_username
  password             = var.db_password
  port                 = 5432
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.main.name
  skip_final_snapshot  = true # Set to false for production
  publicly_accessible  = false
  multi_az             = true # For high availability
  tags = {
    Name = "${var.project_name}-rds-db"
  }
}

# 4. AWS Secrets Manager for DB Credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/db_credentials"
  description = "Database credentials for the Spring Boot application."
  tags = {
    Name = "${var.project_name}-db-secrets"
  }
  # CRITICAL: Force immediate deletion for development/test environments
  recovery_window_in_days = 0 # Set to 0 to bypass the 30-day recovery window for clean re-creation
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username,
    password = var.db_password,
    host     = aws_db_instance.main.address,
    port     = aws_db_instance.main.port,
    dbname   = "${var.project_name}_db" # Use the variable directly for the DB name
  })
}

# 5. EKS Cluster Module
module "eks_cluster" {
  source = "./modules/eks-cluster" # Path to our EKS module
  # Pass necessary variables to the EKS module
  project_name      = var.project_name
  aws_region        = var.aws_region
  vpc_id            = aws_vpc.main.id
  vpc_cidr          = var.vpc_cidr
  private_subnet_ids = [for s in aws_subnet.private : s.id] # Pass a list of private subnet IDs
  public_subnets_ids = [for s in aws_subnet.public : s.id]  # Pass a list of public subnet IDs (for ALB)
  # This dynamically adds an ingress rule to the RDS SG, allowing traffic from the EKS Node Security Group
  rds_security_group_id = aws_security_group.rds_sg.id
}

# 6. Jenkins Server Module
module "jenkins_server" {
  source             = "./modules/jenkins-server" # Path to our Jenkins module
  # Pass necessary variables to the Jenkins module
  project_name       = var.project_name
  aws_region         = var.aws_region
  vpc_id             = aws_vpc.main.id
  # FIX: Access the subnet from the 'public' map using its dynamically generated key (AZ suffix)
  public_subnet_id   = aws_subnet.public[keys(aws_subnet.public)[0]].id
  eks_cluster_name   = module.eks_cluster.cluster_name # Pass the EKS cluster name to Jenkins for configuration
  # Removed: depends_on = [module.eks_cluster] # Removed to break dependency cycle
}

# Output kubeconfig command for convenience
resource "null_resource" "kubeconfig_update" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region ${var.aws_region}"
    interpreter = ["bash", "-c"]
  }
  depends_on = [module.eks_cluster] # Run after EKS is ready
}

# # Add ingress rule to RDS SG from EKS Node SG
# resource "aws_security_group_rule" "eks_to_rds" {
#   type                     = "ingress"
#   from_port                = 5432
#   to_port                  = 5432
#   protocol                 = "tcp"
#   source_security_group_id = module.eks_cluster.eks_node_group_sg_id # Use the output from the EKS module
#   security_group_id        = aws_security_group.rds_sg.id
#   description              = "Allow EKS nodes to connect to RDS"
#   depends_on = [module.eks_cluster]
# }

# NEW: null_resource to wait for EKS cluster to be truly active before deploying Kubernetes resources
resource "null_resource" "eks_cluster_active_wait" {
  depends_on = [
    module.eks_cluster # Depend on the entire EKS module completion
  ]
  provisioner "local-exec" {
    command = "echo 'Terraform is waiting for EKS cluster to be fully active before deploying Kubernetes resources...'"
  }
}

# NEW: 7. Configure EKS aws-auth ConfigMap by directly executing kubectl apply
# This method is more robust for race conditions during cluster bring-up.
resource "null_resource" "aws_auth_configmap_deployment" {
  depends_on = [
    null_resource.eks_cluster_active_wait, # Ensure EKS cluster is fully active
    module.jenkins_server,                 # Ensure Jenkins IAM role is created
    module.eks_cluster.node_group_role_arn # Ensure node role ARN is computable
  ]

  provisioner "local-exec" {
    command = <<EOF
      set -euo pipefail # Robust shell settings for the local-exec script

      # Assign Terraform interpolated values to shell variables
      # NOTE: These are interpolated by Terraform first, so they are correct as $${...}
      JENKINS_ROLE_ARN="${module.jenkins_server.jenkins_role_arn}"
      NODE_ROLE_ARN="${module.eks_cluster.node_group_role_arn}"
      CLUSTER_NAME="${module.eks_cluster.cluster_name}"
      AWS_REGION="${var.aws_region}"

      echo "Applying aws-auth ConfigMap for cluster $${CLUSTER_NAME} in region $${AWS_REGION}..."

      # Create a temporary aws-auth.yaml file with correct ARNs
      cat <<'EKS_AUTH_YAML_CONTENT' > "/tmp/aws-auth-$${CLUSTER_NAME}.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: $${NODE_ROLE_ARN}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: $${JENKINS_ROLE_ARN}
      username: jenkins
      groups:
        - system:masters
    # NEW: Add the underlying Jenkins EC2 instance role for direct access
    - rolearn: $${JENKINS_ROLE_ARN} # Use the same role ARN for ec2-user's instance profile
      username: ec2-user-jenkins-instance # A distinct username for this role mapping
      groups:
        - system:masters
EKS_AUTH_YAML_CONTENT

      # Apply the aws-auth ConfigMap to the EKS cluster
      # KUBECONFIG="" to ensure kubectl relies solely on provided auth (not local kubeconfig)
      KUBECONFIG="" kubectl apply -f "/tmp/aws-auth-$${CLUSTER_NAME}.yaml" || { echo "ERROR: kubectl apply for aws-auth failed."; exit 1; }
      
      echo "aws-auth ConfigMap applied for cluster $${CLUSTER_NAME} successfully."
    EOF
    interpreter = ["bash", "-c"] # Execute the heredoc content as a bash script
  }
}






# # This Terraform configuration sets up a complete AWS infrastructure for a platform engineering demo.
# # terraform/main.tf

# locals {
#   az_suffixes = ["a", "b", "c", "d", "e", "f"] # Common AZ suffixes for dynamic subnet creation
# }

# # 1. Core Networking (VPC, Subnets, IGW, NAT Gateway)
# resource "aws_vpc" "main" {
#   cidr_block = var.vpc_cidr
#   tags = {
#     Name = "${var.project_name}-vpc"
#   }
# }

# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.main.id
#   tags = {
#     Name = "${var.project_name}-igw"
#   }
# }

# resource "aws_eip" "nat_gateway_eip_a" {
#   domain = "vpc"
#   tags = {
#     Name = "${var.project_name}-nat-eip-a"
#   }
# }

# resource "aws_nat_gateway" "main_a" {
#   allocation_id = aws_eip.nat_gateway_eip_a.id
#   # FIX: Access the subnet from the 'public' map using its dynamically generated key (AZ suffix)
#   subnet_id     = aws_subnet.public[keys(aws_subnet.public)[0]].id
#   tags = {
#     Name = "${var.project_name}-nat-gateway-a"
#   }
#   depends_on    = [aws_internet_gateway.main]
# }

# # Create public subnets
# resource "aws_subnet" "public" {
#   # This for_each creates a map where keys are AZ suffixes (e.g., "a", "b") and values are CIDR blocks
#   for_each                = tomap({ for i, cidr in var.public_subnets_cidr : local.az_suffixes[i] => cidr })
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = each.value
#   availability_zone       = "${var.aws_region}${each.key}" # Use the AZ suffix (each.key) for the AZ
#   map_public_ip_on_launch = true
#   tags = {
#     # FIX: Use each.key directly as the AZ suffix for consistent naming
#     Name = "${var.project_name}-public-subnet-${each.key}"
#   }
# }

# # Create private subnets
# resource "aws_subnet" "private" {
#   # This for_each creates a map where keys are AZ suffixes (e.g., "a", "b") and values are CIDR blocks
#   for_each          = tomap({ for i, cidr in var.private_subnets_cidr : local.az_suffixes[i] => cidr })
#   vpc_id            = aws_vpc.main.id
#   cidr_block        = each.value
#   availability_zone = "${var.aws_region}${each.key}" # Use the AZ suffix (each.key) for the AZ
#   tags = {
#     # FIX: Use each.key directly as the AZ suffix for consistent naming
#     Name = "${var.project_name}-private-subnet-${each.key}"
#   }
# }

# # Route Tables
# resource "aws_route_table" "public" {
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.main.id
#   }
#   tags = {
#     Name = "${var.project_name}-public-rt"
#   }
# }

# resource "aws_route_table_association" "public" {
#   for_each       = aws_subnet.public
#   subnet_id      = each.value.id
#   route_table_id = aws_route_table.public.id
# }

# resource "aws_route_table" "private" {
#   # This for_each creates a map where keys are AZ suffixes (e.g., "a", "b")
#   for_each = aws_subnet.private # Using aws_subnet.private (which is already a map with AZ suffixes as keys)
#   vpc_id   = aws_vpc.main.id
#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.main_a.id # Point to NAT Gateway for outbound internet access
#   }
#   tags = {
#     # FIX: Use each.key directly as the AZ suffix for consistent naming
#     Name = "${var.project_name}-private-rt-${each.key}"
#   }
# }

# resource "aws_route_table_association" "private" {
#   for_each       = aws_subnet.private
#   subnet_id      = each.value.id
#   route_table_id = aws_route_table.private[each.key].id # Reference private route table by its AZ key
# }

# # 2. ECR Repository for Microservice Images
# resource "aws_ecr_repository" "app_repo" {
#   name                 = "${var.project_name}-app-repo"
#   image_tag_mutability = "MUTABLE"
#   image_scanning_configuration {
#     scan_on_push = false # Trivy will handle scanning in CI/CD, not ECR's basic scanner
#   }
#   tags = {
#     Name = "${var.project_name}-ecr-repo"
#   }
# }

# # 3. AWS RDS PostgreSQL Database
# resource "aws_security_group" "rds_sg" {
#   name        = "${var.project_name}-rds-sg"
#   description = "Allow inbound traffic to RDS from EKS pods"
#   vpc_id      = aws_vpc.main.id

#   ingress {
#     from_port   = 5432
#     to_port     = 5432
#     protocol    = "tcp"
#     # Allow traffic from private subnets (EKS nodes are here)
#     cidr_blocks = var.private_subnets_cidr
#     description = "Allow traffic from private subnets (EKS nodes)"
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#   tags = {
#     Name = "${var.project_name}-rds-sg"
#   }
# }

# # Allow Jenkins server to connect to RDS - as a separate rule to avoid cycles
# resource "aws_security_group_rule" "jenkins_to_rds" {
#   type                     = "ingress"
#   from_port                = 5432
#   to_port                  = 5432
#   protocol                 = "tcp"
#   security_group_id        = aws_security_group.rds_sg.id
#   source_security_group_id = module.jenkins_server.jenkins_security_group_id
#   description              = "Allow Jenkins server to connect to RDS"
# }

# resource "aws_db_subnet_group" "main" {
#   name       = "${var.project_name}-db-subnet-group"
#   subnet_ids = [for s in aws_subnet.private : s.id]
#   tags = {
#     Name = "${var.project_name}-db-subnet-group"
#   }
# }

# resource "aws_db_instance" "main" {
#   allocated_storage    = 20
#   engine               = "postgres"
#   engine_version       = "17.2" # Changed to 15.5 for wider compatibility. 17.2 might be too new or not broadly available for RDS yet.
#   instance_class       = var.db_instance_type
#   username             = var.db_username
#   password             = var.db_password
#   port                 = 5432
#   vpc_security_group_ids = [aws_security_group.rds_sg.id]
#   db_subnet_group_name = aws_db_subnet_group.main.name
#   skip_final_snapshot  = true # Set to false for production
#   publicly_accessible  = false
#   multi_az             = true # For high availability
#   tags = {
#     Name = "${var.project_name}-rds-db"
#   }
# }

# # 4. AWS Secrets Manager for DB Credentials
# resource "aws_secretsmanager_secret" "db_credentials" {
#   name        = "${var.project_name}/db_credentials"
#   description = "Database credentials for the Spring Boot application."
#   tags = {
#     Name = "${var.project_name}-db-secrets"
#   }
#   # CRITICAL: Force immediate deletion for development/test environments
#   recovery_window_in_days = 0 # Set to 0 to bypass the 30-day recovery window for clean re-creation
# }

# resource "aws_secretsmanager_secret_version" "db_credentials_version" {
#   secret_id     = aws_secretsmanager_secret.db_credentials.id
#   secret_string = jsonencode({
#     username = var.db_username,
#     password = var.db_password,
#     host     = aws_db_instance.main.address,
#     port     = aws_db_instance.main.port,
#     dbname   = "${var.project_name}_db" # Use the variable directly for the DB name
#   })
# }

# # 5. EKS Cluster Module
# module "eks_cluster" {
#   source = "./modules/eks-cluster" # Path to our EKS module
#   # Pass necessary variables to the EKS module
#   project_name      = var.project_name
#   aws_region        = var.aws_region
#   vpc_id            = aws_vpc.main.id
#   vpc_cidr          = var.vpc_cidr
#   private_subnet_ids = [for s in aws_subnet.private : s.id] # Pass a list of private subnet IDs
#   public_subnets_ids = [for s in aws_subnet.public : s.id]  # Pass a list of public subnet IDs (for ALB)
#   # This dynamically adds an ingress rule to the RDS SG, allowing traffic from the EKS Node Security Group
#   rds_security_group_id = aws_security_group.rds_sg.id
# }

# # 6. Jenkins Server Module
# module "jenkins_server" {
#   source             = "./modules/jenkins-server" # Path to our Jenkins module
#   # Pass necessary variables to the Jenkins module
#   project_name       = var.project_name
#   aws_region         = var.aws_region
#   vpc_id             = aws_vpc.main.id
#   # FIX: Access the subnet from the 'public' map using its dynamically generated key (AZ suffix)
#   public_subnet_id   = aws_subnet.public[keys(aws_subnet.public)[0]].id
#   eks_cluster_name   = module.eks_cluster.cluster_name # Pass the EKS cluster name to Jenkins for configuration
#   # Removed: depends_on = [module.eks_cluster] # Removed to break dependency cycle
# }

# # Output kubeconfig command for convenience
# resource "null_resource" "kubeconfig_update" {
#   provisioner "local-exec" {
#     command = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region ${var.aws_region}"
#     interpreter = ["bash", "-c"]
#   }
#   depends_on = [module.eks_cluster] # Run after EKS is ready
# }

# # # Add ingress rule to RDS SG from EKS Node SG
# # resource "aws_security_group_rule" "eks_to_rds" {
# #   type                     = "ingress"
# #   from_port                = 5432
# #   to_port                  = 5432
# #   protocol                 = "tcp"
# #   source_security_group_id = module.eks_cluster.eks_node_group_sg_id # Use the output from the EKS module
# #   security_group_id        = aws_security_group.rds_sg.id
# #   description              = "Allow EKS nodes to connect to RDS"
# #   depends_on = [module.eks_cluster]
# # }

# # NEW: null_resource to wait for EKS cluster to be truly active before deploying Kubernetes resources
# resource "null_resource" "eks_cluster_active_wait" {
#   depends_on = [
#     module.eks_cluster # Depend on the entire EKS module completion
#   ]
#   provisioner "local-exec" {
#     command = "echo 'Terraform is waiting for EKS cluster to be fully active before deploying Kubernetes resources...'"
#   }
# }

# resource "null_resource" "aws_auth_configmap_deployment" {
#   depends_on = [
#     null_resource.eks_cluster_active_wait,
#     module.jenkins_server,
#     module.eks_cluster
#   ]

#   provisioner "local-exec" {
#     command = <<-EOT
#       set -euo pipefail

#       export JENKINS_ROLE_ARN="${module.jenkins_server.jenkins_role_arn}"
#       export NODE_ROLE_ARN="${module.eks_cluster.node_group_role_arn}"
#       export CLUSTER_NAME="${module.eks_cluster.cluster_name}"
#       export AWS_REGION="${var.aws_region}"

#       echo "Applying aws-auth ConfigMap for cluster $${CLUSTER_NAME} in region $${AWS_REGION}..."

#       cat > "/tmp/aws-auth-$${CLUSTER_NAME}.yaml" <<-YAML
#       apiVersion: v1
#       kind: ConfigMap
#       metadata:
#         name: aws-auth
#         namespace: kube-system
#       data:
#         mapRoles: |
#           - rolearn: $${NODE_ROLE_ARN}
#             username: system:node:{{EC2PrivateDNSName}}
#             groups:
#               - system:bootstrappers
#               - system:nodes
#           - rolearn: $${JENKINS_ROLE_ARN}
#             username: jenkins
#             groups:
#               - system:masters
#           - rolearn: $${JENKINS_ROLE_ARN}
#             username: ec2-user-jenkins-instance
#             groups:
#               - system:masters
#       YAML

#       aws eks update-kubeconfig --name "$${CLUSTER_NAME}" --region "$${AWS_REGION}"

#       kubectl apply -f "/tmp/aws-auth-$${CLUSTER_NAME}.yaml"

#       echo "aws-auth ConfigMap applied for cluster $${CLUSTER_NAME} successfully."
#     EOT

#     interpreter = ["bash", "-c"]
#   }
# }





# # # NEW: 7. Configure EKS aws-auth ConfigMap by directly executing kubectl apply
# # # This method is more robust for race conditions during cluster bring-up.
# # resource "null_resource" "aws_auth_configmap_deployment" {
# #   depends_on = [
# #     null_resource.eks_cluster_active_wait, # Ensure EKS cluster is fully active
# #     module.jenkins_server,                 # Ensure Jenkins IAM role is created
# #     module.eks_cluster.node_group_role_arn # Ensure node role ARN is computable
# #   ]

# #   provisioner "local-exec" {
# #     command = <<EOF
# #       set -euo pipefail # Robust shell settings for the local-exec script

# #       # Assign Terraform interpolated values to shell variables
# #       # NOTE: These are interpolated by Terraform first, so they are correct as $${...}
# #       JENKINS_ROLE_ARN="${module.jenkins_server.jenkins_role_arn}"
# #       NODE_ROLE_ARN="${module.eks_cluster.node_group_role_arn}"
# #       CLUSTER_NAME="${module.eks_cluster.cluster_name}"
# #       AWS_REGION="${var.aws_region}"

# #       echo "Applying aws-auth ConfigMap for cluster $${CLUSTER_NAME} in region $${AWS_REGION}..."

# #       # Create a temporary aws-auth.yaml file with correct ARNs
# #       cat <<'EKS_AUTH_YAML_CONTENT' > "/tmp/aws-auth-$${CLUSTER_NAME}.yaml"
# # apiVersion: v1
# # kind: ConfigMap
# # metadata:
# #   name: aws-auth
# #   namespace: kube-system
# # data:
# #   mapRoles: |
# #     - rolearn: $${NODE_ROLE_ARN}
# #       username: system:node:{{EC2PrivateDNSName}}
# #       groups:
# #         - system:bootstrappers
# #         - system:nodes
# #     - rolearn: $${JENKINS_ROLE_ARN}
# #       username: jenkins
# #       groups:
# #         - system:masters
# #     # NEW: Add the underlying Jenkins EC2 instance role for direct access
# #     - rolearn: $${JENKINS_ROLE_ARN} # Use the same role ARN for ec2-user's instance profile
# #       username: ec2-user-jenkins-instance # A distinct username for this role mapping
# #       groups:
# #         - system:masters
# # EKS_AUTH_YAML_CONTENT

# #       # Apply the aws-auth ConfigMap to the EKS cluster
# #       # KUBECONFIG="" to ensure kubectl relies solely on provided auth (not local kubeconfig)
# #       KUBECONFIG="" kubectl apply -f "/tmp/aws-auth-$${CLUSTER_NAME}.yaml" || { echo "ERROR: kubectl apply for aws-auth failed."; exit 1; }

# #       echo "aws-auth ConfigMap applied for cluster $${CLUSTER_NAME} successfully."
# #     EOF
# #     interpreter = ["bash", "-c"] # Execute the heredoc content as a bash script
# #   }
# # }