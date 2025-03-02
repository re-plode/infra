output "hcloud_internal_net_ip_addr" {
  value = hcloud_server.internal_net.ipv4_address
}

output "mailgun_smtp_login" {
  value = mailgun_domain.replode.smtp_login
}
output "mailgun_smtp_password" {
  value     = mailgun_domain.replode.smtp_password
  sensitive = true
}
output "mailgun_receiving_records" {
  value = mailgun_domain.replode.receiving_records_set
}
output "mailgun_sending_records" {
  value = mailgun_domain.replode.sending_records_set
}
