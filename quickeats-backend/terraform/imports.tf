# Adopts the resources that were created by hand in the AWS console.
# After the first successful apply these are no-ops; they stay as a record of
# where each resource came from.

import {
  to = aws_instance.server
  id = var.instance_id
}

import {
  to = aws_security_group.server
  id = var.security_group_id
}

import {
  to = aws_eip.server
  id = var.eip_allocation_id
}

import {
  to = aws_iam_role.server
  id = "quickeats-ec2-ecr"
}

import {
  to = aws_iam_role_policy_attachment.ecr
  id = "quickeats-ec2-ecr/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

import {
  to = aws_iam_instance_profile.server
  id = "quickeats-ec2-ecr"
}

import {
  for_each = local.images
  to       = aws_ecr_repository.image[each.key]
  id       = "quickeats-${each.key}"
}
