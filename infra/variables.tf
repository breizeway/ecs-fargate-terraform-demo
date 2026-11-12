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

variable "az_count" {
  description = "Number of availability zones to spread across (a load balancer needs at least 2)"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "A load balancer needs subnets in at least 2 availability zones."
  }
}
