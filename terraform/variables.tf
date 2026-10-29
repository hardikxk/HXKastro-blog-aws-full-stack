variable "project_name" {
  description = "Short name used as a prefix for every resource"
  type        = string
  default     = "astro-blog"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

# --- Networking ---
variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for two public subnets across two AZs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# --- EC2 / Auto Scaling (Core Compute) ---
variable "ec2_instance_type" {
  description = "Instance type for the blog's EC2 Auto Scaling Group"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 1
}

variable "container_port" {
  description = "Port the Astro SSR blog app listens on"
  type        = number
  default     = 4321
}

variable "blog_image_tag" {
  type    = string
  default = "latest"
}

# --- Fargate (comments/reactions API) ---
variable "comments_api_port" {
  type    = number
  default = 3000
}

variable "ecs_task_cpu" {
  type    = string
  default = "256"
}

variable "ecs_task_memory" {
  type    = string
  default = "512"
}

variable "comments_api_image_tag" {
  type    = string
  default = "latest"
}

# --- Notifications ---
variable "admin_notification_email" {
  description = "Email to subscribe to the SNS notification topic. Leave blank to skip the subscription (avoids the confirmation email)."
  type        = string
  default     = ""
}

# --- Optional Route 53 (Custom Domain) ---
variable "enable_route53" {
  description = "Enable Route 53 hosted zone and DNS record creation for custom domains."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain name for Route 53, only used when enable_route53 = true"
  type        = string
  default     = ""
}
