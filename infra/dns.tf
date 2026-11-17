# Only the subdomain lives in Route 53; the parent domain's DNS provider delegates this name here with NS records. https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingNewSubdomain.html
resource "aws_route53_zone" "app" {
  name = var.domain_name
}

# A public certificate lets browsers trust the site; DNS validation proves we control the name. https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html
resource "aws_acm_certificate" "app" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # The listener uses the certificate, so a replacement must exist before the old one is removed. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
  lifecycle {
    create_before_destroy = true
  }
}

# ACM names the record that proves ownership; creating it in our zone validates the certificate. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
resource "aws_route53_record" "certificate_validation" {
  for_each = { for option in aws_acm_certificate.app.domain_validation_options : option.domain_name => option }

  zone_id = aws_route53_zone.app.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

# Waits until ACM has issued the certificate, so the HTTPS listener never receives a pending one. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

# An alias record follows the load balancer's changing addresses, which a fixed IP in an A record could not. https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html
resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.app.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
