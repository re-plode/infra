resource "terraform_data" "force_run" {
  input = timestamp()

  # Comment this to force replacement
  lifecycle {
    ignore_changes = [input]
  }
}
