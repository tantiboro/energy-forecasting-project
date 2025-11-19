terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  
  # Configure the GCS backend to store your state file
  # This is a best practice!
  backend "gcs" {
    bucket = "tanti-energy-project-tf-state" # <-- CHANGE THIS
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# 1. A GCS Bucket to store our Terraform state
#    (You must create this bucket manually first)
#
#    Run this command in your gcloud shell:
#    gsutil mb -p YOUR_PROJECT_ID gs://your-tf-state-bucket-name

# 2. The BigQuery "Dataset" (like a folder or schema)
resource "google_bigquery_dataset" "energy_data" {
  dataset_id                  = "energy_forecasting"
  friendly_name               = "Energy Forecasting"
  description                 = "Dataset for real-time energy data"
  location                    = var.gcp_region
}

# 3. The BigQuery "Table" (where the data lives)
resource "google_bigquery_table" "hourly_demand" {
  dataset_id = google_bigquery_dataset.energy_data.dataset_id
  table_id   = "hourly_demand"

  # Define the schema to match our Python script's output
  schema = <<EOF
[
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "The timestamp of the energy reading"
  },
  {
    "name": "demand_mwh",
    "type": "FLOAT",
    "description": "The energy demand in Megawatt-hours"
  },
  {
    "name": "units",
    "type": "STRING",
    "description": "The unit of measurement (e.g., megawatthours)"
  },
  {
    "name": "region_name",
    "type": "STRING",
    "description": "The full name of the grid region (e.g., PJM Interconnection)"
  },
  {
    "name": "subba_name",
    "type": "STRING",
    "description": "The sub-balancing authority name"
  }
  
]
EOF

  # Set partitioning on the timestamp column for efficiency
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
}

# --- PHASE 2: CLOUD FUNCTION & SCHEDULER ---

# 4. Zip our Python code for the Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "../cloud_function" # Path to our 'cloud_function' folder
  output_path = "/tmp/function-source.zip"
}

# 5. Upload the zipped code to a new GCS Bucket
resource "google_storage_bucket" "function_bucket" {
  name     = "${var.gcp_project_id}-cf-source" # Must be globally unique
  location = var.gcp_region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "function_source" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path
}

# 6. Define the Cloud Function (2nd Gen)
resource "google_cloudfunctions2_function" "etl_function" {
  name     = "etl-energy-data"
  location = var.gcp_region
  
  build_config {
    runtime     = "python311" # Use an up-to-date Python
    entry_point = "etl_entry_point" # The name of the @functions_framework function
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    timeout_seconds    = 540 # Max timeout for scheduler
    
    # Set the environment variables for the function
    environment_variables = {
      GCP_PROJECT_ID = var.gcp_project_id
      TABLE_ID       = "${google_bigquery_dataset.energy_data.project}.${google_bigquery_dataset.energy_data.dataset_id}.${google_bigquery_table.hourly_demand.table_id}"
      SECRET_ID      = "eia-api-key"
    }
  }
}

# 7. Grant the Cloud Function permission to access secrets
resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  secret_id = "eia-api-key"
  role      = "roles/secretmanager.secretAccessor"
  # This 'principal' is a special string that grants access to the function
  member    = "serviceAccount:${google_cloudfunctions2_function.etl_function.service_config[0].service_account_email}"
}

# 8. Grant the Cloud Function permission to write to BigQuery
resource "google_bigquery_dataset_iam_member" "bq_writer" {
  dataset_id = google_bigquery_dataset.energy_data.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_cloudfunctions2_function.etl_function.service_config[0].service_account_email}"
}

# 9. Create a service account for the Scheduler to use
resource "google_service_account" "scheduler_invoker" {
  account_id   = "scheduler-invoker-sa"
  display_name = "Scheduler Invoker SA"
}

# 10. Grant the Scheduler's SA permission to invoke the function
resource "google_cloud_run_service_iam_member" "scheduler_invoker_permission" {
  location = google_cloudfunctions2_function.etl_function.location
  service  = google_cloudfunctions2_function.etl_function.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_invoker.email}"
}

# 11. Create a Scheduler job to run the function every day
resource "google_cloud_scheduler_job" "daily_etl_job" {
  name     = "daily-energy-etl"
  schedule = "0 3 * * *" # 3:00 AM every day
  time_zone = "America/Chicago"

  http_target {
    uri = google_cloudfunctions2_function.etl_function.service_config[0].uri
    http_method = "POST"
    
    # Use OIDC authentication
    oidc_token {
      service_account_email = google_service_account.scheduler_invoker.email
    }
  }
}

# --- PHASE 3: ML MODEL STORAGE ---

# 12. GCS Bucket to store the trained ML models
resource "google_storage_bucket" "model_bucket" {
  name     = "${var.gcp_project_id}-ml-models" # This is the bucket name
  location = var.gcp_region
  uniform_bucket_level_access = true
}

# --- PHASE 4: AUTOMATED ML TRAINING ---

