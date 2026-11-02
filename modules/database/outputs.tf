output "db_endpoint" {
  description = "Connection endpoint (host:port)"
  value       = "${aws_instance.mysql.private_ip}:3306"
}

output "db_address" {
  description = "Private IP of the database server"
  value       = aws_instance.mysql.private_ip
}

output "db_port" {
  value = 3306
}

output "db_name" {
  value = var.db_name
}

output "db_instance_id" {
  value = aws_instance.mysql.id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "soar_writer_secret_arn" {
  description = "Secret with the password of soar_writer (the SOAR writes the ban history)"
  value       = aws_secretsmanager_secret.soar_writer.arn
}

output "soar_reader_secret_name" {
  description = "Secret with the password of soar_reader (read the ban history from mgmt01)"
  value       = aws_secretsmanager_secret.soar_reader.name
}
