resource "google_bigquery_dataset" "energy" {
  dataset_id = "energy_data"
  project    = var.project_id
  location   = var.location

  delete_contents_on_destroy = true
}

resource "google_bigquery_table" "raw_energy" {
  dataset_id = google_bigquery_dataset.energy.dataset_id
  table_id   = "raw_energy"
  project    = var.project_id

  schema = <<EOF
[
  {"name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED"},
  {"name": "region", "type": "STRING", "mode": "REQUIRED"},
  {"name": "demand", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "price", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "carbon_intensity", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "metadata", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

resource "google_bigquery_table" "clean_energy" {
  dataset_id = google_bigquery_dataset.energy.dataset_id
  table_id   = "clean_energy"
  project    = var.project_id

  schema = <<EOF
[
  {"name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED"},
  {"name": "region", "type": "STRING", "mode": "REQUIRED"},
  {"name": "demand", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "price", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "carbon_intensity", "type": "FLOAT", "mode": "NULLABLE"}
]
EOF
}

resource "google_bigquery_table" "forecast" {
  dataset_id = google_bigquery_dataset.energy.dataset_id
  table_id   = "forecast"
  project    = var.project_id

  schema = <<EOF
[
  {"name": "timestamp", "type": "TIMESTAMP", "mode": "REQUIRED"},
  {"name": "region", "type": "STRING", "mode": "REQUIRED"},
  {"name": "predicted_demand", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "predicted_price", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "created_at", "type": "TIMESTAMP", "mode": "REQUIRED"}
]
EOF
}
