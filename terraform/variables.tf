variable "gcp_project_id" {
  description = "Your Google Cloud project ID."
  type        = string
  # No default - Terraform will ask you for this
}

variable "gcp_region" {
  description = "The GCP region for resources."
  type        = string
  default     = "us-central1"
}