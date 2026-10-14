# Outputs of the DNS module

output "zone_id" {
  description = "ID of the private hosted zone"
  value       = aws_route53_zone.internal.zone_id
}

output "zone_name" {
  description = "Name of the private hosted zone"
  value       = aws_route53_zone.internal.name
}

output "db_fqdn" {
  description = "Private DNS name of the database server"
  value       = aws_route53_record.db.fqdn
}