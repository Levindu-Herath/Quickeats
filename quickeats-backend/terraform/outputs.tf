output "public_ip" {
  value = aws_eip.server.public_ip
}

output "instance_id" {
  value = aws_instance.server.id
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.image : k => r.repository_url }
}
