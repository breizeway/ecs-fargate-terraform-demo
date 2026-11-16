terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket name is account-specific, so it is not committed. Supply it at
  # init time:  tofu init -backend-config=backend.hcl  (see backend.hcl.example).
  backend "s3" {
    key          = "ecs-fargate-demo/terraform.tfstate"
    region       = "us-west-2" # backend blocks cannot use variables
    encrypt      = true
    use_lockfile = true # S3-native state locking (OpenTofu/Terraform >= 1.10)
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "opentofu"
      Stack     = "main"
    }
  }
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name used for resources and tags"
  type        = string
  default     = "ecs-fargate-demo"
}

variable "vpc_cidr" {
  description = "IP range for the VPC (private address space, RFC 1918)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "image_tag" {
  description = "Tag of the image in ECR to run. No default: say exactly which version to deploy (CI passes the commit SHA)."
  type        = string
}

variable "cpu_architecture" {
  description = "CPU architecture of the image: ARM64 (matches Apple silicon, cheaper) or X86_64"
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64, matching the image's architecture."
  }
}

variable "desired_count" {
  description = "Number of copies of the container to run (2 = one per zone)"
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "Fargate CPU units (256 = 0.25 vCPU); only certain CPU/memory pairs are valid"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate memory in MiB (512 = 0.5 GB)"
  type        = string
  default     = "512"
}

variable "az_count" {
  description = "Number of availability zones to spread across (a load balancer needs at least 2)"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "A load balancer needs subnets in at least 2 availability zones."
  }
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, by availability zone"
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "app_url" {
  description = "Public address of the load balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  description = "Where to push the image (the account ID is computed by AWS, not hard-coded)"
  value       = aws_ecr_repository.app.repository_url
}
