################################################################################
# ACM certificate validated through DNS in the existing hosted zone, and the
# alias record that points the domain at the ALB.
################################################################################

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = var.domain_name
  }
}

locals {
  validation_options = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => dvo
  }
}

# Keyed by the (static) domain name rather than by the certificate's computed
# attributes, so the plan never depends on values known only after apply.
resource "aws_route53_record" "validation" {
  for_each = toset([var.domain_name])

  zone_id         = var.zone_id
  name            = local.validation_options[each.key].resource_record_name
  type            = local.validation_options[each.key].resource_record_type
  records         = [local.validation_options[each.key].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_route53_record" "alias" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
