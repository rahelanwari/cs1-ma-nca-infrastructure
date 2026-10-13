# Outputs of the VPN module

output "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN connection"
  value       = aws_vpn_connection.netlab.id
}

output "tunnel1_address" {
  description = "Public IP of AWS tunnel 1 (remote gateway in pfSense)"
  value       = aws_vpn_connection.netlab.tunnel1_address
}

output "tunnel2_address" {
  description = "Public IP of AWS tunnel 2 (remote gateway in pfSense)"
  value       = aws_vpn_connection.netlab.tunnel2_address
}

output "tunnel1_preshared_key" {
  description = "Pre-shared key of tunnel 1"
  value       = aws_vpn_connection.netlab.tunnel1_preshared_key
  sensitive   = true
}

output "tunnel2_preshared_key" {
  description = "Pre-shared key of tunnel 2"
  value       = aws_vpn_connection.netlab.tunnel2_preshared_key
  sensitive   = true
}