Platform Engineering Demo Project
This project serves as a comprehensive demonstration of building, deploying, and managing a modern, scalable, and highly available microservice application using cloud-native tools and practices on AWS. It simulates a real-world Platform Engineer III role, focusing on infrastructure-as-code, CI/CD, container orchestration, and secure secret management.

🚀 Project Goal
The primary goal of this project is to automate the end-to-end process of deploying a Spring Boot microservice to a Kubernetes cluster on AWS, leveraging a robust CI/CD pipeline. This includes provisioning all necessary infrastructure, configuring tooling, and ensuring secure communication.

🛠️ Key Technologies Used
Cloud Provider: AWS

Infrastructure as Code (IaC): Terraform

Container Orchestration: AWS Elastic Kubernetes Service (EKS)

Microservice Framework: Java Spring Boot

Containerization: Docker

Container Registry: Docker Hub

Database: AWS RDS PostgreSQL

CI/CD Automation: Jenkins

Vulnerability Scanning: Trivy

Secret Management: AWS Secrets Manager

Command Line Tools: AWS CLI v2, kubectl, mvn, git

Shell Scripting: Bash (install_jenkins.sh.tpl for EC2 user_data)

✨ Implemented Components & Features (Current Stage)
At this stage, the project has successfully automated the deployment of the core infrastructure and critical tooling:

Network Infrastructure:

AWS VPC: Custom Virtual Private Cloud with defined CIDR blocks.

Public and Private Subnets: Separated for secure and accessible resources, spanning multiple Availability Zones.

Internet Gateway (IGW): For internet access from public subnets.

NAT Gateway: For outbound internet access from private subnets.

Security Groups: Finely tuned firewall rules for inter-service communication (e.g., EKS to RDS, Jenkins to RDS, ALB to EKS nodes).

AWS RDS PostgreSQL Database:

A managed PostgreSQL instance for the Spring Boot application's persistence.

Configured for multi-AZ deployment for high availability.

recovery_window_in_days = 0 set for terraform destroy cleanliness (for demo purposes).

AWS Secrets Manager:

Securely stores database credentials.

The Jenkins pipeline retrieves these credentials at runtime to inject into Kubernetes secrets.

AWS EKS Kubernetes Cluster:

A fully managed Kubernetes cluster with worker nodes.

Automated setup of the aws-auth ConfigMap to grant necessary IAM roles (EKS node group role, Jenkins EC2 instance role, Jenkins pipeline user role) system:masters (admin) access within the cluster. This resolves authentication issues for kubectl.

Jenkins CI/CD Server:

An EC2 instance provisioned to host Jenkins.

Its user_data script (install_jenkins.sh.tpl) automates the installation and configuration of:

Java (Amazon Corretto 17): Runtime environment for Jenkins and Spring Boot builds.

Git: For SCM checkout.

Maven (3.9.10): For building the Spring Boot application.

Docker: For building and pushing container images.

kubectl: Kubernetes command-line tool for deploying to EKS.

AWS CLI v2: For AWS service interaction (Secrets Manager, EKS authentication).

Jenkins Service: Running and enabled.

User Permissions: ec2-user and jenkins users are added to the docker group, and the Docker daemon is restarted to apply permissions.

Kubeconfig Setup: The jenkins user's kubeconfig is automatically updated on the server to interact with the EKS cluster.

EKS Authentication Robustness:

Terraform explicitly waits for the EKS cluster to be fully ACTIVE before attempting to deploy Kubernetes-specific resources (aws-auth ConfigMap).

The aws-auth ConfigMap deployment uses a robust null_resource with a local-exec provisioner, executing kubectl apply with an aggressive retry strategy to overcome transient EKS control plane startup/IAM propagation race conditions. This ensures the Jenkins role has system:masters access.

CI/CD Pipeline Definition (Jenkinsfile):

The jenkins/Jenkinsfile defines the multi-stage pipeline for the Spring Boot application.

It retrieves Docker Hub credentials from Jenkins's credential store.

It constructs dynamic image tags using BUILD_NUMBER.

It fetches DB credentials from AWS Secrets Manager using shell commands (aws secretsmanager get-secret-value | jq).

It dynamically injects these secrets into Kubernetes secret.yaml template before deployment.

