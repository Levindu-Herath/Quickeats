locals {
  # One repository per image the Jenkinsfile pushes
  images = toset(["identity", "catalog", "order", "payment", "notification", "admin"])
}

resource "aws_ecr_repository" "image" {
  for_each = local.images

  name = "quickeats-${each.key}"
  # Jenkins re-pushes the same SHA tag when a build is replayed, so tags stay mutable
  image_tag_mutability = "MUTABLE"

  # Basic CVE scan of every pushed image (free)
  image_scanning_configuration {
    scan_on_push = true
  }
}

# Every build pushes a new tag, so without this the repos grow forever.
# 10 tags is plenty of rollback history (the pipeline only rolls back one release).
resource "aws_ecr_lifecycle_policy" "image" {
  for_each = aws_ecr_repository.image

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Drop untagged layers after a day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the 10 newest images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}
