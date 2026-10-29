resource "aws_ecr_repository" "blog_app" {
  name                 = "${var.project_name}-blog-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = var.project_name }
}

resource "aws_ecr_repository" "comments_api" {
  name                 = "${var.project_name}-comments-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = var.project_name }
}
