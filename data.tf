data "sops_file" "secrets" {
  source_file = "config/secrets.enc.json"
}
