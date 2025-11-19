resource "google_storage_bucket" "artifacts" {
  name     = var.gcs_bucket_name
  project  = var.project_id
  location = var.location

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90
    }
  }
}
