resource "b2_application_key" "s920p_bak" {
  key_name = "s920p-bak"
  capabilities = [
    "deleteFiles",
    "listAllBucketNames",
    "listBuckets",
    "listFiles",
    "readBucketEncryption",
    "readBucketLifecycleRules",
    "readBucketLogging",
    "readBucketNotifications",
    "readBucketReplications",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeBucketEncryption",
    "writeBucketLifecycleRules",
    "writeBucketLogging",
    "writeBucketNotifications",
    "writeBucketReplications",
    "writeBuckets",
    "writeFiles"
  ]
  bucket_ids = ["s920p-bak"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "b2_bucket" "s920p_bak" {
  bucket_name = "s920p-bak"
  bucket_type = "allPrivate"

  lifecycle {
    prevent_destroy = true
  }
}
