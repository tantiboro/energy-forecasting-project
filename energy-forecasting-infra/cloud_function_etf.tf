data "archive_file" "etl_source" {
  type        = "zip"
  source_dir  = "${path.module}/functions/etl"
  output_path = "${path.module}/functions/etl.zip"
}

resource "google_storage_bucket_object" "etl_source" {
  name   = "functions/etl-${data.archive_file.etl_source.output_md5}.zip"
  bucket = google_storage_bucket.artifacts.name
  source = data.archive_file.etl_source.output_path
}

resource "google_cloudfunctions2_function" "etl" {
  name        = "energy-etl-function"
  location    = var.region
  description = "ETL function to ingest energy data into BigQuery"

  build_config {
    runtime     = "python311"
    entry_point = "main" # function name in main.py

    source {
      storage_source {
        bucket = google_storage_bucket.artifacts.name
        object = google_storage_bucket_object.etl_source.name
      }
    }

    environment_variables = {
      BQ_DATASET      = google_bigquery_dataset.energy.dataset_id
      RAW_TABLE       = google_bigquery_table.raw_energy.table_id
      CLEAN_TABLE     = google_bigquery_table.clean_energy.table_id
      PROJECT_ID      = var.project_id
    }
  }

  service_config {
    max_instance_count = 3
    min_instance_count = 0
    available_memory   = "512M"
    timeout_seconds    = 540
    ingress_settings   = "ALLOW_INTERNAL_AND_GCLB"
    service_account_email = google_service_account.etl_sa.email
  }

  depends_on = [
    google_project_service.services,
    google_storage_bucket_object.etl_source
  ]
}
