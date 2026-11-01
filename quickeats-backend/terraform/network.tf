# GitHub publishes the address ranges its webhooks come from; Jenkins needs them
# on 8080 or pushes to main never trigger a build.
data "http" "github_meta" {
  url             = "https://api.github.com/meta"
  request_headers = { Accept = "application/vnd.github+json" }
}

locals {
  github_hook_cidrs = jsondecode(data.http.github_meta.response_body).hooks
}

resource "aws_security_group" "server" {
  name        = "quickeats-sg"
  description = var.security_group_description

  # Public traffic: Kong on 80 (and 443 once HTTPS is added)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Admin access, only from the operator's current IP
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Webhook deliveries to /github-webhook/ (verified with the webhook secret)
  ingress {
    description      = "GitHub webhooks to Jenkins"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = [for c in local.github_hook_cidrs : c if !strcontains(c, ":")]
    ipv6_cidr_blocks = [for c in local.github_hook_cidrs : c if strcontains(c, ":")]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "quickeats-sg"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_eip" "server" {
  domain   = "vpc"
  instance = aws_instance.server.id

  tags = {
    Name = "quickeats-eip"
  }

  lifecycle {
    prevent_destroy = true # the mobile apps point at this IP
  }
}
