resource "google_cloud_run_service" "api" {
  name     = "energy-forecast-api"
  location = var.region

  template {
    spec {
      service_account_name = google_service_account.api_sa.email

      containers {
        image = "gcr.io/${var.project_id}/energy-forecast-api:latest"

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "BQ_DATASET"
          value = google_bigquery_dataset.energy.dataset_id
        }

        env {
          name  = "FORECAST_TABLE"
          value = google_bigquery_table.forecast.table_id
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true

  depends_on = [
    google_project_service.services
  ]
}

# Allow unauthenticated access (for now – you can lock it down later)
resource "google_cloud_run_service_iam_member" "api_invoker" {
  location = google_cloud_run_service.api.location
  project  = var.project_id
  service  = google_cloud_run_service.api.name

  role   = "roles/run.invoker"
  member = "allUsers"
}
