# IAM binding so Cloud Scheduler can invoke the function
resource "google_project_iam_member" "scheduler_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

resource "google_service_account" "scheduler_sa" {
  account_id   = "sa-energy-scheduler"
  display_name = "Cloud Scheduler Service Account for ETL"
}

resource "google_cloud_scheduler_job" "etl_job" {
  name        = "energy-etl-job"
  description = "Triggers the ETL Cloud Function on a schedule"
  schedule    = var.scheduler_cron
  time_zone   = "Etc/UTC"

  http_target {
    uri         = google_cloudfunctions2_function.etl.service_config[0].uri
    http_method = "POST"

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }

  depends_on = [
    google_project_service.services,
    google_cloudfunctions2_function.etl
  ]
}
