# Platform Engineering Demo Project: An Interview Story

This project provided an invaluable opportunity to apply a wide range of platform engineering principles and technologies to build a robust, automated, and scalable deployment solution on AWS. Here's a breakdown of the journey of setting up a **CI/CD pipeline** for a **Spring Boot microservice**, focusing on the challenges and how they were overcome.

---

## Project Overview & Initial Vision

**Our goal was to create a fully automated pipeline to deploy a Java Spring Boot microservice to AWS EKS.**

**We aimed to:**

**Provision infrastructure using Terraform**  
**Set up a Jenkins CI/CD server**  
**Containerize with Docker and push to Docker Hub**  
**Secure credentials using AWS Secrets Manager**  
**Deploy to an AWS EKS (Kubernetes) cluster**

**The core idea was to build an end-to-end, repeatable, and self-healing deployment process.**

---

## Phase 1: Robust Infrastructure Automation with Terraform

### Initial Design

**Designed a secure AWS VPC with public/private subnets, Internet Gateway, and NAT Gateway**  
**Provisioned AWS RDS PostgreSQL for persistent storage (multi-AZ for high availability)**  
**Defined an AWS EKS cluster using Terraform**  
**Provisioned an EC2 instance for Jenkins**

### Challenges & Solutions

**Terraform Cycle Errors**  
Problem: Circular dependency between Jenkins and EKS  
Solution: Refactored `depends_on` and added `null_resource` with `local-exec` to wait for EKS readiness

```hcl
resource "null_resource" "wait_for_eks" {
  provisioner "local-exec" {
    command = "aws eks describe-cluster --name my-cluster --query cluster.status --output text | grep ACTIVE"
  }
  depends_on = [aws_eks_cluster.main]
}
``` 

## Secrets Manager Deletion Conflicts

Problem: Secrets stuck in "scheduled for deletion"
Solution: Set recovery_window_in_days = 0 to allow immediate re-creation

```h
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "db-password"
  recovery_window_in_days = 0
}
``` 
## Windows Line Ending Issues ($'\r')
- Problem: Shell scripts failed on Linux due to CRLF endings
- Solution: Converted line endings to LF using VS Code or dos2unix

Outcome
Fully automated, idempotent infrastructure provisioning
Reliable terraform apply from a clean slate

Phase 2: Building a Robust Jenkins Server
Jenkins EC2 Provisioning
Provisioned EC2 via user_data using install_jenkins.sh.tpl
Installed Java, Maven, Docker, AWS CLI, and kubectl

Challenges & Solutions
Tool Not Found Errors (e.g., mvn, docker)
Problem: Tools missing or not in PATH
Solution: Used absolute paths and installed via direct binary downloads (e.g., Apache for Maven), updated /etc/profile.d/ scripts

Docker Permission Denied for Jenkins User
Problem: Jenkins couldn't run Docker
Solution:

bash
Copy
Edit
usermod -aG docker jenkins
systemctl restart docker
Sudo TTY Requirement
Problem: sudo: no tty present error in user_data
Solution:

bash
Copy
Edit
echo "jenkins ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jenkins
chmod 440 /etc/sudoers.d/jenkins
EKS Authentication Errors on EC2
Problem: Jenkins EC2 couldn't run kubectl
Solution: Added IAM role to aws-auth ConfigMap with system:masters access

yaml
Copy
Edit
mapRoles:
  - rolearn: arn:aws:iam::ACCOUNT_ID:role/platform-engineer-eks-demo-jenkins-role
    username: jenkins
    groups:
      - system:masters
Outcome
Jenkins server provisioned with necessary tools and EKS access
Fully operational build agent for CI/CD pipelines

Phase 3: Implementing a Robust CI/CD Pipeline
Jenkinsfile Pipeline Design
Defined multi-stage Jenkins pipeline: build, scan, push, deploy
Used Docker, Trivy, AWS CLI, and kubectl

Challenges & Solutions
Groovy Sandbox & Serialization Errors
Problem: Groovy methods blocked or not serializable
Solution: Shifted secrets and JSON parsing logic to shell:

bash
Copy
Edit
aws secretsmanager get-secret-value --secret-id my-secret | jq -r .SecretString | base64
Invalid Docker Base Image
Problem: openjdk:17-slim-bookworm not found
Solution: Used openjdk:17-slim-bullseye

Dockerfile
Copy
Edit
FROM openjdk:17-slim-bullseye
Trivy Scan Failures
Problem: Scan stage failed pipeline on warnings
Solution:

bash
Copy
Edit
trivy image my-image || echo "Scan completed with warnings"
Kubernetes Manifest Not Found
Problem: Jenkins couldn’t find deployment.yaml due to repo nesting
Solution: Flattened repo with:

bash
Copy
Edit
git mv repo-root/platform-engineer-demo/* .
git push origin main --force
EKS Authentication Race Condition
Problem: Initial kubectl apply failed due to IAM propagation delay
Solution: Added retry logic in Jenkinsfile:

groovy
Copy
Edit
sh '''
for i in {1..10}; do
  kubectl apply -f deployment.yaml && break || sleep 10
done
'''
Outcome
CI/CD pipeline successfully builds, scans, pushes, and deploys to EKS
Health checks and basic observability included

Key Learnings and Takeaways
Understanding and enforcing idempotence in Terraform is critical
Troubleshooting via set -eux and analyzing cloud-init-output.log is extremely effective
Moving logic from Groovy to shell is often necessary for complex Jenkins scripts
AWS EKS authentication involves race conditions and IAM propagation challenges
A clean, flat Git repository structure ensures predictable CI/CD execution

Future Enhancements
Implement HTTPS (ALB TLS) for application and Jenkins UI
Scale Jenkins with distributed build agents (Jenkins nodes)
Integrate AWS CloudWatch for real-time monitoring and alerting
Enforce Trivy scan failures on CRITICAL vulnerabilities in production
Use EKS IAM Roles for Service Accounts (IRSA) for fine-grained pod-level permissions