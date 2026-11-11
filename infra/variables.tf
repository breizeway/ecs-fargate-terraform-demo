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