It prepares and applies Kubernetes manifests (deployment, service, ingress, aws-load-balancer-controller-service-account).

It performs kubectl rollout status for deployment verification.

It includes a Vulnerability Scan stage using Trivy.

🚀 Getting Started (Deployment Instructions)
Follow these steps to deploy the entire infrastructure from scratch.

📋 Prerequisites
Ensure you have the following installed and configured on your local machine:

AWS Account: With programmatic access (Access Key ID & Secret Access Key).

AWS CLI: Configured (aws configure) with a default region (e.g., us-east-1 or ap-southeast-2).

Terraform: Install Terraform

Git: Install Git

Docker Desktop: (For local testing only, not for Jenkins server) Download Docker Desktop

Java Development Kit (JDK): Version 17 or higher (for local Spring Boot development)

Maven: (For local Spring Boot development)

kubectl: Install kubectl

Docker Hub Account: Create an account

📦 Project Structure
platform-engineer-demo/  (Local Git Repository Root)
├── jenkins/
│   ├── Jenkinsfile          # Jenkins Pipeline definition
│   └── scripts/
│       └── trivy_scan.sh    # Trivy scan helper script
├── kubernetes/
│   ├── aws-load-balancer-controller-service-account.yaml # K8s ServiceAccount for ALB Controller
│   ├── deployment.yaml      # K8s Deployment for Spring Boot app
│   ├── ingress.yaml         # K8s Ingress for ALB exposure
│   ├── secret.yaml.tpl      # K8s Secret template for DB credentials
│   └── service.yaml         # K8s Service for Spring Boot app
├── microservice/
│   └── demo/                # Spring Boot application root
│       ├── pom.xml
│       ├── src/
│       └── Dockerfile
└── terraform/               # Terraform IaC
    ├── modules/
    │   ├── eks-cluster/     # EKS cluster module
    │   │   ├── iam_policy.json # ALB Controller IAM Policy document
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── jenkins-server/  # Jenkins server module
    │   │   ├── install_jenkins.sh.tpl # User data script for Jenkins EC2
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    ├── main.tf              # Main Terraform orchestration
    ├── variables.tf
    ├── outputs.tf
    └── providers.tf
    └── versions.tf

🚀 Deployment Steps (from Local Machine)
Clone the Repository:

git clone https://github.com/abayomi2/platform-engineer-demo.git
cd platform-engineer-demo

Make sure the repository is flat locally (i.e., jenkins/, kubernetes/, microservice/, terraform/ are directly in the platform-engineer-demo root). If your previous pushes resulted in nesting (e.g., platform-engineer-demo/platform-engineer-demo/...), you will need to flatten your GitHub repository by force-pushing your local flat version.

Navigate to Terraform Directory:

cd terraform

Initialize Terraform:

terraform init -upgrade

Review the Plan (Optional but Recommended):

KUBECONFIG="" terraform plan

This will show you all the resources Terraform plans to create (VPC, EKS, RDS, Jenkins, etc.). Verify it looks correct.

Apply the Terraform Configuration:

KUBECONFIG="" terraform apply

When prompted for var.db_password, enter a strong password (at least 8 characters long).

Type yes to confirm the apply.

This step will take a significant amount of time (20-40+ minutes) as EKS clusters and RDS instances are provisioned. Be patient.

Retrieve Terraform Outputs:
Once terraform apply completes, get the critical output values:

terraform output jenkins_public_ip
terraform output cluster_name
terraform output aws_region
terraform output alb_controller_policy_arn
terraform output # (to see all outputs)

Copy these values down carefully.

🌐 Accessing Jenkins
Wait for Jenkins to Start: After terraform apply completes, it might take a few more minutes (5-10 mins) for the Jenkins service on the EC2 instance to fully start and initialize.

Open Jenkins in Browser: Navigate to http://<YOUR_JENKINS_PUBLIC_IP>:8080 (use the jenkins_public_ip from terraform output).

Retrieve Initial Admin Password:

SSH into your Jenkins EC2 instance:

ssh -i /path/to/your/prod-kp.pem ec2-user@<YOUR_JENKINS_PUBLIC_IP>

Get the password:

sudo cat /var/lib/jenkins/secrets/initialAdminPassword

Paste the password into the Jenkins UI.

Complete Jenkins Setup:

