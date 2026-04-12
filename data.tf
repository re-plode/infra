# data "terraform_remote_state" "s3" {
#   backend = "s3"
#   config = {
#     bucket = "infra"
#     key    = "terraform.tfstate"

#     region                      = "auto"
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#     skip_requesting_account_id  = true
#     skip_s3_checksum            = true
#     use_path_style              = true

#     access_key = var.cloudflare_r2_key
#     secret_key = var.cloudflare_r2_secret

#     endpoints = { s3 = var.cloudflare_r2_endpoint }
#   }
# }
