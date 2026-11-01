variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "admin_cidr" {
  description = "Your current public IP as x.x.x.x/32; the only source allowed on SSH (22) and Jenkins (8080). Pass it with -var on every plan/apply."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr must be a single IPv4 address with /32."
  }
}

# --- Existing resources (created in the console, adopted with imports.tf) ---

variable "instance_id" {
  type = string
}

variable "ami_id" {
  description = "AMI the instance was launched from. Ignored after import, but required by the resource."
  type        = string
}

variable "subnet_id" {
  type = string
}

variable "key_name" {
  description = "EC2 key pair name used for SSH."
  type        = string
}

variable "security_group_id" {
  type = string
}

variable "security_group_description" {
  description = "Must match the existing description exactly; changing it would replace the group."
  type        = string
}

variable "eip_allocation_id" {
  type = string
}

# --- Cost guard ---

variable "alert_email" {
  description = "Where AWS Budgets sends spend alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly spend (before credits) that triggers alerts at 50%, 80% and forecast 100%."
  type        = number
  default     = 25
}
