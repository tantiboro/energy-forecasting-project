output "bucket_name" {
  value = google_storage_bucket.artifacts.name
}

output "bq_dataset" {
  value = google_bigquery_dataset.energy.dataset_id
}

output "etl_function_url" {
  value = google_cloudfunctions2_function.etl.service_config[0].uri
}

output "cloud_run_api_url" {
  value = google_cloud_run_service.api.status[0].url
}
