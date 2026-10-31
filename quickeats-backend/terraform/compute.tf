resource "aws_instance" "server" {
  ami                    = var.ami_id
  instance_type          = "c7i-flex.large"
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.server.id]
  iam_instance_profile   = aws_iam_instance_profile.server.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "quickeats-server"
  }

  lifecycle {
    # Prod runs here: refuse any plan that would replace it
    prevent_destroy = true
    # Newer Ubuntu AMIs must not trigger a rebuild
    ignore_changes = [ami, user_data, user_data_base64]
  }
}

# The instance pulls images from ECR with this role, so Jenkins needs no AWS keys.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "server" {
  name               = "quickeats-ec2-ecr"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "server" {
  name = aws_iam_role.server.name
  role = aws_iam_role.server.name
}
