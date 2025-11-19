# Service account for ETL Cloud Function
resource "google_service_account" "etl_sa" {
  account_id   = "sa-energy-etl"
  display_name = "Energy ETL Cloud Function SA"
}

# Service account for Cloud Run API
resource "google_service_account" "api_sa" {
  account_id   = "sa-energy-api"
  display_name = "Energy Forecast API SA"
}

# BigQuery access for ETL
resource "google_project_iam_member" "etl_bq_role" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.etl_sa.email}"
}

resource "google_project_iam_member" "etl_logging_role" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.etl_sa.email}"
}

# API SA BigQuery read access (for serving forecasts)
resource "google_project_iam_member" "api_bq_role" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "api_logging_role" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}
