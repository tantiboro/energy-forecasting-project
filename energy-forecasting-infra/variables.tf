variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Default region for resources"
  type        = string
  default     = "us-central1"
}

variable "location" {
  description = "Location for BigQuery dataset and GCS bucket"
  type        = string
  default     = "US"
}

variable "gcs_bucket_name" {
  description = "Bucket for code & artifacts"
  type        = string
}

variable "scheduler_cron" {
  description = "Cron schedule for ETL job"
  type        = string
  default     = "0 * * * *" # every hour
}