# 13. Zip the new training function's code
data "archive_file" "training_function_source" {
  type        = "zip"
  source_dir  = "../model_training_function" # Path to the NEW folder
  output_path = "/tmp/training-function-source.zip"
}

# 14. Upload the new zipped code to the function bucket
resource "google_storage_bucket_object" "training_function_source" {
  name   = "training-function-source.zip" # A new name for the zip
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.training_function_source.output_path
}

# 15. Define the new Cloud Function for training
resource "google_cloudfunctions2_function" "training_function" {
  name     = "train-energy-model"
  location = var.gcp_region
  
  build_config {
    runtime     = "python311"
    entry_point = "train_model_entry_point"
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.training_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    # IMPORTANT: Give it a long timeout. Training takes time.
    timeout_seconds    = 1800 # 30 minutes (Prophet install is slow)
    available_memory   = "1Gi" # Training needs more memory
    
    # Set environment variables for the training function
    environment_variables = {
      GCP_PROJECT_ID = var.gcp_project_id
      TABLE_ID       = "${google_bigquery_dataset.energy_data.project}.${google_bigquery_dataset.energy_data.dataset_id}.${google_bigquery_table.hourly_demand.table_id}"
      MODEL_BUCKET   = google_storage_bucket.model_bucket.name
    }
  }
}

# 16. Grant the new function permission to read from BigQuery
resource "google_bigquery_dataset_iam_member" "training_bq_reader" {
  dataset_id = google_bigquery_dataset.energy_data.dataset_id
  role       = "roles/bigquery.dataViewer" # 'dataUser' is read-only
  member     = "serviceAccount:${google_cloudfunctions2_function.training_function.service_config[0].service_account_email}"
}

# 17. Grant the new function permission to write to the model bucket
resource "google_storage_bucket_iam_member" "model_bucket_writer" {
  bucket = google_storage_bucket.model_bucket.name
  role   = "roles/storage.objectAdmin" # Can create/overwrite objects
  member = "serviceAccount:${google_cloudfunctions2_function.training_function.service_config[0].service_account_email}"
}

# 18. Grant our existing Scheduler SA permission to invoke the new function
resource "google_cloud_run_service_iam_member" "scheduler_invoker_permission_training" {
  location = google_cloudfunctions2_function.training_function.location
  service  = google_cloudfunctions2_function.training_function.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_invoker.email}"
}

# 19. Create the new weekly Scheduler job
resource "google_cloud_scheduler_job" "weekly_training_job" {
  name     = "weekly-model-training"
  schedule = "0 2 * * 0" # 2:00 AM every Sunday
  time_zone = "America/Chicago"

  http_target {
    uri = google_cloudfunctions2_function.training_function.service_config[0].uri
    http_method = "POST"
    
    # Use the same OIDC auth as our first job
    oidc_token {
      service_account_email = google_service_account.scheduler_invoker.email
    }
  }
}

# --- PHASE 5: API SERVING (CLOUD RUN) ---

# 20. Define the Artifact Registry (where our image lives)
# This is a "data" source, it just looks up the repo we made
data "google_artifact_registry_repository" "app_images" {
  location      = var.gcp_region
  repository_id = "app-images"
}

# 21. Define the Cloud Run Service
resource "google_cloud_run_v2_service" "api_service" {
  name     = "energy-forecasting-api"
  location = var.gcp_region
  
  # This tells Cloud Run to build and deploy our code
  template {
    # This is the "build" step
    build {
      git_source {
        uri        = "https://github.com/tantiboro/energy-forecasting-project.git" # <-- CHANGE THIS
        repo_type  = "GITHUB"
        revision   = "main" # Or your branch name
      }
      build_steps {
        name = "gcr.io/cloud-builders/docker"
        args = [
          "build",
          "-t",
          "${data.google_artifact_registry_repository.app_images.location}-docker.pkg.dev/${var.gcp_project_id}/${data.google_artifact_registry_repository.app_images.repository_id}/energy-api:latest",
          "./api_service" # Path to the Dockerfile
        ]
      }
    }

    # This is the "deploy" step
    containers {
      image = "${data.google_artifact_registry_repository.app_images.location}-docker.pkg.dev/${var.gcp_project_id}/${data.google_artifact_registry_repository.app_images.repository_id}/energy-api:latest"
      ports {
        container_port = 8080
      }
      
      # Set environment variables for the API
      env {
        name  = "GCP_PROJECT_ID"
        value = var.gcp_project_id
      }
      env {
        name  = "MODEL_BUCKET"
        value = google_storage_bucket.model_bucket.name
      }
    }
  }
}

# 22. Grant the API's service account permission to read the model
resource "google_storage_bucket_iam_member" "api_model_reader" {
  bucket = google_storage_bucket.model_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_cloud_run_v2_service.api_service.template.service_account}"
}

# 23. Allow public access to the API
resource "google_cloud_run_service_iam_member" "api_invoker" {
  location = google_cloud_run_v2_service.api_service.location
  service  = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 24. Output the API's URL so we can test it
output "api_service_url" {
  description = "The URL of the deployed forecasting API"
  value       = google_cloud_run_v2_service.api_service.uri
}
