# A public certificate lets browsers trust the site; DNS validation proves we control the name. https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html
resource "aws_acm_certificate" "app" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # The listener uses the certificate, so a replacement must exist before the old one is removed. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
  lifecycle {
    create_before_destroy = true
  }
}

# Waits until ACM has issued the certificate, which needs the validation CNAME added at the DNS provider by hand. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
resource "aws_acm_certificate_validation" "app" {
  certificate_arn = aws_acm_certificate.app.arn
}
