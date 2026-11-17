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

# Private (RFC 1918) range: 65,536 addresses to carve into subnets. https://docs.aws.amazon.com/vpc/latest/userguide/vpc-cidr-blocks.html
variable "vpc_cidr" {
  description = "IP range for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# No default, so every deploy names the exact image version (CI will pass the commit SHA). https://opentofu.org/docs/language/values/variables/
variable "image_tag" {
  description = "Tag of the image in ECR to run"
  type        = string
}

# Must match the image's architecture, or the task fails with "exec format error". https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-arm64.html
variable "cpu_architecture" {
  description = "CPU architecture of the image: ARM64 (cheaper, matches Apple silicon) or X86_64"
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64, matching the image's architecture."
  }
}

# Two tasks, one per zone, so losing a task or a zone does not take the service down. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html
variable "desired_count" {
  description = "Number of copies of the container to run"
  type        = number
  default     = 2
}

# Only certain CPU and memory pairs are valid on Fargate; the defaults are the smallest size. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html
variable "task_cpu" {
  description = "Fargate CPU units (256 = 0.25 vCPU)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate memory in MiB (512 = 0.5 GB)"
  type        = string
  default     = "512"
}

# A load balancer needs subnets in at least two zones, and one zone failing leaves the other serving. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html
variable "az_count" {
  description = "Number of availability zones to spread across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "A load balancer needs subnets in at least 2 availability zones."
  }
}

# The subdomain is delegated to Route 53 at the parent domain's DNS provider, which is outside AWS. https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingNewSubdomain.html
variable "domain_name" {
  description = "Subdomain that serves the site over HTTPS"
  type        = string
  default     = "ecs-fargate-terraform-demo.tannor.net"
}