Choose "Install suggested plugins".

Create your first Admin User (remember these credentials!).

Click "Start using Jenkins".

⚙️ Configuring and Running the Jenkins Pipeline
Configure Jenkins Global Tools:

Log in to Jenkins.

Go to Manage Jenkins -> Tools.

Scroll to "Maven installations" -> "Add Maven".

Name: Maven3.9.10 (must match the name in Jenkinsfile).

Check "Install automatically".

Version: Select 3.9.10 (or the latest 3.x.x that corresponds to what user_data installed).

Scroll to "Git installations" -> "Add Git".

Name: Default (or Git).

Check "Install automatically".

Click Save.

Configure Jenkins Credentials (Docker Hub):

Go to Manage Jenkins -> Credentials -> System -> Global credentials (unrestricted).

Click Add Credentials.

Kind: Username with password

Scope: Global

ID: dockerhub-credentials (must match exactly).

Username: Your Docker Hub Username.

Password: Your Docker Hub Password.

Description: Docker Hub Credentials

Click Create.

Configure Jenkins Job Parameters:

Navigate to your spring-boot-eks-pipeline job -> Configure.

Scroll down to "This project is parameterized".

Ensure or add the following "String Parameter" fields, using values from your terraform output:

Name: EKS_CLUSTER_NAME

Default Value: platform-engineer-eks-demo-eks-cluster

Name: AWS_REGION

Default Value: us-east-1

Name: ALB_CONTROLLER_POLICY_ARN

Default Value: Paste the ARN from terraform output alb_controller_policy_arn.

Name: AWS_ACCOUNT_ID

Default Value: Your 12-digit AWS Account ID (e.g., 905418222266).

Click Save.

Run the Pipeline:

From your spring-boot-eks-pipeline job dashboard, click Build with Parameters.

Verify all parameters are correctly pre-filled.

Click Build.

✅ Expected Outcome of Pipeline
Upon successful execution of the Jenkins pipeline, you should see:

Checkout: Source code successfully cloned.

Build Spring Boot App JAR: Maven builds the .jar file.

Build Docker Image: Docker image spring-boot-demo-app:<BUILD_NUMBER> is built.

Vulnerability Scan with Trivy: Trivy scans the image, reports any vulnerabilities, but the stage will pass (for demo purposes) even with warnings.

Push Docker Image to Docker Hub: The image is tagged your-dockerhub-username/spring-boot-demo-app:<BUILD_NUMBER> and pushed.

Deploy to EKS:

DB credentials from Secrets Manager are retrieved.

Kubernetes secret is created/updated.

Kubernetes aws-load-balancer-controller-service-account is applied.

Kubernetes deployment, service, and ingress manifests are applied.

An AWS Application Load Balancer (ALB) is provisioned by the ALB Controller in EKS.

Verify Deployment:

kubectl rollout status confirms application pods are ready.

The ALB DNS name is retrieved and printed.

A curl health check to your application's /api/products/health endpoint passes.

The pipeline will end with Finished: SUCCESS.

⚠️ Important Notes & Considerations
Security of SSH Key (prod-kp.pem): Your private SSH key should never be committed to a public Git repository. If it was, immediately remove it from Git history, generate a new key pair, and update your Terraform.

GitHub Repository Nesting: The Jenkinsfile assumes a flat repository structure. If your GitHub repo is nested (e.g., repo-root/platform-engineer-demo/...), you must flatten it on GitHub (via git push --force from a local flat repo) for the Jenkins pipeline to find files.

IAM Role Propagation: AWS IAM changes (especially those affecting EKS authentication) can take a few minutes to propagate. If kubectl commands fail in Jenkins or manually on the EC2 instance with authentication errors, wait and retry.

Trivy Scan: In a production environment, you would configure Trivy to fail the pipeline automatically if HIGH or CRITICAL vulnerabilities are found. You would then fix these vulnerabilities before deployment.

Resource Cleanup: To destroy all resources created by this project, navigate to your terraform directory and run terraform destroy. Be aware of Secrets Manager's default 30-day deletion window (or use recovery_window_in_days = 0 for immediate deletion).

Cost: Running this infrastructure will incur AWS costs (EC2, EKS, RDS, ALB, NAT Gateway). Remember to terraform destroy when not in use.