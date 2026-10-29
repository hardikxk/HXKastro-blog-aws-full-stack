# Optional Route 53 DNS configuration (requires an active custom domain).

resource "aws_route53_zone" "main" {
  count = var.enable_route53 ? 1 : 0
  name  = var.domain_name

  tags = { Project = var.project_name }
}

resource "aws_route53_record" "root" {
  count   = var.enable_route53 ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
